# Hello World — module template

Squelette minimal pour démarrer votre propre module Commune Solutions. Clonez ce dossier sous `modules-community/<votre-id>/` puis adaptez.

## Structure

```
hello-world/
├── manifest.json         # contrat module : id, version, capabilities, écrans
├── screens/
│   └── main.json         # description DSL d'un écran
└── data/
    └── sample.json       # données statiques bundlées
```

## Manifest

Champs obligatoires : `id`, `version`, `displayName`, `icon`, `description`, `author`, `licence`, `screens`. Voir `docs/developers.md` pour le schéma complet.

`id` doit correspondre au nom du dossier. `version` suit semver. `licence` doit être dans la liste blanche (EUPL-1.2 / MIT / Apache-2.0 / BSD-3-Clause).

`capabilities: []` — un module communauté ne peut déclarer que des capabilités à lecture seule (`firestore.read`, `module.read`). Pour les écritures (formulaires, vote, etc.), passer en module officiel ou attendre la roadmap CF tiers.

## Écran

Le DSL est du JSON décrivant un arbre de primitives natives (`scroll`, `vstack`, `card`, `text`, `for`, `if`, etc.). Voir `docs/developers.md` pour la liste des 13 primitives validées au spike.

Les chaînes acceptent des templates **Mustache** : `{{ path.to.value }}`. La donnée est définie dans le bloc `data` de l'écran et accessible par le nom de binding.

## Données

Trois sources possibles dans le bloc `data` d'un écran :

- `module:<name>` — fichier JSON statique du module (déclaré dans `manifest.data`)
- `firestore:<path>` — collection ou document du projet Firebase de la commune (read-only en communauté)
- `cf:<endpoint>` — appel à une Cloud Function (officiels uniquement en v0)

## Tester localement

À venir : `npx create-commune-module` (CLI scaffold) + émulateur local intégré. Pour l'instant : copier le module dans `modules-official/<id>/`, ajouter à `tenants/spike/app.json`, lancer le spike iOS ou Android.

## Soumettre

PR sur `github.com/xxcb4000/commune_solutions`, dossier `modules-community/<votre-id>/`. La CI valide le manifest, refuse les schémas invalides. Review humaine ensuite.
