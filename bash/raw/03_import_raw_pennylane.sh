#!/bin/bash
# ============================================================
# IMPORT RAW PENNYLANE (depuis Redshift)
# Export CSV depuis Redshift puis chargement dans raw_pennylane
# Modes: --full (défaut), --incremental, --since DATE
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/logging.sh"

# ─── Configuration pagination ──────────────────────────────
BATCH_SIZE=100000  # Nombre de lignes par batch pour general_ledger

# ─── Arguments ─────────────────────────────────────────────
MODE="full"  # Par défaut: import complet
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
fi

# Récupérer last_sync_date si mode incremental
if [ "$MODE" = "incremental" ]; then
    SINCE_DATE=$($MYSQL $MYSQL_OPTS -N -e "
        SELECT IFNULL(MAX(last_sync_date), '2000-01-01 00:00:00')
        FROM raw_pennylane.sync_tracking
        WHERE table_name IN ('pl_companies', 'pl_general_ledger')
    " 2>/dev/null || echo "2000-01-01 00:00:00")
    log "INFO" "Mode incrémental: import depuis $SINCE_DATE"
fi

log_section "IMPORT RAW_PENNYLANE (Redshift) - Mode: $MODE"

# Fichiers temporaires
TMP_COMPANIES="/tmp/pl_companies.csv"
TMP_FISCAL_YEARS="/tmp/pl_fiscal_years.csv"
TMP_GL="/tmp/pl_general_ledger.csv"
TMP_COMPANIES_ID="/tmp/acc_companies_identification.csv"

# Créer le schéma si nécessaire
log "INFO" "Création du schéma raw_pennylane si nécessaire..."
$MYSQL $MYSQL_OPTS -e "CREATE DATABASE IF NOT EXISTS raw_pennylane CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# Exécuter le script SQL de création des tables
log "INFO" "Création des tables raw_pennylane..."
$MYSQL $MYSQL_OPTS < "$SCRIPT_DIR/../sql/02_raw_pennylane_tables.sql"

export PGPASSWORD="$REDSHIFT_PASS"

# ─── Export Companies ───────────────────────────────────────
log_subsection "Export pl_companies"
log "INFO" "Export Companies depuis Redshift..."

# Construire la clause WHERE si mode incremental/since
WHERE_CLAUSE=""
if [ "$MODE" != "full" ] && [ -n "$SINCE_DATE" ]; then
    WHERE_CLAUSE="WHERE c.updated_at >= '$SINCE_DATE'"
    log "INFO" "Filtre: updated_at >= $SINCE_DATE"
fi

psql --csv -v ON_ERROR_STOP=1 --pset null='NULL' \
    -h "$REDSHIFT_HOST" -p "$REDSHIFT_PORT" -U "$REDSHIFT_USER" -d "$REDSHIFT_DB" \
    > "$TMP_COMPANIES" <<EOF
SELECT
    c.id as company_id,
    REPLACE(c.name, ',', ';') as name,
    REPLACE(c.firm_name, ',', ';') as firm_name,
    REPLACE(c.trade_name, ',', ';') as trade_name,
    c.registration_number,
    c.vat_number,
    c.country_alpha2,
    REPLACE(c.city, ',', ';') as city,
    c.postal_code,
    c.saas_plan,
    c.vat_frequency,
    c.vat_day_of_month,
    c.fiscal_category,
    c.fiscal_regime,
    c.registration_date,
    REPLACE(c.activity_code, '.', '') as activity_code,
    REPLACE(c.activity_sector, ',', ';') as activity_sector,
    c.legal_form_code,
    REPLACE(c.legal_form, ',', ';') as legal_form,
    c.created_at,
    c.updated_at
FROM pennylane.companies c
$WHERE_CLAUSE
ORDER BY c.id;
EOF

if [ $? -ne 0 ]; then
    log "ERROR" "Échec export Companies"
    exit 1
fi
log "SUCCESS" "Export Companies OK"

# ─── Export Companies Identification ────────────────────────
log_subsection "Export acc_companies_identification"
log "INFO" "Export Companies Identification depuis Redshift..."

psql --csv -v ON_ERROR_STOP=1 --pset null='NULL' \
    -h "$REDSHIFT_HOST" -p "$REDSHIFT_PORT" -U "$REDSHIFT_USER" -d "$REDSHIFT_DB" \
    > "$TMP_COMPANIES_ID" <<EOF
SELECT 
    ci.id as company_id,
    ci.external_id,
    ci.file_type,
    ci.accountant_email,
    ci.accounting_supervisor_email,
    ci.accounting_manager_email,
    ci.company_updated_at
FROM accounting.companies_identification ci
ORDER BY ci.id;
EOF

if [ $? -ne 0 ]; then
    log "ERROR" "Échec export Companies Identification"
    exit 1
fi
log "SUCCESS" "Export Companies Identification OK"

# ─── Export Fiscal Years ────────────────────────────────────
log_subsection "Export pl_fiscal_years"
log "INFO" "Export Fiscal Years depuis Redshift..."

psql --csv -v ON_ERROR_STOP=1 --pset null='NULL' \
    -h "$REDSHIFT_HOST" -p "$REDSHIFT_PORT" -U "$REDSHIFT_USER" -d "$REDSHIFT_DB" \
    > "$TMP_FISCAL_YEARS" <<EOF
SELECT 
    company_id,
    company_name,
    start_year,
    start_date,
    end_date,
    closed_at
FROM pennylane.fiscal_years
ORDER BY company_id, start_date;
EOF

if [ $? -ne 0 ]; then
    log "ERROR" "Échec export Fiscal Years"
    exit 1
fi
log "SUCCESS" "Export Fiscal Years OK"

# ─── Export General Ledger (paginé par batches) ────────────
log_subsection "Export pl_general_ledger"
log "INFO" "Export General Ledger depuis Redshift (mode paginé, $BATCH_SIZE lignes/batch)..."

# Construire la clause WHERE pour GL
WHERE_CLAUSE_GL=""
if [ "$MODE" != "full" ] && [ -n "$SINCE_DATE" ]; then
    WHERE_CLAUSE_GL="WHERE glv.document_updated_at >= '$SINCE_DATE'"
    log "INFO" "Filtre GL: document_updated_at >= $SINCE_DATE"
fi

# Préparer la table pour l'import (TRUNCATE si full)
if [ "$MODE" = "full" ]; then
    log "INFO" "Mode full: TRUNCATE pl_general_ledger + désactivation indexes..."
    $MYSQL $MYSQL_OPTS -e "
    SET FOREIGN_KEY_CHECKS = 0;
    SET UNIQUE_CHECKS = 0;
    ALTER TABLE raw_pennylane.pl_general_ledger DISABLE KEYS;
    TRUNCATE TABLE raw_pennylane.pl_general_ledger;
    "
fi

# Export et import par batches
OFFSET=0
BATCH_NUM=1
TOTAL_ROWS=0
GL_EXPORT_FAILED=false

while true; do
    BATCH_FILE="/tmp/gl_batch_${OFFSET}.csv"

    log "INFO" "Batch $BATCH_NUM: export OFFSET $OFFSET LIMIT $BATCH_SIZE..."

    # Export du batch depuis Redshift
    RETRY_COUNT=0
    BATCH_SUCCESS=false

    while [ $RETRY_COUNT -lt 2 ]; do
        if psql --csv -v ON_ERROR_STOP=1 --pset null='NULL' \
            -h "$REDSHIFT_HOST" -p "$REDSHIFT_PORT" -U "$REDSHIFT_USER" -d "$REDSHIFT_DB" \
            > "$BATCH_FILE" 2>/dev/null <<EOF
SELECT
    glv.id AS gl_line_id,
    glv.company_id,
    glv.company_name,
    glv."date" AS txn_date,
    glv.plan_item_number AS compte,
    REPLACE(glv.plan_item_label, ',', ';') AS compte_label,
    COALESCE(glv.journal_code, '') AS journal_code,
    REPLACE(glv.journal_label, ',', ';') AS journal_label,
    COALESCE(glv.debit, 0) AS debit,
    COALESCE(glv.credit, 0) AS credit,
    glv.document_updated_at
FROM accounting.general_ledger_revision glv
$WHERE_CLAUSE_GL
ORDER BY glv.id
LIMIT $BATCH_SIZE OFFSET $OFFSET;
EOF
        then
            BATCH_SUCCESS=true
            break
        else
            RETRY_COUNT=$((RETRY_COUNT + 1))
            if [ $RETRY_COUNT -lt 2 ]; then
                log "WARNING" "Échec export batch $BATCH_NUM (tentative $RETRY_COUNT/2), retry..."
                sleep 2
            fi
        fi
    done

    # Si échec après 2 tentatives, arrêter l'import de cette table
    if [ "$BATCH_SUCCESS" = false ]; then
        log "ERROR" "Échec export batch $BATCH_NUM après 2 tentatives - arrêt import pl_general_ledger"
        GL_EXPORT_FAILED=true
        rm -f "$BATCH_FILE"
        break
    fi

    # Vérifier si le batch est vide (fin des données)
    ROWS=$(tail -n +2 "$BATCH_FILE" | wc -l)
    if [ "$ROWS" -eq 0 ]; then
        log "INFO" "Batch $BATCH_NUM vide - fin de l'export"
        rm -f "$BATCH_FILE"
        break
    fi

    log "INFO" "Batch $BATCH_NUM: $ROWS lignes exportées, import MySQL..."

    # Import du batch dans MySQL
    if [ "$MODE" = "full" ]; then
        LOAD_MODE="INTO"
    else
        LOAD_MODE="REPLACE INTO"
    fi

    if ! $MYSQL $MYSQL_OPTS --local-infile=1 -e "
    LOAD DATA LOCAL INFILE '$BATCH_FILE'
    $LOAD_MODE TABLE raw_pennylane.pl_general_ledger
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\"'
    IGNORE 1 LINES
    (gl_line_id, company_id, company_name, txn_date, compte, compte_label,
     journal_code, journal_label, debit, credit, document_updated_at);
    " 2>/dev/null; then
        log "ERROR" "Échec import batch $BATCH_NUM dans MySQL - arrêt import pl_general_ledger"
        GL_EXPORT_FAILED=true
        rm -f "$BATCH_FILE"
        break
    fi

    TOTAL_ROWS=$((TOTAL_ROWS + ROWS))
    log "SUCCESS" "Batch $BATCH_NUM importé ($ROWS lignes) - Total: $TOTAL_ROWS lignes"

    # Nettoyage du batch
    rm -f "$BATCH_FILE"

    # Si moins de lignes que BATCH_SIZE, c'est le dernier batch
    if [ "$ROWS" -lt "$BATCH_SIZE" ]; then
        log "INFO" "Dernier batch traité (< $BATCH_SIZE lignes)"
        break
    fi

    # Passer au batch suivant
    OFFSET=$((OFFSET + BATCH_SIZE))
    BATCH_NUM=$((BATCH_NUM + 1))
done

# Réactiver les indexes si mode full
if [ "$MODE" = "full" ] && [ "$GL_EXPORT_FAILED" = false ]; then
    log "INFO" "Reconstruction des indexes pl_general_ledger..."
    $MYSQL $MYSQL_OPTS -e "
    ALTER TABLE raw_pennylane.pl_general_ledger ENABLE KEYS;
    SET UNIQUE_CHECKS = 1;
    SET FOREIGN_KEY_CHECKS = 1;
    "
    log "SUCCESS" "Indexes reconstruits"
fi

if [ "$GL_EXPORT_FAILED" = true ]; then
    log "WARNING" "Import pl_general_ledger incomplet - passage aux tables suivantes"
    GL_COUNT=0
else
    GL_COUNT=$($MYSQL $MYSQL_OPTS -N -e "SELECT COUNT(*) FROM raw_pennylane.pl_general_ledger")
    log "SUCCESS" "Export/Import General Ledger OK - $GL_COUNT lignes au total"
fi

# ─── Chargement dans MySQL ──────────────────────────────────
log_section "CHARGEMENT DANS MYSQL"

# Vider et charger pl_companies
log "INFO" "Chargement pl_companies..."
if [ "$MODE" = "full" ]; then
    $MYSQL $MYSQL_OPTS -e "TRUNCATE TABLE raw_pennylane.pl_companies;"
    LOAD_MODE="INTO"
else
    LOAD_MODE="REPLACE INTO"
fi

$MYSQL $MYSQL_OPTS --local-infile=1 -e "
LOAD DATA LOCAL INFILE '$TMP_COMPANIES'
$LOAD_MODE TABLE raw_pennylane.pl_companies
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\"'
IGNORE 1 LINES
(company_id, name, firm_name, trade_name, registration_number, vat_number,
 country_alpha2, city, postal_code, saas_plan, vat_frequency, vat_day_of_month,
 fiscal_category, fiscal_regime, registration_date, activity_code,
 activity_sector, legal_form_code, legal_form, created_at, updated_at);
"
COMPANIES_COUNT=$($MYSQL $MYSQL_OPTS -N -e "SELECT COUNT(*) FROM raw_pennylane.pl_companies")
log "SUCCESS" "pl_companies: $COMPANIES_COUNT lignes"

# Vider et charger acc_companies_identification
log "INFO" "Chargement acc_companies_identification..."
$MYSQL $MYSQL_OPTS -e "TRUNCATE TABLE raw_pennylane.acc_companies_identification;"
$MYSQL $MYSQL_OPTS --local-infile=1 -e "
LOAD DATA LOCAL INFILE '$TMP_COMPANIES_ID'
INTO TABLE raw_pennylane.acc_companies_identification
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\"'
IGNORE 1 LINES
(company_id, external_id, file_type, accountant_email, 
 accounting_supervisor_email, accounting_manager_email, company_updated_at);
"
COMPANIES_ID_COUNT=$($MYSQL $MYSQL_OPTS -N -e "SELECT COUNT(*) FROM raw_pennylane.acc_companies_identification")
log "SUCCESS" "acc_companies_identification: $COMPANIES_ID_COUNT lignes"

# Vider et charger pl_fiscal_years
log "INFO" "Chargement pl_fiscal_years..."
$MYSQL $MYSQL_OPTS -e "TRUNCATE TABLE raw_pennylane.pl_fiscal_years;"
$MYSQL $MYSQL_OPTS --local-infile=1 -e "
LOAD DATA LOCAL INFILE '$TMP_FISCAL_YEARS'
INTO TABLE raw_pennylane.pl_fiscal_years
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\"'
IGNORE 1 LINES
(company_id, company_name, start_year, start_date, end_date, closed_at);
"
FY_COUNT=$($MYSQL $MYSQL_OPTS -N -e "SELECT COUNT(*) FROM raw_pennylane.pl_fiscal_years")
log "SUCCESS" "pl_fiscal_years: $FY_COUNT lignes"

# Nettoyage
log "INFO" "Nettoyage fichiers temporaires..."
rm -f "$TMP_COMPANIES" "$TMP_COMPANIES_ID" "$TMP_FISCAL_YEARS" "$TMP_GL" /tmp/gl_batch_*.csv

# ─── Mise à jour sync_tracking ─────────────────────────────
log "INFO" "Mise à jour du tracking..."

$MYSQL $MYSQL_OPTS raw_pennylane -e "
    UPDATE sync_tracking
    SET last_sync_date = NOW(),
        last_sync_type = '$MODE',
        rows_count = $COMPANIES_COUNT,
        last_status = 'success'
    WHERE table_name = 'pl_companies';

    UPDATE sync_tracking
    SET last_sync_date = NOW(),
        last_sync_type = '$MODE',
        rows_count = $GL_COUNT,
        last_status = 'success'
    WHERE table_name = 'pl_general_ledger';

    UPDATE sync_tracking
    SET last_sync_date = NOW(),
        last_sync_type = '$MODE',
        rows_count = $FY_COUNT,
        last_status = 'success'
    WHERE table_name = 'pl_fiscal_years';

    UPDATE sync_tracking
    SET last_sync_date = NOW(),
        last_sync_type = '$MODE',
        rows_count = $COMPANIES_ID_COUNT,
        last_status = 'success'
    WHERE table_name = 'acc_companies_identification';
"

log_section "IMPORT RAW_PENNYLANE TERMINÉ"
log "SUCCESS" "Mode: $MODE | Companies: $COMPANIES_COUNT | Fiscal Years: $FY_COUNT | GL: $GL_COUNT"
