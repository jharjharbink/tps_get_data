#!/bin/bash
# ============================================================
# ORCHESTRATEUR RAW - Import de toutes les sources
# Lance séquentiellement tous les imports RAW
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/logging.sh"

log_section "🚀 DÉMARRAGE IMPORT RAW COMPLET"
START_TIME=$(date +%s)

# ─── Import DIA ────────────────────────────────────────────
log "INFO" "Import raw_dia..."
bash "$SCRIPT_DIR/raw/01_import_raw_dia.sh"

# ─── Import compta_* ───────────────────────────────────────
log "INFO" "Import bases compta_*..."
bash "$SCRIPT_DIR/raw/02_import_raw_compta.sh"

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
echo "  - compta_*: $($MYSQL $MYSQL_OPTS -N -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name LIKE 'compta_%'") bases"
echo "  - raw_pennylane: $($MYSQL $MYSQL_OPTS -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='raw_pennylane'") tables"
