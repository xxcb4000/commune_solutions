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

## Roadmap haut niveau

### Spike (terminé, validé GO 2026-04-30)

| Phase | Statut | Description |
|---|---|---|
| 0. Design contrat plateforme | ✅ Fait | `docs/platform.md` — 4 modules officiels passés à la moulinette (Sondages, Carte, Actualités, Agenda) |
| 1. Spike technique DSL renderer | ✅ GO | 13 primitives natives validées sur iVince + Android device. Cf `spike/SPIKE_VERDICT.md` |
| 2. Renderer extrait en library | ✅ Fait | `core/renderer-ios/` (Swift Package) + `core/renderer-android/` (:renderer module). Spike consomme |
| 3. Manifest + structure module + tenant | ✅ Fait | `modules-official/<id>/{manifest.json,screens,data}` + `tenants/<id>/app.json`. ModuleRegistry résout `<module>:<screen>` à la volée |
| 4. Loader HTTP | ✅ Fait | `AssetPreloader` fetch tenant + manifests + screens + data au démarrage ; cache mémoire, fallback bundle si HTTP injoignable |
| 5. CF + data dynamique | ✅ Fait | Backend dev `tools/dev-server.py` (Python stdlib). Primitive `calendar` ajoutée |
| 6a. Multi-tenant + persist | ✅ Fait | TenantPicker natif, persistance UserDefaults / SharedPreferences, action DSL `logout`. 2 tenants côte à côte (`spike` / `spike-2`) |
| 6b. Auth Firebase | ✅ Fait | 2 projets Firebase, `CommuneFirebase.configure([...])` au démarrage, AuthGate + LoginForm natif par tenant. Logout sign-out + clear tenant |
| 6c. Firestore par tenant | ✅ Fait | DSL data source `firestore:<path>` (collection ou doc). 3 modules scopés : `articles`, `events`, `info/main`. Chaque tenant lit dans son propre projet. Rules : read = authed, write = denied côté client |

### Au-delà du spike (à attaquer en mode prod)

| Phase | Statut | Description |
|---|---|---|
| 7. Backend Python réel | ✅ Fait | `core/cloud-functions/main.py` — 2nd-gen Python CFs (`submit_contact`, `submit_vote`) déployées par projet Firebase, vérification ID token Firebase Auth, écriture Firestore scopée au tenant. iOS + Android routent vers `tenant.functionsBaseURL` quand défini, sinon dev-server. |
| 8. Form fields DSL | ✅ Fait | Primitives `field.email`, `field.secret`, `field.text`, `field.text.long`, `field.yesno`, `field.radio`, `field.scale` + form state + action `cf` |
| 9. Premier vrai module greenfield | ✅ Fait | Module `sondages` construit from scratch sur le contrat (3 sondages, vote via CF, résultats par poll) |
| 10. Dashboard admin commune | ✅ Fait (read-only) | `dashboard/` — single-page HTML + ES modules + Firebase Web SDK (CDN, pas de build). Tenant picker → login → 4 onglets (Sondages, Événements, Actualités, Infos) lus depuis Firestore par tenant. Édition + dashboard DSL-driven = phase ultérieure |
| 11. Marketplace web v0 | ✅ Fait | `marketplace/` — site statique servi à `communesolutions.be/marketplace` via Firebase Hosting (projet `be-mde-commune-notification`, site `commune-solutions`). Catalogue des 4 modules officiels + page détail (capabilities style permissions Android, écrans, auteur, licence). Manifests enrichis (`description`, `author`, `licence`, `capabilities`). Build unifié landing + marketplace via `tools/build-site.sh`. Validation manifest via `tools/validate-manifests.py` |
| 12. Onboarding première commune | À faire | Provisioning auto (Firebase project + sous-domaine + tenant config). Choix de la commune pilote = ouvert |

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

