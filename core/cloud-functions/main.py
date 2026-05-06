"""Cloud Functions Python officielles (v0.2 + agenda moderation).

Each Firebase project deploys the same code. Per-tenant data scoping is
implicit because each function runs against its own project's Firestore.

Endpoints :
  - submit_contact              : persist contact form submission
  - submit_vote                 : persist a poll vote (idempotent per user/poll)
  - submit_event_proposal       : citoyen propose un event → file modération
  - submit_signalement_proposal : citoyen signale un problème → file modération
  - submit_idea_proposal        : citoyen propose une idée → file modération
  - fetch_weather               : météo OpenWeatherMap, lit la clé via _get_secret
  - send_notification           : admin fan-out push aux citoyens (FCM Admin SDK)

Tous requièrent un FirebaseAuth ID token en `Authorization: Bearer <token>`.

Pattern modération (phase 18.2). Tout module UGC suit la même forme :
  1. Le submit CF valide les champs requis
  2. Délègue à `_queue_proposal(...)` qui écrit dans `_moderation_queue/<id>`
     une enveloppe standard {targetCollection, moduleId, submittedBy,
     submittedByEmail, submittedAt, payload} et auto-injecte dans `payload`
     les champs `status: "pending"`, `visible: false`, `createdAt`
  3. Le dashboard (handleModerationAction) sur approve copie payload + ajoute
     `status: "approved"`, `visible: true`, `approvedAt`, `approvedBy`
     dans `targetCollection`, puis supprime l'entrée queue.
"""
from firebase_admin import initialize_app, auth as fb_auth, firestore
from firebase_functions import https_fn, options
import google.auth
import google.auth.transport.requests as google_auth_requests
import requests
import json
import os
import urllib.parse
import urllib.request
import urllib.error

# Sur Cloud Functions Gen 2 (Python), GOOGLE_CLOUD_PROJECT n'est PAS set par
# le runtime — seul GCLOUD_PROJECT l'est. firebase-admin lit GOOGLE_CLOUD_PROJECT
# en priorité ; sans lui le projectId n'est pas inféré et FCM v1 retourne
# UNAUTHENTICATED. On force la valeur depuis GCLOUD_PROJECT (Gen 1 + Gen 2)
# avant l'init.
_gcloud_proj = os.environ.get("GCLOUD_PROJECT")
if _gcloud_proj and not os.environ.get("GOOGLE_CLOUD_PROJECT"):
    os.environ["GOOGLE_CLOUD_PROJECT"] = _gcloud_proj

initialize_app()


@https_fn.on_request(
    region="europe-west1",
    cors=options.CorsOptions(
        cors_origins=["*"],
        cors_methods=["POST", "OPTIONS"],
    ),
)
def submit_contact(req: https_fn.Request) -> https_fn.Response:
    if req.method != "POST":
        return _error(405, "Method not allowed")
    uid = _verify_auth(req)
    if not uid:
        return _error(401, "Unauthorized")
    payload = req.get_json(silent=True) or {}
    db = firestore.client()
    db.collection("contact_submissions").add({
        "submittedBy": uid,
        "name": payload.get("name", ""),
        "email": payload.get("email", ""),
        "message": payload.get("message", ""),
        "consent": payload.get("consent", "false"),
        "submittedAt": firestore.SERVER_TIMESTAMP,
    })
    return _ok({"ok": True})


@https_fn.on_request(
    region="europe-west1",
    cors=options.CorsOptions(
        cors_origins=["*"],
        cors_methods=["POST", "OPTIONS"],
    ),
)
def submit_vote(req: https_fn.Request) -> https_fn.Response:
    if req.method != "POST":
        return _error(405, "Method not allowed")
    uid = _verify_auth(req)
    if not uid:
        return _error(401, "Unauthorized")
    payload = req.get_json(silent=True) or {}
    poll_id = payload.get("pollId")
    choice = payload.get("choice")
    if not poll_id or not choice:
        return _error(400, "pollId + choice requis")
    # Doc id = uid + poll → un user vote une fois par sondage, ré-écriture = update.
    vote_id = f"{uid}_{poll_id}"
    db = firestore.client()
    db.collection("votes").document(vote_id).set({
        "submittedBy": uid,
        "pollId": poll_id,
        "choice": choice,
        "confidence": payload.get("confidence"),
        "submittedAt": firestore.SERVER_TIMESTAMP,
    })
    return _ok({"ok": True})


@https_fn.on_request(
    region="europe-west1",
    cors=options.CorsOptions(
        cors_origins=["*"],
        cors_methods=["POST", "OPTIONS"],
    ),
)
def submit_event_proposal(req: https_fn.Request) -> https_fn.Response:
    """Le citoyen propose un événement. Voir pattern modération en tête de fichier."""
    if req.method != "POST":
        return _error(405, "Method not allowed")
    decoded = _verify_auth_full(req)
    if not decoded:
        return _error(401, "Unauthorized")
    payload = req.get_json(silent=True) or {}
    title = (payload.get("title") or "").strip()
    location = (payload.get("location") or "").strip()
    if not title:
        return _error(400, "title requis")
    if not location:
        return _error(400, "location requis")
    return _queue_proposal(
        decoded=decoded,
        target_collection="events",
        module_id="agenda",
        payload_fields={
            "title": title,
            "location": location,
            "date": (payload.get("date") or "").strip(),
            "dateStart": (payload.get("dateStart") or "").strip(),
            "description": (payload.get("description") or "").strip(),
            "imageUrl": "",
        },
        summary=f"« {title} » — {location}",
    )


@https_fn.on_request(
    region="europe-west1",
    cors=options.CorsOptions(
        cors_origins=["*"],
        cors_methods=["POST", "OPTIONS"],
    ),
)
def submit_signalement_proposal(req: https_fn.Request) -> https_fn.Response:
    """Le citoyen signale un problème du domaine public. Voir pattern modération en tête de fichier."""
    if req.method != "POST":
        return _error(405, "Method not allowed")
    decoded = _verify_auth_full(req)
    if not decoded:
        return _error(401, "Unauthorized")
    payload = req.get_json(silent=True) or {}
    title = (payload.get("title") or "").strip()
    address = (payload.get("address") or "").strip()
    if not title:
        return _error(400, "title requis")
    if not address:
        return _error(400, "address requis")
    category = (payload.get("category") or "autre").strip()
    category_labels = {
        "voirie": "Voirie",
        "eclairage": "Éclairage public",
        "proprete": "Propreté",
        "mobilier": "Mobilier urbain",
        "espaces-verts": "Espaces verts",
        "autre": "Autre",
    }
    # lat/lng peuvent venir vides (citoyen a saisi address sans capter la
    # position) — on les passe en payload uniquement si parseable Float
    lat = _parse_float(payload.get("lat"))
    lng = _parse_float(payload.get("lng"))
    payload_fields = {
        "title": title,
        "category": category,
        "categoryLabel": category_labels.get(category, "Autre"),
        "address": address,
        "imageUrl": (payload.get("imageUrl") or "").strip(),
        "description": (payload.get("description") or "").strip(),
    }
    if lat is not None and lng is not None:
        payload_fields["lat"] = lat
        payload_fields["lng"] = lng
    return _queue_proposal(
        decoded=decoded,
        target_collection="signalements",
        module_id="signalements",
        payload_fields=payload_fields,
        summary=f"[{category_labels.get(category, 'Autre')}] {title} — {address}",
    )


@https_fn.on_request(
    region="europe-west1",
    cors=options.CorsOptions(
        cors_origins=["*"],
        cors_methods=["POST", "OPTIONS"],
    ),
)
def submit_idea_proposal(req: https_fn.Request) -> https_fn.Response:
    """Le citoyen propose une idée pour la commune. Voir pattern modération en tête de fichier."""
    if req.method != "POST":
        return _error(405, "Method not allowed")
    decoded = _verify_auth_full(req)
    if not decoded:
        return _error(401, "Unauthorized")
    payload = req.get_json(silent=True) or {}
    title = (payload.get("title") or "").strip()
    description = (payload.get("description") or "").strip()
    if not title:
        return _error(400, "title requis")
    if not description:
        return _error(400, "description requise")
    category = (payload.get("category") or "autre").strip()
    category_labels = {
        "mobilite": "Mobilité",
        "environnement": "Environnement",
        "culture-sport": "Culture & sport",
        "jeunesse": "Jeunesse & écoles",
        "seniors": "Seniors & aidants",
        "vivre-ensemble": "Vivre-ensemble",
        "urbanisme": "Urbanisme",
        "autre": "Autre",
    }
    return _queue_proposal(
        decoded=decoded,
        target_collection="ideas",
        module_id="idees",
        payload_fields={
            "title": title,
            "category": category,
            "categoryLabel": category_labels.get(category, "Autre"),
            "description": description,
        },
        summary=f"[{category_labels.get(category, 'Autre')}] {title}",
    )


# Helper pattern modération phase 18.2 : enveloppe standard + auto-injection des
# champs lifecycle dans `payload`. Les modules UGC officiels passent par ici plutôt
# que d'écrire leur propre `db.collection("_moderation_queue").add(...)`.
def _queue_proposal(decoded, target_collection: str, module_id: str,
                    payload_fields: dict, summary: str) -> https_fn.Response:
    db = firestore.client()
    db.collection("_moderation_queue").add({
        "targetCollection": target_collection,
        "moduleId": module_id,
        "submittedBy": decoded["uid"],
        "submittedByEmail": decoded.get("email", ""),
        "submittedAt": firestore.SERVER_TIMESTAMP,
        "payload": {
            **payload_fields,
            "status": "pending",
            "visible": False,
            "createdAt": firestore.SERVER_TIMESTAMP,
            "_summary": summary,
        },
    })
    return _ok({"ok": True})


@https_fn.on_request(
    region="europe-west1",
    cors=options.CorsOptions(
        cors_origins=["*"],
        cors_methods=["POST", "OPTIONS"],
    ),
)
def fetch_weather(req: https_fn.Request) -> https_fn.Response:
    """Lit la météo actuelle via OpenWeatherMap. Le module `meteo` envoie
    lat/lng (depuis le tenant config) ; ce CF lit la clé API via le helper
    `_get_secret` (phase 17) puis renvoie un texte court à afficher."""
    if req.method != "POST":
        return _error(405, "Method not allowed")
    if not _verify_auth(req):
        return _error(401, "Unauthorized")
    payload = req.get_json(silent=True) or {}
    lat = _parse_float(payload.get("lat"))
    lng = _parse_float(payload.get("lng"))
    if lat is None or lng is None:
        return _error(400, "lat + lng (numériques) requis")
    api_key = _get_secret("openweather_api_key")
    if not api_key:
        return _error(503, "Clé API OpenWeather non configurée — admin doit la renseigner dans le dashboard")
    try:
        params = urllib.parse.urlencode({
            "lat": f"{lat}",
            "lon": f"{lng}",
            "appid": api_key,
            "units": "metric",
            "lang": "fr",
        })
        url = f"https://api.openweathermap.org/data/2.5/weather?{params}"
        with urllib.request.urlopen(url, timeout=8) as resp:
            data = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        if e.code == 401:
            return _error(503, "Clé API OpenWeather rejetée — vérifier la valeur dans le dashboard")
        return _error(502, f"OpenWeather API erreur {e.code}")
    except (urllib.error.URLError, TimeoutError):
        return _error(504, "OpenWeather API injoignable (timeout)")
    except Exception as e:
        return _error(500, f"Erreur fetch_weather: {e}")
    name = data.get("name", "votre commune")
    weather = (data.get("weather") or [{}])[0]
    description = weather.get("description", "—").capitalize()
    main_kind = (weather.get("main") or "").lower()
    main = data.get("main") or {}
    wind = data.get("wind") or {}
    temp = main.get("temp")
    feels = main.get("feels_like")
    temp_min = main.get("temp_min")
    temp_max = main.get("temp_max")
    humidity = main.get("humidity")
    wind_speed = wind.get("speed")  # m/s
    # Mapping condition principale → emoji. Couvre le commun sans dépendre
    # du code numérique exact (OpenWeather a ~50 codes ; on regroupe par
    # famille). Fallback ciel partiellement nuageux pour l'inconnu.
    icon = {
        "clear": "☀️",
        "clouds": "☁️",
        "rain": "🌧️",
        "drizzle": "🌦️",
        "snow": "❄️",
        "thunderstorm": "⛈️",
        "mist": "🌫️",
        "fog": "🌫️",
        "haze": "🌫️",
    }.get(main_kind, "🌤️")
    lines = []
    line1 = f"{icon} {name}"
    if temp is not None:
        line1 += f" · {round(temp)}°C"
    lines.append(line1)
    line2_bits = [description]
    if feels is not None and temp is not None and abs(feels - temp) >= 1:
        line2_bits.append(f"ressenti {round(feels)}°C")
    if temp_min is not None and temp_max is not None and round(temp_min) != round(temp_max):
        line2_bits.append(f"min {round(temp_min)}° / max {round(temp_max)}°")
    lines.append(" · ".join(line2_bits))
    line3_bits = []
    if wind_speed is not None:
        line3_bits.append(f"Vent {round(wind_speed * 3.6)} km/h")
    if humidity is not None:
        line3_bits.append(f"Humidité {humidity}%")
    if line3_bits:
        lines.append(" · ".join(line3_bits))
    return _ok({"text": "\n".join(lines)})


@https_fn.on_request(
    region="europe-west1",
    cors=options.CorsOptions(
        cors_origins=["*"],
        cors_methods=["POST", "OPTIONS"],
    ),
)
def send_notification(req: https_fn.Request) -> https_fn.Response:
    """Admin fan-out push aux citoyens. Lit tous les FCM tokens du tenant
    dans `_push_tokens/`, batch-send via FCM Admin SDK, prune les tokens
    invalides (NotRegistered → device désinstallé) au passage. Auth requiert
    custom claim `admin: true`."""
    if req.method != "POST":
        return _error(405, "Method not allowed")
    decoded = _verify_auth_full(req)
    if not decoded:
        return _error(401, "Unauthorized")
    if not decoded.get("admin"):
        return _error(403, "Admin claim requis pour envoyer un push")
    payload = req.get_json(silent=True) or {}
    title = (payload.get("title") or "").strip()
    body = (payload.get("body") or "").strip()
    if not title:
        return _error(400, "title requis")
    if not body:
        return _error(400, "body requis")
    # Deep-link interne optionnel : `target.screen` au format `module:screen`,
    # `target.bindings` dict de paramètres pour la screen ciblée. Encodé dans
    # le payload FCM `data.target` (JSON string — `data` ne supporte que les
    # strings, pas d'objets imbriqués). Le client décode au tap et push une
    # Route via le NavigationStack.
    target = payload.get("target") or {}
    target_screen = (target.get("screen") or "").strip()
    target_bindings = target.get("bindings") if isinstance(target.get("bindings"), dict) else {}
    fcm_data: dict[str, str] = {}
    if target_screen:
        fcm_data["target"] = json.dumps({
            "screen": target_screen,
            "bindings": target_bindings,
        })

    db = firestore.client()
    docs = list(db.collection("_push_tokens").stream())
    if not docs:
        return _ok({"text": "Aucun citoyen abonné aux notifications. Token = 0 envoi.", "sent": 0, "failed": 0})

    tokens = [d.id for d in docs]
    sent_total = 0
    failed_total = 0
    invalid_token_doc_ids: list[str] = []
    failure_reasons: list[str] = []

    # Appel REST direct vers FCM HTTP v1 avec un access token google-auth
    # scoped explicitement `firebase.messaging`. On bypasse la couche
    # firebase-admin messaging pour 2 raisons :
    #   1. Sur CF Gen 2 Python, firebase_admin avait un comportement opaque
    #      avec ADC + scopes qui produisait des UNAUTHENTICATED silencieux.
    #   2. L'erreur APNs sous-jacente (THIRD_PARTY_AUTH_ERROR / InvalidProviderToken)
    #      est mieux remontée via la réponse REST directe.
    creds, project = google.auth.default(scopes=["https://www.googleapis.com/auth/firebase.messaging"])
    auth_req = google_auth_requests.Request()
    creds.refresh(auth_req)
    fcm_url = f"https://fcm.googleapis.com/v1/projects/{project}/messages:send"
    headers = {"Authorization": f"Bearer {creds.token}", "Content-Type": "application/json"}
    for token in tokens:
        message: dict = {"token": token, "notification": {"title": title, "body": body}}
        if fcm_data:
            message["data"] = fcm_data
        msg_body = {"message": message}
        try:
            r = requests.post(fcm_url, headers=headers, json=msg_body, timeout=15)
            if r.status_code == 200:
                sent_total += 1
            else:
                failed_total += 1
                err_payload = r.json() if r.text else {}
                err_status = err_payload.get("error", {}).get("status", str(r.status_code))
                err_msg = err_payload.get("error", {}).get("message", r.text[:200])
                failure_reasons.append(f"[{err_status}] {err_msg}")
                if err_status in ("NOT_FOUND", "INVALID_ARGUMENT") or "Unregistered" in err_msg:
                    invalid_token_doc_ids.append(token)
        except Exception as e:
            failed_total += 1
            failure_reasons.append(f"[{e.__class__.__name__}] {e}")
    # Prune des tokens morts (best-effort, ignore les erreurs delete).
    for doc_id in invalid_token_doc_ids:
        try:
            db.collection("_push_tokens").document(doc_id).delete()
        except Exception:
            pass
    pruned = len(invalid_token_doc_ids)
    text = f"Envoyé à {sent_total} appareil(s), {failed_total} échec(s)"
    if pruned:
        text += f", {pruned} token(s) invalide(s) supprimé(s)"
    text += "."
    return _ok({
        "text": text,
        "sent": sent_total,
        "failed": failed_total,
        "pruned": pruned,
        "failureReasons": failure_reasons[:10] if failure_reasons else [],
    })


# Helper secrets phase 17 : lit `_secrets/<id>.value` via Admin SDK. Les modules
# qui ont besoin d'une clé API tierce (météo, transports, géocoding…) déclarent
# leurs secrets dans le manifest ; l'admin commune les renseigne dans le
# dashboard ; le CF du module les lit via cet helper. Stockage Firestore = OK
# pour secrets faiblement sensibles. Migration vers Google Secret Manager
# quand un secret plus sensible (FCM, paiement) le motivera.
def _get_secret(secret_id: str) -> str | None:
    db = firestore.client()
    doc = db.collection("_secrets").document(secret_id).get()
    if not doc.exists:
        return None
    return (doc.to_dict() or {}).get("value")


def _parse_float(v):
    try:
        return float(v) if v not in (None, "") else None
    except (TypeError, ValueError):
        return None


def _verify_auth(req: https_fn.Request):
    decoded = _verify_auth_full(req)
    return decoded["uid"] if decoded else None


def _verify_auth_full(req: https_fn.Request):
    header = req.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return None
    try:
        return fb_auth.verify_id_token(header[7:])
    except Exception:
        return None


def _ok(body: dict) -> https_fn.Response:
    return https_fn.Response(
        json.dumps(body),
        status=200,
        headers={"Content-Type": "application/json"},
    )


def _error(status: int, message: str) -> https_fn.Response:
    return https_fn.Response(
        json.dumps({"error": message}),
        status=status,
        headers={"Content-Type": "application/json"},
    )
