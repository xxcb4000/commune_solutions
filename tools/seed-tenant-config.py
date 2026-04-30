#!/usr/bin/env python3
"""Seed Firestore avec le tenant config (modules + view) par projet commune.

Phase 11.3 : la liste des modules activés et la nav (tabbar) deviennent
runtime-config dans Firestore plutôt que JSON versionné. Ce script lit
`tenants/<id>/app.json` et écrit la partie runtime dans `_config/modules`
du projet Firebase correspondant.

Idempotent : peut être relancé sans danger (PATCH overwrite).

Usage :
    1. Loosen rules : `allow write: if true;` sur `_config/{doc}` (ou globalement)
    2. python3 tools/seed-tenant-config.py
    3. Re-lock rules avec la version qui distingue `_config/*` (public read,
       admin write) du reste.
"""
from __future__ import annotations
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TENANTS_DIR = ROOT / "tenants"

# Mapping local tenant id → projet Firebase de la commune
TENANT_TO_PROJECT = {
    "spike": "commune-spike-1",
    "spike-2": "commune-spike-2",
}


def to_value(v):
    if v is None:
        return {"nullValue": None}
    if isinstance(v, bool):
        return {"booleanValue": v}
    if isinstance(v, int):
        return {"integerValue": str(v)}
    if isinstance(v, float):
        return {"doubleValue": v}
    if isinstance(v, str):
        return {"stringValue": v}
    if isinstance(v, list):
        return {"arrayValue": {"values": [to_value(x) for x in v]}}
    if isinstance(v, dict):
        return {"mapValue": {"fields": {k: to_value(val) for k, val in v.items()}}}
    return {"stringValue": str(v)}


def upsert(project: str, doc_path: str, data: dict):
    url = (
        f"https://firestore.googleapis.com/v1/projects/{project}"
        f"/databases/(default)/documents/{doc_path}"
    )
    body = json.dumps({"fields": {k: to_value(v) for k, v in data.items()}}).encode()
    req = urllib.request.Request(
        url,
        data=body,
        method="PATCH",
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req) as resp:
            print(f"  ✓ {project}/{doc_path} ({resp.status})")
    except urllib.error.HTTPError as e:
        print(f"  ✗ {project}/{doc_path}: {e.code} {e.read().decode()}")
        sys.exit(1)


def seed_tenant(tenant_id: str):
    project = TENANT_TO_PROJECT.get(tenant_id)
    if not project:
        print(f"⚠ tenant {tenant_id}: pas de mapping Firebase, skip")
        return

    config_path = TENANTS_DIR / tenant_id / "app.json"
    if not config_path.exists():
        print(f"⚠ tenant {tenant_id}: {config_path} introuvable, skip")
        return

    config = json.loads(config_path.read_text())
    runtime = {
        "modules": config.get("modules", []),
        "view": config.get("view", {}),
        "seededFromBundle": True,
    }
    print(f"Seed {tenant_id} → {project} (modules={len(runtime['modules'])})")
    upsert(project, "_config/modules", runtime)


def main():
    for tenant_id in TENANT_TO_PROJECT.keys():
        seed_tenant(tenant_id)


if __name__ == "__main__":
    main()
