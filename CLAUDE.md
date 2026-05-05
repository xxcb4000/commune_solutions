# Commune Solutions

Plateforme civic tech open source à destination des communes wallonnes : multi-communes white-label + architecture à modules. Marketplace publique sur `communesolutions.be/marketplace`. Licence EUPL 1.2 sur le core. Repo greenfield, aucune appli existante n'est migrée.

## Phase actuelle (mai 2026)

Pipeline complet validé end-to-end sur 2 tenants test (Démo A / Démo B). Tout est live :
- 5 modules officiels (`actualites` / `agenda` / `sondages` / `info` / `carte`) + 2 modules communauté (`associations` / `restos-locaux`) — exercés en réel sur device + dashboard admin
- Renderers iOS (SwiftUI) + Android (Compose) + **web** (3ème renderer JS pour preview navigateur)
- Build paramétré single-commune iOS + Android, provisioning Firebase auto, fastlane TestFlight scaffold, DNS + AASA + assetlinks templates
- Dashboard admin commune avec CRUD modules + branding + modération UGC + Storage upload, déployé sur les projets spike-1 + spike-2
- Marketplace `communesolutions.be/marketplace` avec catalogue + détail + preview hostée + auto-deploy GitHub Actions sur push main
- CI : `validate-manifests.yml` sur PR + `deploy-marketplace.yml` sur main
- Pipeline contributeur exercé end-to-end (PR #1 mergée pour `restos-locaux`, modération UGC en réel via "Proposer un événement")

**Reste sur la roadmap (cf `docs/roadmap.md`)** :
- Provisionnement réel d'une vraie commune (Awans en perspective) — c'est le test final du pipeline end-to-end
- Décisions ouvertes design : i18n, JSON Schema runtime, mode hors-ligne, quotas, etc.

## Docs à lire en priorité

1. **`README.md`** — vision, structure du repo, setup local, roadmap résumée
2. **`docs/roadmap.md`** — état exhaustif fait / à faire / décisions ouvertes
3. **`docs/platform.md`** — design complet du contrat module : manifest, DSL UI, capabilities, extension points, marketplace, tenant model, licence, gouvernance, décisions ouvertes
4. **`spike/SPIKE_VERDICT.md`** — verdict GO du spike, primitives validées, surprises rencontrées, recommandations

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
- **Code de la plateforme** (renderer, modules officiels, dashboard, tooling) : aucune référence à des communes spécifiques. Les tenants de test s'appellent `spike` / `spike-2` (labels affichés "Démo A" / "Démo B"). Les modules sont packagés comme des contributions externes : neutres.
- **Landing / marketing** (`landing/`, `design/`) : peut mentionner Awans (première commune adoptante) et autres clients réels — c'est du discours commercial, pas du code plateforme.
- Repo **public** sur `github.com/xxcb4000/commune_solutions` (compte perso). Apple Team : Mosa Data Engineering (compte central, signe les apps des communes).
