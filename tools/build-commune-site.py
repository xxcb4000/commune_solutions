#!/usr/bin/env python3
"""Génère le site web public d'une commune (sous-domaine).

Lit `tenants/<commune-id>/app.json` + `commune-sites/_template/` et
matérialise `commune-sites/<commune-id>/` avec :
  - public/index.html (landing branded : label + dots + nom)
  - public/style.css
  - public/.well-known/apple-app-site-association (Universal Links iOS)
  - public/.well-known/assetlinks.json (App Links Android)
  - firebase.json (config hosting per-commune)

Pré-requis sur tenants/<commune-id>/app.json :
  - tenant
  - build.bundleId (iOS = Android dans la convention actuelle)
  - build.displayName (sera affiché en hero)
  - view.brand.label (défaut "" → COMMUNE_ID upper)
  - view.brand.textColor (défaut #0f172a)
  - view.brand.dots (défaut 6 couleurs neutres)

Usage :
  python3 tools/build-commune-site.py <commune-id>

Le sha256 fingerprint Android n'est pas connu avant le premier build
de release signé. Un placeholder est laissé dans assetlinks.json — à
remplir manuellement après la phase 12.4 (fastlane match Android).
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APPLE_TEAM_ID = "TJ2759P685"  # Mosa Data Engineering — cf docs/roadmap.md §15
DEFAULT_DOTS = ["#1976d2", "#26a69a", "#ffa000", "#ec407a", "#7e57c2", "#26c6da"]


def render(template: str, vars: dict) -> str:
    out = template
    for k, v in vars.items():
        out = out.replace("{{" + k + "}}", str(v))
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description="Build commune public site")
    parser.add_argument("commune_id")
    args = parser.parse_args()

    commune_id = args.commune_id
    tenant_path = ROOT / "tenants" / commune_id / "app.json"
    template_dir = ROOT / "commune-sites" / "_template"
    out_dir = ROOT / "commune-sites" / commune_id

    if not tenant_path.exists():
        sys.exit(f"✗ tenants/{commune_id}/app.json introuvable")
    if not template_dir.exists():
        sys.exit("✗ commune-sites/_template/ introuvable")

    tenant = json.loads(tenant_path.read_text())
    build = tenant.get("build", {}) or {}
    brand = (tenant.get("view") or {}).get("brand", {}) or {}

    bundle_id = build.get("bundleId") or f"be.communesolutions.{commune_id.replace('-', '')}"
    display_name = build.get("displayName") or commune_id.title()
    firebase_subfolder = tenant.get("firebase") or commune_id
    firebase_project = f"commune-{firebase_subfolder}"
    brand_label = brand.get("label") or display_name.upper()
    brand_text_color = brand.get("textColor") or "#0f172a"
    dots = brand.get("dots") if isinstance(brand.get("dots"), list) and len(brand.get("dots")) == 6 else DEFAULT_DOTS

    dots_html = "\n            ".join(
        f'<span style="background:{c};"></span>' for c in dots
    )

    template_vars = {
        "COMMUNE_ID": commune_id,
        "COMMUNE_NAME": display_name,
        "BRAND_LABEL": brand_label,
        "BRAND_TEXT_COLOR": brand_text_color,
        "BRAND_DOTS_HTML": dots_html,
        "APPLE_TEAM_ID": APPLE_TEAM_ID,
        "IOS_BUNDLE_ID": bundle_id,
        "ANDROID_PACKAGE_NAME": bundle_id,
        "ANDROID_SHA256_FINGERPRINT": "PLACEHOLDER_SHA256_REMPLIR_APRES_PREMIER_BUILD_RELEASE",
    }

    # Copy template to commune dir, écraser si existe (idempotent)
    if out_dir.exists():
        shutil.rmtree(out_dir)
    shutil.copytree(template_dir, out_dir)

    # Substituer les variables dans tous les fichiers texte
    for f in out_dir.rglob("*"):
        if not f.is_file():
            continue
        # Skip binary files (none expected ici, mais safe)
        try:
            text = f.read_text()
        except UnicodeDecodeError:
            continue
        rendered = render(text, template_vars)
        f.write_text(rendered)

    print(f"✓ commune-sites/{commune_id}/ généré")
    print(f"   bundle    : {bundle_id}")
    print(f"   label     : {brand_label}")
    print(f"   display   : {display_name}")
    print(f"   project   : {firebase_project}")
    print()
    print("Prochaines étapes :")
    print(f"  1. Créer le site Firebase Hosting :")
    print(f"     firebase hosting:sites:create {commune_id} --project {firebase_project}")
    print(f"  2. Ajouter le custom domain {commune_id}.communesolutions.be dans la console Firebase")
    print(f"     → Firebase Console → Hosting → Add custom domain")
    print(f"     → Suit les instructions DNS (TXT verify + A records vers IPs Firebase)")
    print(f"  3. Configurer les DNS chez Infomaniak (cf docs/skills/onboard-commune-dns.md)")
    print(f"  4. Déployer :")
    print(f"     cd commune-sites/{commune_id} && firebase deploy --project {firebase_project} --only hosting")
    print(f"  5. Une fois Android signé : remplir le sha256_cert_fingerprints dans")
    print(f"     commune-sites/{commune_id}/public/.well-known/assetlinks.json puis re-deploy")


if __name__ == "__main__":
    main()
