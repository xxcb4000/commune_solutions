# Commune Solutions

Plateforme civic tech open source à destination des communes wallonnes : multi-communes white-label + architecture à modules. Marketplace publique sur `communesolutions.be/marketplace`. Licence EUPL 1.2 sur le core.

L'app actuelle de la commune d'Awans (repo séparé `~/Documents/Dev/commune_awans/`) est l'**instance pilote** : la même équipe construit la plateforme et son premier déploiement.

## Phase actuelle (avril 2026)

Design contrat plateforme **terminé** : 4 modules officiels passés à la moulinette (Sondages, Carte POI, Actualités, Agenda), 17 patterns identifiés. E-guichet 🅿️ parqué (trop spéculatif tant qu'on n'a pas exploré l'API iMio).

**Prochain pas : spike technique DSL renderer iOS + Android**, 2 semaines max, GO/NO-GO du chantier. Tant que le spike n'a pas tranché, on n'investit pas plus côté plateforme et **rien dans Awans ne change**.

## Docs à lire en priorité

1. **`README.md`** — vision, roadmap, structure du repo
2. **`docs/platform.md`** — design complet du contrat module : manifest, DSL UI, capabilities, extension points, marketplace, tenant model, licence, gouvernance, décisions ouvertes, validation par cas d'usage
3. **`spike/SPIKE_PLAN.md`** — scope, primitives testées, critères de succès/échec, livrables du spike en cours

À la fin du spike : remplir `spike/SPIKE_VERDICT.md` (template fourni) avec verdict explicite, surprises rencontrées, primitives à réviser.

## Lien avec commune_awans/

Le repo `commune_awans/` reste la production en cours (iOS Swift + Android Kotlin + dashboard + backend Firebase). Si la plateforme se concrétise après spike validé, Awans devient la **première instance** : ses fonctionnalités existantes sont progressivement extraites en modules officiels du présent repo (stratégie strangler fig — un module à la fois).

## Décisions structurantes déjà prises (cf `docs/platform.md`)

- Core minimal : auth, navigation, multi-tenant, registry de modules. Tout le reste = module (y compris features historiques d'Awans).
- DSL UI riche server-driven (90%+ des modules), extension native rare et contribuée au core via PR.
- Tenant Firebase par commune (jusqu'à ~20). Pas de partage data cross-tenant — données globales via API HTTP explicite (`publicEndpoints`).
- Licence EUPL 1.2 sur le core (faite pour secteur public européen).
- Modèle éco MVP : abonnement par commune facturé hors plateforme. Pas de Stripe en MVP.
- Marketplace officiels (équipe core) vs communauté (tiers) avec distinction visible. Capabilities visibles avant install (Android-like permissions).

## Conventions

- **Pas d'implémentation tant que le spike n'est pas validé.** Le risque le plus élevé est le rendu DSL → natif. Si on bâcle ça, tout s'effondre.
- **Pas de framework tiers pour le spike** (Hyperview, etc.). Greenfield SwiftUI + Compose.
- **Pas de feature flag, pas de migration prématurée.** Le spike est jetable : si verdict NO-GO, on jette sans regret.
- Quand le doc `docs/platform.md` doit évoluer : pas de fichiers MD intermédiaires, on l'édite directement (il est conçu pour être découpé plus tard quand il grossit trop).
