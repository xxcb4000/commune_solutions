#!/usr/bin/env bash
# Scaffolde un nouveau module communautaire en clonant le template
# hello-world. Le module est créé sous `modules-community/<id>/`.
#
# Usage :
#   tools/create-commune-module.sh <module-id> [<display-name>]
#
# Exemple :
#   tools/create-commune-module.sh marches-publics "Marchés publics"
#   tools/create-commune-module.sh annuaire
#
# Le module créé contient un manifest pré-rempli (avec votre id +
# displayName si fourni), un écran main.json minimal, et un fichier
# de data bundlée. Adapter ensuite les fichiers à votre cas et
# soumettre une PR.
#
# Validation : id doit être lowercase + kebab-case ; ne doit pas
# entrer en collision avec un module existant (officiel ou communauté).

set -euo pipefail

MODULE_ID="${1:?Usage: $0 <module-id> [<display-name>]}"
DISPLAY_NAME="${2:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$ROOT/modules-template/hello-world"
TARGET="$ROOT/modules-community/$MODULE_ID"

# Validation id
if ! [[ "$MODULE_ID" =~ ^[a-z][a-z0-9-]*$ ]]; then
    echo "✗ id invalide : '$MODULE_ID'"
    echo "  Doit être lowercase + kebab-case (a-z, 0-9, -). Exemples valides :"
    echo "    annuaire, marches-publics, mobilite-douce"
    exit 1
fi

# Pas de collision avec officiel
if [[ -d "$ROOT/modules-official/$MODULE_ID" ]]; then
    echo "✗ Un module officiel '$MODULE_ID' existe déjà — choisis un autre id."
    exit 1
fi

# Pas de collision avec communautaire
if [[ -d "$TARGET" ]]; then
    echo "✗ '$TARGET' existe déjà — choisis un autre id ou supprime le dossier."
    exit 1
fi

# Template présent
if [[ ! -d "$TEMPLATE" ]]; then
    echo "✗ Template introuvable : $TEMPLATE"
    exit 1
fi

# DisplayName par défaut = id avec majuscules + tirets en espaces
if [[ -z "$DISPLAY_NAME" ]]; then
    DISPLAY_NAME="$(echo "$MODULE_ID" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))} 1')"
fi

# Copie + patch
cp -r "$TEMPLATE" "$TARGET"

# Patch manifest.json : id, displayName, official=false (déjà false dans
# template mais on confirme), description neutre.
python3 - <<PY
import json
from pathlib import Path

p = Path("$TARGET/manifest.json")
data = json.loads(p.read_text())
data["id"] = "$MODULE_ID"
data["displayName"] = "$DISPLAY_NAME"
data["official"] = False
data["description"] = "Module communautaire — à adapter à votre cas."
data["longDescription"] = "Module créé via tools/create-commune-module.sh. Adaptez ce manifest, screens/, et data/ selon votre cas, puis soumettez une PR."
data["author"] = "À renseigner"
data["licence"] = data.get("licence", "MIT")
p.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
PY

# README minimal pour le module
cat > "$TARGET/README.md" <<EOF
# $DISPLAY_NAME

Module communautaire pour Commune Solutions.

## Structure

\`\`\`
$MODULE_ID/
├── manifest.json
├── screens/main.json
└── data/sample.json
\`\`\`

## Adapter

1. Compléter \`manifest.json\` (auteur, description, capabilities)
2. Modifier \`screens/main.json\` pour votre UI
3. Mettre à jour \`data/sample.json\` (ou remplacer par \`firestore:<collection>\`)
4. Valider : \`python3 tools/validate-manifests.py\`
5. Soumettre une PR

Voir \`docs/developers.md\` pour les détails du contrat plateforme et des primitives DSL disponibles.
EOF

echo "✓ Module '$MODULE_ID' créé dans modules-community/$MODULE_ID/"
echo ""
echo "Prochaines étapes :"
echo "  1. Adapter modules-community/$MODULE_ID/manifest.json (auteur, description, capabilities)"
echo "  2. Modifier modules-community/$MODULE_ID/screens/main.json pour votre UI"
echo "  3. python3 tools/validate-manifests.py"
echo "  4. Ouvrir une PR vers main"
