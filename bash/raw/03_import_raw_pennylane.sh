#!/bin/bash
# ============================================================
# IMPORT RAW PENNYLANE (depuis Redshift)
# Export CSV depuis Redshift puis chargement dans raw_pennylane
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/logging.sh"

log_section "IMPORT RAW_PENNYLANE (Redshift)"

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

# ─── Export General Ledger ──────────────────────────────────
log_subsection "Export pl_general_ledger"
log "INFO" "Export General Ledger depuis Redshift (peut être long)..."

psql --csv -v ON_ERROR_STOP=1 --pset null='NULL' \
    -h "$REDSHIFT_HOST" -p "$REDSHIFT_PORT" -U "$REDSHIFT_USER" -d "$REDSHIFT_DB" \
    > "$TMP_GL" <<EOF
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
ORDER BY glv.company_id, glv.plan_item_number, glv."date";
EOF

if [ $? -ne 0 ]; then
    log "ERROR" "Échec export General Ledger"
    exit 1
fi
log "SUCCESS" "Export General Ledger OK"

# ─── Chargement dans MySQL ──────────────────────────────────
log_section "CHARGEMENT DANS MYSQL"

# Vider et charger pl_companies
log "INFO" "Chargement pl_companies..."
$MYSQL $MYSQL_OPTS -e "TRUNCATE TABLE raw_pennylane.pl_companies;"
$MYSQL $MYSQL_OPTS --local-infile=1 -e "
LOAD DATA LOCAL INFILE '$TMP_COMPANIES'
INTO TABLE raw_pennylane.pl_companies
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

# Chargement GL direct avec désactivation des index (plus rapide pour gros volumes)
log "INFO" "Chargement pl_general_ledger (LOAD DATA direct avec index désactivés)..."

TOTAL_LINES=$(tail -n +2 "$TMP_GL" | wc -l)
log "INFO" "$TOTAL_LINES lignes à charger"

# Désactiver les index, vider la table, charger, réactiver les index
$MYSQL $MYSQL_OPTS -e "
SET FOREIGN_KEY_CHECKS = 0;
SET UNIQUE_CHECKS = 0;
ALTER TABLE raw_pennylane.pl_general_ledger DISABLE KEYS;
TRUNCATE TABLE raw_pennylane.pl_general_ledger;
"

$MYSQL $MYSQL_OPTS --local-infile=1 -e "
LOAD DATA LOCAL INFILE '$TMP_GL'
INTO TABLE raw_pennylane.pl_general_ledger
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\"'
IGNORE 1 LINES
(gl_line_id, company_id, company_name, txn_date, compte, compte_label,
 journal_code, journal_label, debit, credit, document_updated_at);
"

log "INFO" "Reconstruction des index..."
$MYSQL $MYSQL_OPTS -e "
ALTER TABLE raw_pennylane.pl_general_ledger ENABLE KEYS;
SET UNIQUE_CHECKS = 1;
SET FOREIGN_KEY_CHECKS = 1;
"

GL_COUNT=$($MYSQL $MYSQL_OPTS -N -e "SELECT COUNT(*) FROM raw_pennylane.pl_general_ledger")
log "SUCCESS" "pl_general_ledger: $GL_COUNT lignes"

# Nettoyage
log "INFO" "Nettoyage fichiers temporaires..."
rm -f "$TMP_COMPANIES" "$TMP_COMPANIES_ID" "$TMP_FISCAL_YEARS" "$TMP_GL" /tmp/gl_batch_*.csv

log_section "IMPORT RAW_PENNYLANE TERMINÉ"
log "SUCCESS" "Companies: $COMPANIES_COUNT | Fiscal Years: $FY_COUNT | GL: $GL_COUNT"
