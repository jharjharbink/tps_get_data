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

log "INFO" "Suppression des bases compta_*..."
COMPTA_DBS=$($MYSQL $MYSQL_OPTS -N -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name LIKE 'compta_%';")
for DB in $COMPTA_DBS; do
    $MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS \`$DB\`;"
done

log "INFO" "Suppression des schémas TRANSFORM/MDM/MART..."
$MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS transform_compta;"
$MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS mdm;"
$MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS mart_pilotage_cabinet;"
$MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS mart_controle_gestion;"
$MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS mart_production_client;"

log "SUCCESS" "Nettoyage terminé !"
log "INFO" "Bases restantes :"
$MYSQL $MYSQL_OPTS -e "SHOW DATABASES;"
