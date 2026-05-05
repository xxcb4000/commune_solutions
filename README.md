# Commune Solutions

[![License: EUPL-1.2](https://img.shields.io/badge/License-EUPL--1.2-blue.svg)](LICENSE)

> Plateforme civic tech open source à destination des communes wallonnes.
>
> **Statut** : design + spike technique en cours (avril 2026). Pas de prod.

**Contribuer** : [`CONTRIBUTING.md`](CONTRIBUTING.md) — workflow PR, modules communauté, évolutions core. Code de conduite : [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). Sécurité : [`SECURITY.md`](SECURITY.md).

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
│   └── platform.md              # Design complet de la plateforme
├── core/                        # Bibliothèques platform (extraites du spike post-GO)
│   ├── renderer-ios/            # Swift Package — module CommuneRenderer (entrée: CommuneShell)
│   └── renderer-android/        # Gradle library — :renderer (entrée: CommuneShell)
├── modules-official/            # Modules officiels (manifest + screens + data)
│   ├── actualites/              #   - feed + détail articles
│   ├── agenda/                  #   - liste + détail events + calendar primitive
│   ├── sondages/                #   - liste + détail polls (radio + scale)
│   └── info/                    #   - infos pratiques + form contact
├── dashboard/                   # Shell admin web (read-only Firestore par tenant)
├── tenants/                     # Configs tenant (assemblage modules + shell)
│   └── spike/                   #   - tenant de test consommé par le spike
│       └── app.json             #     tabbar pointant vers actualites:feed + info:main
└── spike/                       # Spike technique (validé GO 2026-04-30)
    ├── ios/                     # Consomme core/renderer-ios + bundle modules-official+tenants
    ├── android/                 # Consomme core/renderer-android via project(":renderer")
    ├── SPIKE_PLAN.md
    └── SPIKE_VERDICT.md
```

Le spike reste comme banc de test consommateur de la library — toute évolution du renderer y est validée avant d'être propagée. Le repo continuera à grossir : `sdk/`, `cli/`, `modules-official/`, `dashboard/`, etc.

## Roadmap

Vue détaillée + chantiers à venir : [`docs/roadmap.md`](docs/roadmap.md).

**Résumé** :
- ✅ **Spike technique** validé GO 2026-04-30 — DSL renderer iOS + Android, multi-tenant, auth Firebase, Firestore par tenant
- ✅ **Au-delà du spike** : backend Python réel, form fields DSL, modules `sondages` / `info` / `actualites` / `agenda` / `carte`, dashboard admin commune (toggle modules), marketplace web v0, polish editorial
- ⏭ **Phase 12 — onboarding commune** : pipeline CI build par commune, provisioning Firebase auto, sous-domaine, choix commune pilote
- ⏭ **Phase 13 — communauté ouverte** : `modules-community/`, capability `cf.external`, CLI `create-commune-module`, emulator local
- ⏭ **Phase 14 — dashboard édition** : passer du toggle modules au CRUD contenu (articles, events, polls)
- ✅ **Phase 15 — hygiène repo + ouverture publique** : LICENSE EUPL-1.2, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, audit secrets clean

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

