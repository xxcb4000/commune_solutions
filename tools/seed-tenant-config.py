#!/usr/bin/env python3
"""Seed Firestore avec le tenant config (modules + view) par projet commune.

Phase 11.3 : la liste des modules activés et la nav (tabbar) deviennent
runtime-config dans Firestore plutôt que JSON versionné. Ce script lit
`tenants/<id>/app.json` et écrit la partie runtime dans `_config/modules`
du projet Firebase correspondant.

Auth : Firebase Admin SDK + ADC. Bypasse les règles (pas besoin de loosen).

Idempotent : peut être relancé sans danger.

Usage :
    1. `gcloud auth application-default login` (one-off)
    2. `python3 tools/seed-tenant-config.py`
"""
from __future__ import annotations
import json
import sys
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore

ROOT = Path(__file__).resolve().parent.parent
TENANTS_DIR = ROOT / "tenants"

# Mapping local tenant id → projet Firebase de la commune
TENANT_TO_PROJECT = {
    "spike": "commune-spike-1",
    "spike-2": "commune-spike-2",
}


def client_for(project: str):
    app = firebase_admin.initialize_app(
        credentials.ApplicationDefault(),
        {"projectId": project},
        name=project,
    )
    return firestore.client(app)


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
    db = client_for(project)
    try:
        db.collection("_config").document("modules").set(runtime)
        print(f"  ✓ {project}/_config/modules")
    except Exception as e:
        print(f"  ✗ {project}/_config/modules: {e}")
        sys.exit(1)


def main():
    for tenant_id in TENANT_TO_PROJECT.keys():
        seed_tenant(tenant_id)


if __name__ == "__main__":
    main()
