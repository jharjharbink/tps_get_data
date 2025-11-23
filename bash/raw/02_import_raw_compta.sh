#!/bin/bash
# ============================================================
# IMPORT RAW COMPTA_* (bases ACD)
# Copie les bases compta_* vers le serveur local
# Parallélisme léger : 3 jobs simultanés max
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/logging.sh"

# Nombre de jobs parallèles (prudent avec 4 cores destination)
PARALLEL_JOBS=3

log_section "IMPORT BASES COMPTA_* (ACD) - $PARALLEL_JOBS jobs parallèles"

# Vérifier la connexion distante
log "INFO" "Test connexion vers $ACD_HOST:$ACD_PORT..."
if ! $MYSQL -h "$ACD_HOST" -P "$ACD_PORT" -u "$ACD_USER" -p"$ACD_PASS" -e "SELECT 1" > /dev/null 2>&1; then
    log "ERROR" "Impossible de se connecter à $ACD_HOST:$ACD_PORT"
    exit 1
fi
log "SUCCESS" "Connexion OK"

# Récupérer la liste des bases compta_* éligibles
log "INFO" "Récupération de la liste des bases compta_*..."
BDDS=$($MYSQL -h "$ACD_HOST" -P "$ACD_PORT" -u "$ACD_USER" -p"$ACD_PASS" --skip-column-names -e "
    SELECT schema_name 
    FROM information_schema.schemata 
    WHERE schema_name LIKE 'compta_%'
    AND schema_name NOT IN ('compta_000000', 'compta_zz', 'compta_gombertcOLD', 'compta_gombertcold');
" | grep "compta_")

if [ -z "$BDDS" ]; then
    log "ERROR" "Aucune base compta_* trouvée sur $ACD_HOST"
    exit 1
fi

# Compter le nombre de bases
NB_BASES=$(echo "$BDDS" | wc -l)
log "INFO" "$NB_BASES bases compta_* à importer avec $PARALLEL_JOBS jobs parallèles"

# Fichier temporaire pour stocker la liste des bases
TMP_BDDS_FILE="/tmp/compta_bases_list.txt"
echo "$BDDS" > "$TMP_BDDS_FILE"

# Fonction pour importer une base (appelée en parallèle)
import_one_db() {
    local BDD="$1"
    local ACD_HOST="$2"
    local ACD_PORT="$3"
    local ACD_USER="$4"
    local ACD_PASS="$5"
    local LOCAL_USER="$6"
    local LOCAL_PASS="$7"
    local MYSQL="$8"
    local MYSQLDUMP="$9"
    
    # Créer la base locale si nécessaire
    $MYSQL -u "$LOCAL_USER" -p"$LOCAL_PASS" -e "CREATE DATABASE IF NOT EXISTS \`$BDD\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null
    
    # Dump et restauration avec compression
    $MYSQLDUMP -h "$ACD_HOST" -P "$ACD_PORT" -u "$ACD_USER" -p"$ACD_PASS" \
        --compress --databases "$BDD" 2>/dev/null | $MYSQL -u "$LOCAL_USER" -p"$LOCAL_PASS" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "OK: $BDD"
    else
        echo "ERREUR: $BDD"
    fi
}

# Exporter la fonction pour xargs
export -f import_one_db

# Lancer les imports en parallèle
log "INFO" "Lancement des imports parallèles..."
cat "$TMP_BDDS_FILE" | xargs -P "$PARALLEL_JOBS" -I {} bash -c \
    "import_one_db '{}' '$ACD_HOST' '$ACD_PORT' '$ACD_USER' '$ACD_PASS' '$LOCAL_USER' '$LOCAL_PASS' '$MYSQL' '$MYSQLDUMP'" \
    2>&1 | while read line; do
        echo "[$(date '+%H:%M:%S')] $line"
    done | tee -a "$LOG_FILE"

# Nettoyage
rm -f "$TMP_BDDS_FILE"

# Stats finales
TOTAL_BASES=$($MYSQL $MYSQL_OPTS -N -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name LIKE 'compta_%'")
log "SUCCESS" "Import compta_* terminé : $TOTAL_BASES bases locales"
