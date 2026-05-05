# Écrire un module Commune Solutions

Ce guide vous permet d'écrire votre premier module en moins d'une heure. Le contrat plateforme complet est dans [`platform.md`](platform.md) — ici on se concentre sur le strict nécessaire pour soumettre un module communautaire.

## Pré-requis

- Un compte **GitHub**
- **git** + **Python 3.11+** sur votre machine
- C'est tout. Pas besoin de compte Firebase, pas besoin d'iPhone, pas besoin de dev iOS/Android.

## Quickstart

```sh
# 1. Fork sur github.com/xxcb4000/commune_solutions (bouton Fork en haut à droite)

# 2. Clone votre fork
git clone git@github.com:<votre-username>/commune_solutions.git
cd commune_solutions

# 3. Branche thématique
git checkout -b community/mon-module

# 4. Scaffolder le squelette
tools/create-commune-module.sh mon-module "Mon Module"
# → Crée modules-community/mon-module/ avec manifest pré-rempli + 1 écran + data sample

# 5. Adapter
# Éditer modules-community/mon-module/manifest.json (description, author, capabilities, …)
# Éditer screens/main.json (DSL JSON, cf section "DSL UI" plus bas)
# Éditer data/sample.json si vous utilisez @sample (data bundlée dans le module)

# 6. Valider localement
python3 tools/validate-manifests.py

# 7. Commit + push fork
git add modules-community/mon-module/
git commit -m "feat(mon-module): description courte"
git push -u origin community/mon-module

# 8. Ouvrir la PR (via gh CLI ou via UI GitHub)
gh pr create --title "modules-community: Mon Module" --body "..."
```

**Conseil** : le scaffold fait par `create-commune-module.sh` est très minimal. Pour un point de départ plus riche, **fork un module communauté existant** comme [`modules-community/associations`](../modules-community/associations) ou [`modules-community/restos-locaux`](../modules-community/restos-locaux) puis adaptez. Plus rapide qu'écrire le DSL depuis le template.

## Après votre PR

- **CI tourne en ~10s** : le workflow [`validate-manifests.yml`](../.github/workflows/validate-manifests.yml) re-vérifie le manifest sur la PR. Si fail, le check GitHub affiche l'erreur. Push à nouveau sur la branche pour mettre à jour la PR (la CI relance automatiquement).
- **Review humaine** : un mainteneur core regarde la cohérence DSL, les capabilities demandées, la qualité du contenu. Délai variable, vise <1 semaine pour les modules simples.
- **Merge** : si OK, le mainteneur squash-merge. **Vous n'avez pas accès au merge** — c'est volontaire (séparation auteur / mainteneur).
- **Auto-deploy** : dans les **~2 minutes** après le merge, votre module apparaît sur [`communesolutions.be/marketplace`](https://communesolutions.be/marketplace). Le workflow [`deploy-marketplace.yml`](../.github/workflows/deploy-marketplace.yml) régénère le catalog + redeploy le site Firebase Hosting.

## Limites v0 (modules communautaires)

| Vous pouvez | Vous ne pouvez pas |
|---|---|
| Bundler du contenu statique (`data/*.json` + `@<name>` source) | Écrire dans Firestore commune (réservé officiels via dashboard admin) |
| Lire Firestore commune (`firestore.read` capability + collection cible) | Déployer du code Python dans Firebase commune (CFs réservées officiels) |
| Appeler vos propres CFs externes (`cf.external` + URL) | Demander permissions device (location, camera, notifications) |
| Choisir parmi 4 licences (EUPL-1.2 / MIT / Apache-2.0 / BSD-3-Clause) | Modifier l'auth, le tenant config, le branding |
| Utiliser les 13 primitives DSL standard | Ajouter une primitive native (PR sur le core, pas un module) |

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
| `moderation` | Nom de la collection cible | Le module accepte des soumissions UGC (suggestions, signalements, commentaires…) qui passent par la file `_moderation_queue` avant publication. Voir section dédiée ci-dessous. **Réservé aux modules officiels en v0** (les communautaires ne peuvent pas encore avoir de CF côté serveur). |

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

### Capability `moderation` — modération UGC

Pour les modules qui acceptent du contenu généré par les citoyens (suggestions, signalements, commentaires, propositions…), le contenu **doit** passer par une file de modération avant publication.

Pattern :

```json
"moderation": [
  { "collection": "suggestions", "label": "Suggestions citoyennes" }
],
"capabilities": [
  {
    "type": "moderation",
    "target": "suggestions",
    "description": "Les suggestions postées par les citoyens passent en file admin avant publication"
  }
]
```

Pipeline :

1. **Soumission citoyen** : un écran du module a un formulaire (`field.*` primitives) + bouton avec `action: { type: "cf", endpoint: "submit_suggestion" }`
2. **Cloud Function du module** (officials uniquement en v0 — communauté pas autorisée à écrire) : valide le payload, écrit dans `_moderation_queue/<auto-id>` :
   ```json
   {
     "targetCollection": "suggestions",
     "moduleId": "<module-id>",
     "submittedBy": "<uid>",
     "submittedAt": <timestamp>,
     "payload": { "text": "...", "category": "...", "_summary": "..." }
   }
   ```
   Le champ `_summary` est optionnel — affiché tel quel dans la file admin si présent, sinon les premiers champs du payload.
3. **Modération dashboard** : l'admin voit la file unifiée (tous modules confondus) dans l'onglet « Modération ». Pour chaque item :
   - **Approuver** : le payload est copié dans `<targetCollection>` (avec `approvedAt`, `approvedBy`, `originalSubmittedBy`), l'entrée queue est supprimée
   - **Rejeter** : entrée queue supprimée. Pas d'audit log v0 (rajoutable plus tard si besoin)
4. **Lecture mobile** : la collection `<targetCollection>/` ne contient que les items approuvés (publication automatique). Lecture standard via `firestore:<collection>`.

Sécurité :
- `_moderation_queue/` : admin read + delete uniquement, write réservée aux CFs (Admin SDK bypasse)
- `<targetCollection>/` : auth read citoyens + admin write standard (à whitelister dans `firestore.rules` du projet quand le module est activé pour la première fois)

⚠️ **Statut v0** : le contrat manifest, les Firestore rules, et l'UI dashboard sont en place. Aucun module officiel ne produit d'UGC actuellement — la file reste vide tant qu'un premier module n'a pas implémenté le côté soumission.

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

Workflow PR + Code of Conduct + politique de review : [`CONTRIBUTING.md`](../CONTRIBUTING.md) à la racine du repo.
