"""Spike Phase 7 — Cloud Functions Python (rev 2 — refresh post-IAM grant).

Each Firebase project deploys the same code. Per-tenant data scoping is
implicit because each function runs against its own project's Firestore.

Endpoints:
  - submit_contact : persist contact form submission
  - submit_vote    : persist a poll vote (idempotent per user/poll)

Both require a FirebaseAuth ID token in `Authorization: Bearer <token>`.
"""
from firebase_admin import initialize_app, auth as fb_auth, firestore
from firebase_functions import https_fn, options
import json

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


def _verify_auth(req: https_fn.Request):
    header = req.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return None
    try:
        decoded = fb_auth.verify_id_token(header[7:])
        return decoded["uid"]
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
