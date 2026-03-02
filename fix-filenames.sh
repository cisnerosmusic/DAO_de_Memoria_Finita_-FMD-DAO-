#!/usr/bin/env bash
# fix-filenames.sh
# FMD-DAO — Corrección de nombres de archivos en el repositorio
#
# Problemas que resuelve:
#   1. Oracledispute.SOL   → OracleDispute.sol   (extensión en mayúsculas)
#   2. OracleLayer,md      → OracleLayer.md       (coma en lugar de punto)
#   3. CoopetitionEngine.MD → CoopetitionEngine.md (extensión en mayúsculas)
#   4. GranularReputation.MD → GranularReputation.md
#   5. HumanLayer.MD       → HumanLayer.md
#   6. Ruido_Estabilizador.MD → Ruido_Estabilizador.md
#   7. Sistema_Inmunologico.MD → Sistema_Inmunologico.md
#
# Uso:
#   chmod +x fix-filenames.sh
#   ./fix-filenames.sh
#
# El script verifica que cada archivo existe antes de renombrar
# y muestra un resumen al final.

set -e

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

echo ""
echo "═══════════════════════════════════════════════"
echo "  FMD-DAO — Corrección de nombres de archivos  "
echo "═══════════════════════════════════════════════"
echo ""

RENAMED=0
SKIPPED=0
ERRORS=0

rename_file() {
    local FROM="$1"
    local TO="$2"

    if [ ! -f "$FROM" ]; then
        echo "  ⚠  SKIPPED (no existe): $FROM"
        SKIPPED=$((SKIPPED + 1))
        return
    fi

    if [ -f "$TO" ]; then
        echo "  ⚠  SKIPPED (destino ya existe): $TO"
        SKIPPED=$((SKIPPED + 1))
        return
    fi

    git mv "$FROM" "$TO"
    echo "  ✓  $FROM  →  $TO"
    RENAMED=$((RENAMED + 1))
}

echo "── Contratos Solidity ──────────────────────────"
rename_file "Oracledispute.SOL"  "OracleDispute.sol"

echo ""
echo "── Documentación Markdown ──────────────────────"
rename_file "OracleLayer,md"          "OracleLayer.md"
rename_file "CoopetitionEngine.MD"    "CoopetitionEngine.md"
rename_file "GranularReputation.MD"   "GranularReputation.md"
rename_file "HumanLayer.MD"           "HumanLayer.md"
rename_file "Ruido_Estabilizador.MD"  "Ruido_Estabilizador.md"
rename_file "Sistema_Inmunologico.MD" "Sistema_Inmunologico.md"

echo ""
echo "═══════════════════════════════════════════════"
echo "  Resumen"
echo "  Renombrados: $RENAMED"
echo "  Omitidos:    $SKIPPED"
echo "═══════════════════════════════════════════════"
echo ""

if [ "$RENAMED" -gt 0 ]; then
    echo "Archivos listos para commit. Ejecuta:"
    echo ""
    echo "  git commit -m 'chore: fix file name casing and extension inconsistencies'"
    echo "  git push origin main"
    echo ""
fi
