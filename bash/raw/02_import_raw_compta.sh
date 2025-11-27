#!/bin/bash
# ============================================================
# IMPORT RAW_ACD - Import centralisé des données comptables ACD
# Importe 6 tables spécifiques depuis compta_* vers raw_acd
# Modes: --full, --incremental, --dossier-full, --dossier-incremental
# Tracking par dossier avec sync_tracking_by_dossier
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
DEBUG=false
TARGET_DOSSIER=""

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --full                      Import complet de tous les dossiers (TRUNCATE + réimport) [défaut]"
    echo "  --incremental               Import incrémental de tous les dossiers (depuis last_sync_date)"
    echo "  --dossier-full CODE         Import complet d'un dossier spécifique (DELETE + réimport)"
    echo "  --dossier-incremental CODE  Import incrémental d'un dossier spécifique"
    echo "  --debug                     Mode debug (affiche requêtes SQL et timings détaillés)"
    echo ""
    echo "Exemples:"
    echo "  $0 --full                                   # Import complet de tous les dossiers"
    echo "  $0 --incremental                            # Import incrémental de tous"
    echo "  $0 --dossier-full SCIANNAFOO                # Import complet du dossier SCIANNAFOO"
    echo "  $0 --dossier-incremental SCIANNAFOO --debug # Import incrémental avec debug"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --full)                  MODE="full"; shift ;;
        --incremental)           MODE="incremental"; shift ;;
        --dossier-full)          MODE="dossier-full"; TARGET_DOSSIER="$2"; shift 2 ;;
        --dossier-incremental)   MODE="dossier-incremental"; TARGET_DOSSIER="$2"; shift 2 ;;
        --debug)                 DEBUG=true; shift ;;
        -h|--help)               usage ;;
        *)                       echo "Option inconnue: $1"; usage ;;
    esac
done

# Vérifier que TARGET_DOSSIER est fourni pour les modes dossier-*
if [[ "$MODE" == "dossier-full" || "$MODE" == "dossier-incremental" ]]; then
    if [ -z "$TARGET_DOSSIER" ]; then
        log "ERROR" "Le code dossier est requis pour le mode $MODE"
        usage
    fi
    TARGET_DOSSIER=$(echo "$TARGET_DOSSIER" | tr '[:lower:]' '[:upper:]')
fi

log_section "IMPORT RAW_ACD (ACD) - Mode: $MODE"
if [ "$DEBUG" = true ]; then
    log "INFO" "🐛 Mode DEBUG activé - Affichage des requêtes SQL et timings"
fi

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

        if [ "$EXISTS" -eq 0 ]; then
            return 1
        fi
    done
    return 0
}

# ─── Fonction: Récupérer la last_sync_date pour un dossier et une table ────
get_last_sync_date_for_dossier() {
    local DOSSIER_CODE="$1"
    local TABLE_NAME="$2"

    local LAST_SYNC=$($MYSQL $MYSQL_OPTS -N -e "
        SELECT IFNULL(DATE_FORMAT(last_sync_date, '%Y-%m-%d %H:%i:%s'), '2000-01-01 00:00:00')
        FROM raw_acd.sync_tracking_by_dossier
        WHERE dossier_code = '$DOSSIER_CODE'
        AND table_name = '$TABLE_NAME'
        LIMIT 1
    " 2>/dev/null || echo "2000-01-01 00:00:00")

    echo "$LAST_SYNC"
}

# ─── Fonction: Mettre à jour sync_tracking_by_dossier ─────
update_sync_tracking() {
    local DOSSIER_CODE="$1"
    local TABLE_NAME="$2"
    local ROWS_IMPORTED="$3"
    local SYNC_TYPE="$4"  # full ou incremental

    $MYSQL $MYSQL_OPTS -e "
        INSERT INTO raw_acd.sync_tracking_by_dossier
            (dossier_code, table_name, last_sync_date, last_sync_type, last_status, rows_imported)
        VALUES
            ('$DOSSIER_CODE', '$TABLE_NAME', NOW(), '$SYNC_TYPE', 'success', $ROWS_IMPORTED)
        ON DUPLICATE KEY UPDATE
            last_sync_date = NOW(),
            last_sync_type = '$SYNC_TYPE',
            last_status = 'success',
            rows_imported = $ROWS_IMPORTED,
            updated_at = NOW()
    " 2>/dev/null
}

# ─── Fonction: Import d'une base ──────────────────────────
import_one_database() {
    local DB="$1"
    local DOSSIER_CODE=$(echo "$DB" | sed 's/compta_//' | tr '[:lower:]' '[:upper:]')

    # ─── Validation : Vérifier longueur du code dossier (max 20 caractères) ───
    if [ ${#DOSSIER_CODE} -gt 20 ]; then
        log "ERROR" "⚠️  Code dossier '$DOSSIER_CODE' trop long (${#DOSSIER_CODE} caractères, max 20) - Base $DB ignorée"
        return 1
    fi

    if [ "$DEBUG" = true ]; then
        log "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log "INFO" "📦 Base: $DB | Dossier: $DOSSIER_CODE"
        log "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi

    # Parcourir les 6 tables
    for TABLE in "${REQUIRED_TABLES[@]}"; do

        # ─── Mode incrémental : Ignorer les tables non-incrémentales ───
        if [ "$MODE" = "incremental" ] || [ "$MODE" = "dossier-incremental" ]; then
            TABLE_IS_INCREMENTAL=false
            for INCR_TABLE in "${INCREMENTAL_ONLY_TABLES[@]}"; do
                if [ "$TABLE" = "$INCR_TABLE" ]; then
                    TABLE_IS_INCREMENTAL=true
                    break
                fi
            done

            if [ "$TABLE_IS_INCREMENTAL" = false ]; then
                if [ "$DEBUG" = true ]; then
                    log "INFO" "  → $TABLE (⏭️  skipped - not incremental)"
                fi
                continue
            fi
        fi

        local TMP_FILE="/tmp/acd_import_${DB}_${TABLE}.tsv"

        # ─── Colonnes et requête SELECT selon la table ───
        local LOAD_COLUMNS=""
        local SELECT_COLS=""
        local WHERE_CLAUSE=""

        case $TABLE in
            histo_ligne_ecriture)
                LOAD_COLUMNS="(dossier_code, CPT_CODE, @hle_cre, @hle_deb, HE_CODE, HLE_CODE, HLE_LIB, HLE_JOUR, HLE_PIECE, HLE_LET, HLE_LETP1, HLE_DATE_LET) SET HLE_CRE_ORG = NULLIF(@hle_cre, ''), HLE_DEB_ORG = NULLIF(@hle_deb, '')"
                SELECT_COLS="'$DOSSIER_CODE', CPT_CODE, IFNULL(HLE_CRE_ORG, ''), IFNULL(HLE_DEB_ORG, ''), HE_CODE, HLE_CODE, HLE_LIB, HLE_JOUR, HLE_PIECE, HLE_LET, COALESCE(HLE_LETP1, 0), HLE_DATE_LET"
            ;;

            histo_ecriture)
                LOAD_COLUMNS="(dossier_code, HE_CODE, HE_DATE_SAI, HE_ANNEE, HE_MOIS, JNL_CODE)"
                SELECT_COLS="'$DOSSIER_CODE', HE_CODE, HE_DATE_SAI, HE_ANNEE, HE_MOIS, JNL_CODE"
            ;;

            ligne_ecriture)
                LOAD_COLUMNS="(dossier_code, CPT_CODE, @le_cre, @le_deb, ECR_CODE, LE_CODE, LE_LIB, LE_JOUR, LE_PIECE, LE_LET, LE_LETP1, LE_DATE_LET) SET LE_CRE_ORG = NULLIF(@le_cre, ''), LE_DEB_ORG = NULLIF(@le_deb, '')"
                SELECT_COLS="'$DOSSIER_CODE', CPT_CODE, IFNULL(LE_CRE_ORG, ''), IFNULL(LE_DEB_ORG, ''), ECR_CODE, LE_CODE, LE_LIB, LE_JOUR, LE_PIECE, LE_LET, COALESCE(LE_LETP1, 0), LE_DATE_LET"
            ;;

            ecriture)
                LOAD_COLUMNS="(dossier_code, ECR_CODE, ECR_DATE_SAI, ECR_ANNEE, ECR_MOIS, JNL_CODE)"
                SELECT_COLS="'$DOSSIER_CODE', ECR_CODE, ECR_DATE_SAI, ECR_ANNEE, ECR_MOIS, JNL_CODE"
            ;;

            compte)
                LOAD_COLUMNS="(dossier_code, CPT_CODE, CPT_LIB)"
                SELECT_COLS="'$DOSSIER_CODE', CPT_CODE, CPT_LIB"
            ;;

            journal)
                LOAD_COLUMNS="(dossier_code, JNL_CODE, JNL_LIB, JNL_TYPE)"
                SELECT_COLS="'$DOSSIER_CODE', JNL_CODE, JNL_LIB, JNL_TYPE"
            ;;
        esac

        # ─── Filtre WHERE pour les tables incrémentales ───
        if [ "$MODE" = "incremental" ] || [ "$MODE" = "dossier-incremental" ]; then
            case $TABLE in
                ecriture)
                    # Filtre direct sur ECR_DATE_SAI
                    local SYNC_DATE=$(get_last_sync_date_for_dossier "$DOSSIER_CODE" "$TABLE")
                    WHERE_CLAUSE="WHERE ECR_DATE_SAI > STR_TO_DATE('$SYNC_DATE', '%Y-%m-%d %H:%i:%s')"
                ;;

                ligne_ecriture)
                    # Jointure avec ecriture sur ECR_CODE, filtre sur ECR_DATE_SAI
                    local SYNC_DATE=$(get_last_sync_date_for_dossier "$DOSSIER_CODE" "$TABLE")
                    WHERE_CLAUSE="WHERE EXISTS (
                        SELECT 1 FROM \`$DB\`.ecriture e
                        WHERE e.ECR_CODE = \`$DB\`.ligne_ecriture.ECR_CODE
                        AND e.ECR_DATE_SAI > STR_TO_DATE('$SYNC_DATE', '%Y-%m-%d %H:%i:%s')
                    )"
                ;;
            esac
        fi

        # ─── Mode DEBUG : Afficher la requête SQL ───
        if [ "$DEBUG" = true ]; then
            echo ""
            log "INFO" "  → Table: $TABLE"
            echo ""
            log "INFO" "  📋 REQUÊTE SQL :"
            echo "SELECT $SELECT_COLS"
            echo "FROM \`$DB\`.\`$TABLE\` $WHERE_CLAUSE"
            echo ""
        fi

        # ─── 1. Extraction ACD vers fichier TSV ───
        local EXTRACT_START=$(date +%s.%N)
        local ERR_FILE="/tmp/acd_err_$$.log"

        if ! $MYSQL -h "$ACD_HOST" -P "$ACD_PORT" \
                 -u "$ACD_USER" -p"$ACD_PASS" \
                 --skip-column-names \
                 -e "SELECT $SELECT_COLS FROM \`$DB\`.\`$TABLE\` $WHERE_CLAUSE" \
                 > "$TMP_FILE" 2>"$ERR_FILE"; then
            log "ERROR" "Échec extraction $TABLE depuis $DB"
            if [ -s "$ERR_FILE" ]; then
                echo "  Détails: $(cat $ERR_FILE | head -3)"
            fi
            rm -f "$TMP_FILE" "$ERR_FILE"
            continue
        fi
        rm -f "$ERR_FILE"

        local EXTRACT_END=$(date +%s.%N)
        local EXTRACT_DURATION=$(echo "$EXTRACT_END - $EXTRACT_START" | bc)
        local ROWS_EXTRACTED=$(wc -l < "$TMP_FILE")

        if [ "$DEBUG" = true ]; then
            printf "  ⏱️  Extraction: %s lignes en %.2fs\n" "$ROWS_EXTRACTED" "$EXTRACT_DURATION"
        fi

        # ─── 2. LOAD local dans raw_acd ───
        local LOAD_START=$(date +%s.%N)

        # if ! $MYSQL $MYSQL_OPTS --local-infile=1 -e "
        #     LOAD DATA LOCAL INFILE '$TMP_FILE'
        #     REPLACE INTO TABLE raw_acd.$TABLE
        #     FIELDS TERMINATED BY '\t'
        #     LINES TERMINATED BY '\n'
        #     $LOAD_COLUMNS
        # " 2>/dev/null; then
        #     log "ERROR" "Échec import $TABLE pour $DB"
        #     rm -f "$TMP_FILE"
        #     continue
        # fi

        if ! $MYSQL $MYSQL_OPTS --local-infile=1 -e "
            LOAD DATA LOCAL INFILE '$TMP_FILE'
            REPLACE INTO TABLE raw_acd.$TABLE
            FIELDS TERMINATED BY '\t'
            LINES TERMINATED BY '\n'
            $LOAD_COLUMNS
        "; then
            log "ERROR" "Échec import $TABLE pour $DB - passage à la table suivante"
            rm -f "$TMP_FILE"
            continue
        fi

        local LOAD_END=$(date +%s.%N)
        local LOAD_DURATION=$(echo "$LOAD_END - $LOAD_START" | bc)

        if [ "$DEBUG" = true ]; then
            printf "  ⏱️  LOAD DATA: %.2fs\n" "$LOAD_DURATION"
            log "SUCCESS" "  ✅ $TABLE importé"
            echo ""
        fi

        # ─── 3. Mettre à jour le tracking par dossier ───
        local SYNC_TYPE="full"
        if [ "$MODE" = "incremental" ] || [ "$MODE" = "dossier-incremental" ]; then
            SYNC_TYPE="incremental"
        fi

        update_sync_tracking "$DOSSIER_CODE" "$TABLE" "$ROWS_EXTRACTED" "$SYNC_TYPE"

        # Nettoyage
        rm -f "$TMP_FILE"
    done
}

# ─── MODE: dossier-full (DELETE + réimport d'un seul dossier) ───
if [ "$MODE" = "dossier-full" ]; then
    log "INFO" "🗑️  Suppression des données du dossier $TARGET_DOSSIER..."

    for TABLE in "${REQUIRED_TABLES[@]}"; do
        $MYSQL $MYSQL_OPTS -e "DELETE FROM raw_acd.$TABLE WHERE dossier_code = '$TARGET_DOSSIER'" 2>/dev/null
    done

    log "SUCCESS" "Données du dossier $TARGET_DOSSIER supprimées"

    # Vérifier que la base compta_* existe
    local TARGET_DB="compta_$(echo "$TARGET_DOSSIER" | tr '[:upper:]' '[:lower:]')"

    if ! check_database_has_required_tables "$TARGET_DB"; then
        log "ERROR" "La base $TARGET_DB n'existe pas ou n'a pas les 6 tables requises"
        exit 1
    fi

    log "INFO" "Import complet du dossier $TARGET_DOSSIER depuis $TARGET_DB..."
    import_one_database "$TARGET_DB"

    log "SUCCESS" "✅ Import complet du dossier $TARGET_DOSSIER terminé"

    # Analyser les tables modifiées
    log "INFO" "Analyse des tables modifiées..."
    for TABLE in "${REQUIRED_TABLES[@]}"; do
        $MYSQL $MYSQL_OPTS -e "ANALYZE TABLE raw_acd.$TABLE" > /dev/null 2>&1
    done
    log "SUCCESS" "Tables analysées"

    exit 0
fi

# ─── MODE: dossier-incremental (import incrémental d'un seul dossier) ───
if [ "$MODE" = "dossier-incremental" ]; then
    local TARGET_DB="compta_$(echo "$TARGET_DOSSIER" | tr '[:upper:]' '[:lower:]')"

    if ! check_database_has_required_tables "$TARGET_DB"; then
        log "ERROR" "La base $TARGET_DB n'existe pas ou n'a pas les 6 tables requises"
        exit 1
    fi

    log "INFO" "Import incrémental du dossier $TARGET_DOSSIER depuis $TARGET_DB..."
    import_one_database "$TARGET_DB"

    log "SUCCESS" "✅ Import incrémental du dossier $TARGET_DOSSIER terminé"

    # Analyser les tables modifiées
    log "INFO" "Analyse des tables incrémentales..."
    $MYSQL $MYSQL_OPTS -e "ANALYZE TABLE raw_acd.ecriture, raw_acd.ligne_ecriture" > /dev/null 2>&1
    log "SUCCESS" "Tables analysées"

    exit 0
fi

# ─── MODE: full (TRUNCATE + réimport de tous les dossiers) ───
if [ "$MODE" = "full" ]; then
    log "INFO" "🗑️  TRUNCATE de toutes les tables raw_acd..."

    for TABLE in "${REQUIRED_TABLES[@]}"; do
        $MYSQL $MYSQL_OPTS -e "TRUNCATE TABLE raw_acd.$TABLE" 2>/dev/null
        log "INFO" "  → $TABLE vidée"
    done

    log "SUCCESS" "Tables vidées"
fi

# ─── Lister toutes les bases compta_* éligibles ───
log "INFO" "🔍 Recherche des bases compta_* éligibles..."

DATABASES=()
while IFS= read -r DB; do
    # Exclure les bases dans EXCLUDED_DATABASES
    EXCLUDED=false
    for EXCLUDED_DB in "${EXCLUDED_DATABASES[@]}"; do
        if [ "$DB" = "$EXCLUDED_DB" ]; then
            EXCLUDED=true
            break
        fi
    done

    if [ "$EXCLUDED" = true ]; then
        continue
    fi

    # Vérifier que la base a bien les 6 tables
    if check_database_has_required_tables "$DB"; then
        DATABASES+=("$DB")
    fi
done < <($MYSQL -h "$ACD_HOST" -P "$ACD_PORT" -u "$ACD_USER" -p"$ACD_PASS" -N -e "
    SELECT SCHEMA_NAME
    FROM information_schema.SCHEMATA
    WHERE SCHEMA_NAME LIKE 'compta_%'
    ORDER BY SCHEMA_NAME
" 2>/dev/null)

TOTAL_DBS=${#DATABASES[@]}
log "INFO" "📊 $TOTAL_DBS bases compta_* trouvées avec les 6 tables requises"

if [ "$TOTAL_DBS" -eq 0 ]; then
    log "ERROR" "Aucune base éligible trouvée"
    exit 1
fi

# ─── Import de toutes les bases ───
CURRENT=0
SKIPPED_DOSSIERS=0
FAILED_DOSSIERS=0
START_TIME=$(date +%s)

log_section "IMPORT RAW_ACD - Traitement de $TOTAL_DBS bases"

for DB in "${DATABASES[@]}"; do
    CURRENT=$((CURRENT + 1))

    # Log périodique tous les 100 dossiers + premier + dernier
    if [ "$DEBUG" = false ]; then
        if [ $CURRENT -eq 1 ] || [ $CURRENT -eq $TOTAL_DBS ] || [ $((CURRENT % 100)) -eq 0 ]; then
            log "INFO" "Progression: [$CURRENT/$TOTAL_DBS] bases traitées..."
        fi
        printf "\r[%d/%d] Traitement de %-30s" "$CURRENT" "$TOTAL_DBS" "$DB"
    fi

    # Capturer le code de retour pour détecter les dossiers ignorés
    if ! import_one_database "$DB"; then
        SKIPPED_DOSSIERS=$((SKIPPED_DOSSIERS + 1))
    fi
done

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""  # Nouvelle ligne après la progression
log "SUCCESS" "✅ Import terminé en ${DURATION}s ($TOTAL_DBS bases traitées)"

if [ "$SKIPPED_DOSSIERS" -gt 0 ]; then
    log "WARNING" "⚠️  $SKIPPED_DOSSIERS dossier(s) ignoré(s) (code trop long > 20 caractères)"
fi

# ─── Gestion des indexes selon le mode ───
if [ "$MODE" = "full" ]; then
    log "INFO" "🔧 Création des indexes optimisés..."

    # Drop indexes avant de les recréer
    $MYSQL $MYSQL_OPTS -e "
        -- Drop existing indexes
        ALTER TABLE raw_acd.compte DROP INDEX IF EXISTS idx_dossier;
        ALTER TABLE raw_acd.compte DROP INDEX IF EXISTS idx_dossier_compte;
        ALTER TABLE raw_acd.ecriture DROP INDEX IF EXISTS idx_dossier_annee_mois;
        ALTER TABLE raw_acd.ecriture DROP INDEX IF EXISTS idx_dossier_journal;
        ALTER TABLE raw_acd.ecriture DROP INDEX IF EXISTS idx_date_sai;
        ALTER TABLE raw_acd.histo_ecriture DROP INDEX IF EXISTS idx_dossier_annee_mois;
        ALTER TABLE raw_acd.histo_ecriture DROP INDEX IF EXISTS idx_dossier_journal;
        ALTER TABLE raw_acd.journal DROP INDEX IF EXISTS idx_dossier;
        ALTER TABLE raw_acd.journal DROP INDEX IF EXISTS idx_dossier_code;
        ALTER TABLE raw_acd.ligne_ecriture DROP INDEX IF EXISTS idx_dossier_compte;
        ALTER TABLE raw_acd.ligne_ecriture DROP INDEX IF EXISTS idx_dossier_ecriture;
        ALTER TABLE raw_acd.ligne_ecriture DROP INDEX IF EXISTS idx_compte;
        ALTER TABLE raw_acd.histo_ligne_ecriture DROP INDEX IF EXISTS idx_dossier_compte;
        ALTER TABLE raw_acd.histo_ligne_ecriture DROP INDEX IF EXISTS idx_dossier_ecriture;
        ALTER TABLE raw_acd.histo_ligne_ecriture DROP INDEX IF EXISTS idx_compte;
    " 2>/dev/null || true

    # Recréer les indexes
    $MYSQL $MYSQL_OPTS < "$SCRIPT_DIR/../sql/02b_raw_acd_tables.sql" 2>&1 | grep -v "Duplicate key name" || true

    log "SUCCESS" "Indexes créés"

elif [ "$MODE" = "incremental" ]; then
    log "INFO" "🔧 Analyse des tables incrémentales..."
    $MYSQL $MYSQL_OPTS -e "ANALYZE TABLE raw_acd.ecriture, raw_acd.ligne_ecriture" > /dev/null 2>&1
    log "SUCCESS" "Tables analysées"
fi

# ─── Statistiques finales ───
log "INFO" "📊 Statistiques finales:"

$MYSQL $MYSQL_OPTS -e "
    SELECT
        'ecriture' as table_name,
        COUNT(*) as rows_count,
        COUNT(DISTINCT dossier_code) as dossiers_count
    FROM raw_acd.ecriture
    UNION ALL
    SELECT
        'ligne_ecriture',
        COUNT(*),
        COUNT(DISTINCT dossier_code)
    FROM raw_acd.ligne_ecriture
" | column -t

log "SUCCESS" "🎉 Import raw_acd terminé avec succès !"
