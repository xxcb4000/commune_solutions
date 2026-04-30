#!/usr/bin/env python3
"""Seed Firestore with test data per tenant for the Phase 4c spike.

Each tenant Firebase project gets distinct collections so the spike can prove
tenant isolation visually (different data per commune).

Auth: writes go through unauthenticated Firestore REST while rules are open
during the seed window. Re-tighten with `firebase deploy --only firestore:rules`
after seeding (the repo's `firestore.rules` is locked-down: read = authed only,
write = denied).

Usage:
    1. Loosen rules: edit firestore.rules to `allow write: if true;`,
       `firebase deploy --project commune-spike-X --only firestore:rules`.
    2. python3 tools/seed-firestore.py
    3. Re-lock rules and re-deploy.
"""

import json
import sys
import urllib.error
import urllib.request

# ─── Awans (commune-spike-1) ──────────────────────────────────────────

EVENTS_AWANS = [
    {
        "id": "evt-001",
        "title": "Marché aux fleurs",
        "date": "samedi 3 mai · 9h–17h",
        "dateStart": "2026-05-03",
        "location": "Place communale d'Awans",
        "imageUrl": "https://picsum.photos/seed/agenda-marche/900/506",
        "description": (
            "Plus de **30 producteurs locaux** présents le samedi et le dimanche.\n\n"
            "### Au programme\n\n"
            "- Atelier compostage à 14h (samedi)\n"
            "- Animation enfants à 11h (dimanche)\n\n"
            "Entrée libre."
        ),
    },
    {
        "id": "evt-002",
        "title": "Conseil communal d'Awans",
        "date": "lundi 12 mai · 19h30",
        "dateStart": "2026-05-12",
        "location": "Salle du conseil, maison communale",
        "imageUrl": "https://picsum.photos/seed/agenda-conseil/900/506",
        "description": "Séance publique. Ordre du jour : **budget 2026**, plan vélo, rapport PCDR.",
    },
    {
        "id": "evt-003",
        "title": "Concert de printemps",
        "date": "vendredi 16 mai · 20h",
        "dateStart": "2026-05-16",
        "location": "Église de Hognoul",
        "imageUrl": "https://picsum.photos/seed/agenda-concert/900/506",
        "description": "L'Académie de musique d'Awans donne son concert de printemps.",
    },
]

ARTICLES_AWANS = [
    {
        "id": "art-001",
        "title": "Travaux rue de l'Église : du 5 au 20 mai",
        "excerpt": "La rue de l'Église sera fermée à la circulation pendant deux semaines pour la réfection complète du revêtement.",
        "imageUrl": "https://picsum.photos/seed/awans-eglise/900/506",
        "date": "30 avril 2026",
        "isNew": True,
        "body": "## Détails\n\nLa **rue de l'Église** sera fermée du **5 au 20 mai 2026**.\n\n### Déviations\n\n- Par la rue du Centre puis Wérixhas\n- Par la rue Pirombolle\n\nRiverains : accès piéton conservé."
    },
    {
        "id": "art-002",
        "title": "Inscriptions stages d'été ouvertes",
        "excerpt": "Sport, créativité, nature : 12 stages organisés du 1er juillet au 23 août pour les 4–14 ans.",
        "imageUrl": "https://picsum.photos/seed/awans-stages/900/506",
        "date": "26 avril 2026",
        "isNew": True,
        "body": "Les **inscriptions aux stages d'été 2026** sont ouvertes.\n\n### Thématiques\n\n- Multisports (4–8 ans)\n- Cirque (6–12 ans)\n- Robotique (10–14 ans)\n\nTarif communal : **75€/semaine**."
    },
    {
        "id": "art-003",
        "title": "Ramassage encombrants : 13 mai",
        "excerpt": "Inscrivez-vous avant le 6 mai.",
        "imageUrl": "https://picsum.photos/seed/awans-encombrants/900/506",
        "date": "18 avril 2026",
        "isNew": False,
        "body": "Prochain **ramassage** le **mardi 13 mai 2026**. Inscription gratuite mais obligatoire avant le 6 mai au 04/259.92.00."
    },
]

INFO_AWANS = {
    "communeName": "Maison communale d'Awans",
    "address": "Rue Louis Pirsoul 1\n4340 Awans",
    "hoursMd": "**Lundi → vendredi** : 9h–12h\n\n**Mardi** : 14h–18h (permanence guichet)\n\n*Fermé samedi et dimanche.*",
    "contactMd": "Téléphone : **04 / 259 92 00**\n\nE-mail : info@awans.be",
    "headerImageUrl": "https://picsum.photos/seed/awans-mc/900/506",
}

# ─── Jalhay (commune-spike-2) ─────────────────────────────────────────

EVENTS_JALHAY = [
    {
        "id": "evt-101",
        "title": "Brocante communale de Jalhay",
        "date": "dimanche 18 mai · 7h–18h",
        "dateStart": "2026-05-18",
        "location": "Centre de Jalhay",
        "imageUrl": "https://picsum.photos/seed/jalhay-brocante/900/506",
        "description": (
            "**Plus de 200 emplacements** dans tout le centre.\n\n"
            "### Pratique\n\n"
            "- Inscription emplacement : 04 86 10 12\n"
            "- Petit-déjeuner offert aux exposants\n"
        ),
    },
    {
        "id": "evt-102",
        "title": "Marche ADEPS — Lac de la Gileppe",
        "date": "samedi 24 mai · 9h–14h",
        "dateStart": "2026-05-24",
        "location": "Départ Maison du Tourisme",
        "imageUrl": "https://picsum.photos/seed/jalhay-marche/900/506",
        "description": "Trois parcours (5, 10, 20 km) autour du **lac de la Gileppe** et des Hautes Fagnes.",
    },
]

ARTICLES_JALHAY = [
    {
        "id": "art-101",
        "title": "Nettoyage des Hautes Fagnes — appel à bénévoles",
        "excerpt": "Action commune avec Natagora le 10 mai. Bottes et bonne humeur.",
        "imageUrl": "https://picsum.photos/seed/jalhay-fagnes/900/506",
        "date": "29 avril 2026",
        "isNew": True,
        "body": "Action **bénévole** de nettoyage des Hautes Fagnes le **samedi 10 mai 2026**.\n\n### Pratique\n\n- RDV à 9h Maison du Tourisme\n- Sacs et gants fournis\n- Tartes à 13h pour clôturer"
    },
    {
        "id": "art-102",
        "title": "Travaux à la barrière du barrage",
        "excerpt": "Circulation alternée jusqu'au 30 mai.",
        "imageUrl": "https://picsum.photos/seed/jalhay-barrage/900/506",
        "date": "25 avril 2026",
        "isNew": True,
        "body": "Travaux de remise à neuf de la barrière côté **lac de la Gileppe** jusqu'au 30 mai. **Circulation alternée** par feux temporaires."
    },
]

INFO_JALHAY = {
    "communeName": "Maison communale de Jalhay",
    "address": "Rue de la Fagne 1\n4845 Jalhay",
    "hoursMd": "**Lundi → vendredi** : 8h30–12h\n\n**Mardi** : 14h–17h\n\n*Fermé samedi et dimanche.*",
    "contactMd": "Téléphone : **087 / 37 89 89**\n\nE-mail : info@jalhay.be",
    "headerImageUrl": "https://picsum.photos/seed/jalhay-mc/900/506",
}


# ─── Plumbing ────────────────────────────────────────────────────────

def to_fields(d):
    fields = {}
    for k, v in d.items():
        if isinstance(v, bool):
            fields[k] = {"booleanValue": v}
        elif isinstance(v, int):
            fields[k] = {"integerValue": str(v)}
        elif isinstance(v, float):
            fields[k] = {"doubleValue": v}
        elif isinstance(v, str):
            fields[k] = {"stringValue": v}
        else:
            fields[k] = {"stringValue": str(v)}
    return fields


def upsert(project, doc_path, data):
    url = (
        f"https://firestore.googleapis.com/v1/projects/{project}"
        f"/databases/(default)/documents/{doc_path}"
    )
    body = json.dumps({"fields": to_fields(data)}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        method="PATCH",
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req) as resp:
            print(f"  ✓ {project}/{doc_path} ({resp.status})")
    except urllib.error.HTTPError as e:
        print(f"  ✗ {project}/{doc_path}: {e.code} {e.read().decode()}")
        sys.exit(1)


def seed(project, events, articles, info):
    print(f"Seeding {project}…")
    for evt in events:
        upsert(project, f"events/{evt['id']}", evt)
    for art in articles:
        upsert(project, f"articles/{art['id']}", art)
    upsert(project, "info/main", info)


def main():
    seed("commune-spike-1", EVENTS_AWANS, ARTICLES_AWANS, INFO_AWANS)
    seed("commune-spike-2", EVENTS_JALHAY, ARTICLES_JALHAY, INFO_JALHAY)


if __name__ == "__main__":
    main()
