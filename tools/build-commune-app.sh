#!/usr/bin/env bash
# Build une app iOS pour une commune spécifique (mode single-commune).
#
# Usage:
#   tools/build-commune-app.sh <commune-id> [device-id]
#
# Exemple:
#   tools/build-commune-app.sh spike                    # build only
#   tools/build-commune-app.sh spike FADD...            # build + install + launch
#
# Mécanisme iOS :
#   1. Lit `tenants/<commune-id>/app.json` pour les paramètres build
#      (`build.bundleId`, `build.displayName`, `tenant`, `firebase`).
#   2. Génère `spike/ios/project.commune.yml` (gitignored) à partir du
#      `project.yml` source en patchant Bundle ID, display name, et les
#      clés Info.plist `CommuneTenantID` + `CommuneFirebaseProjects`.
#   3. Lance `xcodegen generate -p project.commune.yml` puis `xcodebuild`
#      sur le scheme CommuneSpike.
#   4. Optionnel : install + launch sur device si UDID fourni.
#
# Le `project.yml` original (multi-tenant dev avec picker) n'est pas touché.
#
# Pour l'équivalent Android (build APK per-commune) :
#   cd spike/android && ./gradlew :app:assembleDebug -PcommuneId=<commune-id>
#
# Sans `-PcommuneId`, le build Android est aussi en mode dev multi-tenant.
set -euo pipefail

COMMUNE_ID="${1:?Usage: $0 <commune-id> [device-id]}"
DEVICE_ID="${2:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_JSON="$ROOT/tenants/$COMMUNE_ID/app.json"
SRC_PROJECT="$ROOT/spike/ios/project.yml"
OUT_PROJECT="$ROOT/spike/ios/project.commune.yml"

[[ -f "$APP_JSON" ]] || { echo "✗ $APP_JSON introuvable"; exit 1; }
[[ -f "$SRC_PROJECT" ]] || { echo "✗ $SRC_PROJECT introuvable"; exit 1; }

# Génère project.commune.yml avec Python (pas de dépendance jq/yq) en
# patchant les 4 champs qui varient. PyYAML est attendu installé localement
# (déjà requis par xcodegen lui-même côté ruby/swift, mais on utilise Python
# pour rester homogène avec le reste de tools/).
python3 - <<PY
import json
import re
from pathlib import Path

app_json = json.loads(Path("$APP_JSON").read_text())
src = Path("$SRC_PROJECT").read_text()

tenant     = app_json["tenant"]
firebase   = app_json["firebase"]
bundle_id  = app_json["build"]["bundleId"]
display    = app_json["build"]["displayName"]

# Substitutions ciblées via regex (préserve le yaml + indentation existante)
out = src
out = re.sub(r"^(\s*bundleIdPrefix:\s*).*", r"\g<1>" + bundle_id, out, count=1, flags=re.M)
out = re.sub(r"^(\s*PRODUCT_BUNDLE_IDENTIFIER:\s*).*", r"\g<1>" + bundle_id, out, count=1, flags=re.M)
out = re.sub(r'^(\s*CFBundleDisplayName:\s*).*', r'\g<1>"' + display + '"', out, count=1, flags=re.M)
out = re.sub(r'^(\s*CommuneTenantID:\s*).*', r'\g<1>"' + tenant + '"', out, count=1, flags=re.M)
out = re.sub(r'^(\s*CommuneFirebaseProjects:\s*).*', r'\g<1>"' + firebase + '"', out, count=1, flags=re.M)

Path("$OUT_PROJECT").write_text(out)
print(f"  ✓ tenant={tenant}  firebase={firebase}  bundle={bundle_id}  name='{display}'")
PY

cd "$ROOT/spike/ios"
echo "→ xcodegen generate (project.commune.yml)"
xcodegen generate --spec project.commune.yml --quiet

echo "→ xcodebuild build"
if [[ -n "$DEVICE_ID" ]]; then
    DEST="id=$DEVICE_ID"
else
    DEST="generic/platform=iOS"
fi

xcodebuild \
    -project CommuneSpike.xcodeproj \
    -scheme CommuneSpike \
    -destination "$DEST" \
    -configuration Debug \
    -derivedDataPath build \
    build 2>&1 | tail -3

APP_PATH="$ROOT/spike/ios/build/Build/Products/Debug-iphoneos/CommuneSpike.app"
[[ -d "$APP_PATH" ]] || { echo "✗ .app introuvable: $APP_PATH"; exit 1; }
echo "  ✓ $APP_PATH"

# Si un device est spécifié, install + launch
if [[ -n "$DEVICE_ID" ]]; then
    echo "→ install on device $DEVICE_ID"
    xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" 2>&1 | tail -2
    BUNDLE=$(python3 -c "import json; print(json.loads(open('$APP_JSON').read())['build']['bundleId'])")
    echo "→ launch $BUNDLE"
    xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE" 2>&1 | tail -2
fi

echo "✓ build commune=$COMMUNE_ID OK"
