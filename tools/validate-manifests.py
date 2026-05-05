"""Valide les manifests des modules avant publication marketplace.

Vérifie le schéma minimum exigé pour qu'un module soit publiable :
champs obligatoires, conventions de versioning (semver), description
non vide, capabilities bien formées, fichiers d'écran présents.

Sortie : exit 0 si tout passe, exit 1 + liste des erreurs sinon.
À brancher dans la CI de la marketplace.
"""
from __future__ import annotations
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = [ROOT / "modules-official", ROOT / "modules-community", ROOT / "modules-template"]

REQUIRED_FIELDS = ["id", "version", "displayName", "icon", "description",
                   "author", "licence", "screens"]
SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+(-[\w.]+)?$")
ALLOWED_LICENCES = {"EUPL-1.2", "MIT", "Apache-2.0", "BSD-3-Clause"}
ALLOWED_CAP_TYPES = {"firestore.read", "firestore.write", "cf.read", "cf.write",
                     "cf.external",
                     "device.location", "device.camera", "device.notifications"}
HTTPS_RE = re.compile(r"^https://[\w.-]+(:\d+)?(/[\w./%-]*)?$")


def validate(manifest_path: Path) -> list[str]:
    errors: list[str] = []
    rel = manifest_path.relative_to(ROOT)
    try:
        data = json.loads(manifest_path.read_text())
    except json.JSONDecodeError as e:
        return [f"{rel}: JSON invalide ({e})"]

    for field in REQUIRED_FIELDS:
        if field not in data or data[field] in (None, "", [], {}):
            errors.append(f"{rel}: champ manquant ou vide « {field} »")

    if "id" in data and data["id"] != manifest_path.parent.name:
        errors.append(f"{rel}: id « {data['id']} » ≠ nom du dossier « {manifest_path.parent.name} »")

    version = data.get("version", "")
    if version and not SEMVER_RE.match(version):
        errors.append(f"{rel}: version « {version} » non semver")

    licence = data.get("licence")
    if licence and licence not in ALLOWED_LICENCES:
        errors.append(f"{rel}: licence « {licence} » non reconnue (autorisées : {sorted(ALLOWED_LICENCES)})")

    desc = data.get("description", "")
    if desc and len(desc) > 200:
        errors.append(f"{rel}: description trop longue ({len(desc)} > 200 chars) — réservez le détail à longDescription")

    cap_types = []
    for cap in data.get("capabilities", []):
        if not isinstance(cap, dict):
            errors.append(f"{rel}: capabilities doit être une liste d'objets")
            continue
        ctype = cap.get("type")
        cap_types.append(ctype)
        if ctype not in ALLOWED_CAP_TYPES:
            errors.append(f"{rel}: capability type « {ctype} » non reconnu")
        if not cap.get("description"):
            errors.append(f"{rel}: capability « {ctype} » sans description (visible utilisateur)")
        if ctype == "cf.external":
            target = cap.get("target", "")
            if not HTTPS_RE.match(target):
                errors.append(f"{rel}: capability cf.external « target » doit être une URL https valide (reçu: « {target} »)")

    # Cohérence cf.external : la capability doit matcher cfExternal.baseURL
    # déclaré au top-level, et inversement.
    cf_external = data.get("cfExternal")
    has_cf_ext_cap = "cf.external" in cap_types
    if has_cf_ext_cap and not isinstance(cf_external, dict):
        errors.append(f"{rel}: capability cf.external présente mais cfExternal.baseURL absent au top-level")
    if isinstance(cf_external, dict):
        if not has_cf_ext_cap:
            errors.append(f"{rel}: cfExternal.baseURL déclaré mais aucune capability cf.external dans capabilities[]")
        base_url = cf_external.get("baseURL", "")
        if not HTTPS_RE.match(base_url):
            errors.append(f"{rel}: cfExternal.baseURL doit être une URL https valide (reçu: « {base_url} »)")
        # Le target de la capability doit être identique à cfExternal.baseURL
        ext_caps = [c for c in data.get("capabilities", []) if isinstance(c, dict) and c.get("type") == "cf.external"]
        for c in ext_caps:
            if c.get("target") != base_url:
                errors.append(
                    f"{rel}: capability cf.external « target » ({c.get('target')}) "
                    f"≠ cfExternal.baseURL ({base_url})"
                )

    for name, rel_path in (data.get("screens") or {}).items():
        screen_file = manifest_path.parent / rel_path
        if not screen_file.exists():
            errors.append(f"{rel}: screen « {name} » → fichier manquant ({rel_path})")

    return errors


def main():
    all_errors: list[str] = []
    count = 0
    for src in SOURCES:
        if not src.exists():
            continue
        for manifest in sorted(src.glob("*/manifest.json")):
            count += 1
            all_errors.extend(validate(manifest))

    if all_errors:
        for e in all_errors:
            print(f"  ✗ {e}")
        print(f"\n{len(all_errors)} erreur(s) sur {count} manifest(s).")
        sys.exit(1)
    print(f"✓ {count} manifest(s) validés.")


if __name__ == "__main__":
    main()
