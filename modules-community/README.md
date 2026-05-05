# Modules communauté

Modules contribués par des développeurs externes ou par la communauté civic-tech wallonne. Chaque sous-dossier ici est un module distinct.

## Distinction officiel ↔ communauté

| Aspect | Officiel (`modules-official/`) | Communauté (`modules-community/`) |
|---|---|---|
| Mainteneur | Équipe core Commune Solutions | Auteur / asbl / dev externe |
| Licence | EUPL-1.2 | Au choix (EUPL-1.2 / MIT / Apache-2.0 / BSD-3-Clause) |
| Capabilities | Toutes (firestore.write, cf.write, device.*) | **Lecture seule** : `firestore.read`, `module.read` |
| CFs Python | Déployées par le core dans le projet de la commune | Pas de CF tiers en v0 (capability `cf.external` arrivera plus tard) |
| Review | Code review interne avant merge | PR review humaine + CI valide manifest |
| Visibilité marketplace | Onglet **Officiels** | Onglet **Communauté** (badge distinct) |

L'admin commune voit clairement la distinction avant d'activer un module dans son dashboard, et voit la liste des capabilités demandées style permissions Android.

## Soumettre un module

Voir [`docs/developers.md`](../docs/developers.md). En résumé :

1. Forker le repo
2. `cp -r modules-template/hello-world modules-community/<votre-id>`
3. Adapter manifest, screens, data
4. `python3 tools/validate-manifests.py`
5. PR vers `main`

La CI valide le schema, l'équipe core review pour cohérence DSL et capabilities. Une fois mergé, le module apparaît automatiquement dans la marketplace au prochain déploiement.

## Modules présents

- [`associations`](associations/) — annuaire des associations / asbl actives sur la commune. Module purement bundlé (data dans le manifest), aucune permission demandée. Sert d'**exemple de référence** pour les contributeurs.
