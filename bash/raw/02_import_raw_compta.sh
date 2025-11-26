#!/bin/bash
# ============================================================
# IMPORT RAW_ACD - Import centralisé des données comptables ACD
# Importe 6 tables spécifiques depuis compta_* vers raw_acd
# Modes: --full (TRUNCATE) ou --incremental (ON DUPLICATE KEY)
# VERSION CORRIGÉE - Ordre SQL LOAD DATA LOCAL INFILE fixé
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/logging.sh"

# ─── Bases à exclure ───────────────────────────────────────
EXCLUDED_DATABASES=("compta_000000" "compta_zz")

# ─── Tables requises pour import ──────────────────────────
REQUIRED_TABLES=(
    "histo_ligne_ecriture"
    "histo_ecriture"
    "ligne_ecriture"
    "ecriture"
    "compte"
    "journal"
)

# Tables supportant l'import incrémental (avec colonne date)
INCREMENTAL_ONLY_TABLES=(
    "ecriture"
    "ligne_ecriture"
)

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

# MODE PRODUCTION: Importer TOUTES les bases éligibles
ELIGIBLE_DATABASES_LIMITED=("${ELIGIBLE_DATABASES[@]}")
NB_TO_PROCESS=${#ELIGIBLE_DATABASES_LIMITED[@]}

log "INFO" "Traitement de toutes les $NB_TO_PROCESS bases éligibles"

# ─── Mode INCREMENTAL: Dossiers éligibles ─────────────────
if [ "$MODE" = "incremental" ]; then
    # Vérifier si les tables incrémentales ont déjà été synchronisées
    ECRITURE_LAST_SYNC=$($MYSQL $MYSQL_OPTS -N -e "
        SELECT last_sync_date
        FROM raw_acd.sync_tracking
        WHERE table_name = 'ecriture'
    " 2>/dev/null || echo "")

    if [ -z "$ECRITURE_LAST_SYNC" ]; then
        log "ERROR" "Aucune synchronisation précédente trouvée pour 'ecriture'"
        log "ERROR" "Le mode --incremental nécessite un import --full initial"
        log "INFO" "Exécutez d'abord : $0 --full"
        exit 1
    fi

    log "INFO" "Dernière synchronisation: $ECRITURE_LAST_SYNC"

    # Récupérer les dossiers déjà présents dans raw_acd.ecriture
    KNOWN_DOSSIERS=$($MYSQL $MYSQL_OPTS -N -e "
        SELECT DISTINCT dossier_code
        FROM raw_acd.ecriture
        ORDER BY dossier_code
    " 2>/dev/null || echo "")

    if [ -z "$KNOWN_DOSSIERS" ]; then
        log "ERROR" "Aucun dossier trouvé dans raw_acd.ecriture"
        log "ERROR" "Le mode --incremental nécessite des données existantes"
        exit 1
    fi

    # Construire la liste des bases compta_* correspondantes
    KNOWN_DOSSIERS_ARRAY=()
    for CODE in $KNOWN_DOSSIERS; do
        KNOWN_DOSSIERS_ARRAY+=("compta_$CODE")
    done

    # Utiliser uniquement les dossiers connus
    ELIGIBLE_DATABASES_LIMITED=("${KNOWN_DOSSIERS_ARRAY[@]}")
    NB_TO_PROCESS=${#ELIGIBLE_DATABASES_LIMITED[@]}

    log "INFO" "Mode incrémental: $NB_TO_PROCESS dossiers à mettre à jour"

    # Capturer le timestamp du DÉBUT de l'import (pour éviter perte de données)
    IMPORT_START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    log "INFO" "Timestamp de départ de l'import : $IMPORT_START_TIME"
fi

# ─── Filtrer les dossiers déjà importés (reprise après crash) ──
if [ "$MODE" = "incremental" ] && [ -n "$IMPORT_START_TIME" ]; then
    log "INFO" "Vérification des dossiers déjà synchronisés depuis $IMPORT_START_TIME..."

    # En mode incrémental, vérifier seulement les tables incrémentales
    EXPECTED_TABLE_COUNT=${#INCREMENTAL_ONLY_TABLES[@]}

    ALREADY_SYNCED=$($MYSQL $MYSQL_OPTS raw_acd -N -e "
        SELECT dossier_code
        FROM sync_tracking_by_dossier
        WHERE last_sync_date >= '$IMPORT_START_TIME'
          AND last_status = 'success'
          AND table_name IN ('ecriture', 'ligne_ecriture')
        GROUP BY dossier_code
        HAVING COUNT(DISTINCT table_name) = $EXPECTED_TABLE_COUNT
    " 2>/dev/null || echo "")

    if [ -n "$ALREADY_SYNCED" ]; then
        FILTERED_DATABASES=()
        SKIPPED_COUNT=0

        for DB in "${ELIGIBLE_DATABASES_LIMITED[@]}"; do
            DOSSIER_CODE="${DB#compta_}"

            if echo "$ALREADY_SYNCED" | grep -qx "$DOSSIER_CODE"; then
                ((SKIPPED_COUNT++)) || true
            else
                FILTERED_DATABASES+=("$DB")
            fi
        done

        if [ $SKIPPED_COUNT -gt 0 ]; then
            log "INFO" "✅ $SKIPPED_COUNT dossiers déjà synchronisés (reprise après crash)"
            ELIGIBLE_DATABASES_LIMITED=("${FILTERED_DATABASES[@]}")
            NB_TO_PROCESS=${#ELIGIBLE_DATABASES_LIMITED[@]}
        fi
    fi
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

if [ "$MODE" = "incremental" ]; then
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

# ─── Fonction: Importer une base (optimisée) ──────────────
import_one_database() {
    local DB="$1"
    local DOSSIER_CODE="${DB#compta_}"

    echo ""
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║ Import: $DB (dossier: $DOSSIER_CODE)"
    echo "╚════════════════════════════════════════════════════════╝"

    # Boucle des 6 tables
    for TABLE in histo_ligne_ecriture histo_ecriture ligne_ecriture ecriture compte journal; do

        # ─── Mode incrémental : Ignorer les tables non-incrémentales ───
        if [ "$MODE" = "incremental" ] || [ "$MODE" = "since" ]; then
            TABLE_IS_INCREMENTAL=false
            for INCR_TABLE in "${INCREMENTAL_ONLY_TABLES[@]}"; do
                if [ "$TABLE" = "$INCR_TABLE" ]; then
                    TABLE_IS_INCREMENTAL=true
                    break
                fi
            done

            if [ "$TABLE_IS_INCREMENTAL" = false ]; then
                printf "  → %-25s ⏭️  Skipped (not incremental)\n" "$TABLE..."
                continue
            fi
        fi

        local COLUMNS=""
        local SELECT_COLS=""

        case "$TABLE" in
            histo_ligne_ecriture)
                COLUMNS="(dossier_code, CPT_CODE, HLE_CRE_ORG, HLE_DEB_ORG, HE_CODE, HLE_CODE, HLE_LIB, HLE_JOUR, HLE_PIECE, HLE_LET, HLE_LETP1, HLE_DATE_LET)"
                SELECT_COLS="'$DOSSIER_CODE', CPT_CODE, HLE_CRE_ORG, HLE_DEB_ORG, HE_CODE, HLE_CODE, HLE_LIB, HLE_JOUR, HLE_PIECE, HLE_LET, HLE_LETP1, HLE_DATE_LET"
            ;;

            histo_ecriture) 
                COLUMNS="(dossier_code, HE_CODE, HE_DATE_SAI, HE_ANNEE, HE_MOIS, JNL_CODE)"
                SELECT_COLS="'$DOSSIER_CODE', HE_CODE, HE_DATE_SAI, HE_ANNEE, HE_MOIS, JNL_CODE"
            ;;

            ligne_ecriture)
                COLUMNS="(dossier_code, CPT_CODE, LE_CRE_ORG, LE_DEB_ORG, ECR_CODE, LE_CODE, LE_LIB, LE_JOUR, LE_PIECE, LE_LET, LE_LETP1, LE_DATE_LET)"
                SELECT_COLS="'$DOSSIER_CODE', CPT_CODE, LE_CRE_ORG, LE_DEB_ORG, ECR_CODE, LE_CODE, LE_LIB, LE_JOUR, LE_PIECE, LE_LET, COALESCE(LE_LETP1, 0), LE_DATE_LET"
            ;;

            ecriture)
                COLUMNS="(dossier_code, ECR_CODE, ECR_DATE_SAI, ECR_ANNEE, ECR_MOIS, JNL_CODE)"
                SELECT_COLS="'$DOSSIER_CODE', ECR_CODE, ECR_DATE_SAI, ECR_ANNEE, ECR_MOIS, JNL_CODE"
            ;;

            compte)
                COLUMNS="(dossier_code, CPT_CODE, CPT_LIB)"
                SELECT_COLS="'$DOSSIER_CODE', CPT_CODE, CPT_LIB"
            ;;

            journal)
                COLUMNS="(dossier_code, JNL_CODE, JNL_LIB, JNL_TYPE)"
                SELECT_COLS="'$DOSSIER_CODE', JNL_CODE, JNL_LIB, JNL_TYPE"
            ;;
        esac

        # Temp TSV
        TMP_FILE="/tmp/acd_${DB}_${TABLE}_$$.tsv"

        printf "  → %-25s " "$TABLE..."
        local START=$(date +%s)

        # Déterminer le filtre WHERE selon la table et le mode
        local WHERE_CLAUSE=""

        if [ "$MODE" = "incremental" ] || [ "$MODE" = "since" ]; then
            case "$TABLE" in
                ecriture)
                    # Filtre direct sur ECR_DATE_SAI
                    local SYNC_DATE="${LAST_SYNC_DATES[$TABLE]:-2000-01-01 00:00:00}"
                    if [ "$MODE" = "since" ]; then SYNC_DATE="$SINCE_DATE"; fi
                    WHERE_CLAUSE="WHERE ECR_DATE_SAI > STR_TO_DATE('$SYNC_DATE', '%Y-%m-%d %H:%i:%s')"
                ;;

                ligne_ecriture)
                    # Jointure avec ecriture sur ECR_CODE, filtre sur ECR_DATE_SAI
                    local SYNC_DATE="${LAST_SYNC_DATES[$TABLE]:-2000-01-01 00:00:00}"
                    if [ "$MODE" = "since" ]; then SYNC_DATE="$SINCE_DATE"; fi
                    WHERE_CLAUSE="WHERE EXISTS (
                        SELECT 1 FROM \`$DB\`.ecriture e
                        WHERE e.ECR_CODE = \`$DB\`.ligne_ecriture.ECR_CODE
                        AND e.ECR_DATE_SAI > STR_TO_DATE('$SYNC_DATE', '%Y-%m-%d %H:%i:%s')
                    )"
                ;;
            esac
        fi

        # 1. Extraction ACD vers fichier TSV (avec filtre WHERE si applicable)
        if ! $MYSQL -h "$ACD_HOST" -P "$ACD_PORT" \
                 -u "$ACD_USER" -p"$ACD_PASS" \
                 --skip-column-names \
                 -e "SELECT $SELECT_COLS FROM \`$DB\`.\`$TABLE\` $WHERE_CLAUSE" \
                 > "$TMP_FILE" 2>/tmp/acd_err_$$.log
        then
            echo "❌ ERREUR (ACD)"
            cat /tmp/acd_err_$$.log
            rm -f "$TMP_FILE" /tmp/acd_err_$$.log
            return 1
        fi

        # 2. Load dans raw_acd local
        # IMPORTANT: FIELDS/LINES doivent être AVANT la liste des colonnes
        # REPLACE INTO : gestion des doublons en mode incrémental
        if ! $MYSQL $MYSQL_OPTS -e "
            LOAD DATA LOCAL INFILE '$TMP_FILE'
            REPLACE INTO TABLE raw_acd.$TABLE
            FIELDS TERMINATED BY '\t'
            LINES TERMINATED BY '\n'
            $COLUMNS;
        " 2>/tmp/local_err_$$.log
        then
            echo "❌ ERREUR (LOCAL)"
            echo "Requête SQL:"
            echo "LOAD DATA LOCAL INFILE '$TMP_FILE'"
            echo "INTO TABLE raw_acd.$TABLE"
            echo "FIELDS TERMINATED BY '\t'"
            echo "LINES TERMINATED BY '\n'"
            echo "$COLUMNS;"
            echo "---"
            cat /tmp/local_err_$$.log
            rm -f "$TMP_FILE" /tmp/local_err_$$.log
            return 1
        fi

        rm -f "$TMP_FILE" /tmp/acd_err_$$.log /tmp/local_err_$$.log

        # 3. Statistiques locales
        local COUNT=$($MYSQL $MYSQL_OPTS -N -e \
            "SELECT COUNT(*) FROM raw_acd.$TABLE WHERE dossier_code='$DOSSIER_CODE'" \
            2>/dev/null || echo 0)

        local END=$(date +%s)
        printf "✓ (%ds, %s lignes)\n" "$((END - START))" "$COUNT"
    done

    # Mettre à jour le tracking PAR DOSSIER (nouvelle table)
    if [ "$MODE" = "incremental" ] || [ "$MODE" = "since" ]; then
        for TABLE in "${INCREMENTAL_ONLY_TABLES[@]}"; do
            local ROWS_IMPORTED=$([ -f "$TMP_FILE" ] && wc -l < "$TMP_FILE" 2>/dev/null || echo 0)

            $MYSQL $MYSQL_OPTS raw_acd -e "
                INSERT INTO sync_tracking_by_dossier
                    (table_name, dossier_code, last_sync_date, last_sync_type, last_status, rows_imported)
                VALUES
                    ('$TABLE', '$DOSSIER_CODE', '$IMPORT_START_TIME', '$MODE', 'success', $ROWS_IMPORTED)
                ON DUPLICATE KEY UPDATE
                    last_sync_date = '$IMPORT_START_TIME',
                    last_sync_type = '$MODE',
                    last_status = 'success',
                    rows_imported = $ROWS_IMPORTED,
                    updated_at = CURRENT_TIMESTAMP;
            " 2>/dev/null || true  # Ne pas bloquer si erreur de tracking
        done
    fi

    echo "OK: $DB"
}

# Exporter la fonction et les variables pour xargs
export -f import_one_database
export MODE SINCE_DATE
export ACD_HOST ACD_PORT ACD_USER ACD_PASS
export MYSQL MYSQL_OPTS

# Exporter les dates de sync en mode incremental
if [ "$MODE" = "incremental" ]; then
    for TABLE in "${REQUIRED_TABLES[@]}"; do
        VAR_NAME="SYNC_DATE_${TABLE}"
        export "${VAR_NAME}=${LAST_SYNC_DATES[$TABLE]}"
    done
fi

# ─── Créer fichier temporaire avec liste des bases ────────
TMP_BDDS_FILE="/tmp/acd_eligible_bases_$$.txt"
printf "%s\n" "${ELIGIBLE_DATABASES_LIMITED[@]}" > "$TMP_BDDS_FILE"

# ─── Import séquentiel (pas de parallélisme sur la source) ─
log "INFO" "Lancement des imports (traitement séquentiel pour protéger la source)..."
log "INFO" "Nombre de bases à traiter: $NB_TO_PROCESS"
START_TIME=$(date +%s)

# Compteur pour la progression
COUNTER=0
BATCH_SIZE=5

cat "$TMP_BDDS_FILE" | xargs -P "$PARALLEL_JOBS" -I {} bash -c \
    "import_one_database '{}'" \
    2>&1 | while read line; do
        echo "[$(date '+%H:%M:%S')] $line"

        # Incrémenter et afficher progression tous les 5 imports
        if [[ "$line" == OK:* ]]; then
            ((COUNTER++)) || true
            if (( COUNTER % BATCH_SIZE == 0 )); then
                ELAPSED=$(($(date +%s) - START_TIME))
                REMAINING=$(($NB_TO_PROCESS - COUNTER))
                AVG_TIME=$((ELAPSED / COUNTER))
                ETA=$((REMAINING * AVG_TIME))

                echo ""
                echo "════════════════════════════════════════════════════════"
                echo "📊 PROGRESSION: $COUNTER / $NB_TO_PROCESS bases traitées ($(( COUNTER * 100 / NB_TO_PROCESS ))%)"
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

# Tracker uniquement les tables effectivement traitées
if [ "$MODE" = "incremental" ] || [ "$MODE" = "since" ]; then
    TABLES_TO_TRACK=("${INCREMENTAL_ONLY_TABLES[@]}")
else
    TABLES_TO_TRACK=("${REQUIRED_TABLES[@]}")
fi

for TABLE in "${TABLES_TO_TRACK[@]}"; do
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