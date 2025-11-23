#!/bin/bash
# ============================================================
# EXÉCUTION PROCÉDURES TRANSFORM
# Lance toutes les procédures de la couche TRANSFORM
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/logging.sh"

log_section "🔄 EXÉCUTION COUCHE TRANSFORM"
START_TIME=$(date +%s)

# Vérifier que les schémas existent
log "INFO" "Vérification des prérequis..."
if ! $MYSQL $MYSQL_OPTS -e "USE transform_compta" 2>/dev/null; then
    log "ERROR" "Schéma transform_compta inexistant. Exécuter d'abord le script SQL de création."
    exit 1
fi

# Exécuter la procédure orchestrateur
log "INFO" "Appel de transform_compta.run_all()..."
$MYSQL $MYSQL_OPTS -t -v --unbuffered -e "CALL transform_compta.run_all();"

if [ $? -ne 0 ]; then
    log "ERROR" "Erreur lors de l'exécution de transform_compta.run_all()"
    exit 1
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_section "✅ TRANSFORM TERMINÉ"
log "SUCCESS" "Durée: $(($DURATION / 60)) min $(($DURATION % 60)) sec"

# Stats
log "INFO" "Volumes finaux:"
$MYSQL $MYSQL_OPTS -t -e "
SELECT 
    'dossiers_acd' AS table_name, COUNT(*) AS lignes FROM transform_compta.dossiers_acd
UNION ALL SELECT 'dossiers_pennylane', COUNT(*) FROM transform_compta.dossiers_pennylane
UNION ALL SELECT 'ecritures_mensuelles', COUNT(*) FROM transform_compta.ecritures_mensuelles
UNION ALL SELECT 'ecritures_tiers_detaillees', COUNT(*) FROM transform_compta.ecritures_tiers_detaillees
UNION ALL SELECT 'exercices', COUNT(*) FROM transform_compta.exercices
UNION ALL SELECT 'temps_collaborateurs', COUNT(*) FROM transform_compta.temps_collaborateurs;
"
