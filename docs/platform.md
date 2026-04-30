# Commune Solutions — Plateforme civic tech open source

> **Statut** : design en cours (avril 2026). Spike technique iOS + Android validé **GO** le 2026-04-30 (cf `spike/SPIKE_VERDICT.md`) — l'hypothèse "DSL JSON rendue par shell natif indissociable d'une app codée à la main" tient sur les 11 primitives critiques. Pas encore d'implémentation production.
> Ce document capture les décisions de conception. Il est vivant et sera découpé en sous-documents quand il grossira.

## Les deux chantiers

L'app actuelle (Awans) est à 99% de complétion fonctionnelle. La suite, ambitieuse, se joue sur deux axes simultanés :

1. **Templatiser pour embarquer d'autres communes** — multi-tenant white-label : la même stack iOS + Android + dashboard servant N communes wallonnes, chacune avec son branding, ses contenus, son sous-domaine `<commune>.communesolutions.be`.

2. **Open source + architecture à modules** — toute fonctionnalité (sondages, agenda, carte, actualités, services, vie politique, e-guichet…) est un module installable. Communauté de devs externes peut proposer de nouveaux modules. Marketplace publique sur `communesolutions.be/marketplace`.

Ces deux chantiers sont indissociables : la modularité justifie la mutualisation entre communes, la mutualisation finance la modularité.

## Vision et principes

- **Core minimal** : le shell central ne contient que l'auth, la navigation, le multi-tenant, le registry de modules. Tout le reste est module — y compris les fonctionnalités historiques (sondages, agenda, carte…), qui deviennent des **modules officiels**.
- **Dogfooding** : les modules officiels sont packagés exactement comme un contributeur externe le ferait. Si nos propres features ne tiennent pas dans le contrat, c'est que le contrat est mal conçu.
- **DSL UI riche, natif rare** : le shell embarque toutes les primitives répétitives en civic tech (carte, scan QR, partage, capture photo) dans son DSL déclaratif. Les modules sont 90%+ server-driven (CF Python + DSL JSON). Les rares cas exotiques (AR, visualisation 3D urbanisme à terme…) passent par des **extension points** stables exposés par le core, contribués via PR — pas chargés dynamiquement.
- **Souveraineté & ouverture** : licence EUPL 1.2 sur le core (compatible secteur public européen). Backend Python, déployable hors GCP à terme si une commune le demande.

## Architecture en couches

```
┌───────────────────────────────────────────────────────────┐
│            App native (iOS + Android) + Dashboard         │
│  • Shell mobile : auth, navigation, theming, runtime DSL  │
│  • Shell admin : login, navigation, page registry         │
│  • Primitives DSL natives (carte, scan, partage, photo…)  │
│  • Extension points natifs pour cas exotiques             │
└───────────────────────────────────────────────────────────┘
                           ▲
                           │ API stable (versionnée)
┌───────────────────────────────────────────────────────────┐
│             Modules (officiels + communauté)              │
│  Backend Python (CF) + DSL UI déclaratif + manifest       │
│  Sondages | Agenda | Carte | Actualités | E-guichet | …   │
└───────────────────────────────────────────────────────────┘
                           ▲
                           │
┌───────────────────────────────────────────────────────────┐
│                Tenant Firebase par commune                │
│  Projet Firebase isolé · données séparées · branding      │
└───────────────────────────────────────────────────────────┘
```

## Tenant model

**Décision MVP** : un projet Firebase par commune (jusqu'à ~20 communes). Au-delà, migration vers projet partagé multi-tenant à envisager.

**Avantages isolation par projet** :
- Isolation maximale (RGPD béton, fuite cross-commune impossible)
- Billing par commune naturel
- Suspension d'une commune = désactivation projet, pas de migration data
- Commune souveraine de ses données (export Firebase complet à tout moment)

**Conséquences** :
- Un module utilise **uniquement** les données du tenant Firebase de sa commune
- Toute donnée "globale" passe par une **API HTTP explicite**, jamais par accès cross-projet direct
- Données canoniques (rues BeST, catalogue démarches) **répliquées au provisioning** depuis sources externes

| Donnée | Stratégie MVP |
|---|---|
| Rues canoniques (BeST) | Réplication au provisioning depuis dump fédéral, filtrage par code INS commune |
| Catalogue démarches iMio | Déclaratif dans le module e-guichet de chaque commune |
| Agenda culturel régional | Pas de partage en MVP. À terme : module fédéré qui agrège des endpoints publics par commune |
| Identifiants utilisateurs | Strict tenant : un user d'Awans n'existe pas dans le tenant Liège |

## Contrat module — `manifest.yaml`

Tout module déclare son contrat dans un fichier manifest unique. Source de vérité pour la sécurité, les permissions, les screens, le lifecycle.

```yaml
id: sondages
version: 2.0.0
displayName: "Sondages & Consultations"
description: "Sondages multi-questions avec restriction territoriale"
icon: chart.bar.fill
maintainer: { type: official, email: ... }
license: EUPL-1.2

coreCompat: ">=1.0.0 <2.0.0"

# Données possédées (RLS auto-générée à partir d'ici)
ownedCollections:
  - path: sondages/{*}
  - path: sondages/{*}/user_votes/{*}

# Permissions accordées par l'admin commune à l'installation
capabilities:
  user.read: [rue, adressePostale, canVote, status]
  module.read:
    - awans_streets/{*}
  fcm.send: { topics: [sondages-new] }
  cloudFunctions: [submit_response, get_list, get_responses, delete]

# Permissions device (aggregées au build, génèrent Info.plist + AndroidManifest)
device:
  permissions: []   # sondages n'a besoin de rien

# Écrans contribués au shell
screens:
  - id: sondages.detail
    type: server-driven
    spec: ./screens/detail.ssui.json
  - id: sondages.builder
    type: server-driven
    audience: admin
    spec: ./screens/builder.ssui.json

# Contributions à d'autres modules
extensions:
  - to: actualites:feed.topCards
    handler: { type: cf, endpoint: get_open_for_feed }
    contractVersion: 1

# Config par commune
config:
  schema: ./config.schema.json
  defaults:
    territorialRestrictionEnabled: true
    notifyOnPublish: true

# Migrations versionnées
migrations:
  - from: ">=1.0.0 <2.0.0"
    to: 2.0.0
    handler: ./migrations/v1-to-v2.py
```

### Exemple avec UGC modérée — Carte POI

```yaml
id: carte
version: 1.0.0
displayName: "Carte"
icon: map.fill

ownedCollections:
  - path: map_overlays/{*}
    moderation: true   # ← active le pattern UGC standard (cf section "Modération")

capabilities:
  storage:
    read: ["pois/{*}"]
    write: ["pois/{*}"]   # photos POI (uploads via CF, jamais SDK direct côté client)
  cloudFunctions: [get_pois, submit_poi_proposal, admin_approve_poi, admin_reject_poi]

device:
  permissions:
    - id: location.in-use
      justification: "Centrer la carte sur votre position"
      required: false   # le module fonctionne sans

extensions:
  - to: dashboard:moderation.pending   # contribution auto si moderation: true
    handler: { type: cf, endpoint: get_pending_pois }
    contractVersion: 1

config:
  defaults:
    citizenProposalsEnabled: true
    defaultMapCenter: { lat: 50.6588, lng: 5.4767 }
    defaultMapZoom: 13
```

### Exemple avec hôte d'extension points + pipeline — Actualités

```yaml
id: actualites
version: 1.0.0
displayName: "Actualités"

ownedCollections:
  - path: articles/{*}
    moduleAccess: read              # autorise autres modules à lire
  - path: articles_staging/{*}
    visibility: internal            # pas de lecture client (pipeline interne)
  - path: source_fingerprints/{*}
    visibility: internal
  - path: posts_analyzed/{*}
    visibility: internal

capabilities:
  storage: { read: ["articles/{*}"], write: ["articles/{*}"] }
  external.http: [api.openai.com, graph.facebook.com, www.awans.be]
  fcm.send: { topics: [news] }

# Secrets fournis par la commune via dashboard (Google Secret Manager)
secrets:
  - id: OPENAI_API_KEY
    description: "Dedup intelligent (optionnel — fallback heuristique sans)"
    required: false
  - id: FACEBOOK_GRAPH_TOKEN
    required: false

# Cron Cloud Scheduler créés au projet commune à l'install
scheduledJobs:
  - id: sync-daily
    schedule: "0 19 * * *"
    timezone: Europe/Brussels
    handler: { type: cf, endpoint: sync_all }
    timeout: 540s
    memory: 1Gi

# Extension points EXPOSÉS par ce module (côté hôte)
extensionPoints:
  - id: feed.topCards
    description: "Cards en tête du feed Actualités"
    contract: { schema: ./contracts/feed-card.schema.v1.json, version: 1 }
    aggregation: { strategy: priority-merge, maxItems: 5, cacheBudget: 2s }

# Routes deep-link (validées au build pour collisions)
deepLinks:
  - id: article-detail
    pattern: /article/{articleId}
    screen: actualites.article.detail
    fcmCategory: news

config:
  schema: ./config.schema.json
  ui: ./config-ui.ssui.json         # formulaire admin server-driven (DSL)
  defaults:
    sources:
      cms: { enabled: true }
      facebook: { enabled: false }
    dedupStrategy: gpt              # "gpt" | "heuristic" | "off"
```

### Sections clés

- **`ownedCollections`** : collections que le module possède. Génère automatiquement les Firestore Rules. Trois flags par path :
  - `moderation: true` active le pattern UGC standard (cf section dédiée)
  - `visibility: internal` interdit toute lecture client, même admin (collections de pipeline interne)
  - `moduleAccess: read | write | none` (défaut `none`) autorise d'autres modules à accéder à cette collection — sécurité par défaut
- **`capabilities`** : permissions explicites visibles par l'admin commune à l'installation. Static analysis Python à la soumission compare déclaré vs effectif (refus PR si discordance).
- **`device.permissions`** : permissions device (Location, Camera, Photos…). Aggregées au build par commune → Info.plist + AndroidManifest. Une commune sans le module n'a pas la permission dans son binaire.
- **`secrets`** : clés API et tokens fournis par la commune via dashboard (Secret Manager). Lus par les CFs en env. `required: false` permet la dégradation gracieuse.
- **`scheduledJobs`** : crons déclaratifs (Cloud Scheduler). Créés/supprimés au lifecycle du module dans le projet Firebase de la commune.
- **`screens`** : écrans contribués au shell, identifiés par un id unique. Type `server-driven` (DSL JSON) ou `native-extension` (rare).
- **`extensions`** : contributions à des extension points (côté contributeur).
- **`extensionPoints`** : extension points exposés par ce module (côté hôte). Définit schema contrat + stratégie d'aggregation + limites de sécurité.
- **`deepLinks`** : routes deep-link déclarées. Validées au build pour collisions, routées par FCM et Universal/App Links.
- **`publicEndpoints`** : routes HTTP publiques exposées à des tiers (iCal, RSS, JSON feeds). Fondation de la fédération inter-communes.
- **`config`** : schema JSON + `ui` (DSL formulaire admin) pour la config commune-level.
- **`migrations`** : migrations idempotentes entre versions. Exécutées au upgrade.

## DSL UI — primitives identifiées

Le DSL est en **JSON Schema strict** (validation native, tooling, conversion humaine via UI builder dans le dashboard).

### Couches de primitives

Une primitive marquée ✅ a été validée en natif sur device (iOS + Android) lors du spike du 2026-04-30.

| Couche | Primitives |
|---|---|
| Shell | `tabbar` ✅ (racine multi-onglets, back-stack par onglet) |
| Layout | `scroll` ✅, `vstack` ✅, `hstack` ✅, `section`, `card` ✅, `grid` |
| Navigation | `segmented` (toggle entre 2-3 sections hétérogènes dans une vue, pattern Liste/Calendrier, Services/Vie politique) |
| Logique | `if/then/else` ✅, `for` ✅, `switch` |
| Affichage | `header` ✅ (atomique, cf notes), `text` ✅, `markdown` ✅ (sous-ensemble, cf notes), `image` ✅, `alert`, `badge` ✅, `divider` |
| Form | `field` polymorphe (`yesno`, `radio`, `checkbox`, `text`, `text.long`, `scale`, `date`, `date.range`, `address`, `street`, `phone`, `email`, `map.picker`, `photo`, `secret`) |
| Civic-tech | `map` (multi-marker, filtre catégorie, user location), `calendar` ✅ (vue mois, marqueurs ISO depuis un binding `in:` + champ date `dateField`) — implémentations natives MapKit/Google Maps + SwiftUI/Compose dans le shell |
| Device | `scan.qr`, `share`, `camera.capture` (utilisent les `device.permissions` déclarées) |
| Action | `button`, `link` + `action` (`navigate` ✅, `cf`, `firestore.write`, `toast`, `alert`, `share`, `pull-to-refresh`, `addToCalendar`) |
| Data sources | `firestore` (listener temps-réel + offline cache natif), `cf` (cache via `Cache-Control` HTTP serveur), `static` (bundlé) ✅, `module` (cross-module read avec capability) |

### Notes du spike

**`calendar` validé ✅** — UICalendarView (iOS 16+) côté Apple, grille Compose custom côté Android (Material 3 n'a pas de calendrier markable). Le DSL passe une liste d'events via `in:` et le nom du champ ISO via `dateField:` ; le renderer extrait les dates `yyyy-MM-dd`, marque la grille, et sélectionne automatiquement le mois du premier event comme mois affiché. **Limites actuelles** : pas de `onDateTap` (documenté mais pas implémenté), pas de polish (padding/couleur/style configurable), iOS conserve le picker de mois interne du UICalendarView.

**`markdown` — sous-ensemble supporté.** Ni SwiftUI (`Text(AttributedString(markdown:options: .full))`) ni Compose ne rendent le markdown block-level — les deux collapse les blocs en run inline ou n'ont rien. Les renderers font un paragraph-split maison. Le contrat plateforme garantit donc :

- Headings niveaux 1-3 (`#`, `##`, `###`)
- Listes à puces simples (`- ` ou `* `, pas d'imbrication)
- Inline `**bold**` et `*italic*`

Pas garantis : tableaux, blocs de code, citations, listes numérotées, listes imbriquées, images embarquées. Liens inline (`[label](url)`) : décision ouverte (cf section finale).

**`header` — primitive atomique.** Ne peut pas être recomposé en `vstack + image + text` parce que `Image.scaledToFill` (iOS) déborde horizontalement sans encadrement explicite. Le shell fournit le composite : image plein-cadre + dégradé bas + titre overlay. Champs : `title`, `subtitle?`, `imageUrl`, `height`. Pas de variations free-form — un module qui veut un autre look doit motiver une nouvelle primitive shell.

**Mapping iconographique.** Les noms d'icône dans le DSL (`tab.icon`, `manifest.icon`, futurs `card.icon`...) suivent la convention **SF Symbols** (Apple). Le renderer Android maintient une **table de correspondance** SF Symbol → Material Icon. Conséquences :

- Vocabulaire d'icônes **fermé** (comme `device.permissions`) : un module ne peut référencer que des noms validés.
- La marketplace refuse une PR module si elle utilise un nom non mappé.
- Premier set mappé au spike : `newspaper`, `info.circle`, `house`, `person`, `magnifyingglass`, `gearshape`, `calendar`, `calendar.day`, `map`. Table complète à maintenir dans la doc SDK.

**Templating Mustache-like, type-preserving.** `{{ path.to.value }}` substitue par la stringification. Quand l'expression est exactement une seule binding (`{{ article }}`), le renderer préserve le type natif (objet, array, bool) — utile pour passer un objet entier en `with:` à une action `navigate`. Validé au spike, à figer dans le contrat.

**Types numériques.** Tous les nombres dans le DSL (`spacing`, `padding`, `height`, `aspectRatio`, etc.) sont des **floats** — Kotlinx-serialization est strict (`Int` ≠ `Double`) et le contrat préfère uniformiser plutôt qu'introduire un parseur tolérant.

### Primitive `map` — exemple

```json
{
  "type": "map",
  "dataSource": { "source": "cf", "endpoint": "get_pois" },
  "marker": {
    "id": "{{item.id}}",
    "coord": { "lat": "{{item.coordinates[0].lat}}", "lng": "{{item.coordinates[0].lng}}" },
    "title": "{{item.name}}",
    "icon": "{{item.iconName}}",
    "color": "{{item.color}}"
  },
  "overlays": {
    "filter": { "type": "categoryChips", "categories": "{{config.categories}}", "field": "category" },
    "userLocation": "{{device.permissions.location}}"
  },
  "onMarkerTap": {
    "type": "navigate",
    "screen": "carte.poi.detail",
    "params": { "poiId": "{{marker.id}}" }
  }
}
```

L'implémentation native (MapKit iOS / Google Maps Android) est dans le shell — le module ne s'occupe que des données et du binding.

### Primitive `calendar` — exemple

```json
{
  "type": "calendar",
  "view": "month",
  "dataSource": {
    "source": "firestore",
    "path": "events",
    "where": [{ "field": "date_start", "op": ">=", "value": "{{viewedMonth.start}}" }]
  },
  "dateField": "date_start",
  "marker": { "color": "{{config.theme.accent}}" },
  "onDateTap": {
    "type": "navigate",
    "screen": "agenda.feed",
    "params": { "date": "{{date}}" }
  }
}
```

### Primitive `segmented` — exemple

```json
{
  "type": "segmented",
  "selected": "{{state.view}}",
  "options": [
    { "id": "list", "label": "Liste", "renders": { "$ref": "#/screens/agenda.list" } },
    { "id": "calendar", "label": "Calendrier", "renders": { "$ref": "#/screens/agenda.calendar" } }
  ]
}
```

Distinction nette avec `field.segmented` (input form qui produit une valeur) : `segmented` orchestre le **rendu** d'une portion d'écran selon la sélection.

### Primitive `tabbar` — exemple

```json
{
  "screen": "root",
  "view": {
    "type": "tabbar",
    "tabs": [
      { "title": "Actualités", "icon": "newspaper", "screen": "actualites.feed" },
      { "title": "Agenda", "icon": "calendar", "screen": "agenda.feed" },
      { "title": "Carte", "icon": "map", "screen": "carte.main" },
      { "title": "Plus", "icon": "ellipsis", "screen": "plus.menu" }
    ]
  }
}
```

`tabbar` est la primitive **racine** des apps multi-onglets. Chaque onglet maintient son propre back-stack de navigation (push/pop indépendants par onglet). Le shell mobile rend TabView (iOS) / NavigationBar Material 3 (Android). Limite à 5 onglets visibles par convention iOS — au-delà, un onglet "Plus" agrège.

### Exemple — `sondages.detail.ssui.json` (extrait)

```json
{
  "screen": "sondages.detail",
  "params": ["sondageId"],
  "data": {
    "sondage": { "source": "firestore", "path": "sondages/{sondageId}" },
    "myVote": { "source": "firestore", "path": "sondages/{sondageId}/user_votes/{sondageId}_{auth.uid}", "optional": true },
    "eligibility": { "source": "cf", "endpoint": "check_voting_eligibility" }
  },
  "layout": { "type": "scroll", "children": [
    { "type": "header", "title": "{{sondage.title}}", "subtitle": "{{sondage.description}}" },
    { "type": "if", "cond": "!eligibility.canVote",
      "then": { "type": "alert", "kind": "info", "text": "Inscription requise" } },
    { "type": "for", "items": "{{sondage.questions}}", "as": "q", "children": [
      { "type": "field", "kind": "{{q.type}}",
        "id": "{{q.id}}", "label": "{{q.label}}", "required": "{{q.required}}",
        "options": "{{q.options}}", "min": "{{q.scaleMin}}", "max": "{{q.scaleMax}}",
        "value": "{{myVote.answers[q.id]}}" } ] },
    { "type": "button", "label": "{{myVote ? 'Mettre à jour' : 'Voter'}}",
      "enabled": "{{eligibility.canVote && form.allRequiredAnswered}}",
      "action": { "type": "cf", "endpoint": "submit_response",
        "body": { "sondageId": "{{sondageId}}", "answers": "{{form.values}}" },
        "onSuccess": { "type": "toast", "text": "Vote enregistré" } } }
  ]}
}
```

## Cross-module — extension points

Pattern de découplage : un module **hôte** déclare des extension points avec contrat versionné. D'autres modules **contributeurs** s'y greffent via leur section `extensions`.

### Côté hôte — `extensionPoints`

```yaml
extensionPoints:
  - id: feed.topCards
    description: "Cards en tête du feed Actualités"
    contract: { schema: ./contracts/feed-card.schema.v1.json, version: 1 }
    aggregation:
      strategy: priority-merge   # contributors retournent priority desc
      maxItems: 5                # safety
      cacheBudget: 2s            # timeout : un contributeur lent est ignoré
```

### Côté contributeur — `extensions`

```yaml
extensions:
  - to: actualites:feed.topCards
    handler: { type: cf, endpoint: get_open_for_feed }
    contractVersion: 1
```

### Stratégies d'agrégation

| Stratégie | Comportement | Use case |
|---|---|---|
| `priority-merge` | Merge + sort par champ `priority` desc | Feed avec ordre éditorialisé |
| `round-robin` | Interleave un item par contributeur, par tour | Feed équitable multi-source |
| `concat` | Append dans l'ordre d'enregistrement des modules | Listes admin (modération, settings) |
| `first-match` | Premier handler qui retourne non-null | Stratégie de fallback / override |

### Runtime

1. Hôte charge l'écran → scanne les modules activés contribuant au point
2. Appelle les handlers en parallèle avec timeout `cacheBudget`
3. Valide chaque réponse contre le schema du contrat (refus si non-conforme)
4. Aggrège selon la stratégie
5. Le hôte rend (en DSL ou natif selon ce que le contrat exige)

**Bénéfices** :
- Découplage : l'hôte ne connaît pas les contributeurs
- Composition : nouveaux contributeurs sans toucher l'hôte
- Robustesse : un contributeur en panne ne casse pas l'écran (timeout + skip)

**Coût** : versioning des contrats (`contractVersion`) et matrice de compat. Breaking change = nouvelle version de contrat, migration coordonnée annoncée dans la marketplace.

## Cron déclaratif — `scheduledJobs`

Les modules à pipeline (Actualités, Agenda, …) déclarent leurs jobs Cloud Scheduler dans le manifest :

```yaml
scheduledJobs:
  - id: sync-daily
    schedule: "0 19 * * *"           # cron classique
    timezone: Europe/Brussels
    handler: { type: cf, endpoint: sync_all }
    timeout: 540s
    memory: 1Gi
```

Au lifecycle du module :
- **Enable** : framework crée les jobs Cloud Scheduler dans le projet Firebase de la commune (région `europe-west1`), configure auth OIDC, target HTTP
- **Update** : si `schedule` ou `handler` change → update job
- **Disable** : suppression des jobs (pas d'orphelins)

Élimine la dette actuelle d'Awans (jobs créés à la main via `gcloud`, oubliés au déploiement). Source de vérité = manifest.

## Secrets commune — `secrets`

Différent de `config` : les secrets sont stockés dans **Google Secret Manager** côté projet commune, jamais en Firestore, jamais relus dans le dashboard après création (input mode `password` write-only).

```yaml
secrets:
  - id: OPENAI_API_KEY
    description: "Clé OpenAI pour dedup intelligent"
    required: false                  # dégradation gracieuse si absent
  - id: FACEBOOK_GRAPH_TOKEN
    required: false
```

À l'installation/config :
- Admin commune voit les secrets demandés dans le formulaire `config.ui`
- Saisie en mode masqué, écrit directement dans Secret Manager
- Les CFs du module reçoivent les valeurs via env (binding standard Cloud Functions)
- Rotation : admin peut régénérer/réécrire à tout moment

`required: false` permet aux modules d'avoir des fonctionnalités optionnelles : Actualités sans OpenAI utilise un dedup heuristique.

## Deep-links — `deepLinks`

Routes natives de l'app, déclarées par chaque module :

```yaml
deepLinks:
  - id: article-detail
    pattern: /article/{articleId}
    screen: actualites.article.detail
    fcmCategory: news                # alias FCM legacy pour compat
```

Au build :
- **Validation collision** : refus si deux modules claim `/article/{id}` (CI bloque la PR)
- **Universal Links iOS / App Links Android** : `apple-app-site-association` et `assetlinks.json` générés au build commune avec toutes les routes des modules activés
- **FCM routing** : payload `{ category, ...params }` → table de mapping → écran cible

Première classe dans le manifest, plus de magic strings. Coordonne toutes les routes natives de l'app multi-modules.

## Config commune — `config.ui` formulaire DSL

La config commune-level est éditée via un formulaire DSL, versionné avec le module :

```json
{
  "type": "form",
  "model": "config",
  "children": [
    { "type": "section", "title": "Sources de contenu" },
    { "type": "field", "kind": "toggle", "id": "sources.cms.enabled", "label": "CMS communal" },
    { "type": "if", "cond": "{{config.sources.cms.enabled}}", "then": [
      { "type": "field", "kind": "url", "id": "sources.cms.endpoint", "label": "Endpoint @results", "required": true } ] },
    { "type": "field", "kind": "secret", "id": "secrets.OPENAI_API_KEY", "label": "Clé OpenAI" }
  ]
}
```

Cohérent avec le reste : tout est server-driven, y compris l'install/config dans le dashboard. Le formulaire évolue avec le module (versionné), le code dashboard ne touche à rien.

Le `field.secret` est une primitive sœur de `field.text`/`field.url`/etc. : input masqué, write-only, écrit directement dans Secret Manager.

## Endpoints publics — `publicEndpoints`

Routes HTTP brutes exposées par le module à des **tiers** (pas l'app), via Firebase Hosting → CF :

```yaml
publicEndpoints:
  - path: /agenda.ics
    handler: { type: cf, endpoint: ical_feed }
    contentType: text/calendar
    cache: { maxAge: 3600, public: true }     # CDN-cacheable
  - path: /agenda.json
    handler: { type: cf, endpoint: json_feed }
    contentType: application/json
    cache: { maxAge: 600, public: true }
```

Routées sous `<commune>.communesolutions.be/<path>`. Validation collision au build comme `deepLinks`.

`cache.public: true` autorise le cache CDN/proxies (vs cache uniquement client) — important pour des feeds lus par centaines de calendriers/aggregateurs simultanément.

### Pattern de fédération

C'est aussi le mécanisme de fédération posé par notre tenant model : pas de partage data cross-tenant, mais chaque commune **expose** des feeds publics qu'un module futur (ex. "Agenda fédéré régional") peut **agréger** côté client. Découplage complet, pas de dépendance Firebase cross-projet.

### Symétrie des trois mécanismes HTTP

| Section | Public | Consommateur typique |
|---|---|---|
| `cloudFunctions` | App propre (HTTP authentifié ou public selon CF) | Modules de l'app — appels DSL `source: cf` |
| `deepLinks` | Universal Links / App Links | Routes natives ouvertes depuis FCM, navigateur, autre app |
| `publicEndpoints` | HTTP brut, CDN-cacheable | Tiers : calendriers (iCal), RSS readers, modules d'autres communes (fédération), aggregateurs |

## Visibilité collections & accès cross-module

Trois flags par path dans `ownedCollections` :

| Flag | Valeurs | Effet |
|---|---|---|
| `moderation` | `true` / défaut absent | Active le pattern UGC (cf section dédiée) |
| `visibility` | `public` (défaut) / `internal` | `internal` = aucune lecture client (RLS `read: false`), seules les CFs du module y accèdent via Admin SDK |
| `moduleAccess` | `none` (défaut) / `read` / `write` | Autorise d'autres modules à accéder via `module.read` / `module.write` dans leurs capabilities |

**Sécurité par défaut** : un module ne peut pas lire les données d'un autre sans déclaration explicite côté propriétaire ET côté consommateur. Static analysis bloque toute tentative d'accès non déclarée.

Exemple Actualités :
- `articles/{*}` → `moduleAccess: read` (un module "Recommandations" peut lire pour faire du ML)
- `articles_staging/{*}` → `visibility: internal` (pipeline interne, jamais exposé)
- `posts_analyzed/{*}` → `visibility: internal` (cache GPT, sensible/coûteux)

## Extension native — l'échappatoire (rare)

Le shell embarque déjà les primitives répétitives en civic tech : `map`, `scan.qr`, `share`, `camera.capture`, `field.map.picker`, `field.photo`. Donc 90%+ des modules sont 100% server-driven.

Pour les cas vraiment exotiques (AR, visualisation 3D urbanisme, lecteur de plans techniques…), le core expose des **extension points natifs** stables. Ces extensions :

- Sont contribuées au **core** via PR (pas chargées dynamiquement à l'install)
- Nécessitent un **build app par commune** intégrant les modules natifs activés
- Sont **rares** by design : la doc et les RFC découragent activement le natif quand le DSL ou une nouvelle primitive shell suffisent

Si une extension native est demandée par 2+ modules, c'est le signal qu'elle doit devenir une primitive shell.

## Modération UGC — pattern standard

Plusieurs modules ont besoin de modérer du contenu utilisateur (POIs proposés, events proposés, signalements voirie, propositions budget participatif…). Plutôt que chacun ré-implémente, le framework offre une abstraction :

```yaml
ownedCollections:
  - path: map_overlays/{*}
    moderation: true
```

Quand `moderation: true` :
- **Champs auto-injectés** : `status` (`pending`/`active`/`rejected`), `visible`, `proposed_by` (uid), `proposed_by_email`, `proposed_at`, `moderated_by`, `moderated_at`, `moderation_reason`
- **RLS standards** : citoyens créent en `pending`, admin lit/écrit tout, anonymes lisent uniquement les `visible: true`
- **CFs standards exposées** : `<module>.list_pending()`, `<module>.approve(id)`, `<module>.reject(id, reason)`
- **Sync auto** `status` ↔ `visible` (résout la dette historique d'Awans où il fallait les synchroniser à la main)
- **Contribution auto** à l'extension point `dashboard:moderation.pending` — l'admin voit tout ce qui attend dans un widget unifié

C'est le premier vrai cas où le framework **offre** une abstraction (pas juste contraindre un contrat). Ça fait gagner ~200 lignes de code et de tests par module concerné.

## Permissions device — aggregation au build

Les permissions iOS Info.plist (`NSLocationWhenInUseUsageDescription`, `NSCameraUsageDescription`, …) et Android Manifest (`ACCESS_FINE_LOCATION`, `CAMERA`, …) sont déclarées par chaque module dans `device.permissions` :

```yaml
device:
  permissions:
    - id: location.in-use
      justification: "Centrer la carte sur votre position"
      required: false
```

Au build par commune :
1. CI scanne les modules activés
2. Aggrège les permissions device
3. Génère Info.plist + AndroidManifest minimaux
4. Une commune sans Carte n'a pas la permission Location dans son binaire

**Bénéfices** : pas de prompts "fantômes", compliance review stores plus simple, confiance utilisateur.

**Vocabulaire fermé** (à publier dans la doc SDK) : `location.in-use`, `location.always`, `camera`, `microphone`, `photos.read`, `photos.write`, `notifications`, `contacts.read`, `calendar.read`, `calendar.write` (utilisé par Agenda pour "Ajouter à mon calendrier"), `bluetooth`, `motion`. Pas de free-text — un module ne peut demander que ce qui est dans le vocabulaire officiel.

## Stratégie de cache

Le DSL ne porte **pas** de TTL côté client (mauvais pattern : rigide, mélange UI et fraîcheur, ignore les patterns natifs).

| Source | Stratégie |
|---|---|
| `firestore` | Listener temps-réel + offline cache natif Firestore. Toujours frais quand connecté, dernière valeur connue offline. Aucune config nécessaire. |
| `cf` | La CF retourne `Cache-Control: max-age=N, stale-while-revalidate=M`. Le client HTTP respecte. Le serveur seul décide de la fraîcheur (il sait quand ses données changent). |
| `static` (config, vocabulaires fermés) | Bundlé à l'install/upgrade du module. Refresh à l'enable. |

**Pull-to-refresh** est une primitive shell globale (geste natif sur tout écran liste/détail) — invalide les caches HTTP et force re-fetch listeners. Pas une option par data source.

## Dashboard core — shell admin

Le dashboard est un **shell admin** fourni par le core (au même titre que le shell mobile). Pas un module. Il expose des extension points consommés par les modules :

| Extension point | Description | Exemple consommateur |
|---|---|---|
| `dashboard:moderation.pending` | Items en attente de modération, agrégé par module | Auto pour tout module avec `moderation: true` |
| `dashboard:overview.widgets` | Widgets de la home dashboard (KPIs) | Sondages : "3 sondages ouverts, 142 votes" |
| `dashboard:settings.sections` | Sections de la page Paramètres | E-guichet : URL endpoint iMio |
| `dashboard:nav.entries` | Entrées de menu latéral | Tout module avec écran `audience: admin` |

Concerns transverses (gestion users, modération, billing si un jour, audit log) sont dans le core dashboard. Les modules contribuent leurs vues spécifiques via DSL `audience: admin`.

## Capabilities & sécurité

### Modèle

- Le manifest = source de vérité
- À l'installation : admin commune voit la liste des permissions demandées (UI dashboard, type "Android-like permissions")
- Static analysis Python à la soumission PR : déclaré vs effectif. Refus si discordance.
- Au runtime : middleware CF vérifie que l'accès aux champs `users` ne dépasse pas la déclaration ; RLS Firestore générées depuis `ownedCollections`

### Capabilities standard

| Capability | Description |
|---|---|
| `user.read: [field, …]` | Lecture champs spécifiques de `users/{uid}` |
| `user.write: [field, …]` | Écriture champs spécifiques (rare, justification requise) |
| `module.read: [path]` | Lecture de collections d'un autre module (avec son accord ou collection partagée publique) |
| `module.write` | Écriture cross-module (interdit pour modules communauté) |
| `fcm.send` | Envoi de notifications push, topics restreints |
| `storage.read/write: [path]` | Firebase Storage |
| `cloudFunctions: [name, …]` | Déclaration des CFs exposées par le module |
| `external.http: [domain]` | Appels HTTP sortants vers domaines déclarés |

### Distinction officiel / communauté

- **Officiel** (équipe core / Awans) : SLA, sécurité auditée, badge visible
- **Communauté** (tiers) : review légère, "as is", admin commune voit clairement la distinction avant d'activer

## Marketplace — `communesolutions.be/marketplace`

### Pour les communes

- Catalogue (description, captures, démo, auteur, licence, lien repo)
- **Manifest visible** : capabilities demandées, comme une page de permissions Android
- Versioning + matrice de compat (`module v1.2 ≥ core v3.0`)
- Distinction officiel / communauté visible
- UI dashboard d'activation/désactivation par commune
- Pas de notation/reviews tant que la communauté est petite (biais, brigading)

### Pour les devs

- `communesolutions.be/developers` : doc + tuto + showcase
- CLI : `npx create-commune-module mon-module` → squelette livré (manifest, CF Python, DSL UI, tests, emulator)
- Emulator local : commune fictive + Firebase emulator + app simulator
- Soumission : PR sur `github.com/communesolutions/modules-community`
- CI : tests, lint, security scan, semver check, preview deployment
- Review humaine : mainteneurs core, RFC pour gros modules
- Merge → publication marketplace + semver + changelog auto
- Bot de migration assistée pour breaking changes du core

## Flow commune — configurer son app

1. **Onboarding** : provisioning auto (`<commune>.communesolutions.be`, projet Firebase, branding)
2. **Dashboard admin commune** → section Modules (catalogue + état activé/désactivé)
3. **Activer un module** :
   - Choix placement (tab bar 5 slots ou section "Plus")
   - Config spécifique (URL endpoint, settings, seed data)
   - Permissions accordées (capabilities visibles)
4. **Publier** :
   - Modules server-driven → activation runtime instantanée
   - Modules avec extension native → CI build app par commune (≈30 min) + upload stores
5. **Mise à jour** : notif dashboard, admin valide diff (changelog + nouvelles permissions), nouveau build/activation
6. **Désactivation** : écran masqué, data préservée (rétention configurable RGPD)

## Modèle économique — MVP

- **Abonnement par commune**, géré **hors plateforme** (facturation manuelle toi → commune)
- Pas d'intégration Stripe / billing automation pour MVP
- Champ `subscriptionStatus` (active/suspended/trial) sur tenant côté backend pour suspension d'accès si non-paiement
- Réévaluation à 5-10 communes adoptantes

## Licence & gouvernance

### Licence

- **Core** : EUPL 1.2 (créée pour secteur public européen, copyleft, compatible AGPL/GPL, traduite en 23 langues UE)
- **Modules officiels** : EUPL 1.2 par défaut
- **Modules communauté** : libre choix du contributeur (recommandation EUPL ou MIT, AGPL accepté)

### Gouvernance

- **MVP** : Vincent BDFL, Awans = sponsor de référence
- **À terme** : asbl ou structure portée par les communes adoptantes + UVCW (Union Villes et Communes Wallonie), puis intégration Région wallonne possible

## Décisions ouvertes

- [x] ~~Format DSL définitif~~ : JSON Schema. Templating **Mustache-like** (`{{ path.to.value }}`), avec préservation du type natif quand l'expression est une seule binding (cf "Notes du spike"). Validé 2026-04-30.
- [ ] Versioning des contrats d'extension (SemVer + comportement sur breaking change)
- [ ] Multi-runtime backend (Python only en MVP, ouvrir Node/Go plus tard ?)
- [ ] i18n / multi-langue (`displayName: { fr: ..., nl: ..., de: ... }` dès le manifest)
- [ ] Quotas par module (rate limit CFs, taille collections, nombre d'écrans)
- [ ] Mode hors-ligne : que se passe-t-il quand un module DSL appelle une CF sans réseau ? (stale-while-revalidate côté client par défaut ?)
- [ ] Données canoniques répliquées : qui maintient le seed BeST, comment refresh quand BOSA met à jour ?
- [ ] Upload UGC : toujours via CF (mon avis) ou autoriser SDK Storage direct avec RLS dans certains cas ?
- [ ] Vocabulaire fermé `device.permissions` : finaliser la liste canonique (location, camera, photos, notifications, contacts, calendar, bluetooth, motion, …)
- [ ] Stratégies d'agrégation extension points : seuls `priority-merge`, `round-robin`, `concat`, `first-match` documentés — en faut-il d'autres ?
- [ ] Universal Links / App Links : domaine apex `<commune>.communesolutions.be` confirmé, mais qui héberge `apple-app-site-association` quand on a 50 communes ?
- [ ] E-guichet à reprendre quand l'API iMio aura été explorée — risque de découvrir des patterns qu'on n'a pas anticipés (workflows asynchrones longue durée, signature électronique, eID Belgium)
- [ ] **Mapping iconographique SF Symbols ↔ Material** : où héberger la table de correspondance (repo plateforme versionné avec le shell vs marketplace) ? Quel pipeline CI valide qu'une PR module ne référence que des noms mappés ? Première liste seedée au spike (~10 noms) à compléter.
- [ ] **Markdown — liens inline** (`[label](url)`) : les autoriser dans la primitive `markdown` ? Si oui, action au tap = ouvrir l'URL externe, déclencher un deep-link interne, ou choix par DSL ?
- [ ] **Validation JSON Schema des DSL** : qui valide les `screens/*.ssui.json` à la soumission module et au runtime ? Le spike charge des assets bundlés sans validation — la prod doit refuser un DSL invalide AVANT de le rendre.

## Validation par cas d'usage

Le contrat est validé en passant chaque module officiel à la moulinette. Si un module casse le contrat, on adapte le contrat (pas le module).

| Module | Statut | A stressé / stresse |
|---|---|---|
| Sondages | ✅ Conçu | Cross-module feed, multi-question form, migrations, auth-conditional, owned collections, capabilities `user.read` |
| Carte POI | ✅ Conçu | A motivé : primitive `map` dans le DSL, `device.permissions`, pattern `moderation: true`, capability `storage`, extension points dashboard |
| Actualités | ✅ Conçu | A motivé : section `extensionPoints` (hôte), `scheduledJobs` (cron déclaratif), `secrets` (Secret Manager), `visibility: internal`, `moduleAccess`, section `deepLinks`, `config.ui` (formulaire DSL admin), stratégies d'agrégation |
| Agenda | ✅ Conçu | A motivé : primitives DSL `calendar` et `segmented`, section `publicEndpoints` (iCal/RSS/JSON pour tiers, fondation fédération), `device.permissions: calendar.write`. Confirme `moderation: true` (2ème cas après Carte) et `actualites:feed.topCards` (2ème contributeur après Sondages) |
| E-guichet | 🅿️ Parqué | API externe (iMio), workflows async, document upload, suivi de dossiers — trop spéculatif tant qu'on n'a pas exploré l'API iMio |
| Services communaux | À faire | Recherche full-text, filtrage, mini-carte intégrée |
| Vie politique | À faire | (probablement aucun nouveau pattern, à confirmer) |
| Présentation commune | À faire | Singleton document éditable, contributeur à `actualites:feed.topCards` (deuxième cas qui valide l'extension point) |
