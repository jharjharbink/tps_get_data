#!/bin/bash
# ============================================================
# ORCHESTRATEUR RAW - Import de toutes les sources
# Lance séquentiellement tous les imports RAW
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/logging.sh"

# ─── Arguments ─────────────────────────────────────────────
ACD_MODE="--full"  # Par défaut : import complet

while [[ $# -gt 0 ]]; do
    case $1 in
        --acd-full)        ACD_MODE="--full"; shift ;;
        --acd-incremental) ACD_MODE="--incremental"; shift ;;
        *)                 echo "Option inconnue: $1"; shift ;;
    esac
done

log_section "🚀 DÉMARRAGE IMPORT RAW COMPLET"
START_TIME=$(date +%s)

# ─── Import DIA ────────────────────────────────────────────
log "INFO" "Import raw_dia..."
bash "$SCRIPT_DIR/raw/01_import_raw_dia.sh"

# ─── Import compta_* vers raw_acd ──────────────────────────
log "INFO" "Import raw_acd (mode: $ACD_MODE)..."
bash "$SCRIPT_DIR/raw/02_import_raw_compta.sh" "$ACD_MODE"

# ─── Import Pennylane ──────────────────────────────────────
log "INFO" "Import raw_pennylane..."
bash "$SCRIPT_DIR/raw/03_import_raw_pennylane.sh"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_section "✅ IMPORT RAW TERMINÉ"
log "SUCCESS" "Durée totale: $(($DURATION / 60)) min $(($DURATION % 60)) sec"

# Stats finales
log "INFO" "Résumé des imports:"
echo "  - raw_dia: $($MYSQL $MYSQL_OPTS -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='raw_dia'") tables"
echo "  - raw_acd: $($MYSQL $MYSQL_OPTS -N -e "SELECT COUNT(DISTINCT dossier_code) FROM raw_acd.histo_ligne_ecriture") dossiers centralisés"
echo "  - raw_pennylane: $($MYSQL $MYSQL_OPTS -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='raw_pennylane'") tables"
