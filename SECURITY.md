# Politique de sécurité

## Reporter une vulnérabilité

> **Ne pas ouvrir d'issue publique** pour une vulnérabilité de sécurité.

Merci d'utiliser un des canaux **privés** suivants :

1. **GitHub Private Vulnerability Reporting** — préféré
   - Aller sur l'onglet *Security* du repo → *Report a vulnerability*
   - Ce canal est intégré à GitHub et permet une coordination chiffrée du fix
2. **Email** : `contact@mosadata.com`
   - Sujet préfixé `[security]`
   - Clé PGP disponible sur demande si nécessaire

Indiquez :
- Description claire du problème (composant affecté : renderer iOS/Android, dashboard, cloud functions, marketplace, …)
- Étapes de reproduction
- Impact estimé (exécution arbitraire, fuite de données, escalade de privilège, déni de service…)
- Version concernée (commit hash de `main` ou release tag)
- PoC si disponible

## Engagement

- **Accusé de réception** : sous 5 jours ouvrables
- **Premier diagnostic** : sous 14 jours
- **Fix coordonné** : selon sévérité (critical = ASAP avec patch hors-cycle, high = prochain release, medium/low = roadmap publique)
- **Crédit** : on créditera le rapporteur dans le changelog (sauf souhait inverse explicite)

## Périmètre

Ce qui rentre dans le périmètre de disclosure responsable :
- Code core de la plateforme (`core/`, `dashboard/`, `marketplace/`, `tools/`)
- Modules officiels (`modules-official/`)
- Cloud Functions (`core/cloud-functions/`)
- Configuration Firestore rules versionnée

Ce qui n'en relève **pas** (à reporter directement à l'équipe concernée) :
- Apps déployées par une commune spécifique (à signaler à la commune)
- Bugs fonctionnels non liés à la sécurité (issue publique OK)
- Modules communautaires tiers (`modules-community/`) : contacter l'auteur du module en premier

## Statut

- **Pas de programme bug bounty rémunéré** en l'état (projet en design + spike)
- L'équipe core peut faire évoluer cette politique avec l'arrivée des premières communes en prod (cf phase 12 [`docs/roadmap.md`](docs/roadmap.md))

## Bonnes pratiques côté contributeurs

- Pas de secret hardcodé dans le code (configs Firebase, clés API, mots de passe). Tout passe par fichiers gitignored
- Pas d'`allow read|write: if true;` mergé sur `main` dans `firestore.rules` (utile localement pour seed mais à re-locker avant push)
- Validation des entrées utilisateur côté CF (`core/cloud-functions/`) — vérification ID token Firebase Auth obligatoire
- Capabilities déclarées dans les manifests doivent matcher l'usage réel — pas de `firestore.read` sur une collection qui n'est jamais lue
