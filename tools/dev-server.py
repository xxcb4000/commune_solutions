#!/usr/bin/env python3
"""Dev server for the Commune Solutions spike.

Serves the platform repo root statically AND a few CF-style endpoints under
`/cf/<module-id>/<endpoint>`. The spike app consumes both:
- Static: `/tenants/<id>/app.json`, `/modules-official/<id>/manifest.json`, etc.
- CF: e.g. `/cf/agenda/get_events` returning JSON.

Run from the repo root:
  python3 tools/dev-server.py
"""

import json
import os
import sys
from datetime import datetime, timezone
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

PORT = 8765
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def cf_agenda_get_events():
    fetched_at = datetime.now(timezone.utc).strftime("%H:%M:%S")
    return [
        {
            "id": "evt-001",
            "title": "Marché aux fleurs",
            "date": "samedi 3 mai · 9h–17h",
            "dateStart": "2026-05-03",
            "location": "Place communale",
            "imageUrl": "https://picsum.photos/seed/agenda-marche/900/506",
            "description": (
                "Plus de **30 producteurs locaux** présents le samedi et le dimanche.\n\n"
                "### Au programme\n\n"
                "- Atelier compostage à 14h (samedi)\n"
                "- Animation enfants à 11h (dimanche)\n"
                "- Restauration sur place\n\n"
                "Entrée libre, parking gratuit derrière la maison communale."
            ),
            "fetchedAt": fetched_at,
        },

        {
            "id": "evt-002",
            "title": "Conseil communal — séance publique",
            "date": "lundi 12 mai · 19h30",
            "dateStart": "2026-05-12",
            "location": "Salle du conseil, maison communale",
            "imageUrl": "https://picsum.photos/seed/agenda-conseil/900/506",
            "description": (
                "Séance publique du conseil communal.\n\n"
                "### Ordre du jour\n\n"
                "- Approbation du PV de la séance précédente\n"
                "- Présentation du **budget 2026**\n"
                "- Plan communal de mobilité — volet vélo\n"
                "- Rapport annuel PCDR\n"
                "- Questions des conseillers\n\n"
                "Citoyens bienvenus depuis la tribune."
            ),
            "fetchedAt": fetched_at,
        },

        {
            "id": "evt-003",
            "title": "Concert de printemps de l'Académie",
            "date": "vendredi 16 mai · 20h",
            "dateStart": "2026-05-16",
            "location": "Église centrale",
            "imageUrl": "https://picsum.photos/seed/agenda-concert/900/506",
            "description": (
                "L'Académie de musique communale donne son concert de printemps.\n\n"
                "### Au programme\n\n"
                "- Ensemble cordes (élèves intermédiaires)\n"
                "- Ensemble vocal\n"
                "- Quatuor à vents\n"
                "- Pièce collective : Vivaldi, *Printemps*\n\n"
                "Entrée libre, collecte au profit du voyage scolaire des élèves."
            ),
            "fetchedAt": fetched_at,
        },

        {
            "id": "evt-004",
            "title": "Distribution de compost",
            "date": "samedi 24 mai · 9h–16h",
            "dateStart": "2026-05-24",
            "location": "Parc à conteneurs",
            "imageUrl": "https://picsum.photos/seed/agenda-compost/900/506",
            "description": (
                "Distribution **gratuite** de compost mature au parc à conteneurs.\n\n"
                "### À savoir\n\n"
                "- Réservé aux habitants de la commune (carte d'identité)\n"
                "- Maximum 200 litres par ménage\n"
                "- Apportez vos sacs ou bidons\n"
                "- Pelles disponibles sur place"
            ),
            "fetchedAt": fetched_at,
        },

    ]


CF_GET_ENDPOINTS = {
    "agenda/get_events": cf_agenda_get_events,
}


def cf_info_submit_contact(payload):
    """Echoes the submission and logs to stdout.

    Real prod = persist to Firestore + send email. Spike = print + ack.
    """
    print(f"[contact] {payload!r}", flush=True)
    return {"ok": True, "received": payload}


CF_POST_ENDPOINTS = {
    "info/submit_contact": cf_info_submit_contact,
}


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=REPO, **kwargs)

    def do_GET(self):
        if self.path.startswith("/cf/"):
            endpoint = self.path[len("/cf/"):]
            handler = CF_GET_ENDPOINTS.get(endpoint)
            if handler is None:
                self.send_error(404, f"Unknown CF GET endpoint: {endpoint}")
                return
            payload = handler()
            body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "max-age=60, public")
            self.end_headers()
            self.wfile.write(body)
            return
        super().do_GET()

    def do_POST(self):
        if not self.path.startswith("/cf/"):
            self.send_error(404, f"Unknown route: {self.path}")
            return
        endpoint = self.path[len("/cf/"):]
        handler = CF_POST_ENDPOINTS.get(endpoint)
        if handler is None:
            self.send_error(404, f"Unknown CF POST endpoint: {endpoint}")
            return
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b""
        try:
            payload = json.loads(raw.decode("utf-8")) if raw else {}
        except json.JSONDecodeError:
            self.send_error(400, "Invalid JSON body")
            return
        result = handler(payload)
        body = json.dumps(result, ensure_ascii=False).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    print(f"Dev server: http://0.0.0.0:{PORT}", flush=True)
    print(f"  Repo root: {REPO}", flush=True)
    print(f"  CF GET : {list(CF_GET_ENDPOINTS.keys())}", flush=True)
    print(f"  CF POST: {list(CF_POST_ENDPOINTS.keys())}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    sys.exit(main())
