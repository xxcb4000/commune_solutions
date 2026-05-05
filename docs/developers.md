# Écrire un module Commune Solutions

Ce guide vous permet d'écrire votre premier module en moins d'une heure. Le contrat plateforme complet est dans [`platform.md`](platform.md) — ici on se concentre sur le strict nécessaire pour soumettre un module communautaire.

## Quickstart

1. **Forker** [github.com/xxcb4000/commune_solutions](https://github.com/xxcb4000/commune_solutions)
2. **Scaffolder** le squelette :
   ```sh
   tools/create-commune-module.sh mon-module "Mon module"
   ```
   Cela crée `modules-community/mon-module/` à partir du template `hello-world`, avec le manifest pré-rempli (id, displayName, license MIT par défaut). Voir aussi `modules-community/associations/` comme exemple de référence.
3. **Adapter** `manifest.json`, `screens/`, `data/` pour décrire votre module
4. **Vérifier** localement : `python3 tools/validate-manifests.py`
5. **Soumettre** une PR vers `main`

La CI valide le manifest. La review humaine porte sur la cohérence DSL, les capabilities demandées, la qualité du contenu.

## Manifest schema

```json
{
  "id": "mon-module",
  "version": "0.1.0",
  "displayName": "Mon Module",
  "icon": "info.circle",
  "description": "Phrase courte (≤ 200 chars) qui sera affichée sur la card du catalogue.",
  "longDescription": "Description plus détaillée pour la page de détail. Pas de limite stricte mais restez concis.",
  "author": "Votre Nom ou Organisation",
  "licence": "EUPL-1.2",
  "official": false,
  "tags": ["communication", "exemple"],
  "capabilities": [],
  "screens": {
    "main": "screens/main.json"
  },
  "data": {
    "sample": "data/sample.json"
  }
}
```

| Champ | Obligatoire | Notes |
|---|---|---|
| `id` | ✅ | Doit correspondre au nom du dossier. Lowercase, kebab-case. |
| `version` | ✅ | Semver strict (`MAJOR.MINOR.PATCH`). |
| `displayName` | ✅ | Nom affiché dans la marketplace et dans l'app. |
| `icon` | ✅ | Nom **SF Symbol** (Apple). Mappé en Material Icon côté Android. |
| `description` | ✅ | ≤ 200 chars. Visible dans le catalogue. |
| `longDescription` | recommandé | Page de détail. |
| `author` | ✅ | Personne ou organisation responsable. |
| `licence` | ✅ | `EUPL-1.2`, `MIT`, `Apache-2.0` ou `BSD-3-Clause`. |
| `official` | ✅ | `false` pour les modules communauté (par défaut). |
| `tags` | optionnel | 1-3 tags courts. |
| `capabilities` | ✅ | Voir section dédiée. Liste vide = aucune permission demandée. |
| `screens` | ✅ | Au moins un écran. La clé est l'identifiant interne, la valeur est le chemin relatif. |
| `data` | optionnel | Sources de données statiques bundlées avec le module. |

## Capabilities (modules communauté)

En v0, un module communautaire peut déclarer :

| Type | Cible | Usage |
|---|---|---|
| `firestore.read` | Nom de collection ou de document | Lit dans le projet Firebase de la commune. RLS activées : pas d'accès aux collections d'autres modules sans accord. |
| `module.read` | `<autre-module>:<collection>` | Lecture cross-module si l'hôte a déclaré une `extensionPoint` correspondante. |
| `cf.external` | URL `https://...` complète | Le module appelle ses propres Cloud Functions hébergées par l'auteur (météo, transports, scrapers, etc.). L'ID token Firebase de l'utilisateur est passé en `Authorization: Bearer <token>` ; l'auteur valide côté serveur. Voir section dédiée ci-dessous. |

Les capabilities **d'écriture sur le projet Firebase de la commune** (`firestore.write`, `cf.write`, `device.*`) sont réservées aux modules officiels en v0.

Format :

```json
"capabilities": [
  {
    "type": "firestore.read",
    "target": "events_public",
    "description": "Lecture des événements publiés par la commune"
  }
]
```

Le champ `description` est **visible par l'admin commune** quand il active votre module — soyez clair sur ce que vous lisez et pourquoi.

### Capability `cf.external` — Cloud Functions externes

Pour les modules qui ont besoin d'une logique serveur sans toucher au Firestore de la commune (lecture API tierce, scraping, agrégation), déclarer :

```json
"cfExternal": {
  "baseURL": "https://votre-mod.example.org"
},
"capabilities": [
  {
    "type": "cf.external",
    "target": "https://votre-mod.example.org",
    "description": "Lit la météo locale via une API hébergée par l'auteur du module"
  }
]
```

- Le `target` de la capability **doit être identique** au `cfExternal.baseURL` (validé par la CI)
- Le module appelle ses endpoints via la primitive DSL `action: { type: "cf", endpoint: "<route>" }` — le renderer route vers `<baseURL>/<route>` au lieu des CFs officielles de la commune
- Le serveur reçoit `Authorization: Bearer <id-token>` et doit valider via Firebase Admin SDK pour identifier la commune + l'utilisateur
- L'admin de la commune voit l'URL en clair lors de l'activation et accepte ou refuse (Android-style permission)

⚠️ **Statut** : le contrat manifest et la validation CI sont en place dès aujourd'hui (vous pouvez déclarer la capability et passer la CI). Le **routing renderer** sera implémenté quand un premier module en aura besoin — d'ici là, déclarer la capability ne donne pas encore le pouvoir d'appeler une URL externe à runtime. Cf [`docs/roadmap.md`](roadmap.md) §13.4.

## DSL UI — primitives

Les écrans sont du JSON déclaratif. Le renderer iOS (SwiftUI) et Android (Compose) interprètent le même contrat. **13 primitives** validées au spike :

### Layout
- `scroll` — conteneur scrollable, `refreshable: true` pour pull-to-refresh
- `vstack` / `hstack` — layout vertical / horizontal, `spacing`, `padding`, `alignment`
- `header` — titre + sous-titre stylés
- `card` — surface élevée, optionnellement `action` pour la rendre tappable

### Contenu
- `text` — texte stylé : `style` (title1..3, body, caption, badge), `color` (primary/secondary/tertiary)
- `image` — `url` (Firestore ou externe), `aspectRatio`, `cornerRadius`
- `markdown` — bloc markdown rendu (titres, gras, listes, liens si autorisé)

### Logique
- `for` — boucle sur une liste. `in: "items"`, `as: "item"`, `child: { ... }`
- `if` — rendu conditionnel. `condition: "{{ item.featured }}"`, `then: { ... }`, optionnel `else`

### Navigation
- `tabbar` — barre d'onglets (5 max), chaque tab pointe vers un écran
- `calendar` — vue calendrier mensuelle, événements depuis une source de données

### Forms
- `field` — input formulaire. Sous-types : `email`, `secret`, `text`, `text.long`, `yesno`, `radio`, `scale`. `id` = clé dans le form state.
- `button` — bouton, `action` = `navigate` (vers un autre écran) ou `cf` (appel Cloud Function, officiels seulement)

### Templating

Les chaînes acceptent du Mustache : `{{ path.to.value }}`. Si l'expression est exactement une seule binding, le type natif est préservé (booléen, nombre, etc.). Sinon le résultat est stringifié.

### Sources de données

Dans le bloc `data` d'un écran :

```json
"data": {
  "items": "firestore:events",
  "config": "@settings"
}
```

| Préfixe | Description |
|---|---|
| `firestore:<path>` | Collection ou document Firestore. Lecture, scope = projet de la commune. |
| `@<name>` | Fichier JSON bundlé avec le module (déclaré dans `manifest.data`). |
| `cf:<endpoint>` | Appel d'une Cloud Function (officiels uniquement). |

## Icônes

Le DSL utilise les noms **SF Symbols** (Apple). Le renderer Android maintient une **table de correspondance** SF Symbol → Material Icon. Une icône non mappée est rejetée par la CI.

La table actuelle est minimale (~10 noms). Pour ajouter une icône, soumettez une PR sur le repo plateforme avec la mise à jour de la table.

## Tester localement

### Avec un projet Firebase existant

1. Le module est déjà dans `modules-community/<id>/` (créé via `tools/create-commune-module.sh`)
2. Activer votre module sur le tenant `spike` via le dashboard admin (`http://localhost:8770` → Modules), ou directement via Firestore (`_config/modules`)
3. Lancer le spike iOS (`spike/ios/`) ou Android (`spike/android/`) — voir README racine

### Avec les Firebase emulators (sans projet Firebase réel)

Pour développer sans dépendance à un vrai projet Firebase :

```sh
# Terminal 1 : démarre Auth + Firestore + Functions emulators + UI
tools/dev-emulators.sh

# Terminal 2 : seed les emulators avec les données de test
FIRESTORE_EMULATOR_HOST=localhost:8080 \
  FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 \
  python3 tools/seed-firestore.py

# Terminal 3 (Android emulator) : pointer le SDK sur les emulators
cd spike/android && ./gradlew :app:installDebug \
  -PfirebaseEmulatorHost=10.0.2.2

# iOS Simulator : pareil mais via xcodegen env var (TODO : flag dans
# build-commune-app.sh à venir)
```

L'UI Firebase (`http://localhost:4000`) permet de browser les données et créer des users de test à la volée.

## Validation manifest

```bash
python3 tools/validate-manifests.py
```

Vérifie : champs obligatoires, semver, licence whitelist, fichiers d'écran présents, capabilities bien formées. La CI fait pareil sur chaque PR.

## Soumettre

1. Branch + commit + push sur votre fork
2. Ouvrir une PR vers `main` du repo plateforme
3. La CI valide le manifest
4. Un mainteneur core review : qualité DSL, capabilities justifiées, contenu approprié
5. Merge → publication automatique dans la marketplace au prochain deploy

Politique de review (SLA + critères de rejet) : [`docs/contributing.md`](contributing.md) — *à venir*.
