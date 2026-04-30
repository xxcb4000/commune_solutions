"""Agrège les manifests des modules pour la marketplace.

Lit `modules-official/<id>/manifest.json` (officiels) et un futur
`modules-community/<id>/manifest.json` (communauté, vide en v0). Pour
chaque module, compte aussi le nombre d'écrans/data déclarés. Écrit
le résultat dans `marketplace/public/data/manifests.json` consommé
par le frontend statique.
"""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = [
    (ROOT / "modules-official", True),
    (ROOT / "modules-community", False),
]
OUTPUT = ROOT / "marketplace" / "public" / "data" / "manifests.json"


def collect():
    modules = []
    for src_dir, official in SOURCES:
        if not src_dir.exists():
            continue
        for manifest_path in sorted(src_dir.glob("*/manifest.json")):
            data = json.loads(manifest_path.read_text())
            data["official"] = official if "official" not in data else data["official"]
            data["screenCount"] = len(data.get("screens", {}))
            data["dataCount"] = len(data.get("data", {}))
            modules.append(data)
    return modules


def main():
    modules = collect()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps({"modules": modules}, ensure_ascii=False, indent=2))
    print(f"marketplace: {len(modules)} module(s) → {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
