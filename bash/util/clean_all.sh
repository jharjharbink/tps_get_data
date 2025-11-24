#!/bin/bash
# ============================================================
# CLEAN ALL - Version ultra rapide (Solution 2 : suppression physique)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/bash/config.sh"
source "$SCRIPT_DIR/bash/logging.sh"

log_section "🧹 NETTOYAGE COMPLET DE LA BDD (mode ULTRA-RAPIDE)"

read -p "⚠️  Ceci va SUPPRIMER TOUTES les données. Continuer ? (oui/non) : " CONFIRM
[ "$CONFIRM" != "oui" ] && { echo "Annulé."; exit 0; }

# Récupération du datadir MySQL
DATADIR=$($MYSQL $MYSQL_OPTS -N -e "SELECT @@datadir;")
log "INFO" "Répertoire MySQL : $DATADIR"

# ============================================================
# FONCTION DE SUPPRESSION ULTRA-RAPIDE
# ============================================================
delete_schemas_fast() {
    local PATTERN="$1"

    log "INFO" "Recherche des schémas ${PATTERN}..."

    DBS=$($MYSQL $MYSQL_OPTS -N -e "
        SELECT schema_name
        FROM information_schema.schemata
        WHERE schema_name LIKE '${PATTERN}'
          AND schema_name NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys');
    " || echo "")

    if [ -z "$DBS" ]; then
        log "INFO" "Aucune base correspondant à ${PATTERN}"
        return
    fi

    COUNT=$(echo "$DBS" | wc -l)
    log "WARNING" "$COUNT bases ${PATTERN} trouvées, suppression rapide..."

    START=$(date +%s)

    # 1. DROP DATABASE d'abord (nettoyage métadonnées + partitions)
    TMP_SQL="/tmp/drop_physical_${PATTERN}_$$.sql"
    echo "SET FOREIGN_KEY_CHECKS=0;" > "$TMP_SQL"

    while read -r DB; do
        echo "DROP DATABASE IF EXISTS \`${DB}\`;" >> "$TMP_SQL"
    done <<< "$DBS"

    echo "SET FOREIGN_KEY_CHECKS=1;" >> "$TMP_SQL"

    $MYSQL $MYSQL_OPTS < "$TMP_SQL"
    rm -f "$TMP_SQL"

    # 2. Suppression physique des dossiers restants (fichiers orphelins)
    while read -r DB; do
        if [ -d "${DATADIR}/${DB}" ]; then
            rm -rf "${DATADIR}/${DB}"
        fi
    done <<< "$DBS"

    END=$(date +%s)
    log "SUCCESS" "Bases ${PATTERN} supprimées en $((END - START))s"
}

# ============================================================
# SUPPRESSIONS ULTRA-RAPIDES
# ============================================================
delete_schemas_fast "raw_%"
delete_schemas_fast "compta_%"
delete_schemas_fast "transform_%"
delete_schemas_fast "mart_%"

# Schéma mdm
log "INFO" "Suppression du schéma mdm..."
# 1. DROP DATABASE d'abord (métadonnées)
$MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS mdm;" || true
# 2. Suppression physique (fichiers orphelins)
if [ -d "${DATADIR}/mdm" ]; then
    rm -rf "${DATADIR}/mdm"
fi
log "SUCCESS" "Schéma mdm supprimé"

# ============================================================
# FLUSH MySQL (obligatoire après suppression physique)
# ============================================================
log "INFO" "Exécution des FLUSH MySQL..."
$MYSQL $MYSQL_OPTS -e "FLUSH LOGS;"
$MYSQL $MYSQL_OPTS -e "FLUSH TABLES;"
log "SUCCESS" "FLUSH terminé"

# ============================================================
# FIN
# ============================================================
log "SUCCESS" "Nettoyage complet terminé !"
log "INFO" "Bases encore présentes :"
$MYSQL $MYSQL_OPTS -e "SHOW DATABASES;"
