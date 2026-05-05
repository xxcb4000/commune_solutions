#!/usr/bin/env bash
# Build assemblé pour Firebase Hosting (site `commune-solutions`).
# Sources :
#   - landing/public/                → racine
#   - marketplace/public/            → /marketplace/
#   - core/renderer-web/             → /core/renderer-web/  (3ème renderer
#                                       servi à preview.html — phase 16.1)
#   - modules-official/              → /modules-official/   (preview lit les
#                                       manifests + screens + data via fetch)
#   - modules-community/             → /modules-community/
#   - tools/build-marketplace.py     → génère marketplace/public/data/manifests.json
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=_site
rm -rf "$OUT"
mkdir -p "$OUT"

python3 tools/build-marketplace.py

# Pas de --delete : `rm -rf "$OUT"` au-dessus a déjà wipé tout l'output,
# donc une simple copie suffit. Le --delete sur landing → $OUT/ avait
# l'effet de bord de supprimer $OUT/core/ et $OUT/marketplace/ créés par
# les autres rsync, d'où le fail CI précédent.
rsync -a landing/public/ "$OUT/"
mkdir -p "$OUT/marketplace" "$OUT/core/renderer-web" "$OUT/modules-official" "$OUT/modules-community"
rsync -a marketplace/public/ "$OUT/marketplace/"
rsync -a core/renderer-web/ "$OUT/core/renderer-web/"
rsync -a modules-official/ "$OUT/modules-official/"
rsync -a modules-community/ "$OUT/modules-community/"

echo "site assemblé → $OUT"
