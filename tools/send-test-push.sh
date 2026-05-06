#!/usr/bin/env bash
# Smoke test CLI : envoie une notification push via la CF send_notification.
# Lit la config Firebase web du tenant (dashboard/firebase-config-<tenant>.json)
# pour obtenir l'apiKey, signe in via Firebase Auth REST API avec un compte
# admin, puis POST sur la CF.
#
# Usage :
#   tools/send-test-push.sh <tenant> <admin-email> <admin-password> [titre] [corps]
#
# Exemples :
#   tools/send-test-push.sh spike-1 demo-a@test.be Pa55word!
#   tools/send-test-push.sh spike-2 demo-b@test.be Pa55word! "Travaux" "Rue Haute fermée"
#
# Requires : curl, jq.
# À utiliser pour le smoke test post-provisionnement d'une commune
# (provision-commune.py l'appellera dans phase 18.8).

set -euo pipefail

if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <tenant> <admin-email> <admin-password> [title] [body]" >&2
    exit 1
fi

TENANT="$1"
EMAIL="$2"
PASSWORD="$3"
TITLE="${4:-Test push}"
BODY="${5:-Smoke test envoyé en CLI à $(date '+%H:%M:%S')}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$REPO_ROOT/dashboard/firebase-config-${TENANT}.json"

if [[ ! -f "$CONFIG" ]]; then
    echo "✗ Config Firebase introuvable : $CONFIG" >&2
    exit 1
fi

API_KEY=$(jq -r '.apiKey' "$CONFIG")
PROJECT_ID=$(jq -r '.projectId' "$CONFIG")
if [[ -z "$API_KEY" || "$API_KEY" == "null" ]]; then
    echo "✗ apiKey manquant dans $CONFIG" >&2
    exit 1
fi

echo "→ Auth ${EMAIL} sur ${PROJECT_ID}…"
AUTH_RESP=$(curl -s -X POST \
    "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"returnSecureToken\":true}")
ID_TOKEN=$(echo "$AUTH_RESP" | jq -r '.idToken // empty')
if [[ -z "$ID_TOKEN" ]]; then
    echo "✗ Auth échouée : $(echo "$AUTH_RESP" | jq -c .)" >&2
    exit 1
fi
echo "  ✓ ID token obtenu"

# La CF vérifie le custom claim admin: true. Si l'user n'a pas le claim,
# on aura 403 — l'admin claim doit être set via tools/set-admin-claim.py.
echo "→ POST send_notification…"
RESP=$(curl -s -w "\n%{http_code}" -X POST \
    "https://europe-west1-${PROJECT_ID}.cloudfunctions.net/send_notification" \
    -H "Authorization: Bearer ${ID_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg t "$TITLE" --arg b "$BODY" '{title: $t, body: $b}')")
HTTP=$(echo "$RESP" | tail -n 1)
BODY_RESP=$(echo "$RESP" | sed '$d')

if [[ "$HTTP" =~ ^2 ]]; then
    echo "  ✓ ${HTTP}"
    echo "$BODY_RESP" | jq .
else
    echo "  ✗ HTTP ${HTTP}"
    echo "$BODY_RESP" | jq . >&2 2>/dev/null || echo "$BODY_RESP"
    exit 1
fi
