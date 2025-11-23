#!/bin/bash
# ============================================================
# CLEAN ALL - Supprime toutes les bases/schémas du pipeline
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/bash/config.sh"
source "$SCRIPT_DIR/bash/logging.sh"

log_section "🧹 NETTOYAGE COMPLET DE LA BDD"

read -p "⚠️  Ceci va SUPPRIMER toutes les données. Confirmer ? (oui/non) : " CONFIRM
if [ "$CONFIRM" != "oui" ]; then
    echo "Annulé."
    exit 0
fi

log "INFO" "Suppression des schémas RAW..."
$MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS raw_dia;"
$MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS raw_pennylane;"
$MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS raw_acd;"

log "INFO" "Suppression des anciennes bases compta_* (si présentes)..."
COMPTA_DBS=$($MYSQL $MYSQL_OPTS -N -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name LIKE 'compta_%';" 2>/dev/null || echo "")
if [ -n "$COMPTA_DBS" ]; then
    COMPTA_COUNT=$(echo "$COMPTA_DBS" | wc -l)
    log "WARNING" "$COMPTA_COUNT bases compta_* trouvées, suppression..."
    for DB in $COMPTA_DBS; do
        $MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS \`$DB\`;" 2>/dev/null
    done
    log "SUCCESS" "Bases compta_* supprimées"
else
    log "INFO" "Aucune base compta_* trouvée (normal avec raw_acd)"
fi

log "INFO" "Suppression des schémas TRANSFORM/MDM/MART..."
$MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS transform_compta;"
$MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS mdm;"
$MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS mart_pilotage_cabinet;"
$MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS mart_controle_gestion;"
$MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS mart_production_client;"

log "SUCCESS" "Nettoyage terminé !"
log "INFO" "Bases restantes :"
$MYSQL $MYSQL_OPTS -e "SHOW DATABASES;"
