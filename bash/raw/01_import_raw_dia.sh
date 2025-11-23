#!/bin/bash
# ============================================================
# IMPORT RAW DIA (valoxy)
# Copie la base DIA vers raw_dia
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/logging.sh"

log_section "IMPORT RAW_DIA (valoxy)"

# Vérifier la connexion distante
log "INFO" "Test connexion vers $DIA_HOST..."
if ! $MYSQL -h "$DIA_HOST" -P "$DIA_PORT" -u "$DIA_USER" -p"$DIA_PASS" -e "SELECT 1" > /dev/null 2>&1; then
    log "ERROR" "Impossible de se connecter à $DIA_HOST"
    exit 1
fi
log "SUCCESS" "Connexion OK"

# Créer le schéma raw_dia si nécessaire
log "INFO" "Création du schéma raw_dia si nécessaire..."
$MYSQL $MYSQL_OPTS -e "CREATE DATABASE IF NOT EXISTS raw_dia CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# Liste des tables à exclure (blobs, vues, tmp, test)
EXCLUDED_PATTERNS="
    AND table_name NOT LIKE 'doc%'
    AND table_name NOT LIKE 'paniere_blob%'
    AND table_name NOT LIKE 'v_collab%'
    AND table_name NOT LIKE 'v_adresse%'
    AND table_name NOT LIKE 'paniere_mirf%'
    AND table_name NOT LIKE 'v_%blob%'
    AND table_name NOT LIKE 'tmp%'
    AND table_name NOT LIKE 'test%'
    AND table_name NOT LIKE 'web%'
    AND table_name != 'email_log'
"

# Récupérer la liste des tables à importer
log "INFO" "Récupération de la liste des tables..."
INCLUDED_TABLES=$($MYSQL -h "$DIA_HOST" -P "$DIA_PORT" -u "$DIA_USER" -p"$DIA_PASS" -N -e "
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = 'valoxy'
    AND table_type = 'BASE TABLE'
    $EXCLUDED_PATTERNS
")

TABLE_LIST=()
for TABLE in $INCLUDED_TABLES; do
    TABLE_LIST+=("$TABLE")
done

NB_TABLES=${#TABLE_LIST[@]}
log "INFO" "Dump de $NB_TABLES tables depuis valoxy..."

# Dump et restauration directe avec compression réseau
(
    echo "USE raw_dia;"
    $MYSQLDUMP -h "$DIA_HOST" -P "$DIA_PORT" -u "$DIA_USER" -p"$DIA_PASS" \
        --compress --replace --skip-triggers --single-transaction --quick \
        valoxy "${TABLE_LIST[@]}" 2>> "$LOG_FILE"
) | $MYSQL $MYSQL_OPTS

if [ $? -eq 0 ]; then
    log "SUCCESS" "Import raw_dia terminé : $NB_TABLES tables"
else
    log "ERROR" "Échec de l'import raw_dia"
    exit 1
fi

# Stats
TABLE_COUNT=$($MYSQL $MYSQL_OPTS -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='raw_dia'")
log "INFO" "Tables dans raw_dia : $TABLE_COUNT"
