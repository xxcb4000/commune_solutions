#!/usr/bin/env bash
# Lance les Firebase emulators locaux (Auth + Firestore + Functions + UI)
# pour développer un module sans projet Firebase réel.
#
# Usage :
#   tools/dev-emulators.sh [<project-id>]
#
# `project-id` par défaut = `commune-spike-1`. N'importe quelle valeur
# fonctionne en local — l'emulator simule.
#
# Émulateurs lancés :
#   - Auth      : http://localhost:9099
#   - Firestore : http://localhost:8080
#   - Functions : http://localhost:5001
#   - UI        : http://localhost:4000  (interface web pour browse data)
#
# Pour seed les emulators :
#   FIRESTORE_EMULATOR_HOST=localhost:8080 \
#     FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 \
#     python3 tools/seed-firestore.py
#   (firebase-admin SDK respecte ces env vars automatiquement.)
#
# Pour pointer le spike sur les emulators :
#   iOS :     tools/build-commune-app.sh spike + xcodegen avec env
#             FirebaseEmulatorHost=<IP-mac> dans Info.plist (TODO :
#             flag dans build-commune-app.sh à venir)
#   Android : ./gradlew :app:assembleDebug -PfirebaseEmulatorHost=10.0.2.2
#             (10.0.2.2 = localhost depuis l'émulateur Android)

set -euo pipefail

PROJECT_ID="${1:-commune-spike-1}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v firebase >/dev/null 2>&1; then
    echo "✗ Firebase CLI introuvable. Install : npm install -g firebase-tools"
    exit 1
fi

echo "→ Lancement Firebase emulators (project: $PROJECT_ID)"
echo "  Auth      → localhost:9099"
echo "  Firestore → localhost:8080"
echo "  Functions → localhost:5001"
echo "  UI        → http://localhost:4000"
echo ""
echo "  Ctrl-C pour arrêter."
echo ""

firebase emulators:start \
    --project "$PROJECT_ID" \
    --only auth,firestore,functions
