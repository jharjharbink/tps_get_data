#!/bin/bash
# ============================================================
# EXÉCUTION PROCÉDURES MDM
# Lance toutes les procédures de la couche MDM
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/logging.sh"

log_section "🔄 EXÉCUTION COUCHE MDM"
START_TIME=$(date +%s)

# Vérifier que les schémas existent
log "INFO" "Vérification des prérequis..."
if ! $MYSQL $MYSQL_OPTS -e "USE mdm" 2>/dev/null; then
    log "ERROR" "Schéma mdm inexistant. Exécuter d'abord le script SQL de création."
    exit 1
fi

# Vérifier que TRANSFORM a été exécuté
DOSSIERS_ACD=$($MYSQL $MYSQL_OPTS -N -e "SELECT COUNT(*) FROM transform_compta.dossiers_acd" 2>/dev/null || echo "0")
if [ "$DOSSIERS_ACD" -eq 0 ]; then
    log "ERROR" "transform_compta.dossiers_acd vide. Exécuter d'abord run_transform.sh"
    exit 1
fi

# Exécuter la procédure orchestrateur
log "INFO" "Appel de mdm.run_all()..."
$MYSQL $MYSQL_OPTS -t -v --unbuffered -e "CALL mdm.run_all();"

if [ $? -ne 0 ]; then
    log "ERROR" "Erreur lors de l'exécution de mdm.run_all()"
    exit 1
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_section "✅ MDM TERMINÉ"
log "SUCCESS" "Durée: $(($DURATION / 60)) min $(($DURATION % 60)) sec"

# Stats
log "INFO" "Volumes finaux:"
$MYSQL $MYSQL_OPTS -t -e "
SELECT 
    'dossiers' AS table_name, COUNT(*) AS lignes FROM mdm.dossiers
UNION ALL SELECT 'collaborateurs', COUNT(*) FROM mdm.collaborateurs
UNION ALL SELECT 'contacts', COUNT(*) FROM mdm.contacts;
"

# Stats jointures
log "INFO" "Répartition des sources:"
$MYSQL $MYSQL_OPTS -t -e "
SELECT 
    CASE 
        WHEN has_compta_acd AND has_compta_pennylane THEN 'ACD + Pennylane'
        WHEN has_compta_acd THEN 'ACD uniquement'
        WHEN has_compta_pennylane THEN 'Pennylane uniquement'
        ELSE 'Aucune source'
    END AS source,
    COUNT(*) AS nb_dossiers
FROM mdm.dossiers
GROUP BY 1
ORDER BY 2 DESC;
"
