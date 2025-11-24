#!/bin/bash
# ============================================================
# IMPORT RAW_ACD - Import centralisé des données comptables ACD
# Importe 6 tables spécifiques depuis compta_* vers raw_acd
# Modes: --full (TRUNCATE) ou --incremental (ON DUPLICATE KEY)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/logging.sh"

# ─── Arguments ─────────────────────────────────────────────
MODE="full"  # Par défaut: import complet
PARALLEL_JOBS=1  # Pas de parallélisme pour protéger la source ACD
SINCE_DATE=""

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --full              Import complet (TRUNCATE + réimport) [défaut]"
    echo "  --incremental       Import incrémental (depuis last_sync_date)"
    echo "  --since DATE        Import depuis une date spécifique"
    echo "                      Format: \"23/11/2025 13:32:43\" (DD/MM/YYYY HH:MM:SS)"
    echo ""
    echo "Exemples:"
    echo "  $0 --full"
    echo "  $0 --incremental"
    echo "  $0 --since \"01/01/2025 00:00:00\""
    exit 0
}

# Fonction pour convertir DD/MM/YYYY HH:MM:SS vers YYYY-MM-DD HH:MM:SS
convert_date_format() {
    local input_date="$1"
    # Format: 23/11/2025 13:32:43 -> 2025-11-23 13:32:43
    echo "$input_date" | awk -F'[/ :]' '{printf "%s-%s-%s %s:%s:%s", $3, $2, $1, $4, $5, $6}'
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --full)        MODE="full"; shift ;;
        --incremental) MODE="incremental"; shift ;;
        --since)       MODE="since"; SINCE_DATE="$2"; shift 2 ;;
        -h|--help)     usage ;;
        *)             echo "Option inconnue: $1"; usage ;;
    esac
done

# Convertir la date si mode --since
if [ "$MODE" = "since" ]; then
    if [ -z "$SINCE_DATE" ]; then
        echo "Erreur: --since nécessite une date"
        usage
    fi
    SINCE_DATE=$(convert_date_format "$SINCE_DATE")
    log "INFO" "Date convertie: $SINCE_DATE"
fi

log_section "IMPORT RAW_ACD (ACD) - Mode: $MODE"

# ─── Vérifier connexion ACD ────────────────────────────────
log "INFO" "Test connexion vers $ACD_HOST:$ACD_PORT..."
if ! $MYSQL -h "$ACD_HOST" -P "$ACD_PORT" -u "$ACD_USER" -p"$ACD_PASS" -e "SELECT 1" > /dev/null 2>&1; then
    log "ERROR" "Impossible de se connecter à $ACD_HOST:$ACD_PORT"
    exit 1
fi
log "SUCCESS" "Connexion OK"

# ─── Vérifier que raw_acd existe ──────────────────────────
log "INFO" "Vérification du schéma raw_acd..."
if ! $MYSQL $MYSQL_OPTS -e "USE raw_acd" 2>/dev/null; then
    log "ERROR" "Le schéma raw_acd n'existe pas. Exécutez d'abord: mysql < sql/02b_raw_acd_tables.sql"
    exit 1
fi

# ─── Fonction: Vérifier qu'une base a les 6 tables ────────
check_database_has_required_tables() {
    local DB="$1"

    for TABLE in "${REQUIRED_TABLES[@]}"; do
        local EXISTS=$($MYSQL -h "$ACD_HOST" -P "$ACD_PORT" -u "$ACD_USER" -p"$ACD_PASS" -N -e "
            SELECT COUNT(*)
            FROM information_schema.tables
            WHERE table_schema = '$DB'
            AND table_name = '$TABLE'
        " 2>/dev/null)

        if [ "$EXISTS" != "1" ]; then
            return 1  # Table manquante
        fi
    done
    return 0  # Toutes les tables présentes
}

# ─── Récupérer les bases compta_* ─────────────────────────
log "INFO" "Récupération de la liste des bases compta_*..."
ALL_DATABASES=$($MYSQL -h "$ACD_HOST" -P "$ACD_PORT" -u "$ACD_USER" -p"$ACD_PASS" --skip-column-names -e "
    SELECT schema_name
    FROM information_schema.schemata
    WHERE schema_name LIKE 'compta_%'
" | grep "compta_")

if [ -z "$ALL_DATABASES" ]; then
    log "ERROR" "Aucune base compta_* trouvée sur $ACD_HOST"
    exit 1
fi

# ─── Filtrer les bases éligibles ──────────────────────────
log "INFO" "Vérification des tables requises dans chaque base..."
ELIGIBLE_DATABASES=()
EXCLUDED_COUNT=0

for DB in $ALL_DATABASES; do
    # Vérifier si la base est dans la liste d'exclusion
    SKIP=false
    for EXCLUDED in "${EXCLUDED_DATABASES[@]}"; do
        if [ "$DB" = "$EXCLUDED" ]; then
            SKIP=true
            break
        fi
    done

    if [ "$SKIP" = true ]; then
        ((EXCLUDED_COUNT++)) || true
        continue
    fi

    # Vérifier que les 6 tables requises existent
    if check_database_has_required_tables "$DB"; then
        ELIGIBLE_DATABASES+=("$DB")
    else
        log "WARNING" "Base $DB ignorée : tables manquantes"
        ((EXCLUDED_COUNT++)) || true
    fi
done

NB_ELIGIBLE=${#ELIGIBLE_DATABASES[@]}
log "INFO" "$NB_ELIGIBLE bases éligibles trouvées ($EXCLUDED_COUNT exclues)"

if [ "$NB_ELIGIBLE" -eq 0 ]; then
    log "ERROR" "Aucune base éligible trouvée"
    exit 1
fi

# ─── Mode FULL: TRUNCATE des tables ───────────────────────
if [ "$MODE" = "full" ]; then
    log "INFO" "Mode FULL: Vidage des tables raw_acd..."
    $MYSQL $MYSQL_OPTS raw_acd -e "
        SET FOREIGN_KEY_CHECKS=0;
        TRUNCATE TABLE histo_ligne_ecriture;
        TRUNCATE TABLE histo_ecriture;
        TRUNCATE TABLE ligne_ecriture;
        TRUNCATE TABLE ecriture;
        TRUNCATE TABLE compte;
        TRUNCATE TABLE journal;
        SET FOREIGN_KEY_CHECKS=1;
    "
    log "SUCCESS" "Tables vidées"
fi

# ─── Mode INCREMENTAL: Récupérer last_sync_date UNE FOIS ──
declare -A LAST_SYNC_DATES
IMPORT_START_TIME=""

if [ "$MODE" = "incremental" ]; then
    # Capturer le timestamp du DÉBUT de l'import (pour éviter perte de données)
    IMPORT_START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    log "INFO" "Timestamp de départ de l'import : $IMPORT_START_TIME"
    log "INFO" "⚠️  Ce timestamp sera enregistré dans sync_tracking (pas l'heure de fin)"

    log "INFO" "Récupération des dernières dates de synchronisation..."
    for TABLE in "${REQUIRED_TABLES[@]}"; do
        LAST_SYNC=$($MYSQL $MYSQL_OPTS -N -e "
            SELECT IFNULL(last_sync_date, '2000-01-01 00:00:00')
            FROM raw_acd.sync_tracking
            WHERE table_name = '$TABLE'
        " 2>/dev/null || echo "2000-01-01 00:00:00")
        LAST_SYNC_DATES[$TABLE]="$LAST_SYNC"
        log "INFO" "  - $TABLE: $LAST_SYNC"
    done
fi

# ─── Fonction: Importer une base (optimisée selon Méthode 1 benchmark) ───
import_one_database() {
    local DB="$1"
    local DOSSIER_CODE="${DB#compta_}"  # Extraire "00123" de "compta_00123"

    # Import pour chaque table (approche directe comme dans le benchmark)
    for TABLE in histo_ligne_ecriture histo_ecriture ligne_ecriture ecriture compte journal; do

        # Déterminer le champ date selon la table
        local DATE_FIELD=""
        if [[ "$TABLE" == histo_* ]]; then
            DATE_FIELD="HE_DATE_SAI"
        elif [[ "$TABLE" == "ligne_ecriture" ]] || [[ "$TABLE" == "ecriture" ]]; then
            DATE_FIELD="ECR_DATE_SAI"
        fi

        # Construire la requête selon le mode (simplifié)
        local QUERY=""
        if [ "$MODE" = "full" ]; then
            # Mode FULL: INSERT simple (tables déjà vidées) - Comme benchmark Méthode 1
            QUERY="INSERT INTO raw_acd.$TABLE SELECT '$DOSSIER_CODE' as dossier_code, t.* FROM \`$DB\`.\`$TABLE\` t;"

        elif [ "$MODE" = "since" ]; then
            # Mode SINCE: Avec filtre date
            if [ -n "$DATE_FIELD" ]; then
                QUERY="INSERT INTO raw_acd.$TABLE SELECT '$DOSSIER_CODE' as dossier_code, t.* FROM \`$DB\`.\`$TABLE\` t WHERE t.$DATE_FIELD >= '$SINCE_DATE' ON DUPLICATE KEY UPDATE dossier_code = VALUES(dossier_code);"
            else
                # compte/journal: pas de filtre date
                QUERY="INSERT INTO raw_acd.$TABLE SELECT '$DOSSIER_CODE' as dossier_code, t.* FROM \`$DB\`.\`$TABLE\` t ON DUPLICATE KEY UPDATE dossier_code = VALUES(dossier_code);"
            fi

        else  # incremental
            # Mode INCREMENTAL: Récupérer last_sync depuis variable d'environnement
            local LAST_SYNC="${SYNC_DATE_histo_ligne_ecriture}"  # Défaut
            case "$TABLE" in
                histo_ligne_ecriture) LAST_SYNC="${SYNC_DATE_histo_ligne_ecriture}" ;;
                histo_ecriture)       LAST_SYNC="${SYNC_DATE_histo_ecriture}" ;;
                ligne_ecriture)       LAST_SYNC="${SYNC_DATE_ligne_ecriture}" ;;
                ecriture)             LAST_SYNC="${SYNC_DATE_ecriture}" ;;
                compte)               LAST_SYNC="${SYNC_DATE_compte}" ;;
                journal)              LAST_SYNC="${SYNC_DATE_journal}" ;;
            esac

            if [ -n "$DATE_FIELD" ]; then
                QUERY="INSERT INTO raw_acd.$TABLE SELECT '$DOSSIER_CODE' as dossier_code, t.* FROM \`$DB\`.\`$TABLE\` t WHERE t.$DATE_FIELD > '$LAST_SYNC' ON DUPLICATE KEY UPDATE dossier_code = VALUES(dossier_code);"
            else
                # compte/journal: pas de filtre date
                QUERY="INSERT INTO raw_acd.$TABLE SELECT '$DOSSIER_CODE' as dossier_code, t.* FROM \`$DB\`.\`$TABLE\` t ON DUPLICATE KEY UPDATE dossier_code = VALUES(dossier_code);"
            fi
        fi

        # Exécuter l'import (simplifié, set -e gère les erreurs)
        $MYSQL -h "$ACD_HOST" -P "$ACD_PORT" -u "$ACD_USER" -p"$ACD_PASS" \
            --compress -e "$QUERY" 2>/dev/null || {
            echo "ERREUR: $DB - $TABLE"
            return 1
        }
    done

    echo "OK: $DB"
}

# Exporter la fonction et les variables pour xargs
export -f import_one_database
export MODE SINCE_DATE
export ACD_HOST ACD_PORT ACD_USER ACD_PASS
export MYSQL

# Exporter les dates de sync en mode incremental
if [ "$MODE" = "incremental" ]; then
    for TABLE in "${REQUIRED_TABLES[@]}"; do
        VAR_NAME="SYNC_DATE_${TABLE}"
        export "${VAR_NAME}=${LAST_SYNC_DATES[$TABLE]}"
    done
fi

# ─── Créer fichier temporaire avec liste des bases ────────
TMP_BDDS_FILE="/tmp/acd_eligible_bases_$$.txt"
printf "%s\n" "${ELIGIBLE_DATABASES[@]}" > "$TMP_BDDS_FILE"

# ─── Import séquentiel (pas de parallélisme sur la source) ─
log "INFO" "Lancement des imports (traitement séquentiel pour protéger la source)..."
log "INFO" "Nombre de bases à traiter: $NB_ELIGIBLE"
START_TIME=$(date +%s)

# Compteur pour la progression
COUNTER=0
BATCH_SIZE=10

cat "$TMP_BDDS_FILE" | xargs -P "$PARALLEL_JOBS" -I {} bash -c \
    "import_one_database '{}'" \
    2>&1 | while read line; do
        echo "[$(date '+%H:%M:%S')] $line"

        # Incrémenter et afficher progression tous les 10 imports
        if [[ "$line" == OK:* ]]; then
            ((COUNTER++)) || true
            if (( COUNTER % BATCH_SIZE == 0 )); then
                ELAPSED=$(($(date +%s) - START_TIME))
                REMAINING=$((NB_ELIGIBLE - COUNTER))
                AVG_TIME=$((ELAPSED / COUNTER))
                ETA=$((REMAINING * AVG_TIME))

                echo ""
                echo "════════════════════════════════════════════════════════"
                echo "📊 PROGRESSION: $COUNTER / $NB_ELIGIBLE bases traitées ($(( COUNTER * 100 / NB_ELIGIBLE ))%)"
                echo "⏱️  Temps écoulé: $(($ELAPSED / 60))min $(($ELAPSED % 60))s"
                echo "⏳ Temps moyen par base: ${AVG_TIME}s"
                echo "🎯 ETA restant: $(($ETA / 3600))h $(($ETA % 3600 / 60))min"
                echo "════════════════════════════════════════════════════════"
                echo ""
            fi
        fi
    done | tee -a "$LOG_FILE"

# ─── Nettoyage ─────────────────────────────────────────────
rm -f "$TMP_BDDS_FILE"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# ─── Mise à jour sync_tracking ────────────────────────────
log "INFO" "Mise à jour du tracking..."

# Déterminer la date à enregistrer selon le mode
if [ "$MODE" = "incremental" ] && [ -n "$IMPORT_START_TIME" ]; then
    SYNC_DATE="$IMPORT_START_TIME"
    log "INFO" "Utilisation du timestamp de départ : $SYNC_DATE"
    log "INFO" "⚠️  Cela garantit qu'aucune donnée insérée pendant l'import ne sera perdue"
else
    SYNC_DATE=$(date '+%Y-%m-%d %H:%M:%S')
    log "INFO" "Utilisation du timestamp actuel : $SYNC_DATE"
fi

for TABLE in "${REQUIRED_TABLES[@]}"; do
    ROW_COUNT=$($MYSQL $MYSQL_OPTS -N -e "SELECT COUNT(*) FROM raw_acd.$TABLE")

    $MYSQL $MYSQL_OPTS raw_acd -e "
        UPDATE sync_tracking
        SET last_sync_date = '$SYNC_DATE',
            last_sync_type = '$MODE',
            rows_count = $ROW_COUNT,
            last_status = 'success',
            last_duration_sec = $DURATION
        WHERE table_name = '$TABLE';
    "
done

# ─── Stats finales ─────────────────────────────────────────
log "SUCCESS" "Import raw_acd terminé (mode: $MODE)"
log "INFO" "Durée: $(($DURATION / 60)) min $(($DURATION % 60)) sec"

echo ""
log "INFO" "Statistiques raw_acd:"
$MYSQL $MYSQL_OPTS raw_acd -t -e "
    SELECT
        table_name,
        FORMAT(rows_count, 0) as nb_lignes,
        last_sync_type as mode,
        DATE_FORMAT(last_sync_date, '%Y-%m-%d %H:%i') as derniere_synchro
    FROM sync_tracking
    ORDER BY table_name;
"

# Nombre de dossiers uniques
NB_DOSSIERS=$($MYSQL $MYSQL_OPTS -N -e "SELECT COUNT(DISTINCT dossier_code) FROM raw_acd.histo_ligne_ecriture")
log "INFO" "Nombre de dossiers centralisés : $NB_DOSSIERS"
