# Contribuer à Commune Solutions

Merci de votre intérêt pour le projet ! Ce document décrit le workflow de contribution.

> **Statut** : design + spike technique en cours (avril 2026). Pas encore de prod. La gouvernance et le workflow contributions s'affineront avec les premiers contributeurs externes.

## Trois types de contributions

### 1. Module communautaire

Vous voulez **ajouter une fonctionnalité** (un nouveau module) à la marketplace.

Suivez le guide dédié : [`docs/developers.md`](docs/developers.md).

En résumé :
1. Forker ce repo
2. Cloner `modules-template/hello-world/` dans `modules-community/<votre-id>/`
3. Adapter le manifest, les écrans DSL, les data
4. Valider localement : `python3 tools/validate-manifests.py`
5. Ouvrir une PR

La CI valide automatiquement le manifest. La review humaine porte sur la cohérence DSL, les capabilities demandées, la qualité du contenu.

**Capabilities limitées en v0** : `firestore.read` et `module.read` uniquement. Voir [`docs/developers.md`](docs/developers.md) pour les détails et la roadmap d'ouverture.

### 2. Évolution du core (renderer, dashboard, plateforme)

Vous voulez **améliorer la plateforme elle-même** : ajouter une primitive DSL, un extension point, fixer un bug renderer, etc.

Avant d'ouvrir une PR :
- Lire [`docs/platform.md`](docs/platform.md) (contrat plateforme complet)
- Vérifier [`docs/roadmap.md`](docs/roadmap.md) pour voir si le sujet est déjà tracké ou en cours
- Pour les changements structurants (nouveau primitive, breaking change, nouvelle capability) : ouvrir une **issue de discussion** avant la PR

### 3. Documentation, traductions, signalement de bug

- **Bug** : ouvrir une issue avec un titre descriptif, étapes de repro, version (commit hash), platform (iOS/Android/web)
- **Doc** : PR directe bienvenue
- **Traduction** : la plateforme est fr-only en v0. Les contributions i18n (nl, de, en) sont les bienvenues — voir l'état dans [`docs/roadmap.md`](docs/roadmap.md) (i18n est encore une décision ouverte)

## Workflow PR

1. Forker, créer une branche thématique (`feat/<id>`, `fix/<id>`, `docs/<id>`)
2. Commits clairs et atomiques. Convention de message : préfixe descriptif (`renderer:`, `marketplace:`, `module/<id>:`, `docs:`, …)
3. Pousser sur votre fork, ouvrir la PR vers `main`
4. La CI doit passer (validation manifest, plus tard tests + lint)
5. Review : au moins un mainteneur core approuve. Les changements majeurs nécessitent un RFC en amont
6. Merge en squash par défaut (historique linéaire propre)

## Style de commits

- Messages en français OK, anglais OK, restez cohérent dans une PR
- Une ligne courte (≤ 72 chars) qui décrit le **quoi** + **pourquoi**, body si besoin
- Pas de `WIP`, pas de `fix typo` orphelins (squash en local avant push)

## Commit signing / DCO

Pas obligatoire en v0. Si la communauté grossit, on adoptera probablement le **Developer Certificate of Origin** (signature `Signed-off-by:` sur chaque commit) pour clarifier la chaîne de droits sur les contributions.

## Code of Conduct

Voir [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). En résumé : Contributor Covenant 2.1 — interactions respectueuses et constructives.

## Sécurité — disclosure responsable

Voir [`SECURITY.md`](SECURITY.md). **Ne pas ouvrir d'issue publique** pour une vulnérabilité — utiliser le canal de contact privé indiqué.

## Licence

En contribuant à ce repo, vous acceptez que votre contribution soit publiée sous **EUPL 1.2** (voir [`LICENSE`](LICENSE)) — sauf indication contraire claire dans votre PR pour un module communautaire (auquel cas la licence du module communautaire prime, parmi les licences acceptées : EUPL-1.2, MIT, Apache-2.0, BSD-3-Clause).

## Setup local

Voir la section "Setup local" du [`README.md`](README.md).

## Questions

- Issues GitHub pour les questions techniques
- [`docs/platform.md`](docs/platform.md) pour le design rationale
- [`docs/roadmap.md`](docs/roadmap.md) pour savoir où on en est
