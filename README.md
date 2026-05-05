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

Les configs Firebase (`GoogleService-Info.plist`, `google-services.json`) et les credentials test sont **gitignored**. Pour faire tourner le spike :

1. Créer 2 projets Firebase (`commune-spike-1` et `-2` ou ce que tu veux). Activer **Email/Password** auth + **Firestore** (`europe-west1`, mode test).
2. Récupérer les 4 configs SDK via Firebase CLI et les placer dans `core/firebase/spike-1/` et `core/firebase/spike-2/` :
   ```sh
   firebase apps:create --project <id> IOS --bundle-id be.communesolutions.spike
   firebase apps:create --project <id> ANDROID --package-name be.communesolutions.spike
   firebase apps:sdkconfig --project <id> IOS <APP_ID> > core/firebase/spike-1/GoogleService-Info.plist
   # idem ANDROID + spike-2
   ```
3. Créer 2 users test (un par projet, ex: `demo-a@test.be` et `demo-b@test.be`) via console Firebase ou REST `accounts:signUp`.
4. Seeder Firestore avec des données différentes par tenant : `python3 tools/seed-firestore.py` (passe les Firestore rules en `allow write: if true;` temporairement).
5. Lancer le dev server : `python3 tools/dev-server.py` (sert les manifests + JSONs en HTTP, et un endpoint CF mock).
6. Mettre à jour l'IP du Mac dans `spike/ios/Sources/SpikeApp.swift` et `spike/android/app/src/main/kotlin/be/communesolutions/spike/MainActivity.kt`.
7. iOS : `cd spike/ios && xcodegen generate && xcodebuild -scheme CommuneSpike ...`
8. Android : `cd spike/android && ./gradlew :app:assembleDebug`
9. Dashboard admin web :
   ```sh
   firebase apps:create --project <id> WEB "Commune Spike Web"
   firebase apps:sdkconfig --project <id> WEB <APP_ID> > dashboard/firebase-config-spike-1.json
   # idem pour spike-2
   cd dashboard && python3 -m http.server 8770
   # → http://localhost:8770
   ```

