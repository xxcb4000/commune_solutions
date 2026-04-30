# Commune Solutions

> Plateforme civic tech open source à destination des communes wallonnes.
>
> **Statut** : design + spike technique en cours (avril 2026). Pas de prod.

## Idée

Construire une plateforme **multi-communes** + **architecture à modules** :

- Toute fonctionnalité (sondages, agenda, carte, actualités, services, vie politique, e-guichet…) = module installable
- Communes adoptantes ont chacune leur tenant Firebase, leur sous-domaine `<commune>.communesolutions.be`, leur branding
- Marketplace publique sur `communesolutions.be/marketplace` pour modules officiels + communauté
- Open source (licence EUPL 1.2 sur le core)

L'app actuelle de la commune d'Awans (`commune_awans/` côté repos) est l'**instance pilote** : la même équipe construit la plateforme et son premier déploiement.

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
│   └── info/                    #   - écran statique infos pratiques
├── tenants/                     # Configs tenant (assemblage modules + shell)
│   └── spike/                   #   - tenant de test consommé par le spike
│       └── app.json             #     tabbar pointant vers actualites:feed + info:main
└── spike/                       # Spike technique (validé GO 2026-04-30)
    ├── ios/                     # Consomme core/renderer-ios + bundle modules-official+tenants
    ├── android/                 # Consomme core/renderer-android via project(":renderer")
    ├── dsl-samples/             # Anciens JSON spike (gardés pour référence, plus utilisés)
    ├── SPIKE_PLAN.md
    └── SPIKE_VERDICT.md
```

Le spike reste comme banc de test consommateur de la library — toute évolution du renderer y est validée avant d'être propagée. Le repo continuera à grossir : `sdk/`, `cli/`, `modules-official/`, `dashboard/`, etc.

## Roadmap haut niveau

| Phase | Statut | Description |
|---|---|---|
| 0. Design contrat plateforme | ✅ Fait | `docs/platform.md` — 4 modules officiels passés à la moulinette (Sondages, Carte, Actualités, Agenda) |
| 1. Spike technique DSL renderer | ✅ GO (2026-04-30) | 11 primitives validées sur iVince + device Android. Cf `spike/SPIKE_VERDICT.md` |
| 2. Renderer extrait en library | ✅ Fait | `core/renderer-ios/` (Swift Package) + `core/renderer-android/` (:renderer module). Spike consomme |
| 3. Manifest + structure module + tenant | ✅ Fait | `modules-official/<id>/{manifest.json,screens,data}` + `tenants/<id>/app.json`. ModuleRegistry résout `<module>:<screen>` à la volée |
| 4. Loader HTTP | ✅ Fait (iOS validé) | `AssetPreloader` fetch tenant + manifests + screens + data au démarrage ; cache mémoire, fallback bundle si HTTP injoignable. Spike pointe sur `http://<dev-mac>:8765` |
| 5. CF + data dynamique | ✅ Fait (iOS validé) | Module `agenda` avec `data: { events: "cf:get_events" }` ; preloader appelle `/cf/agenda/get_events` et cache. Backend dev = `tools/dev-server.py` (Python stdlib, pas Firebase encore). Primitive `calendar` ✅ ajoutée |
| 6a. Multi-tenant + persist | ✅ Fait | TenantPicker natif au premier lancement, persistance UserDefaults / SharedPreferences, action DSL `logout`. 2 tenants côte à côte (`spike` / `spike-2`) avec contenu différent |
| 6b. Auth Firebase | ✅ Fait (iOS validé) | 2 projets Firebase (`commune-spike-1`, `-2`), `CommuneFirebase.configure([...])` au démarrage, AuthGate + LoginForm natif par tenant. Tenant config référence son projet Firebase via `firebase: "spike-1"`. Logout sign-out les 2 projets + clear le tenant. Android = même architecture, à plumber (deps Firebase BoM ajoutées) |
| 6c. Firestore par tenant | ✅ Fait (iOS validé) | DSL data source `firestore:<path>` (collection ou doc selon parité du path). 3 modules complètement scopés : `actualites/articles`, `agenda/events`, `info/main`. Chaque tenant lit dans son propre projet Firebase. Seed via `tools/seed-firestore.py`. Rules : read = authed, write = denied côté client |
| 7. Marketplace web + soumission | À faire | Site, validation manifest, capabilities UX, distinction officiel/communauté |
| 4. Premier module extrait d'Awans | — | Probable : Vie politique (le moins critique) |
| 5. Ouverture open source + marketplace v0 | — | Une fois 2-3 modules stables |
| 6. Première commune non-Awans onboardée | — | Validation white-label |

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
3. Créer 2 users test (`awans@test.be`, `jalhay@test.be`) via console Firebase ou REST `accounts:signUp`.
4. Seeder Firestore avec des données différentes par tenant : `python3 tools/seed-firestore.py` (passe les Firestore rules en `allow write: if true;` temporairement).
5. Lancer le dev server : `python3 tools/dev-server.py` (sert les manifests + JSONs en HTTP, et un endpoint CF mock).
6. Mettre à jour l'IP du Mac dans `spike/ios/Sources/SpikeApp.swift` et `spike/android/app/src/main/kotlin/be/communesolutions/spike/MainActivity.kt`.
7. iOS : `cd spike/ios && xcodegen generate && xcodebuild -scheme CommuneSpike ...`
8. Android : `cd spike/android && ./gradlew :app:assembleDebug`

## Lien avec commune_awans/

Le repo `commune_awans/` reste la production en cours (iOS Swift + Android Kotlin + dashboard + backend Firebase). Tant que le spike n'est pas validé, **rien dans Awans ne change**.

Si la plateforme se concrétise, Awans devient la **première instance** : ses fonctionnalités existantes sont progressivement extraites en modules officiels du présent repo.
