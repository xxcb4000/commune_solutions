#!/usr/bin/env bash
# Build assemblé pour Firebase Hosting (site `commune-solutions`).
# Sources :
#   - landing/public/        → racine
#   - marketplace/public/    → /marketplace/
#   - tools/build-marketplace.py → génère marketplace/public/data/manifests.json
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=_site
rm -rf "$OUT"
mkdir -p "$OUT"

python3 tools/build-marketplace.py

rsync -a --delete landing/public/ "$OUT/"
rsync -a --delete marketplace/public/ "$OUT/marketplace/"

echo "site assemblé → $OUT"
