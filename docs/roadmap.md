# Roadmap

> Vue exhaustive de l'état d'avancement et des chantiers à venir. Le README garde une vue résumée et renvoie ici pour le détail.
>
> Convention : `✅ fait` · `🚧 en cours` · `⏭ à faire` · `🤔 décision ouverte`

## 1. Fait

### Spike technique (validé GO 2026-04-30 — cf [`spike/SPIKE_VERDICT.md`](../spike/SPIKE_VERDICT.md))

| # | Phase | Notes |
|---|---|---|
| 0 | Design contrat plateforme | [`docs/platform.md`](platform.md) — 4 modules officiels passés à la moulinette |
| 1 | Spike DSL renderer iOS + Android | 13 primitives natives validées sur device |
| 2 | Renderer extrait en library | `core/renderer-ios/` (Swift Package) + `core/renderer-android/` (`:renderer`) |
| 3 | Manifest + structure module + tenant | `modules-official/<id>/`, `tenants/<id>/`, ModuleRegistry runtime |
| 4 | Loader HTTP + cache | `AssetPreloader` fetch tenant + manifests + screens + data, fallback bundle |
| 5 | CF + data dynamique | `tools/dev-server.py` Python stdlib, primitive `calendar` |
| 6a | Multi-tenant + persist | TenantPicker natif, action DSL `logout`, 2 tenants côte à côte |
| 6b | Auth Firebase | 2 projets, `CommuneFirebase.configure()`, AuthGate + LoginForm natif par tenant |
| 6c | Firestore par tenant | DSL data source `firestore:<path>`, rules locked-down (read = authed, write = denied) |

### Au-delà du spike

| # | Phase | Notes |
|---|---|---|
| 7 | Backend Python réel | `core/cloud-functions/main.py` — 2nd-gen Python CFs, vérification ID token, écriture Firestore scopée tenant |
| 8 | Form fields DSL | `field.email/secret/text/text.long/yesno/radio/scale` + form state + action `cf` |
| 9 | Premier module greenfield | `sondages` construit from scratch sur le contrat, vote via CF, résultats par poll |
| 10 | Dashboard admin commune (read-only) | `dashboard/` HTML + ES modules + Firebase Web SDK CDN, 4 onglets read |
| 11 | Marketplace web v0 | Site statique sur `communesolutions.be/marketplace`, catalogue + détail capabilities, build unifié landing + marketplace |
| 11.2 | Doc dev + template + CI | [`docs/developers.md`](developers.md), `modules-template/hello-world/`, workflow CI sur les manifests |
| 11.3 | Tenant config Firestore + dashboard activation | Modules + tabbar dans `_config/modules`, public read + admin write, dashboard onglet Modules toggle |
| 11.4 | Polish editorial | Direction civic-editorial sur les 5 modules officiels — primitives `header` (hero), `map` (MapKit/maps-compose stub), styles serif, primitives layout enrichies |
| 11.5 | Module carte | Premier module avec primitive native non-triviale (MKMapView iOS, stub Android), pins par catégorie, detail single-place |

## 2. Phases prioritaires à faire

### 12. Onboarding première commune

Le morceau qui fait passer la plateforme du spike au déploiement réel. Décomposition :

- **🚧 12.1 — Build paramétré par commune** (en cours, validé end-to-end iOS + Android)
  - ✅ Section `build` (`bundleId`, `displayName`) ajoutée à `tenants/<id>/app.json`
  - ✅ iOS : `tools/build-commune-app.sh <commune-id> [device-id]` génère un `project.commune.yml` patché à partir de `project.yml`, lance xcodegen + xcodebuild, optionnellement install + launch via devicectl. Validé sur iVince avec tenant `spike` (single-commune mode, picker skip)
  - ✅ Android : `./gradlew :app:assembleDebug -PcommuneId=<id>` lit `tenants/<id>/app.json` via JsonSlurper, applique `applicationId` + `resValue("string", "app_name", …)` + `buildConfigField` `COMMUNE_TENANT_ID` / `COMMUNE_FIREBASE_PROJECTS`. APK validé avec "Démo A" baké en label
  - ✅ Mode dev (multi-tenant picker) intact : sans flag/env, projects.yml + build.gradle.kts produisent l'app actuelle
  - ⏭ Injection `GoogleService-Info.plist` / `google-services.json` per-commune (actuellement les 2 sont bundlés via le sources block — à filtrer par `firebase` du tenant)
  - ⏭ Icône d'app + launch screen variables par commune
  - ⏭ Agrégation `NS*UsageDescription` + `<uses-permission>` depuis les modules activés (cf platform.md `device.permissions`)
- **🚧 12.2 — Provisioning auto commune (post-project)** : `tools/provision-commune.py <commune-id> --display-name <nom>` automatise tout ce qui est répétable APRÈS création manuelle du projet Firebase :
  - ✅ Vérifie projet existe (`firebase projects:list --json`)
  - ✅ Crée apps iOS / Android / Web (idempotent — détecte par bundle/package/displayName)
  - ✅ Télécharge SDK configs (`firebase apps:sdkconfig --out`) vers `core/firebase/<id>/` + `dashboard/firebase-config-<id>.json`
  - ✅ Génère `tenants/<id>/app.json` starter (modules par défaut: actualites + agenda + info, tabbar correspondante, branding)
  - ✅ Initialise `_config/modules` dans Firestore via firebase-admin SDK + ADC
  - ⏭ Hors scope (skill séparé à venir) : `firebase projects:create`, activation Firestore/Auth/Functions, custom claim admin, deploy CFs + rules
- **🚧 12.3 — CI GitHub Actions** : `.github/workflows/build-commune-app.yml`
  - ✅ Trigger `workflow_dispatch` avec input `commune_id`
  - ✅ Job iOS sur `macos-latest` : xcodegen + xcodebuild via `tools/build-commune-app.sh` (avec `CODE_SIGNING_ALLOWED=NO` quand `CI=true`)
  - ✅ Job Android sur `ubuntu-latest` : `./gradlew :app:assembleDebug -PcommuneId=<id>`
  - ✅ Decode des Firebase configs depuis les secrets de l'environment GitHub correspondant (`FIREBASE_IOS_CONFIG`, `FIREBASE_ANDROID_CONFIG` en base64)
  - ✅ Upload des artifacts (`.app` non signé + APK debug-signé)
  - ⏭ Test live (workflow run réel) : pas encore — nécessite création d'un environment GitHub avec les secrets
  - ⏭ Trigger automatique sur tag pattern (style `commune-<id>-v*`) : à activer plus tard
  - ⏭ Signature distribution (IPA prêt pour TestFlight) = phase 12.4
- **🚧 12.4 — Distribution stores iOS (TestFlight)** : scaffolding fastlane écrit
  - ✅ `Gemfile` + `fastlane/{Appfile,Fastfile,README.md}` + `.env.fastlane.example`
  - ✅ Lane `archive commune_id:<id>` : build .ipa signée App Store, sans upload
  - ✅ Lane `testflight commune_id:<id>` : build + upload TestFlight
  - ✅ Auth via App Store Connect API key (clé Mosa Data Engineering existante : `AuthKey_JD5MN9XL6W.p8`, key ID + issuer ID documentés dans le README)
  - ✅ Bundle ID + display name lus dynamiquement depuis `tenants/<id>/app.json`
  - ✅ `tools/build-commune-app.sh --no-build` pour permettre à fastlane (gym) de prendre le relais
  - ⏭ Test live (lane testflight sur tenant `spike`) : pas encore — nécessite création du record App Store Connect pour `be.communesolutions.spike`
  - ⏭ Workflow CI `release-commune-app.yml` : à écrire après validation du lane local
- **⏭ 12.4b — Distribution Google Play** : `fastlane supply` + service account JSON pour Play Console
- **🚧 12.5 — Sous-domaine + Universal Links / App Links**
  - ✅ Template `commune-sites/_template/` : landing branded + AASA + assetlinks.json + firebase.json
  - ✅ `tools/build-commune-site.py <commune-id>` : matérialise `commune-sites/<commune-id>/` depuis `tenants/<commune-id>/app.json`. Substitue label, dots, bundle ID, Apple Team ID
  - ✅ Skill doc `docs/skills/onboard-commune-dns.md` — étapes manuelles DNS Infomaniak + Firebase Hosting custom domain (vérification TXT, A records, SSL Let's Encrypt, troubleshooting)
  - ✅ AASA + assetlinks.json servis avec `Content-Type: application/json` (sinon iOS/Android refusent)
  - ⏭ Automation Infomaniak DNS API + Firebase Hosting custom domain API → quand on aura > 5 communes en prod (pas justifié avant)
  - ⏭ Compléter sha256_cert_fingerprints Android dans assetlinks.json après premier build release signé (cf phase 12.4)
- **⏭ Universal Links / App Links à l'échelle** : `apple-app-site-association` mutualisé sur `communesolutions.be` 🤔 (cf décision ouverte platform.md)
- **⏭ Choix commune pilote** : à arbitrer

### 13. Communauté ouverte (premier module tiers)

Tout le pipeline contributeur n'existe que sur papier. À matérialiser :

- **🚧 13.1 — Dossier `modules-community/` + module exemple** (fait)
  - ✅ `modules-community/README.md` : différences officiel ↔ communauté, workflow soumission
  - ✅ Module exemple `associations` (annuaire des asbl, MIT, capabilities=[], data bundlée — exemple le plus simple)
  - ✅ Loader iOS + Android étendu : 2 roots (`modules-official` prioritaire, fallback `modules-community`). `ModuleRegistry` track le root par module. `screenPath` / `dataPath` retournent des chemins complets
  - ✅ Spike iOS bundle `modules-community/` (project.yml sources). Android symlink dans assets
  - ✅ Marketplace : 6 modules listés (5 officiels + 1 communauté), filtre Communauté désormais peuplé
  - ✅ Bug fix : préfixe data static `module:` corrigé en `@` dans hello-world template + docs/developers.md (les renderers utilisaient `@` mais la doc disait `module:`)
- **✅ 13.2 — CLI `create-commune-module`** : `tools/create-commune-module.sh <id> [<display-name>]` clone `modules-template/hello-world` vers `modules-community/<id>/` avec manifest pré-rempli (id, displayName, license MIT). Validation kebab-case + détection collisions. README minimal généré dans le module. Documenté dans `docs/developers.md`
- **🚧 13.3 — Emulator local Firebase**
  - ✅ `firebase.json` étendu avec block `emulators` (Auth 9099, Firestore 8080, Functions 5001, UI 4000)
  - ✅ `CommuneFirebase.configure(_, emulatorHost:)` — iOS + Android, route Auth + Firestore SDK vers les emulators si host fourni
  - ✅ SpikeApp.swift lit `FirebaseEmulatorHost` depuis Info.plist ; MainActivity.kt lit `BuildConfig.FIREBASE_EMULATOR_HOST` (Gradle property `-PfirebaseEmulatorHost=10.0.2.2`)
  - ✅ `tools/dev-emulators.sh` lance les emulators
  - ✅ `seed-firestore.py` respecte automatiquement `FIRESTORE_EMULATOR_HOST` / `FIREBASE_AUTH_EMULATOR_HOST` (firebase-admin natif)
  - ✅ Workflow documenté dans `docs/developers.md`
  - ⏭ Flag `--emulator-host` dans `build-commune-app.sh` (iOS) pour exposer la même UX qu'Android
  - ⏭ DSL hot-reload : pull-to-refresh existant suffit en MVP. Live-reload via WebSocket = future si la friction est réelle
- **🚧 13.4 — Capability `cf.external`** (contrat manifest seul, routing renderer différé)
  - ✅ Validator `tools/validate-manifests.py` reconnaît `cf.external` dans `ALLOWED_CAP_TYPES`
  - ✅ Champ top-level `cfExternal: { baseURL }` validé en https
  - ✅ Cohérence cross-checked : capability cf.external **doit** matcher cfExternal.baseURL et inversement (target == baseURL)
  - ✅ Documenté dans `docs/developers.md` (section dédiée + ⚠️ statut "contrat OK, routing à venir")
  - ⏭ Routing renderer (iOS + Android) : action DSL `cf:<endpoint>` route vers `cfExternal.baseURL/<endpoint>` au lieu de `tenant.functionsBaseURL` — implémenté quand un premier module en a besoin
  - ⏭ Marketplace : afficher la capability `cf.external` avec l'URL en clair dans le détail module (Android-style permission preview) — UI à enrichir
- **🤔 Repo split** : `commune_solutions` (plateforme + officiels) vs `commune_solutions-modules-community` (PRs tiers) — décision à prendre selon le rythme d'arrivée des contribs

### 14. Dashboard admin — passer en édition

Aujourd'hui le dashboard ne fait que **toggle des modules** + lecture des collections. Pour qu'une commune soit autonome :

- **✅ 14.1 + 14.3 — CRUD articles + events**
  - Modal éditeur HTML5 `<dialog>` schema-driven (champs configurables par schema JS)
  - Schémas définis pour `articles` et `events`
  - Auto-ID Firestore + sync `id` field, suppression avec confirm, refresh auto
  - Firestore rules : ouverture admin write sur articles, events, polls, places, info — déployées sur spike-1 + spike-2
- **🚧 14.2 — Image upload Firebase Storage**
  - ✅ Type field `image` dans les schémas (articles, events) avec preview live
  - ✅ Lazy import `firebase-storage`, upload vers `uploads/<folder>/<filename>` avec timestamp + suffix random
  - ✅ Storage rules `core/firebase/storage.rules` (admin-only write sur `uploads/`, citizens read)
  - ✅ Storage emulator port 9199 dans firebase.json
  - ⏭ **Activation manuelle Storage** dans la console Firebase (commune-spike-1 + spike-2 → Storage → Get Started, region europe-west1) — pré-requis avant deploy storage rules + test upload live
- **✅ 14.4 — Polls CRUD** : éditeur avec options dynamiques (input id + label, bouton + Ajouter, bouton × supprimer ligne)
- **✅ 14.5 — Places CRUD** : éditeur avec lat/lng (`type: number`), category select limité aux 5 valeurs MapBlock (services/ecole/sport/culture/nature)
- **✅ 14.6 — Info CRUD** : pattern singleton (`schema.singleton: true`, doc id fixe `info/main`, pas de + Nouveau, pas de Supprimer)
- **🚧 14.7 — Branding editor** (onboarding admin partiel)
  - ✅ Onglet « Branding » dans le dashboard, édite `_config/modules.view.brand` (label, textColor, dots[6])
  - ✅ Live preview de la signature visuelle (label serif + 6 ronds colorés)
  - ✅ Color pickers natifs HTML5 pour les dots
  - ✅ Save préserve modules + tabs (merge ciblé sur view.brand)
  - ⏭ Logo upload (pas de slot logo dans le brand schema actuellement — à étendre quand le mobile rendra un logo)
  - ⏭ First-time wizard "vous n'avez pas encore configuré votre commune" — à faire quand on onboarde la première vraie commune (Awans), pour valider la friction réelle
- **✅ 14.8 — Modération UGC** (exercé live avec « Proposer un événement »)
  - ✅ Capability `moderation` reconnue par le validator + champ top-level `moderation: [{collection, label}]` cross-validated
  - ✅ Convention queue unifiée `_moderation_queue/<id>` avec shape standard `{targetCollection, payload, moduleId, submittedBy, submittedAt}` + champ `_summary` optionnel pour l'aperçu admin
  - ✅ Firestore rules : `_moderation_queue` admin read+delete, write réservé aux CFs (Admin SDK), déployées sur spike-1 + spike-2
  - ✅ Dashboard onglet « Modération » : aggregator unifié, badge module, summary, boutons Approuver / Rejeter, gestion permission-denied
  - ✅ Pattern documenté dans `docs/developers.md` (capabilities + section dédiée pipeline)
  - ⏭ Premier module officiel qui produit de l'UGC — exercera le pattern en réel et pourra surfacer les ajustements (rate limit, audit log rejets, notifications citoyens, etc.)
- **🤔 Dashboard DSL-driven** : appliquer le même contrat plateforme au dashboard que côté mobile (modules contribuent à des extension points dashboard) — cf platform.md

### 17. Compléter le DSL (primitives + manifest features)

Le contrat plateforme (cf [`docs/platform.md`](platform.md)) décrit un DSL plus large que ce qui est shippé en v0. À mesure que des modules (officiels ou communautaires) en auront besoin, on complétera. **Ordre suggéré** :

**Primitives utiles probables (priorité haute)** :
- ⏭ `field.date` / `field.date.range` — la plupart des formulaires civic en ont besoin (proposition event date, période de consultation, …)
- ⏭ `field.photo` — UGC avec image (signalements, suggestions de lieux)
- ⏭ `field.checkbox` — choix multiples (vs radio choix unique)
- ⏭ `device.share` (action) — partager un article/event via l'OS
- ⏭ `device.addToCalendar` — exporter event vers calendrier OS
- ⏭ `toast` (action) — feedback transactionnel court (déjà câblé dans CF onSuccess.toast côté form, manque comme action standalone)
- ⏭ `divider` — séparateur visuel léger

**Primitives utiles mais plus de scope (priorité moyenne)** :
- ⏭ `device.scan.qr` — scan QR (parking, codes monument, billetterie)
- ⏭ `device.camera.capture` — photo libre (couplée field.photo ou pure)
- ⏭ `field.map.picker` — placer un pin sur la map (UGC signalement avec lieu)
- ⏭ `field.address` / `field.street` / `field.phone` — typed fields avec validation native
- ⏭ `grid` — layout grille (vs flexbox vstack/hstack)
- ⏭ `alert` — modal alert critique
- ⏭ `badge` — accessoire visuel (count, status)

**Primitives priorité basse / cas exotiques** :
- ⏭ `section` — wrapper sémantique dans un vstack (peu d'utilité)
- ⏭ `switch` (multi-case) — segmented suffit en pratique
- ⏭ `module:` (data source cross-module) — design ouvert, attend un cas réel

**Manifest features designées mais pas livrées** (cf [`docs/platform.md`](platform.md) § scope warning) :
- ⏭ `secrets` (Google Secret Manager) — clés API tierces (météo, OpenAI, Facebook), sortie sécurisée du dashboard
- ⏭ `scheduledJobs` (Cloud Scheduler) — sync auto contenus depuis APIs externes
- ⏭ `deepLinks` — registry Universal Links / FCM routing par module (avec validation collision en CI)
- ⏭ `publicEndpoints` — routes HTTP exposées aux tiers (iCal export agenda, JSON feed actualités)
- ⏭ `config.ui` form-driven — formulaire de config par module dans le dashboard, vs UI codée à la main
- ⏭ `ownedCollections` + `moderation: true` complet — pattern actuellement simplifié à `_moderation_queue`, étendre avec champs auto-injectés (status/visible/proposed_by/moderated_by/...) quand 2-3 modules le justifieront

**Stratégie** : pas de phase dédiée bloquante — chaque primitive s'ajoute quand un module concret en a besoin. La PR qui ajoute la primitive doit aussi documenter son rendu dans les 3 renderers (iOS, Android, web) et son schéma manifest. Cf platform.md § Extension points pour le pattern de contribution.

### 18. Architecture cross-cutting (designée dans platform.md, 0-50% livrée)

Au-delà des primitives DSL et des champs manifest simples (phase 17), [`docs/platform.md`](platform.md) décrit des features **transversales** qui touchent renderer + CF + dashboard + build pipeline. Pas livrées en v0, à développer quand un cas concret le justifie.

- **⏭ 18.1 Extension points cross-module** (cf platform.md §410) — modules hôtes déclarent des extension points avec contrat versionné, autres modules contribuent via leur section `extensions`. Stratégies d'agrégation : `priority-merge`, `round-robin`, `concat`, `first-match`. Versioning des contrats. Permet la composition modulaire (ex: actualités feed avec topCards contribués par sondages, dashboard moderation queue agrégée par tous les modules avec UGC). **Bloquant** pour les UI riches multi-modules. Roadmap dépend du 1er cas concret de composition.

- **⏭ 18.2 Modération UGC — pattern complet** (cf platform.md §604) — champs auto-injectés (`status`/`visible`/`proposed_by`/`proposed_by_email`/`proposed_at`/`moderated_by`/`moderated_at`/`moderation_reason`), RLS standards (citoyens créent en pending, anonymes lisent visible: true), sync auto `status` ↔ `visible`, CFs standardisées `<module>.list_pending` / `.approve(id)` / `.reject(id, reason)`. **V0 actuel** : queue simple `_moderation_queue/<id>` + approve/reject manuel dashboard (suffisant pour 1 module). Étendre quand 2-3 modules UGC le justifient.

- **⏭ 18.3 Capability runtime check** — le renderer + les CFs vérifient à runtime que le module a bien la capability requise pour l'opération demandée. Aujourd'hui : capabilities déclarées dans manifest et reconnues par le validator, mais pas appliquées au runtime (un module peut techniquement appeler une CF qu'il n'a pas déclarée). Implémenter middleware CF (decorator Python qui check `request.module_id` + capability whitelist) et runtime guard dans les renderers (refuser action si capability absente).

- **⏭ 18.4 Permissions device aggregation au build** (cf platform.md §627) — chaque module déclare ses `device.permissions` (location, camera, notifications, contacts, calendar, bluetooth, motion). Le pipeline CI build commune **agrège** ces permissions et génère :
  - iOS Info.plist : `NSLocationWhenInUseUsageDescription`, `NSCameraUsageDescription`, etc. avec la justification du module
  - Android Manifest : `<uses-permission>` correspondants
  Une commune sans le module n'a PAS la permission dans son binaire (« pas dans le binaire » = pas de mauvaise expérience App Store review). Bloquant pour modules avec camera (signalements UGC photo), location (carte centrée user), notifications.

- **⏭ 18.5 Deep-links integration complète** (cf platform.md §502) — au-delà des templates AASA + assetlinks générés par `build-commune-site.py` :
  - Validation collision : CI refuse une PR si deux modules claim la même route `/article/{id}` (déjà spec'd, à implémenter dans `validate-manifests.py`)
  - Aggregation au build : pour chaque commune, l'AASA déployé liste TOUTES les routes de TOUS les modules activés
  - FCM routing : payload `{ category, ...params }` → table de mapping → écran cible mobile (legacy alias pour compat avec apps existantes)

- **⏭ 18.6 Cache strategy** (cf platform.md §649) — au-delà du Firestore SDK offline cache natif et de l'AsyncImage cache utilisés par défaut :
  - Cache-Control headers explicites sur les responses CFs (immutable pour les actualités finalisées, max-age court pour les agendas, no-cache pour les sondages live)
  - Stale-while-revalidate côté client quand le mobile appelle une CF sans réseau (afficher la valeur cachée ET déclencher un refresh en arrière-plan)
  - Cache éviction par tenant (changement branding → invalider la home)

- **⏭ 18.7 Dashboard extension points** (cf platform.md §661) — appliquer le même contrat « modules contribuent » au dashboard qu'au mobile. Aujourd'hui le dashboard a des onglets hardcodés (Modules, Branding, Modération, Articles, Events, Polls, Places, Infos). Demain : chaque module officiel déclare ses contributions dashboard via `extensions: dashboard:moderation.pending`, `extensions: dashboard:settings`, etc. Le dashboard devient lui-même DSL-driven, code-free pour ajouter un module.

- **⏭ 18.8 Flow commune end-to-end automatisé** (cf platform.md §723) — au-delà des outils unitaires actuels (`provision-commune.py`, `build-commune-app.sh`, `build-commune-site.py`, fastlane lanes), un flow CI/CD complet :
  - Commune signup via formulaire web sur `communesolutions.be`
  - Trigger pipeline qui crée projet Firebase + active services + génère configs SDK + provisionne tenant + génère site commune-sites/ + déploie + ajoute DNS Infomaniak via API + soumet AppStore Connect + Play Console + envoie credentials admin par mail
  - Time-to-live commune : viser < 30 min après signup
  - Bloquant à plus de 5 communes en prod (sinon support manuel ne tient pas)

### 15. Hygiène repo + ouverture publique — ✅ fait (2026-05-05)

- ✅ **Audit secrets historique git** : clean — Firebase configs (GoogleService-Info, google-services, firebase-config-spike-*) jamais committées, aucune clé API, aucun token, aucun secret hardcodé détecté
- ✅ **`LICENSE`** EUPL-1.2 racine (texte officiel SPDX)
- ✅ **`CONTRIBUTING.md`** : workflow PR, 3 types de contributions (module communautaire, évolution core, doc/bug), licence
- ✅ **`CODE_OF_CONDUCT.md`** : Contributor Covenant 2.1, contact `contact@mosadata.com`
- ✅ **`SECURITY.md`** : disclosure responsable, GitHub Private Vulnerability Reporting préféré + email `contact@mosadata.com`, engagement délais
- ✅ **Slug GitHub** : `xxcb4000/commune_solutions` validé comme URL canonique (compte perso, transfert vers org possible plus tard)
- ✅ **Badge LICENSE** sur README, liens CONTRIBUTING/COC/SECURITY visibles en haut

## 3. Décisions ouvertes (design)

Listées exhaustivement dans [`docs/platform.md`](platform.md#décisions-ouvertes). Sélection des plus structurantes :

- **🤔 Validation JSON Schema runtime** : qui valide les `screens/*.json` à la soumission module ET au runtime ? Le spike charge sans validation
- **🤔 i18n / multi-langue** : `displayName: { fr, nl, de }` dès le manifest ou plus tard
- **🤔 Mode hors-ligne** : stale-while-revalidate par défaut quand un module DSL appelle une CF sans réseau ?
- **🤔 Quotas par module** : rate limit CFs, taille collections, nombre d'écrans
- **🤔 Multi-runtime backend** : Python only en MVP, ouvrir Node/Go plus tard ?
- **🤔 Mapping iconographique SF Symbols ↔ Material** : où héberger la table, quel pipeline CI valide les noms référencés
- **🤔 Markdown — liens inline** : autoriser `[label](url)` dans la primitive `markdown`, et que faire au tap
- **🤔 Données canoniques BeST** : qui maintient le seed, refresh quand BOSA met à jour
- **🤔 Upload UGC** : toujours via CF ou autoriser SDK Storage direct avec RLS
- **🤔 Vocabulaire fermé `device.permissions`** : finaliser la liste canonique
- **🤔 E-guichet iMio** : à reprendre quand l'API iMio aura été explorée

## 4. Décisions tranchées (2026-05-05)

- ✅ **Awans assumée publiquement** : la landing/marketing peut mentionner Awans comme première commune adoptante. Le code de la plateforme reste neutre (aucune référence à une commune dans renderer / modules / dashboard / tooling). CLAUDE.md mis à jour
- ✅ **GitHub** : repo public à `github.com/xxcb4000/commune_solutions` (compte perso de Vincent). On garde tel quel pour le moment ; transfert vers une org `commune-solutions` envisageable si gouvernance future le demande
- ✅ **Apple Developer** : compte central **Mosa Data Engineering** (Team ID `TJ2759P685`) signe toutes les apps des communes. Une commune peut basculer sur son propre compte plus tard à la demande

## 5. Décisions encore à prendre

- **🤔 Devenir des protos `design/*.html`** : les garder dans le repo public (transparence, moodboards) ou les sortir en repo privé (juste des artefacts de validation interne)
