# Commune Solutions

Plateforme civic tech open source à destination des communes wallonnes : multi-communes white-label + architecture à modules. Marketplace publique sur `communesolutions.be/marketplace`. Licence EUPL 1.2 sur le core. Repo greenfield, aucune appli existante n'est migrée.

## Phase actuelle (avril 2026)

Spike technique **validé GO** (cf `spike/SPIKE_VERDICT.md`) : DSL renderer iOS + Android, modules + tenants + manifests, loader HTTP, multi-tenant + Firebase Auth, Firestore par tenant. 13 primitives natives validées sur device.

Phases qui restent (cf README — section "Au-delà du spike") : backend Python réel (Cloud Functions), form fields DSL, premier vrai module greenfield, dashboard admin commune, marketplace web, onboarding première commune.

## Docs à lire en priorité

1. **`README.md`** — vision, roadmap, structure du repo, setup local
2. **`docs/platform.md`** — design complet du contrat module : manifest, DSL UI, capabilities, extension points, marketplace, tenant model, licence, gouvernance, décisions ouvertes
3. **`spike/SPIKE_VERDICT.md`** — verdict GO du spike, primitives validées, surprises rencontrées, recommandations

## Décisions structurantes déjà prises (cf `docs/platform.md`)

- Core minimal : auth, navigation, multi-tenant, registry de modules. Tout le reste = module.
- DSL UI riche server-driven (90%+ des modules), extension native rare et contribuée au core via PR.
- Tenant Firebase par commune (jusqu'à ~20). Pas de partage data cross-tenant — données globales via API HTTP explicite (`publicEndpoints`).
- Licence EUPL 1.2 sur le core (faite pour secteur public européen).
- Modèle éco MVP : abonnement par commune facturé hors plateforme. Pas de Stripe en MVP.
- Marketplace officiels (équipe core) vs communauté (tiers) avec distinction visible. Capabilities visibles avant install (Android-like permissions).

## Conventions

- **Pas de framework tiers pour le renderer** (Hyperview, etc.). SwiftUI + Compose nativement.
- **Pas de feature flag, pas de migration prématurée.** Le spike est resté jetable, le code de prod sera réécrit en s'appuyant sur sa structure.
- Quand le doc `docs/platform.md` doit évoluer : pas de fichiers MD intermédiaires, on l'édite directement (il sera découpé plus tard quand il grossit trop).
- Aucune référence à des communes spécifiques dans le code public. Les tenants de test s'appellent `spike` / `spike-2` (labels affichés "Démo A" / "Démo B").
