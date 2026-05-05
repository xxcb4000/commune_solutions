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
- **⏭ 12.2 — Provisioning auto commune** : `tools/provision-commune.py <commune-id>` qui crée le projet Firebase + apps SDK + récupère configs + initialise `_config/modules` + branding
- **⏭ 12.3 — CI GitHub Actions** : workflow qui consomme `build-commune-app.sh`, secrets Firebase configs en base64, produit IPA + AAB
- **⏭ 12.4 — Distribution stores** : fastlane match (certs iOS partagés Mosa Data Engineering) + upload TestFlight + Play Console
- **⏭ 12.5 — Sous-domaine `<commune>.communesolutions.be`** : automation DNS + Firebase Hosting custom domain
- **⏭ Universal Links / App Links à l'échelle** : `apple-app-site-association` mutualisé sur `communesolutions.be` 🤔 (cf décision ouverte platform.md)
- **⏭ Choix commune pilote** : à arbitrer

### 13. Communauté ouverte (premier module tiers)

Tout le pipeline contributeur n'existe que sur papier. À matérialiser :

- **⏭ Dossier `modules-community/`** : créer le squelette + un module exemple non-officiel pour exercer le filtre marketplace
- **⏭ CLI `create-commune-module`** : génère un squelette manifest + screens + data depuis un template
- **⏭ Emulator local commune fictive** : Firebase emulator + app simulator + DSL hot-reload pour développer sans device
- **⏭ Capability `cf.external`** : permettre à un module tiers d'héberger ses propres CFs en recevant un ID token de la commune (cf platform.md, validée 2026-04-30)
- **🤔 Repo split** : `commune_solutions` (plateforme + officiels) vs `commune_solutions-modules-community` (PRs tiers) — décision à prendre selon le rythme d'arrivée des contribs

### 14. Dashboard admin — passer en édition

Aujourd'hui le dashboard ne fait que **toggle des modules** + lecture des collections. Pour qu'une commune soit autonome :

- **⏭ CRUD contenu par module** : créer/éditer/publier articles, événements, sondages, lieux carte
- **⏭ Modération UGC** : si un module a `moderation: true` (commentaires, propositions), file unifiée dans le dashboard
- **🤔 Dashboard DSL-driven** : appliquer le même contrat plateforme au dashboard que côté mobile (modules contribuent à des extension points dashboard) — cf platform.md
- **⏭ Onboarding admin** : flow first-login, brand kit upload, preview live

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
