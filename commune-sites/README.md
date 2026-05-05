# Commune sites

Sites web publics par commune, servis sur `<commune-id>.communesolutions.be` via Firebase Hosting.

## Structure

- `_template/` — squelette dont sont dérivés les sites individuels (committé)
- `<commune-id>/` — site matérialisé pour une commune (gitignored, output de `tools/build-commune-site.py`)

## Contenu d'un site commune

Minimal : une landing branded (label + dots + nom de commune + CTA download apps), plus les fichiers d'association mobile :

- `public/index.html` — landing
- `public/style.css` — styles
- `public/.well-known/apple-app-site-association` — Universal Links iOS (associe le domain au bundle ID iOS)
- `public/.well-known/assetlinks.json` — App Links Android (associe le domain au package + sha256 cert)
- `firebase.json` — config Firebase Hosting (target site, headers cache + content-type pour `.well-known/`)

Le sha256 fingerprint Android est laissé en placeholder dans `assetlinks.json` à la génération — à compléter après le premier build release signé (via `keytool -list -v -keystore ...`).

## Workflow

```sh
# 1. Générer le site depuis tenants/<commune-id>/app.json + _template/
python3 tools/build-commune-site.py awans

# 2. Setup hosting + DNS (manuel, cf docs/skills/onboard-commune-dns.md)

# 3. Deploy
cd commune-sites/awans
firebase deploy --project commune-awans --only hosting
```

Voir [`../docs/skills/onboard-commune-dns.md`](../docs/skills/onboard-commune-dns.md) pour la procédure complète DNS Infomaniak + Firebase Hosting custom domain.
