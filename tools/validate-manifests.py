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
SOURCES = [ROOT / "modules-official", ROOT / "modules-community"]

REQUIRED_FIELDS = ["id", "version", "displayName", "icon", "description",
                   "author", "licence", "screens"]
SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+(-[\w.]+)?$")
ALLOWED_LICENCES = {"EUPL-1.2", "MIT", "Apache-2.0", "BSD-3-Clause"}
ALLOWED_CAP_TYPES = {"firestore.read", "firestore.write", "cf.read", "cf.write",
                     "device.location", "device.camera", "device.notifications"}


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

    for cap in data.get("capabilities", []):
        if not isinstance(cap, dict):
            errors.append(f"{rel}: capabilities doit être une liste d'objets")
            continue
        ctype = cap.get("type")
        if ctype not in ALLOWED_CAP_TYPES:
            errors.append(f"{rel}: capability type « {ctype} » non reconnu")
        if not cap.get("description"):
            errors.append(f"{rel}: capability « {ctype} » sans description (visible utilisateur)")

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
