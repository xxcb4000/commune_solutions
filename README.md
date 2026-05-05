# Commune Solutions

[![License: EUPL-1.2](https://img.shields.io/badge/License-EUPL--1.2-blue.svg)](LICENSE)

> Plateforme civic tech open source à destination des communes wallonnes.
>
> **Statut** (mai 2026) : pipeline complet validé end-to-end sur 2 tenants de test (Démo A / Démo B). Marketplace, modules communauté, modération UGC, dashboard admin, web preview, auto-deploy CI tous live. Première vraie commune (Awans) pas encore déployée.

**Marketplace live** : [`communesolutions.be/marketplace`](https://communesolutions.be/marketplace) — catalogue des modules (5 officiels + 2 communauté). Preview en navigateur : `…/marketplace/preview.html?module=<id>`.

**Contribuer** : [`CONTRIBUTING.md`](CONTRIBUTING.md) — workflow PR, modules communauté, évolutions core. Guide technique complet : [`docs/developers.md`](docs/developers.md). Code de conduite : [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). Sécurité : [`SECURITY.md`](SECURITY.md).

## Idée

Construire une plateforme **multi-communes** + **architecture à modules** :

- Toute fonctionnalité (sondages, agenda, carte, actualités, services, vie politique, e-guichet…) = module installable
- Communes adoptantes ont chacune leur tenant Firebase, leur sous-domaine `<commune>.communesolutions.be`, leur branding
- Marketplace publique sur `communesolutions.be/marketplace` pour modules officiels + communauté
- Open source (licence EUPL 1.2 sur le core)

La plateforme se construit **en greenfield**. Elle est motivée par l'expérience terrain de la team (apps civic-tech communales déjà en production), mais aucune appli existante n'est migrée — le code, les modules, et le contrat sont écrits from scratch ici.

## Architecture du repo

```
commune_solutions/
├── docs/
│   ├── platform.md              # Design complet de la plateforme (contrat, capabilities, marketplace, …)
│   ├── developers.md            # Guide contributeur (manifest schema, primitives DSL, capabilities v0)
│   ├── roadmap.md               # État exhaustif fait / à faire / décisions ouvertes
│   └── skills/                  # Procédures opérationnelles (DNS commune, …)
├── core/
│   ├── renderer-ios/            # Swift Package — CommuneRenderer (SwiftUI)
│   ├── renderer-android/        # Gradle library — :renderer (Compose)
│   ├── renderer-web/            # 3ème renderer JS — sert /marketplace/preview.html
│   ├── cloud-functions/         # CFs Python (submit_vote, submit_event_proposal, …)
│   └── firebase/                # firebase.json + firestore.rules + storage.rules + per-project SDK configs (gitignored)
├── modules-official/            # Modules officiels (manifest + screens + data + preview-mock)
│   ├── actualites/              #   - feed hero + rows, detail markdown
│   ├── agenda/                  #   - liste + calendar primitive + propose (UGC modéré)
│   ├── sondages/                #   - liste + detail (form radio + scale + cf submit_vote)
│   ├── carte/                   #   - map MapKit/maps-compose, pins par catégorie, detail lieu
│   └── info/                    #   - hero + facts + services
├── modules-community/           # Modules communauté (PRs externes acceptées)
│   ├── associations/            #   - annuaire asbl (data bundlée, MIT)
│   └── restos-locaux/           #   - annuaire restaurants (data bundlée, MIT)
├── modules-template/
│   └── hello-world/             # Squelette cloné par tools/create-commune-module.sh
├── dashboard/                   # Admin web (Firebase SDK CDN, no build) — CRUD modules + branding + modération
├── marketplace/public/          # Site statique catalog + détail module + preview hostée
├── landing/public/              # Page d'accueil communesolutions.be
├── commune-sites/               # Site public par commune (gitignored, généré par build-commune-site.py)
│   └── _template/               # Squelette : index.html branded + AASA + assetlinks.json + firebase.json
├── tenants/                     # Configs tenant (modules activés + tabbar + branding)
│   ├── spike/                   #   - Démo A
│   └── spike-2/                 #   - Démo B
├── tools/                       # Scripts de provisioning, build, deploy, validation
│   ├── create-commune-module.sh #   - scaffold un nouveau module communautaire
│   ├── provision-commune.py     #   - apps SDK + configs + tenant + Firestore _config
│   ├── build-commune-app.sh     #   - build single-commune iOS (.app)
│   ├── build-commune-site.py    #   - matérialise commune-sites/<id>/
│   ├── build-marketplace.py     #   - agrège manifests dans marketplace/public/data/
│   ├── build-site.sh            #   - assemble landing + marketplace + renderer-web + modules dans _site/
│   ├── dev-emulators.sh         #   - lance Firebase emulators (Auth+Firestore+Storage+Functions+UI)
│   ├── seed-firestore.py        #   - seed via firebase-admin SDK (ADC, bypasse rules)
│   ├── set-admin-claim.py       #   - pose le claim admin sur un user
│   └── validate-manifests.py    #   - validate schema (CI)
├── spike/                       # Banc de test multi-tenant (validé GO 2026-04-30)
│   ├── ios/                     #   - CommuneSpike app, picker mode + single-commune mode
│   ├── android/                 #   - idem en Compose
│   ├── SPIKE_PLAN.md
│   └── SPIKE_VERDICT.md
└── .github/workflows/
    ├── validate-manifests.yml   # CI sur PR — valide manifest
    └── deploy-marketplace.yml   # Auto-deploy hosting sur push main si modules-*/ ou marketplace/ change
```

## Roadmap

Vue détaillée + chantiers à venir : [`docs/roadmap.md`](docs/roadmap.md).

**Résumé (mai 2026)** :
- ✅ **Spike technique** validé GO 2026-04-30 — DSL renderer iOS + Android, multi-tenant, auth Firebase, Firestore par tenant
- ✅ **Au-delà du spike** : backend Python réel, form fields DSL, modules officiels (`actualites` / `agenda` / `sondages` / `info` / `carte`), polish editorial validé sur device, marketplace web v0
- 🚧 **Phase 12 — onboarding commune** : build paramétré single-commune ✅, provisioning post-project ✅, CI GitHub Actions ✅, fastlane TestFlight scaffold ✅, DNS sous-domaine + AASA + assetlinks ✅. Reste : test live sur première vraie commune (Awans)
- ✅ **Phase 13 — communauté ouverte** : `modules-community/` + 2 modules exemple, CLI `create-commune-module.sh`, Firebase emulators locaux, capability `cf.external` (contrat manifest), pipeline contributeur exercé end-to-end (PR #1 mergée)
- ✅ **Phase 14 — dashboard édition** : CRUD articles/events/polls/places/info via modal éditeur schema-driven, image upload Storage, branding editor live preview, modération UGC (queue + approve/reject) — exercée live avec « Proposer un événement » dans agenda
- ✅ **Phase 15 — hygiène repo + ouverture publique** : LICENSE EUPL-1.2, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, audit secrets clean
- ✅ **Phase 16 — web renderer** : 3ème renderer JS qui interprète le DSL en HTML/CSS, preview hostée à `communesolutions.be/marketplace/preview.html?module=<id>` avec forms interactifs, calendar grid, map Leaflet — permet aux contributeurs d'itérer sans Xcode/Android Studio

## Setup local

3 chemins selon ce que vous voulez faire :

### A. Contribuer un module communautaire (le plus courant)

**Pré-requis** : compte GitHub, git, Python 3.11+. **Pas besoin** de projet Firebase, d'iPhone ni de compte Apple/Google Developer.

```sh
git clone <votre-fork>
cd commune_solutions
tools/create-commune-module.sh mon-module "Mon Module"
# adapter modules-community/mon-module/ (manifest + screens + data)

# Preview en navigateur (le 3ème renderer rend votre JSON en HTML/CSS) :
bash tools/build-site.sh
cd _site && python3 -m http.server 8765
# → http://localhost:8765/marketplace/preview.html?module=mon-module

# Validation locale + ouvrir une PR
python3 tools/validate-manifests.py
gh pr create
```

Guide complet : [`docs/developers.md`](docs/developers.md).

### B. Provisionner un projet Firebase pour tester sur device

Pour aller plus loin et tester sur un vrai device avec data Firestore, il faut un projet Firebase. Le script `provision-commune.py` automatise toute la chaîne **post-création-de-projet** (apps SDK + configs + tenant + Firestore _config) :

```sh
# Pré-requis manuels (one-shot par projet, hors scope du script) :
#   1. Créer le projet via console Firebase (ex. "commune-mondev")
#   2. Activer Email/Password auth + Firestore (europe-west1) + Storage
#   3. Créer un user test via console + lui poser le claim admin :
#      python3 tools/set-admin-claim.py
#
# Auth :
firebase login
gcloud auth application-default login

# Provision automatique du reste (apps iOS/Android/Web + configs + tenant) :
python3 tools/provision-commune.py mondev --display-name "Mon Dev"

# Build + install + launch single-commune sur iVince (UDID via xcrun devicectl list devices) :
tools/build-commune-app.sh mondev <udid>

# Android : ./gradlew :app:assembleDebug -PcommuneId=mondev (depuis spike/android/)

# Dashboard admin web (point d'entrée pour gérer les modules + contenu) :
cd dashboard && python3 -m http.server 8770
# → http://localhost:8770
```

### C. Dev sans projet Firebase via les emulators

Pour itérer sans dépendance à un vrai projet Firebase (Auth + Firestore + Storage en local) :

```sh
# Terminal 1 : démarre les emulators (UI sur localhost:4000)
tools/dev-emulators.sh

# Terminal 2 : seed les emulators
FIRESTORE_EMULATOR_HOST=localhost:8080 \
  FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 \
  python3 tools/seed-firestore.py

# Build + install Android pointant sur les emulators (Mac host = 10.0.2.2 depuis l'AVD)
cd spike/android && ./gradlew :app:installDebug -PfirebaseEmulatorHost=10.0.2.2
```

(iOS : un flag `--emulator-host` dans `build-commune-app.sh` est planifié — phase ultérieure.)

### Provisionnement réel d'une commune

Pour onboarder une vraie commune sur la plateforme (DNS Infomaniak + sous-domaine `<commune>.communesolutions.be` + record App Store Connect + Universal Links + …), voir [`docs/skills/onboard-commune-dns.md`](docs/skills/onboard-commune-dns.md) et la roadmap [`docs/roadmap.md`](docs/roadmap.md) phase 12.

