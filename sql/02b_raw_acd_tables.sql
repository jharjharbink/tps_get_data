-- ============================================================
-- TABLES RAW_ACD - Données comptables ACD centralisées
-- Importe 6 tables depuis les bases compta_* vers raw_acd
-- Partitionnement par année pour performances
-- ============================================================

USE raw_acd;

-- ─── TABLE 1: histo_ligne_ecriture ─────────────────────────
CREATE TABLE IF NOT EXISTS histo_ligne_ecriture (
    dossier_code VARCHAR(20) NOT NULL COMMENT 'Code dossier extrait (ex: 00123 de compta_00123)',
    CPT_CODE VARCHAR(32) DEFAULT NULL COMMENT 'Code compte',
    HLE_CRE_ORG DECIMAL(18,2) DEFAULT NULL COMMENT 'Crédit original',
    HLE_DEB_ORG DECIMAL(18,2) DEFAULT NULL COMMENT 'Débit original',
    HE_CODE BIGINT NOT NULL COMMENT 'ID écriture',
    HLE_CODE BIGINT NOT NULL COMMENT 'ID ligne écriture',
    HLE_LIB VARCHAR(255) DEFAULT NULL COMMENT 'Libellé ligne',
    HLE_JOUR SMALLINT COMMENT 'Jour de saisie de l ecriture',
    HLE_PIECE VARCHAR(16) COMMENT 'Chemin dans la GED ?',
    HLE_LET VARCHAR(5) COMMENT 'Lettrage', 
    HLE_LETP1 SMALLINT COMMENT 'Lettrage P1 ?', 
    HLE_DATE_LET VARCHAR(20) COMMENT 'Date Lettrage',
    PRIMARY KEY (dossier_code, HLE_CODE)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- ─── TABLE 2: histo_ecriture ───────────────────────────────
CREATE TABLE IF NOT EXISTS histo_ecriture (
    dossier_code VARCHAR(20) NOT NULL,
    HE_CODE BIGINT NOT NULL COMMENT 'ID écriture',
    HE_DATE_SAI VARCHAR(20) COMMENT 'Date de Saisie',
    HE_ANNEE SMALLINT NOT NULL,
    HE_MOIS TINYINT DEFAULT NULL,
    JNL_CODE VARCHAR(32) DEFAULT NULL,
    PRIMARY KEY (dossier_code, HE_CODE)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- ─── TABLE 3: ligne_ecriture (courant) ────────────────────
CREATE TABLE IF NOT EXISTS ligne_ecriture (
    dossier_code VARCHAR(20) NOT NULL COMMENT 'Code dossier extrait (ex: 00123 de compta_00123)',
    CPT_CODE VARCHAR(32) DEFAULT NULL COMMENT 'Code compte',
    LE_CRE_ORG DECIMAL(18,2) DEFAULT NULL COMMENT 'Crédit original',
    LE_DEB_ORG DECIMAL(18,2) DEFAULT NULL COMMENT 'Débit original',
    ECR_CODE BIGINT NOT NULL COMMENT 'ID écriture',
    LE_CODE BIGINT NOT NULL COMMENT 'ID ligne écriture',
    LE_LIB VARCHAR(255) DEFAULT NULL COMMENT 'Libellé ligne',
    LE_JOUR SMALLINT COMMENT 'Jour de saisie de l ecriture',
    LE_PIECE VARCHAR(16) COMMENT 'Chemin dans la GED ?',
    LE_LET VARCHAR(5) COMMENT 'Lettrage', 
    LE_LETP1 SMALLINT COMMENT 'Lettrage P1 ?', 
    LE_DATE_LET VARCHAR(20) COMMENT 'Date Lettrage',
    PRIMARY KEY (dossier_code, LE_CODE)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- ─── TABLE 4: ecriture (courant) ──────────────────────────
CREATE TABLE IF NOT EXISTS ecriture (
    dossier_code VARCHAR(20) NOT NULL,
    ECR_CODE BIGINT NOT NULL COMMENT 'ID écriture',
    ECR_DATE_SAI VARCHAR(20) COMMENT 'Date de Saisie',
    ECR_ANNEE SMALLINT NOT NULL,
    ECR_MOIS TINYINT DEFAULT NULL,
    JNL_CODE VARCHAR(32) DEFAULT NULL,
    PRIMARY KEY (dossier_code, ECR_CODE)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- ─── TABLE 5: compte ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS compte (
    dossier_code VARCHAR(20) NOT NULL,
    CPT_CODE VARCHAR(32) NOT NULL,
    CPT_LIB VARCHAR(255) DEFAULT NULL,
    PRIMARY KEY (dossier_code, CPT_CODE)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- ─── TABLE 6: journal ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS journal (
    dossier_code VARCHAR(20) NOT NULL,
    JNL_CODE VARCHAR(4) NOT NULL,
    JNL_LIB VARCHAR(30) DEFAULT NULL,
    JNL_TYPE VARCHAR(1) DEFAULT NULL COMMENT 'Type journal (vente, achat, etc.)',
    PRIMARY KEY (dossier_code, JNL_CODE)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- ─── TABLE DE TRACKING (incrémental) ──────────────────────
CREATE TABLE IF NOT EXISTS sync_tracking (
    table_name VARCHAR(50) PRIMARY KEY,
    last_sync_date DATETIME DEFAULT NULL COMMENT 'Dernière synchro réussie',
    last_sync_type ENUM('full', 'incremental') DEFAULT 'full',
    rows_count BIGINT DEFAULT 0 COMMENT 'Nombre de lignes après sync',
    last_status VARCHAR(20) DEFAULT 'pending' COMMENT 'success/failed',
    last_duration_sec INT DEFAULT NULL COMMENT 'Durée du dernier import (sec)',
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- Initialisation du tracking
INSERT INTO sync_tracking (table_name, last_sync_type, last_status) VALUES
    ('histo_ligne_ecriture', 'full', 'pending'),
    ('histo_ecriture', 'full', 'pending'),
    ('ligne_ecriture', 'full', 'pending'),
    ('ecriture', 'full', 'pending'),
    ('compte', 'full', 'pending'),
    ('journal', 'full', 'pending')
ON DUPLICATE KEY UPDATE table_name=table_name;

-- ─── TABLE DE TRACKING PAR DOSSIER (reprise après crash) ──
CREATE TABLE IF NOT EXISTS sync_tracking_by_dossier (
    table_name VARCHAR(50) NOT NULL,
    dossier_code VARCHAR(20) NOT NULL,
    last_sync_date DATETIME NOT NULL COMMENT 'Dernière synchro réussie pour ce dossier',
    last_sync_type ENUM('full', 'incremental', 'since') DEFAULT 'incremental',
    last_status VARCHAR(20) DEFAULT 'success' COMMENT 'success/failed',
    rows_imported INT DEFAULT 0 COMMENT 'Nombre de lignes importées pour ce dossier',
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (table_name, dossier_code),
    INDEX idx_sync_date (last_sync_date),
    INDEX idx_dossier (dossier_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
COMMENT='Tracking granulaire par dossier pour reprise après crash';


-- ============================================================
-- INDEXES OPTIMISÉS POUR PERFORMANCES TRANSFORM
-- Basés sur l'analyse des procédures load_ecritures_acd et load_ecritures_tiers_acd
-- ============================================================

-- ─── INDEXES TABLE compte ──────────────────────────────────
-- Utilisé pour : LEFT JOIN compte c ON c.CPT_CODE = hle.CPT_CODE
CREATE INDEX IF NOT EXISTS idx_dossier ON compte(dossier_code);
CREATE INDEX IF NOT EXISTS idx_dossier_compte ON compte(dossier_code, CPT_CODE);

-- ─── INDEXES TABLE ecriture ────────────────────────────────
-- Utilisé pour : WHERE e.ECR_ANNEE >= YEAR(CURDATE()) - 3
--                GROUP BY prev.journal_code
--                Import incrémental: WHERE ECR_DATE_SAI > last_sync_date
CREATE INDEX IF NOT EXISTS idx_dossier_annee_mois ON ecriture(dossier_code, ECR_ANNEE, ECR_MOIS);
CREATE INDEX IF NOT EXISTS idx_dossier_journal ON ecriture(dossier_code, JNL_CODE);
CREATE INDEX IF NOT EXISTS idx_date_sai ON ecriture(ECR_DATE_SAI);

-- ─── INDEXES TABLE histo_ecriture ──────────────────────────
-- Utilisé pour : WHERE he.HE_ANNEE >= YEAR(CURDATE()) - 3
--                GROUP BY prev.journal_code
CREATE INDEX IF NOT EXISTS idx_dossier_annee_mois ON histo_ecriture(dossier_code, HE_ANNEE, HE_MOIS);
CREATE INDEX IF NOT EXISTS idx_dossier_journal ON histo_ecriture(dossier_code, JNL_CODE);

-- ─── INDEXES TABLE journal ─────────────────────────────────
-- Utilisé pour : LEFT JOIN journal j ON j.JNL_CODE = he.JNL_CODE
CREATE INDEX IF NOT EXISTS idx_dossier ON journal(dossier_code);
CREATE INDEX IF NOT EXISTS idx_dossier_code ON journal(dossier_code, JNL_CODE);

-- ─── INDEXES TABLE ligne_ecriture ──────────────────────────
-- Utilisé pour : WHERE (le.CPT_CODE LIKE 'C%' OR le.CPT_CODE LIKE 'F%')
--                JOIN ecriture e ON e.ECR_CODE = le.ECR_CODE
CREATE INDEX IF NOT EXISTS idx_dossier_compte ON ligne_ecriture(dossier_code, CPT_CODE);
CREATE INDEX IF NOT EXISTS idx_dossier_ecriture ON ligne_ecriture(dossier_code, ECR_CODE);
CREATE INDEX IF NOT EXISTS idx_compte ON ligne_ecriture(CPT_CODE);

-- ─── INDEXES TABLE histo_ligne_ecriture ────────────────────
-- Utilisé pour : WHERE (hle.CPT_CODE LIKE 'C%' OR hle.CPT_CODE LIKE 'F%')
--                JOIN histo_ecriture he ON he.HE_CODE = hle.HE_CODE
CREATE INDEX IF NOT EXISTS idx_dossier_compte ON histo_ligne_ecriture(dossier_code, CPT_CODE);
CREATE INDEX IF NOT EXISTS idx_dossier_ecriture ON histo_ligne_ecriture(dossier_code, HE_CODE);
CREATE INDEX IF NOT EXISTS idx_compte ON histo_ligne_ecriture(CPT_CODE);
-- FROM ligne_ecriture;

-- ─── VÉRIFICATION ─────────────────────────────────────────
SELECT 'Tables raw_acd créées avec succès !' AS status;
SHOW TABLES FROM raw_acd;
