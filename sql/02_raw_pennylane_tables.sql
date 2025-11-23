-- ============================================================
-- COUCHE RAW : TABLES PENNYLANE
-- Import depuis Redshift (4 schémas : pennylane, accounting, etl, practice_management)
-- Préfixes : pl_*, acc_*, etl_*, pm_*
-- ============================================================

USE raw_pennylane;

-- ═══════════════════════════════════════════════════════════
-- SCHEMA PENNYLANE (données partagées)
-- ═══════════════════════════════════════════════════════════

-- Companies - Référentiel des sociétés
DROP TABLE IF EXISTS pl_companies;
CREATE TABLE pl_companies (
    id INT AUTO_INCREMENT PRIMARY KEY,
    company_id BIGINT UNIQUE NOT NULL,
    name VARCHAR(255),
    firm_name VARCHAR(255),
    trade_name VARCHAR(255),
    registration_number VARCHAR(32) COMMENT 'SIRET - LEFT(,9) = SIREN',
    vat_number VARCHAR(32),
    country_alpha2 VARCHAR(2),
    city VARCHAR(255),
    postal_code VARCHAR(20),
    saas_plan VARCHAR(50),
    vat_frequency VARCHAR(20),
    vat_day_of_month INT,
    fiscal_category VARCHAR(50),
    fiscal_regime VARCHAR(50),
    registration_date DATE,
    activity_code VARCHAR(20),
    activity_sector VARCHAR(255),
    legal_form_code VARCHAR(20),
    legal_form VARCHAR(255),
    created_at DATETIME,
    updated_at DATETIME,
    synchro_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_company_id (company_id),
    INDEX idx_registration_number (registration_number),
    INDEX idx_updated_at (updated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Fiscal Years - Exercices comptables
DROP TABLE IF EXISTS pl_fiscal_years;
CREATE TABLE pl_fiscal_years (
    id INT AUTO_INCREMENT PRIMARY KEY,
    company_id BIGINT NOT NULL,
    company_name VARCHAR(255),
    start_year INT,
    start_date DATE,
    end_date DATE,
    closed_at DATE,
    synchro_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_company_id (company_id),
    INDEX idx_dates (start_date, end_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- General Ledger - Grand livre (écritures détaillées)
DROP TABLE IF EXISTS pl_general_ledger;
CREATE TABLE pl_general_ledger (
    id INT AUTO_INCREMENT PRIMARY KEY,
    gl_line_id BIGINT UNIQUE NOT NULL,
    company_id BIGINT NOT NULL,
    company_name VARCHAR(255),
    txn_date DATE NOT NULL,
    compte VARCHAR(255) NOT NULL,
    compte_label VARCHAR(1024),
    journal_code VARCHAR(64) DEFAULT '',
    journal_label VARCHAR(255),
    debit DECIMAL(18,2) DEFAULT 0,
    credit DECIMAL(18,2) DEFAULT 0,
    document_updated_at DATETIME,
    synchro_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_gl_line_id (gl_line_id),
    INDEX idx_company_date (company_id, txn_date),
    INDEX idx_compte (compte),
    INDEX idx_journal (journal_code),
    INDEX idx_updated_at (document_updated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Customer Invoices - Factures clients
DROP TABLE IF EXISTS pl_customer_invoices;
CREATE TABLE pl_customer_invoices (
    id INT AUTO_INCREMENT PRIMARY KEY,
    invoice_id BIGINT UNIQUE,
    company_id BIGINT NOT NULL,
    company_name VARCHAR(255),
    customer_id BIGINT,
    customer_name VARCHAR(255),
    invoice_number VARCHAR(100),
    invoice_date DATE,
    due_date DATE,
    currency VARCHAR(10),
    amount DECIMAL(18,2),
    amount_before_tax DECIMAL(18,2),
    tax_amount DECIMAL(18,2),
    paid_amount DECIMAL(18,2),
    remaining_amount DECIMAL(18,2),
    status VARCHAR(50),
    payment_status VARCHAR(50),
    created_at DATETIME,
    updated_at DATETIME,
    synchro_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_company_id (company_id),
    INDEX idx_customer_id (customer_id),
    INDEX idx_invoice_date (invoice_date),
    INDEX idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Supplier Invoices - Factures fournisseurs
DROP TABLE IF EXISTS pl_supplier_invoices;
CREATE TABLE pl_supplier_invoices (
    id INT AUTO_INCREMENT PRIMARY KEY,
    invoice_id BIGINT UNIQUE,
    company_id BIGINT NOT NULL,
    company_name VARCHAR(255),
    supplier_id BIGINT,
    supplier_name VARCHAR(255),
    invoice_number VARCHAR(100),
    invoice_date DATE,
    due_date DATE,
    currency VARCHAR(10),
    amount DECIMAL(18,2),
    amount_before_tax DECIMAL(18,2),
    tax_amount DECIMAL(18,2),
    paid_amount DECIMAL(18,2),
    remaining_amount DECIMAL(18,2),
    status VARCHAR(50),
    payment_status VARCHAR(50),
    created_at DATETIME,
    updated_at DATETIME,
    synchro_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_company_id (company_id),
    INDEX idx_supplier_id (supplier_id),
    INDEX idx_invoice_date (invoice_date),
    INDEX idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Customers - Clients des sociétés
DROP TABLE IF EXISTS pl_customers;
CREATE TABLE pl_customers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    customer_id BIGINT UNIQUE,
    company_id BIGINT NOT NULL,
    name VARCHAR(255),
    email VARCHAR(255),
    phone VARCHAR(50),
    registration_number VARCHAR(32),
    vat_number VARCHAR(32),
    address VARCHAR(500),
    city VARCHAR(255),
    postal_code VARCHAR(20),
    country VARCHAR(100),
    created_at DATETIME,
    updated_at DATETIME,
    synchro_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_company_id (company_id),
    INDEX idx_customer_id (customer_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Suppliers - Fournisseurs des sociétés
DROP TABLE IF EXISTS pl_suppliers;
CREATE TABLE pl_suppliers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    supplier_id BIGINT UNIQUE,
    company_id BIGINT NOT NULL,
    name VARCHAR(255),
    email VARCHAR(255),
    phone VARCHAR(50),
    registration_number VARCHAR(32),
    vat_number VARCHAR(32),
    address VARCHAR(500),
    city VARCHAR(255),
    postal_code VARCHAR(20),
    country VARCHAR(100),
    created_at DATETIME,
    updated_at DATETIME,
    synchro_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_company_id (company_id),
    INDEX idx_supplier_id (supplier_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Bank Accounts - Comptes bancaires
DROP TABLE IF EXISTS pl_bank_accounts;
CREATE TABLE pl_bank_accounts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    bank_account_id BIGINT UNIQUE,
    company_id BIGINT NOT NULL,
    name VARCHAR(255),
    iban VARCHAR(50),
    bic VARCHAR(20),
    balance DECIMAL(18,2),
    currency VARCHAR(10),
    bank_name VARCHAR(255),
    is_connected BOOLEAN,
    last_sync_at DATETIME,
    created_at DATETIME,
    updated_at DATETIME,
    synchro_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_company_id (company_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Bank Transactions - Transactions bancaires
DROP TABLE IF EXISTS pl_bank_transactions;
CREATE TABLE pl_bank_transactions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    transaction_id BIGINT UNIQUE,
    bank_account_id BIGINT,
    company_id BIGINT NOT NULL,
    execution_date DATE,
    value_date DATE,
    amount DECIMAL(18,2),
    currency VARCHAR(10),
    label VARCHAR(500),
    category VARCHAR(100),
    status VARCHAR(50),
    created_at DATETIME,
    updated_at DATETIME,
    synchro_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_company_id (company_id),
    INDEX idx_bank_account_id (bank_account_id),
    INDEX idx_execution_date (execution_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ═══════════════════════════════════════════════════════════
-- SCHEMA ACCOUNTING (données cabinet uniquement)
-- ═══════════════════════════════════════════════════════════

-- Companies Identification - Infos complémentaires (external_id, emails)
DROP TABLE IF EXISTS acc_companies_identification;
CREATE TABLE acc_companies_identification (
    id INT AUTO_INCREMENT PRIMARY KEY,
    company_id BIGINT UNIQUE NOT NULL,
    external_id VARCHAR(255) COMMENT 'Potentiellement = Code_DIA',
    file_type VARCHAR(50),
    accountant_email VARCHAR(100),
    accounting_supervisor_email VARCHAR(100),
    accounting_manager_email VARCHAR(100),
    company_updated_at DATETIME,
    synchro_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_company_id (company_id),
    INDEX idx_external_id (external_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- General Ledger Revision - Grand livre pour révision
DROP TABLE IF EXISTS acc_general_ledger_revision;
CREATE TABLE acc_general_ledger_revision (
    id INT AUTO_INCREMENT PRIMARY KEY,
    gl_line_id BIGINT UNIQUE NOT NULL,
    company_id BIGINT NOT NULL,
    company_name VARCHAR(255),
    txn_date DATE NOT NULL,
    compte VARCHAR(255) NOT NULL,
    compte_label VARCHAR(1024),
    journal_code VARCHAR(64) DEFAULT '',
    journal_label VARCHAR(255),
    debit DECIMAL(18,2) DEFAULT 0,
    credit DECIMAL(18,2) DEFAULT 0,
    document_updated_at DATETIME,
    synchro_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_company_date (company_id, txn_date),
    INDEX idx_compte (compte)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Timesheet Entries - Saisies de temps
DROP TABLE IF EXISTS acc_timesheet_entries;
CREATE TABLE acc_timesheet_entries (
    id INT AUTO_INCREMENT PRIMARY KEY,
    entry_id BIGINT UNIQUE,
    company_id BIGINT NOT NULL,
    company_name VARCHAR(255),
    user_email VARCHAR(255),
    user_name VARCHAR(255),
    entry_date DATE,
    duration_minutes INT,
    task_type VARCHAR(100),
    task_description VARCHAR(500),
    created_at DATETIME,
    updated_at DATETIME,
    synchro_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_company_id (company_id),
    INDEX idx_entry_date (entry_date),
    INDEX idx_user_email (user_email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Trial Balance Revision - Balance générale
DROP TABLE IF EXISTS acc_trial_balance_revision;
CREATE TABLE acc_trial_balance_revision (
    id INT AUTO_INCREMENT PRIMARY KEY,
    company_id BIGINT NOT NULL,
    company_name VARCHAR(255),
    fiscal_year_id BIGINT,
    compte VARCHAR(255) NOT NULL,
    compte_label VARCHAR(1024),
    opening_debit DECIMAL(18,2) DEFAULT 0,
    opening_credit DECIMAL(18,2) DEFAULT 0,
    period_debit DECIMAL(18,2) DEFAULT 0,
    period_credit DECIMAL(18,2) DEFAULT 0,
    closing_debit DECIMAL(18,2) DEFAULT 0,
    closing_credit DECIMAL(18,2) DEFAULT 0,
    synchro_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_company_id (company_id),
    INDEX idx_compte (compte)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ═══════════════════════════════════════════════════════════
-- SCHEMA ETL (pour synchro incrémentale - Phase 2)
-- Mêmes tables que pennylane avec deleted_at et synchronised_at
-- ═══════════════════════════════════════════════════════════

-- ETL Companies
DROP TABLE IF EXISTS etl_companies;
CREATE TABLE etl_companies LIKE pl_companies;
ALTER TABLE etl_companies 
    ADD COLUMN deleted_at DATETIME NULL,
    ADD COLUMN synchronised_at DATETIME NULL,
    ADD INDEX idx_deleted_at (deleted_at),
    ADD INDEX idx_synchronised_at (synchronised_at);

-- ETL General Ledger
DROP TABLE IF EXISTS etl_general_ledger;
CREATE TABLE etl_general_ledger LIKE pl_general_ledger;
ALTER TABLE etl_general_ledger 
    ADD COLUMN deleted_at DATETIME NULL,
    ADD COLUMN synchronised_at DATETIME NULL,
    ADD INDEX idx_deleted_at (deleted_at),
    ADD INDEX idx_synchronised_at (synchronised_at);

-- ETL Customer Invoices
DROP TABLE IF EXISTS etl_customer_invoices;
CREATE TABLE etl_customer_invoices LIKE pl_customer_invoices;
ALTER TABLE etl_customer_invoices 
    ADD COLUMN deleted_at DATETIME NULL,
    ADD COLUMN synchronised_at DATETIME NULL,
    ADD INDEX idx_deleted_at (deleted_at),
    ADD INDEX idx_synchronised_at (synchronised_at);

-- ETL Supplier Invoices
DROP TABLE IF EXISTS etl_supplier_invoices;
CREATE TABLE etl_supplier_invoices LIKE pl_supplier_invoices;
ALTER TABLE etl_supplier_invoices 
    ADD COLUMN deleted_at DATETIME NULL,
    ADD COLUMN synchronised_at DATETIME NULL,
    ADD INDEX idx_deleted_at (deleted_at),
    ADD INDEX idx_synchronised_at (synchronised_at);

-- ═══════════════════════════════════════════════════════════
-- SCHEMA PRACTICE_MANAGEMENT (gestion interne cabinet)
-- ═══════════════════════════════════════════════════════════

-- Mission Invoice Lines - Lignes de facturation missions
DROP TABLE IF EXISTS pm_mission_invoice_lines;
CREATE TABLE pm_mission_invoice_lines (
    id INT AUTO_INCREMENT PRIMARY KEY,
    line_id BIGINT UNIQUE,
    company_id BIGINT NOT NULL,
    company_name VARCHAR(255),
    mission_id BIGINT,
    invoice_id BIGINT,
    description VARCHAR(500),
    quantity DECIMAL(10,2),
    unit_price DECIMAL(18,2),
    amount DECIMAL(18,2),
    created_at DATETIME,
    updated_at DATETIME,
    synchro_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_company_id (company_id),
    INDEX idx_mission_id (mission_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Timesheet Entries (gestion interne)
DROP TABLE IF EXISTS pm_timesheet_entries;
CREATE TABLE pm_timesheet_entries LIKE acc_timesheet_entries;

-- ═══════════════════════════════════════════════════════════
-- TABLE DE TRACKING (pour imports incrémentaux)
-- ═══════════════════════════════════════════════════════════

DROP TABLE IF EXISTS sync_tracking;
CREATE TABLE sync_tracking (
    table_name VARCHAR(50) PRIMARY KEY,
    last_sync_date DATETIME DEFAULT NULL COMMENT 'Dernière synchro réussie',
    last_sync_type ENUM('full', 'incremental', 'since') DEFAULT 'full',
    rows_count BIGINT DEFAULT 0 COMMENT 'Nombre de lignes après sync',
    last_status VARCHAR(20) DEFAULT 'pending' COMMENT 'success/failed',
    last_duration_sec INT DEFAULT NULL COMMENT 'Durée du dernier import (sec)',
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Initialisation du tracking
INSERT INTO sync_tracking (table_name, last_sync_type, last_status) VALUES
    ('pl_companies', 'full', 'pending'),
    ('acc_companies_identification', 'full', 'pending'),
    ('pl_fiscal_years', 'full', 'pending'),
    ('pl_general_ledger', 'full', 'pending')
ON DUPLICATE KEY UPDATE table_name=table_name;

SELECT '✅ Tables RAW Pennylane créées avec succès !' AS status;
