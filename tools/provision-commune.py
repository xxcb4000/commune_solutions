#!/usr/bin/env python3
"""Provisionne une commune (post Firebase project creation).

Automatise tout ce qui est répétable APRÈS qu'un projet Firebase a été
créé manuellement :
  - Création des apps SDK iOS / Android / Web (idempotent)
  - Téléchargement des configs SDK aux bons emplacements
  - Génération de `tenants/<commune-id>/app.json` starter
  - Initialisation de `_config/modules` dans Firestore (modules par
    défaut + tabbar correspondante)

Hors scope (à faire manuellement, sera couvert par un skill plus tard) :
  - `firebase projects:create commune-<id>` (rate-limité, parfois
    interactif pour billing)
  - Activation Firestore (`firebase init firestore` ou via console)
  - Activation Auth (Email/Password) — via console
  - Création des comptes admin + custom claim `admin: true`
    (`tools/set-admin-claim.py`)
  - Deploy CFs + Firestore rules (`firebase deploy --only ...`)

Prérequis :
  - `firebase login` — authentifié sur le compte qui a accès au projet
  - `gcloud auth application-default login` — pour ADC (Firestore admin)
  - `firebase-admin` Python (déjà installé pour les autres seed scripts)
  - Le projet Firebase doit exister + Firestore activé

Usage :
  python3 tools/provision-commune.py <commune-id> --display-name "<Nom>" \\
    [--firebase-project commune-<commune-id>] \\
    [--firebase-subfolder <commune-id>] \\
    [--bundle-prefix be.communesolutions]

Exemple (cas Awans) :
  python3 tools/provision-commune.py awans --display-name "Awans"

Idempotent : peut être relancé sans danger. Les apps existantes sont
détectées par bundle ID / package name / display name, configs
re-téléchargées, tenant local préservé s'il existe déjà.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_BUNDLE_PREFIX = "be.communesolutions"
DEFAULT_REGION = "europe-west1"

# Modules par défaut activés à la création — communication-only, capabilités
# en lecture seule. La commune peut activer la carte / sondages plus tard
# depuis le dashboard.
STARTER_MODULES = ["actualites", "agenda", "info"]
STARTER_TABS = [
    {"title": "Actualités", "icon": "newspaper", "screen": "actualites:feed"},
    {"title": "Agenda", "icon": "calendar", "screen": "agenda:list"},
    {"title": "Infos", "icon": "info.circle", "screen": "info:main"},
]
DEFAULT_BRAND_DOTS = [
    "#1976d2", "#26a69a", "#ffa000", "#ec407a", "#7e57c2", "#26c6da",
]


def run(cmd: list[str], capture: bool = True) -> subprocess.CompletedProcess:
    """Wrapper subprocess avec print + check_returncode + erreur lisible."""
    print(f"  $ {' '.join(cmd)}")
    res = subprocess.run(cmd, capture_output=capture, text=True)
    if res.returncode != 0:
        sys.stderr.write(f"\n✗ Échec ({res.returncode}): {' '.join(cmd)}\n")
        if res.stderr:
            sys.stderr.write(res.stderr)
        sys.exit(res.returncode)
    return res


def check_firebase_cli() -> None:
    res = subprocess.run(["firebase", "--version"], capture_output=True, text=True)
    if res.returncode != 0:
        sys.exit("✗ Firebase CLI introuvable. Install : npm install -g firebase-tools")


def project_exists(project_id: str) -> bool:
    out = run(["firebase", "projects:list", "--json"]).stdout
    try:
        data = json.loads(out)
    except json.JSONDecodeError:
        return False
    projects = data.get("result", []) if isinstance(data, dict) else []
    return any(p.get("projectId") == project_id for p in projects)


def list_apps(project_id: str, platform: str) -> list[dict]:
    """platform = 'IOS' | 'ANDROID' | 'WEB'"""
    res = subprocess.run(
        ["firebase", "apps:list", platform, "--project", project_id, "--json"],
        capture_output=True, text=True,
    )
    if res.returncode != 0:
        return []
    try:
        data = json.loads(res.stdout)
    except json.JSONDecodeError:
        return []
    return data.get("result", []) if isinstance(data, dict) else []


def find_existing_app(apps: list[dict], platform: str, identifier: str) -> str | None:
    for app in apps:
        if platform == "IOS" and app.get("bundleId") == identifier:
            return app.get("appId")
        if platform == "ANDROID" and app.get("packageName") == identifier:
            return app.get("appId")
        if platform == "WEB" and app.get("displayName") == identifier:
            return app.get("appId")
    return None


def create_app(project_id: str, platform: str, display_name: str, identifier: str | None) -> str:
    cmd = [
        "firebase", "apps:create", platform, display_name,
        "--project", project_id,
    ]
    if platform == "IOS" and identifier:
        cmd += ["--bundle-id", identifier]
    elif platform == "ANDROID" and identifier:
        cmd += ["--package-name", identifier]
    out = run(cmd).stdout
    # Output line ressemble à : "App ID: 1:123:ios:abcdef"
    for line in out.splitlines():
        line = line.strip()
        if line.lower().startswith("app id:"):
            return line.split(":", 1)[1].strip()
    sys.exit(f"✗ App créée mais ID introuvable dans:\n{out}")


def get_or_create_app(project_id: str, platform: str, display_name: str, identifier: str | None) -> str:
    apps = list_apps(project_id, platform)
    lookup_key = identifier if platform != "WEB" else display_name
    existing = find_existing_app(apps, platform, lookup_key)
    if existing:
        print(f"  ✓ {platform} app exists: {existing}")
        return existing
    print(f"  → creating {platform} app '{display_name}'…")
    return create_app(project_id, platform, display_name, identifier)


def download_sdk_config(project_id: str, platform: str, app_id: str, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    rel = target.relative_to(ROOT)
    print(f"  → SDK config {platform} → {rel}")
    run([
        "firebase", "apps:sdkconfig", platform, app_id,
        "--project", project_id,
        "--out", str(target),
    ])


def write_tenant_config(
    commune_id: str,
    display_name: str,
    firebase_subfolder: str,
    firebase_project: str,
    bundle_id: str,
) -> dict:
    tenant_path = ROOT / "tenants" / commune_id / "app.json"
    if tenant_path.exists():
        print(f"  ✓ {tenant_path.relative_to(ROOT)} existe déjà — préservé")
        return json.loads(tenant_path.read_text())

    config = {
        "tenant": commune_id,
        "firebase": firebase_subfolder,
        "functionsBaseURL": f"https://{DEFAULT_REGION}-{firebase_project}.cloudfunctions.net",
        "build": {
            "bundleId": bundle_id,
            "displayName": display_name,
        },
        "modules": [{"id": m, "version": "0.1.0"} for m in STARTER_MODULES],
        "view": {
            "type": "tabbar",
            "brand": {
                "label": display_name.upper(),
                "textColor": "#0f172a",
                "dots": DEFAULT_BRAND_DOTS,
            },
            "tabs": STARTER_TABS,
        },
    }
    tenant_path.parent.mkdir(parents=True, exist_ok=True)
    tenant_path.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n")
    print(f"  ✓ wrote {tenant_path.relative_to(ROOT)}")
    return config


def init_firestore_runtime_config(project_id: str, modules: list[dict], view: dict) -> None:
    print(f"  → Firestore _config/modules ({project_id})…")
    app_name = f"provision-{project_id}"
    try:
        firebase_admin.get_app(app_name)
    except ValueError:
        firebase_admin.initialize_app(
            credentials.ApplicationDefault(),
            {"projectId": project_id},
            name=app_name,
        )
    db = firestore.client(firebase_admin.get_app(app_name))
    db.collection("_config").document("modules").set({
        "modules": modules,
        "view": view,
        "seededFromBundle": True,
    }, merge=True)
    print("  ✓ _config/modules écrit")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Provision une commune (post Firebase project creation)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("commune_id", help="Commune ID lowercase kebab-case (ex: 'awans')")
    parser.add_argument("--display-name", required=True, help="Nom affiché (ex: 'Awans')")
    parser.add_argument("--firebase-project", default=None,
                        help="Firebase project ID (default: commune-<commune-id>)")
    parser.add_argument("--firebase-subfolder", default=None,
                        help="Subfolder dans core/firebase/ (default: <commune-id>)")
    parser.add_argument("--bundle-prefix", default=DEFAULT_BUNDLE_PREFIX,
                        help=f"Bundle ID / package prefix (default: {DEFAULT_BUNDLE_PREFIX})")
    args = parser.parse_args()

    commune_id = args.commune_id
    display_name = args.display_name
    project_id = args.firebase_project or f"commune-{commune_id}"
    fb_subfolder = args.firebase_subfolder or commune_id
    bundle_id = f"{args.bundle_prefix}.{commune_id.replace('-', '')}"

    print(f"\nProvisioning commune={commune_id}")
    print(f"  Firebase project    : {project_id}")
    print(f"  Firebase subfolder  : core/firebase/{fb_subfolder}/")
    print(f"  Bundle ID / package : {bundle_id}")
    print(f"  Display name        : {display_name}\n")

    check_firebase_cli()

    print("→ vérification projet")
    if not project_exists(project_id):
        sys.exit(
            f"✗ Firebase project '{project_id}' introuvable.\n"
            f"  Crée-le d'abord :\n"
            f"    firebase projects:create {project_id}\n"
            f"  Active Firestore via la console (mode test ou rules versionnées)."
        )
    print(f"  ✓ {project_id} existe")

    print("\n→ apps SDK")
    ios_app = get_or_create_app(project_id, "IOS", f"{display_name} iOS", bundle_id)
    android_app = get_or_create_app(project_id, "ANDROID", f"{display_name} Android", bundle_id)
    web_app = get_or_create_app(project_id, "WEB", f"{display_name} Web", None)

    print("\n→ configs SDK")
    download_sdk_config(project_id, "IOS", ios_app,
                        ROOT / "core" / "firebase" / fb_subfolder / "GoogleService-Info.plist")
    download_sdk_config(project_id, "ANDROID", android_app,
                        ROOT / "core" / "firebase" / fb_subfolder / "google-services.json")
    download_sdk_config(project_id, "WEB", web_app,
                        ROOT / "dashboard" / f"firebase-config-{fb_subfolder}.json")

    print("\n→ tenant config local")
    config = write_tenant_config(commune_id, display_name, fb_subfolder, project_id, bundle_id)

    print("\n→ Firestore runtime config")
    init_firestore_runtime_config(project_id, config["modules"], config["view"])

    print(f"\n✓ Commune {commune_id} provisionnée.\n")
    print("Next steps :")
    print(f"  iOS    : tools/build-commune-app.sh {commune_id} <device-udid>")
    print(f"  Android: cd spike/android && ./gradlew :app:assembleDebug -PcommuneId={commune_id}")
    print(f"  Admin  : tools/set-admin-claim.py --project {project_id} --email <admin@email>")
    print(f"  CFs    : cd core/cloud-functions && firebase deploy --project {project_id} --only functions")


if __name__ == "__main__":
    main()
