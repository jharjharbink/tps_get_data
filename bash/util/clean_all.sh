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

log "INFO" "Suppression des schémas raw_*..."
RAW_DBS=$($MYSQL $MYSQL_OPTS -N -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name LIKE 'raw_%';" 2>/dev/null || echo "")
if [ -n "$RAW_DBS" ]; then
    RAW_COUNT=$(echo "$RAW_DBS" | wc -l)
    log "INFO" "$RAW_COUNT bases raw_* trouvées, suppression..."
    for DB in $RAW_DBS; do
        $MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS \`$DB\`;" 2>/dev/null
    done
    log "SUCCESS" "Bases raw_* supprimées"
else
    log "INFO" "Aucune base raw_* trouvée"
fi

log "INFO" "Suppression des schémas compta_*..."
COMPTA_DBS=$($MYSQL $MYSQL_OPTS -N -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name LIKE 'compta_%';" 2>/dev/null || echo "")
if [ -n "$COMPTA_DBS" ]; then
    COMPTA_COUNT=$(echo "$COMPTA_DBS" | wc -l)
    log "WARNING" "$COMPTA_COUNT bases compta_* trouvées, suppression..."
    for DB in $COMPTA_DBS; do
        $MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS \`$DB\`;" 2>/dev/null
    done
    log "SUCCESS" "Bases compta_* supprimées"
else
    log "INFO" "Aucune base compta_* trouvée (normal avec raw_acd centralisé)"
fi

log "INFO" "Suppression des schémas transform_*..."
TRANSFORM_DBS=$($MYSQL $MYSQL_OPTS -N -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name LIKE 'transform_%';" 2>/dev/null || echo "")
if [ -n "$TRANSFORM_DBS" ]; then
    TRANSFORM_COUNT=$(echo "$TRANSFORM_DBS" | wc -l)
    log "INFO" "$TRANSFORM_COUNT bases transform_* trouvées, suppression..."
    for DB in $TRANSFORM_DBS; do
        $MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS \`$DB\`;" 2>/dev/null
    done
    log "SUCCESS" "Bases transform_* supprimées"
else
    log "INFO" "Aucune base transform_* trouvée"
fi

log "INFO" "Suppression du schéma mdm..."
$MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS mdm;" 2>/dev/null
log "SUCCESS" "Schéma mdm supprimé"

log "INFO" "Suppression des schémas mart_*..."
MART_DBS=$($MYSQL $MYSQL_OPTS -N -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name LIKE 'mart_%';" 2>/dev/null || echo "")
if [ -n "$MART_DBS" ]; then
    MART_COUNT=$(echo "$MART_DBS" | wc -l)
    log "INFO" "$MART_COUNT bases mart_* trouvées, suppression..."
    for DB in $MART_DBS; do
        $MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS \`$DB\`;" 2>/dev/null
    done
    log "SUCCESS" "Bases mart_* supprimées"
else
    log "INFO" "Aucune base mart_* trouvée"
fi

log "SUCCESS" "Nettoyage terminé !"
log "INFO" "Bases restantes :"
$MYSQL $MYSQL_OPTS -e "SHOW DATABASES;"
