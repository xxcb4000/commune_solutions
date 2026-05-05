#!/usr/bin/env python3
"""Seed Firestore with test data per tenant for the spike (Phase 4c).

Each tenant Firebase project gets distinct collections so the spike can prove
tenant isolation visually (different data per commune).

Auth: uses Firebase Admin SDK with Application Default Credentials. ADC
bypasses Firestore security rules (admin path), so the locked-down
`firestore.rules` (read = authed, write = denied) doesn't need to be
loosened for seed runs.

Usage:
    1. `gcloud auth application-default login` (one-off)
    2. `python3 tools/seed-firestore.py`
"""

import sys

import firebase_admin
from firebase_admin import credentials, firestore

# ─── Tenant Démo A (commune-spike-1) ──────────────────────────────────

EVENTS_A = [
    {
        "id": "evt-001",
        "title": "Marché aux fleurs",
        "date": "samedi 3 mai · 9h–17h",
        "dateStart": "2026-05-03",
        "location": "Place communale",
        "imageUrl": "https://picsum.photos/seed/demo-a-marche/900/506",
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
        "title": "Conseil communal",
        "date": "lundi 12 mai · 19h30",
        "dateStart": "2026-05-12",
        "location": "Salle du conseil, maison communale",
        "imageUrl": "https://picsum.photos/seed/demo-a-conseil/900/506",
        "description": "Séance publique. Ordre du jour : **budget 2026**, plan vélo, rapport PCDR.",
    },
    {
        "id": "evt-003",
        "title": "Concert de printemps",
        "date": "vendredi 16 mai · 20h",
        "dateStart": "2026-05-16",
        "location": "Église centrale",
        "imageUrl": "https://picsum.photos/seed/demo-a-concert/900/506",
        "description": "Concert de printemps de l'académie de musique communale.",
    },
]

ARTICLES_A = [
    {
        "id": "art-001",
        "title": "Travaux rue Centrale : du 5 au 20 mai",
        "excerpt": "La rue Centrale sera fermée à la circulation pendant deux semaines pour la réfection complète du revêtement.",
        "imageUrl": "https://picsum.photos/seed/demo-a-travaux/900/506",
        "date": "30 avril 2026",
        "dateEyebrow": "nouveau · 30 avril · Travaux",
        "category": "Travaux",
        "isNew": True,
        "body": "## Détails\n\nLa **rue Centrale** sera fermée du **5 au 20 mai 2026**.\n\n### Déviations\n\n- Par la rue du Nord\n- Par la rue du Sud\n\nRiverains : accès piéton conservé."
    },
    {
        "id": "art-002",
        "title": "Inscriptions stages d'été ouvertes",
        "excerpt": "Sport, créativité, nature : 12 stages organisés du 1er juillet au 23 août pour les 4–14 ans.",
        "imageUrl": "https://picsum.photos/seed/demo-a-stages/900/506",
        "date": "26 avril 2026",
        "dateEyebrow": "nouveau · 26 avril · Loisirs",
        "category": "Loisirs",
        "isNew": True,
        "body": "Les **inscriptions aux stages d'été 2026** sont ouvertes.\n\n### Thématiques\n\n- Multisports (4–8 ans)\n- Cirque (6–12 ans)\n- Robotique (10–14 ans)\n\nTarif communal : **75€/semaine**."
    },
    {
        "id": "art-003",
        "title": "Ramassage encombrants : 13 mai",
        "excerpt": "Inscrivez-vous avant le 6 mai.",
        "imageUrl": "https://picsum.photos/seed/demo-a-encombrants/900/506",
        "date": "18 avril 2026",
        "dateEyebrow": "18 avril · Environnement",
        "category": "Environnement",
        "isNew": False,
        "body": "Prochain **ramassage** le **mardi 13 mai 2026**. Inscription gratuite mais obligatoire avant le 6 mai au 04 / 000 00 00."
    },
]

INFO_A = {
    "communeName": "Démo A",
    "tagline": "à votre service depuis 1830",
    "address": "Place communale 1\n4000 Démo A",
    "hours": "Lundi → vendredi  ·  9h – 12h\nMardi (permanence)  ·  14h – 18h\nSamedi & dimanche  ·  fermé",
    "phone": "04 / 000 00 00",
    "email": "info@demo-a.test",
}

PLACES_A = [
    {
        "id": "plc-001",
        "name": "Maison communale",
        "category": "services",
        "categoryLabel": "Services communaux",
        "address": "Place communale 1, 4000 Démo A",
        "meta": "Place communale 1 · ouvert jusqu'à 12h",
        "hours": "Lun → ven · 9h–12h\nMardi (perm.) · 14h–18h",
        "lat": 50.6695,
        "lng": 5.4762,
        "body": "L'**accueil principal** de la commune. État civil, cartes d'identité, permis, urbanisme.",
    },
    {
        "id": "plc-002",
        "name": "École communale du Centre",
        "category": "ecole",
        "categoryLabel": "Écoles",
        "address": "Rue de l'École 14, 4000 Démo A",
        "meta": "Rue de l'École 14 · maternelle + primaire",
        "hours": "Lun → ven · 8h30–15h30 (mer 12h)",
        "lat": 50.6712,
        "lng": 5.4805,
        "body": "Implantation principale du réseau communal. **220 élèves**, sections maternelle et primaire.",
    },
    {
        "id": "plc-003",
        "name": "Centre culturel",
        "category": "culture",
        "categoryLabel": "Culture",
        "address": "Place du Marché 3, 4000 Démo A",
        "meta": "Place du Marché 3 · expositions, concerts",
        "hours": "Mar → sam · 14h–18h\nDim · 14h–17h (selon expo)",
        "lat": 50.6680,
        "lng": 5.4790,
        "body": "Programmation **expositions, concerts, conférences** tout au long de l'année.",
    },
    {
        "id": "plc-004",
        "name": "Hall omnisports",
        "category": "sport",
        "categoryLabel": "Sport",
        "address": "Rue des Sports 12, 4000 Démo A",
        "meta": "Rue des Sports 12 · réservations en ligne",
        "hours": "Lun → ven · 9h–22h\nWeek-end · 9h–18h",
        "lat": 50.6735,
        "lng": 5.4720,
        "body": "Salle omnisports communale. **Réservations** : badminton, basket, futsal, volley.",
    },
    {
        "id": "plc-005",
        "name": "Bibliothèque communale",
        "category": "services",
        "categoryLabel": "Services communaux",
        "address": "Rue Haute 8, 4000 Démo A",
        "meta": "Rue Haute 8 · ouvert mardi → samedi",
        "hours": "Mar–jeu · 14h–18h\nVen · 14h–19h\nSam · 9h–13h",
        "lat": 50.6669,
        "lng": 5.4733,
        "body": "**12 000 ouvrages**. Section jeunesse, fonds régional, presse, ordinateurs publics.",
    },
    {
        "id": "plc-006",
        "name": "Parc des Trois Tilleuls",
        "category": "nature",
        "categoryLabel": "Nature",
        "address": "Avenue des Tilleuls, 4000 Démo A",
        "meta": "Avenue des Tilleuls · plaine de jeux",
        "hours": "Tous les jours · 7h–coucher du soleil",
        "lat": 50.6665,
        "lng": 5.4815,
        "body": "Parc communal **3,2 ha**. Plaine de jeux, vergers, sentiers de promenade, pétanque.",
    },
]

POLLS_A = [
    {
        "id": "poll-001",
        "title": "Plan vélo communal",
        "description": "Aménagement de la mobilité douce — soumis au prochain conseil.",
        "question": "Êtes-vous favorable au plan vélo proposé ?",
        "options": [
            {"id": "yes", "label": "Oui, prioritaire"},
            {"id": "later", "label": "Plus tard"},
            {"id": "no", "label": "Non"},
        ],
    },
    {
        "id": "poll-002",
        "title": "Aire de jeux du parc central",
        "description": "Quel type de structure remplacer en priorité ?",
        "question": "Votre choix de structure ?",
        "options": [
            {"id": "swing", "label": "Balançoires"},
            {"id": "slide", "label": "Toboggan"},
            {"id": "climb", "label": "Mur d'escalade"},
        ],
    },
]

# ─── Tenant Démo B (commune-spike-2) ─────────────────────────────────

EVENTS_B = [
    {
        "id": "evt-101",
        "title": "Brocante communale",
        "date": "dimanche 18 mai · 7h–18h",
        "dateStart": "2026-05-18",
        "location": "Centre communal",
        "imageUrl": "https://picsum.photos/seed/demo-b-brocante/900/506",
        "description": (
            "**Plus de 200 emplacements** dans tout le centre.\n\n"
            "### Pratique\n\n"
            "- Inscription emplacement : 00 00 00 00\n"
            "- Petit-déjeuner offert aux exposants\n"
        ),
    },
    {
        "id": "evt-102",
        "title": "Marche ADEPS",
        "date": "samedi 24 mai · 9h–14h",
        "dateStart": "2026-05-24",
        "location": "Départ Maison du Tourisme",
        "imageUrl": "https://picsum.photos/seed/demo-b-marche/900/506",
        "description": "Trois parcours (5, 10, 20 km) à travers le territoire communal.",
    },
]

ARTICLES_B = [
    {
        "id": "art-101",
        "title": "Nettoyage des sentiers — appel à bénévoles",
        "excerpt": "Action commune avec une asbl locale le 10 mai. Bottes et bonne humeur.",
        "imageUrl": "https://picsum.photos/seed/demo-b-sentiers/900/506",
        "date": "29 avril 2026",
        "dateEyebrow": "nouveau · 29 avril · Environnement",
        "category": "Environnement",
        "isNew": True,
        "body": "Action **bénévole** de nettoyage des sentiers communaux le **samedi 10 mai 2026**.\n\n### Pratique\n\n- RDV à 9h Maison du Tourisme\n- Sacs et gants fournis\n- Goûter à 13h pour clôturer"
    },
    {
        "id": "art-102",
        "title": "Travaux à la barrière du parc",
        "excerpt": "Circulation alternée jusqu'au 30 mai.",
        "imageUrl": "https://picsum.photos/seed/demo-b-parc/900/506",
        "date": "25 avril 2026",
        "dateEyebrow": "nouveau · 25 avril · Travaux",
        "category": "Travaux",
        "isNew": True,
        "body": "Travaux de remise à neuf de la barrière du parc communal jusqu'au 30 mai. **Circulation alternée** par feux temporaires."
    },
]

INFO_B = {
    "communeName": "Démo B",
    "tagline": "votre commune, en plus simple",
    "address": "Rue du Centre 1\n4000 Démo B",
    "hours": "Lundi → vendredi  ·  8h30 – 12h\nMardi (permanence)  ·  14h – 17h\nSamedi & dimanche  ·  fermé",
    "phone": "00 / 00 00 00",
    "email": "info@demo-b.test",
}

PLACES_B = [
    {
        "id": "plc-101",
        "name": "Hôtel de ville",
        "category": "services",
        "categoryLabel": "Services communaux",
        "address": "Rue du Centre 1, 4000 Démo B",
        "meta": "Rue du Centre 1 · administration générale",
        "hours": "Lun → ven · 8h30–12h\nMar (perm.) · 14h–17h",
        "lat": 50.6286,
        "lng": 6.0367,
        "body": "**Hôtel de ville** : tous les services communaux centralisés.",
    },
    {
        "id": "plc-102",
        "name": "Bibliothèque & médiathèque",
        "category": "services",
        "categoryLabel": "Services communaux",
        "address": "Rue Mitoyenne 22, 4000 Démo B",
        "meta": "Rue Mitoyenne 22 · livres, jeux, presse",
        "hours": "Mar–sam · 14h–18h",
        "lat": 50.6310,
        "lng": 6.0335,
        "body": "**Bibliothèque communale** avec section ludothèque (jeux à emprunter).",
    },
    {
        "id": "plc-103",
        "name": "Athénée Royal",
        "category": "ecole",
        "categoryLabel": "Écoles",
        "address": "Rue de l'Athénée 5, 4000 Démo B",
        "meta": "Rue de l'Athénée 5 · primaire + secondaire",
        "hours": "Lun → ven · 8h–16h",
        "lat": 50.6260,
        "lng": 6.0410,
        "body": "**Athénée royal**. Section primaire et secondaire, options sciences et langues.",
    },
    {
        "id": "plc-104",
        "name": "Salle communale",
        "category": "culture",
        "categoryLabel": "Culture",
        "address": "Place du Centre 2, 4000 Démo B",
        "meta": "Place du Centre 2 · concerts, théâtre",
        "hours": "Selon programmation",
        "lat": 50.6298,
        "lng": 6.0380,
        "body": "**Salle polyvalente** communale. Concerts, théâtre amateur, fêtes scolaires.",
    },
    {
        "id": "plc-105",
        "name": "Stade communal",
        "category": "sport",
        "categoryLabel": "Sport",
        "address": "Avenue des Sports 18, 4000 Démo B",
        "meta": "Avenue des Sports 18 · football, athlétisme",
        "hours": "Selon clubs",
        "lat": 50.6325,
        "lng": 6.0290,
        "body": "**Stade communal**. Terrain de foot, piste d'athlétisme, vestiaires modernes.",
    },
    {
        "id": "plc-106",
        "name": "Réserve naturelle des Hautes Fagnes",
        "category": "nature",
        "categoryLabel": "Nature",
        "address": "Sentier Botrange, 4000 Démo B",
        "meta": "Sentier Botrange · randonnée balisée",
        "hours": "Accès libre · sentiers balisés",
        "lat": 50.6240,
        "lng": 6.0455,
        "body": "Accès aux **Hautes Fagnes**. Sentiers balisés, point de vue, guide nature à la maison du parc.",
    },
]

POLLS_B = [
    {
        "id": "poll-101",
        "title": "Sentiers et balisage",
        "description": "Nouveau parcours signalé dans les Hautes Fagnes communales.",
        "question": "Quel type de balisage privilégier ?",
        "options": [
            {"id": "wood", "label": "Bois sculpté"},
            {"id": "metal", "label": "Métal émaillé"},
            {"id": "qr", "label": "QR codes + numérique"},
        ],
    },
]


# ─── Plumbing ────────────────────────────────────────────────────────

def client_for(project):
    """One firebase_admin app per project — each has its own Firestore client."""
    app = firebase_admin.initialize_app(
        credentials.ApplicationDefault(),
        {"projectId": project},
        name=project,
    )
    return firestore.client(app)


def upsert(db, project, collection, doc_id, data):
    try:
        db.collection(collection).document(doc_id).set(data, merge=True)
        print(f"  ✓ {project}/{collection}/{doc_id}")
    except Exception as e:
        print(f"  ✗ {project}/{collection}/{doc_id}: {e}")
        sys.exit(1)


def seed(project, events, articles, info, polls, places):
    print(f"Seeding {project}…")
    db = client_for(project)
    for evt in events:
        upsert(db, project, "events", evt["id"], evt)
    for art in articles:
        upsert(db, project, "articles", art["id"], art)
    upsert(db, project, "info", "main", info)
    for poll in polls:
        upsert(db, project, "polls", poll["id"], poll)
    for place in places:
        upsert(db, project, "places", place["id"], place)


def main():
    seed("commune-spike-1", EVENTS_A, ARTICLES_A, INFO_A, POLLS_A, PLACES_A)
    seed("commune-spike-2", EVENTS_B, ARTICLES_B, INFO_B, POLLS_B, PLACES_B)


if __name__ == "__main__":
    main()
