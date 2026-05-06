"""Crée les explicit Bundle IDs + active Push Notifications via App Store
Connect API. Phase 18.8 partiellement automatisée — exercé par les 2 spike
tenants pour tester le scaling avant la 1ère vraie commune.

Ce que ce script automatise (côté Apple, via JWT + ASC API) :
  1. Crée un bundle ID explicite si absent (ex. `be.communesolutions.spike`)
  2. Active la capability `PUSH_NOTIFICATIONS` sur ce bundle ID
  3. Idempotent — relancer ne casse rien

Ce qui reste **manuel** côté Firebase Console (pas d'API publique exposée
en 2026 — Firebase Cloud Messaging admin auth key upload se fait via UI) :
  4. Upload de `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` sur
     chaque projet Firebase (Project Settings → Cloud Messaging → Apple
     app configuration → Upload APNs Authentication Key) avec Key ID +
     Team ID. ~30s par commune.
  → À automatiser quand Firebase exposera l'endpoint (voir roadmap 18.8).

Pré-requis :
  - clé ASC API : `~/.appstoreconnect/private_keys/AuthKey_JD5MN9XL6W.p8`
    avec scope « App Manager » minimum (pour bundle IDs + capabilities)
  - PyJWT + requests (`pip install PyJWT requests cryptography`)

Usage :
    python3 tools/setup-push-apple.py
"""
from __future__ import annotations
import time
import sys
from pathlib import Path

import jwt
import requests

ASC_API = "https://api.appstoreconnect.apple.com/v1"
KEY_ID = "JD5MN9XL6W"
ISSUER_ID = "6d48c126-e579-417b-9753-8f458d519b55"
KEY_PATH = Path.home() / ".appstoreconnect" / "private_keys" / f"AuthKey_{KEY_ID}.p8"

# Tenants à provisionner. À étendre quand de vraies communes arriveront ;
# l'idéal serait de lire depuis tenants/<id>/app.json mais en v0 on garde
# le mapping ici pour rester focused.
TENANTS = [
    {"bundle_id": "be.communesolutions.spike",  "name": "Commune Solutions Spike A"},
    {"bundle_id": "be.communesolutions.spike2", "name": "Commune Solutions Spike B"},
]


def asc_token() -> str:
    """JWT ES256 signé avec la clé ASC, 20 min de validité (max Apple)."""
    if not KEY_PATH.exists():
        sys.exit(f"✗ Clé ASC introuvable : {KEY_PATH}")
    now = int(time.time())
    payload = {
        "iss": ISSUER_ID,
        "iat": now,
        "exp": now + 20 * 60,
        "aud": "appstoreconnect-v1",
    }
    headers = {"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}
    return jwt.encode(payload, KEY_PATH.read_text(), algorithm="ES256", headers=headers)


def asc_get(path: str, params: dict | None = None) -> dict:
    r = requests.get(f"{ASC_API}{path}",
                     headers={"Authorization": f"Bearer {asc_token()}"},
                     params=params, timeout=20)
    r.raise_for_status()
    return r.json()


def asc_post(path: str, data: dict) -> dict:
    r = requests.post(f"{ASC_API}{path}",
                      headers={"Authorization": f"Bearer {asc_token()}",
                               "Content-Type": "application/json"},
                      json=data, timeout=20)
    if r.status_code >= 400:
        sys.exit(f"✗ POST {path} → {r.status_code}\n  {r.text[:500]}")
    return r.json()


def find_bundle_id(identifier: str) -> dict | None:
    """Cherche un bundle ID existant. ASC API filtre via filter[identifier]."""
    resp = asc_get("/bundleIds", params={
        "filter[identifier]": identifier,
        "include": "bundleIdCapabilities",
        "limit": 1,
    })
    items = resp.get("data", [])
    if not items:
        return None
    bundle = items[0]
    # Attache les capabilities incluses pour éviter un 2e round-trip.
    bundle["_capabilities"] = [
        inc for inc in resp.get("included", [])
        if inc.get("type") == "bundleIdCapabilities"
    ]
    return bundle


def create_bundle_id(identifier: str, name: str) -> dict:
    """Crée un bundle ID explicite (platform IOS)."""
    return asc_post("/bundleIds", {
        "data": {
            "type": "bundleIds",
            "attributes": {
                "identifier": identifier,
                "name": name,
                "platform": "IOS",
            },
        },
    })["data"]


def has_push_capability(capabilities: list[dict]) -> bool:
    """Vrai si PUSH_NOTIFICATIONS apparaît dans les `included` du GET bundle ID."""
    for cap in capabilities:
        if cap.get("attributes", {}).get("capabilityType") == "PUSH_NOTIFICATIONS":
            return True
    return False


def enable_push(bundle_id_id: str) -> None:
    """Active la capability PUSH_NOTIFICATIONS sur un bundle ID explicite."""
    asc_post("/bundleIdCapabilities", {
        "data": {
            "type": "bundleIdCapabilities",
            "attributes": {"capabilityType": "PUSH_NOTIFICATIONS"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_id_id}},
            },
        },
    })


def main() -> None:
    print(f"App Store Connect — clé {KEY_ID} (issuer {ISSUER_ID[:8]}…)\n")
    for tenant in TENANTS:
        bid = tenant["bundle_id"]
        name = tenant["name"]
        print(f"→ {bid} ({name})")
        existing = find_bundle_id(bid)
        if existing:
            bundle_id_id = existing["id"]
            capabilities = existing.get("_capabilities", [])
            print(f"   ✓ Bundle ID existe (id={bundle_id_id})")
        else:
            created = create_bundle_id(bid, name)
            bundle_id_id = created["id"]
            capabilities = []
            print(f"   ✓ Bundle ID créé (id={bundle_id_id})")
        if has_push_capability(capabilities):
            print(f"   ✓ Push Notifications déjà activée")
        else:
            enable_push(bundle_id_id)
            print(f"   ✓ Push Notifications activée")
    print()
    print("Reste à faire **manuellement** sur Firebase Console (1× par commune) :")
    print(f"  Upload {KEY_PATH} sur :")
    print("    - https://console.firebase.google.com/project/commune-spike-1/settings/cloudmessaging")
    print("    - https://console.firebase.google.com/project/commune-spike-2/settings/cloudmessaging")
    print(f"  Section « Apple app configuration » → Upload APNs Authentication Key")
    print(f"  Key ID : {KEY_ID}     Team ID : TJ2759P685")
    print()
    print("À automatiser dans phase 18.8 quand l'API Firebase exposera APNs key upload.")


if __name__ == "__main__":
    main()
