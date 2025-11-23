-- ============================================================
-- TABLES RAW_ACD - Données comptables ACD centralisées
-- Importe 6 tables depuis les bases compta_* vers raw_acd
-- Partitionnement par année pour performances
-- ============================================================

USE raw_acd;

-- ─── TABLE 1: histo_ligne_ecriture ─────────────────────────
DROP TABLE IF EXISTS histo_ligne_ecriture;
CREATE TABLE histo_ligne_ecriture (
    dossier_code VARCHAR(20) NOT NULL COMMENT 'Code dossier extrait (ex: 00123 de compta_00123)',
    HLE_CODE BIGINT NOT NULL COMMENT 'ID ligne écriture',
    HE_CODE BIGINT NOT NULL COMMENT 'ID écriture',
    CPT_CODE VARCHAR(32) DEFAULT NULL COMMENT 'Code compte',
    HLE_CRE_ORG DECIMAL(18,2) DEFAULT NULL COMMENT 'Crédit original',
    HLE_DEB_ORG DECIMAL(18,2) DEFAULT NULL COMMENT 'Débit original',
    HLE_LIBELLE VARCHAR(255) DEFAULT NULL COMMENT 'Libellé ligne',
    HE_DATE_SAI DATE DEFAULT NULL COMMENT 'Date saisie (pour incrémental)',
    HE_ANNEE SMALLINT NOT NULL COMMENT 'Année (pour partitionnement)',
    HE_MOIS TINYINT DEFAULT NULL COMMENT 'Mois',
    JNL_CODE VARCHAR(32) DEFAULT NULL COMMENT 'Code journal',
    PRIMARY KEY (dossier_code, HLE_CODE, HE_ANNEE),
    KEY idx_date_sai (HE_DATE_SAI),
    KEY idx_compte (CPT_CODE),
    KEY idx_journal (JNL_CODE)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
PARTITION BY RANGE (HE_ANNEE) (
    PARTITION p2020 VALUES LESS THAN (2021),
    PARTITION p2021 VALUES LESS THAN (2022),
    PARTITION p2022 VALUES LESS THAN (2023),
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

-- ─── TABLE 2: histo_ecriture ───────────────────────────────
DROP TABLE IF EXISTS histo_ecriture;
CREATE TABLE histo_ecriture (
    dossier_code VARCHAR(20) NOT NULL,
    HE_CODE BIGINT NOT NULL COMMENT 'ID écriture',
    HE_LIBELLE VARCHAR(255) DEFAULT NULL COMMENT 'Libellé écriture',
    HE_DATE_SAI DATE DEFAULT NULL COMMENT 'Date saisie',
    HE_DATE_ECR DATE DEFAULT NULL COMMENT 'Date écriture',
    HE_ANNEE SMALLINT NOT NULL,
    HE_MOIS TINYINT DEFAULT NULL,
    JNL_CODE VARCHAR(32) DEFAULT NULL,
    HE_VALID TINYINT(1) DEFAULT NULL COMMENT 'Validée (0/1)',
    PRIMARY KEY (dossier_code, HE_CODE, HE_ANNEE),
    KEY idx_date_sai (HE_DATE_SAI),
    KEY idx_date_ecr (HE_DATE_ECR)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
PARTITION BY RANGE (HE_ANNEE) (
    PARTITION p2020 VALUES LESS THAN (2021),
    PARTITION p2021 VALUES LESS THAN (2022),
    PARTITION p2022 VALUES LESS THAN (2023),
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

-- ─── TABLE 3: ligne_ecriture (courant) ────────────────────
DROP TABLE IF EXISTS ligne_ecriture;
CREATE TABLE ligne_ecriture (
    dossier_code VARCHAR(20) NOT NULL,
    LE_CODE BIGINT NOT NULL COMMENT 'ID ligne écriture',
    ECR_CODE BIGINT NOT NULL COMMENT 'ID écriture',
    CPT_CODE VARCHAR(32) DEFAULT NULL,
    LE_CRE_ORG DECIMAL(18,2) DEFAULT NULL,
    LE_DEB_ORG DECIMAL(18,2) DEFAULT NULL,
    LE_LIBELLE VARCHAR(255) DEFAULT NULL,
    ECR_DATE_SAI DATE DEFAULT NULL,
    ECR_ANNEE SMALLINT NOT NULL,
    ECR_MOIS TINYINT DEFAULT NULL,
    JNL_CODE VARCHAR(32) DEFAULT NULL,
    PRIMARY KEY (dossier_code, LE_CODE, ECR_ANNEE),
    KEY idx_date_sai (ECR_DATE_SAI),
    KEY idx_compte (CPT_CODE),
    KEY idx_journal (JNL_CODE)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
PARTITION BY RANGE (ECR_ANNEE) (
    PARTITION p2020 VALUES LESS THAN (2021),
    PARTITION p2021 VALUES LESS THAN (2022),
    PARTITION p2022 VALUES LESS THAN (2023),
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

-- ─── TABLE 4: ecriture (courant) ──────────────────────────
DROP TABLE IF EXISTS ecriture;
CREATE TABLE ecriture (
    dossier_code VARCHAR(20) NOT NULL,
    ECR_CODE BIGINT NOT NULL,
    ECR_LIBELLE VARCHAR(255) DEFAULT NULL,
    ECR_DATE_SAI DATE DEFAULT NULL,
    ECR_DATE_ECR DATE DEFAULT NULL,
    ECR_ANNEE SMALLINT NOT NULL,
    ECR_MOIS TINYINT DEFAULT NULL,
    JNL_CODE VARCHAR(32) DEFAULT NULL,
    ECR_VALID TINYINT(1) DEFAULT NULL,
    PRIMARY KEY (dossier_code, ECR_CODE, ECR_ANNEE),
    KEY idx_date_sai (ECR_DATE_SAI),
    KEY idx_date_ecr (ECR_DATE_ECR)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
PARTITION BY RANGE (ECR_ANNEE) (
    PARTITION p2020 VALUES LESS THAN (2021),
    PARTITION p2021 VALUES LESS THAN (2022),
    PARTITION p2022 VALUES LESS THAN (2023),
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

-- ─── TABLE 5: compte ───────────────────────────────────────
DROP TABLE IF EXISTS compte;
CREATE TABLE compte (
    dossier_code VARCHAR(20) NOT NULL,
    CPT_CODE VARCHAR(32) NOT NULL,
    CPT_LIBELLE VARCHAR(255) DEFAULT NULL,
    CPT_TYPE VARCHAR(20) DEFAULT NULL COMMENT 'Type compte (charge, produit, etc.)',
    PRIMARY KEY (dossier_code, CPT_CODE),
    KEY idx_type (CPT_TYPE)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── TABLE 6: journal ──────────────────────────────────────
DROP TABLE IF EXISTS journal;
CREATE TABLE journal (
    dossier_code VARCHAR(20) NOT NULL,
    JNL_CODE VARCHAR(32) NOT NULL,
    JNL_LIBELLE VARCHAR(255) DEFAULT NULL,
    JNL_TYPE VARCHAR(20) DEFAULT NULL COMMENT 'Type journal (vente, achat, etc.)',
    PRIMARY KEY (dossier_code, JNL_CODE),
    KEY idx_type (JNL_TYPE)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── TABLE DE TRACKING (incrémental) ──────────────────────
DROP TABLE IF EXISTS sync_tracking;
CREATE TABLE sync_tracking (
    table_name VARCHAR(50) PRIMARY KEY,
    last_sync_date DATETIME DEFAULT NULL COMMENT 'Dernière synchro réussie',
    last_sync_type ENUM('full', 'incremental') DEFAULT 'full',
    rows_count BIGINT DEFAULT 0 COMMENT 'Nombre de lignes après sync',
    last_status VARCHAR(20) DEFAULT 'pending' COMMENT 'success/failed',
    last_duration_sec INT DEFAULT NULL COMMENT 'Durée du dernier import (sec)',
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Initialisation du tracking
INSERT INTO sync_tracking (table_name, last_sync_type, last_status) VALUES
    ('histo_ligne_ecriture', 'full', 'pending'),
    ('histo_ecriture', 'full', 'pending'),
    ('ligne_ecriture', 'full', 'pending'),
    ('ecriture', 'full', 'pending'),
    ('compte', 'full', 'pending'),
    ('journal', 'full', 'pending')
ON DUPLICATE KEY UPDATE table_name=table_name;

-- ─── VUE UNIFIÉE (histo + courant) ────────────────────────
DROP VIEW IF EXISTS v_ligne_ecriture_unified;
CREATE VIEW v_ligne_ecriture_unified AS
SELECT
    dossier_code,
    HLE_CODE as ligne_code,
    HE_CODE as ecriture_code,
    CPT_CODE,
    HLE_CRE_ORG as credit,
    HLE_DEB_ORG as debit,
    HLE_LIBELLE as libelle,
    HE_DATE_SAI as date_saisie,
    HE_ANNEE as annee,
    HE_MOIS as mois,
    JNL_CODE,
    'histo' as source_table
FROM histo_ligne_ecriture
UNION ALL
SELECT
    dossier_code,
    LE_CODE as ligne_code,
    ECR_CODE as ecriture_code,
    CPT_CODE,
    LE_CRE_ORG as credit,
    LE_DEB_ORG as debit,
    LE_LIBELLE as libelle,
    ECR_DATE_SAI as date_saisie,
    ECR_ANNEE as annee,
    ECR_MOIS as mois,
    JNL_CODE,
    'courant' as source_table
FROM ligne_ecriture;

-- ─── VÉRIFICATION ─────────────────────────────────────────
SELECT 'Tables raw_acd créées avec succès !' AS status;
SHOW TABLES FROM raw_acd;
