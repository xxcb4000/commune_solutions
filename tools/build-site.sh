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

mkdir -p "$OUT/marketplace" "$OUT/core/renderer-web" "$OUT/modules-official" "$OUT/modules-community"
rsync -a --delete landing/public/ "$OUT/"
rsync -a --delete marketplace/public/ "$OUT/marketplace/"
rsync -a --delete core/renderer-web/ "$OUT/core/renderer-web/"
rsync -a --delete modules-official/ "$OUT/modules-official/"
rsync -a --delete modules-community/ "$OUT/modules-community/"

echo "site assemblé → $OUT"
