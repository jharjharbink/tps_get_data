#!/bin/bash
# ============================================================
# CRÉATION/REFRESH VUES MART
# Recrée les vues de la couche MART
# Note: Les vues MART sont recréées à chaque exécution du SQL
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/logging.sh"

log_section "🔄 CRÉATION VUES MART"
START_TIME=$(date +%s)

# Vérifier que MDM a été exécuté
DOSSIERS_MDM=$($MYSQL $MYSQL_OPTS -N -e "SELECT COUNT(*) FROM mdm.dossiers" 2>/dev/null || echo "0")
if [ "$DOSSIERS_MDM" -eq 0 ]; then
    log "ERROR" "mdm.dossiers vide. Exécuter d'abord run_mdm.sh"
    exit 1
fi

# Exécuter le script SQL des vues MART
log "INFO" "Création des vues MART..."
$MYSQL $MYSQL_OPTS < "$SCRIPT_DIR/../sql/05_mart_views.sql"

if [ $? -ne 0 ]; then
    log "ERROR" "Erreur lors de la création des vues MART"
    exit 1
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_section "✅ MART TERMINÉ"
log "SUCCESS" "Durée: $(($DURATION % 60)) sec"

# Lister les vues créées
log "INFO" "Vues créées:"
echo ""
echo "mart_pilotage_cabinet:"
$MYSQL $MYSQL_OPTS -N -e "SHOW FULL TABLES IN mart_pilotage_cabinet WHERE Table_type = 'VIEW'" | awk '{print "  - "$1}'

echo ""
echo "mart_controle_gestion:"
$MYSQL $MYSQL_OPTS -N -e "SHOW FULL TABLES IN mart_controle_gestion WHERE Table_type = 'VIEW'" | awk '{print "  - "$1}'

echo ""
echo "mart_production_client:"
$MYSQL $MYSQL_OPTS -N -e "SHOW FULL TABLES IN mart_production_client WHERE Table_type = 'VIEW'" | awk '{print "  - "$1}'

# Test rapide des vues principales
log "INFO" "Test des vues principales:"
$MYSQL $MYSQL_OPTS -t -e "
SELECT 'v_clients_par_service' AS vue, COUNT(*) AS lignes FROM mart_pilotage_cabinet.v_clients_par_service
UNION ALL SELECT 'v_company_ledger', COUNT(*) FROM mart_controle_gestion.v_company_ledger
UNION ALL SELECT 'v_tiers_detailles', COUNT(*) FROM mart_production_client.v_tiers_detailles;
"
