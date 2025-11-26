-- ============================================================
-- COUCHE TRANSFORM : DONNÉES NORMALISÉES ET AGRÉGÉES
-- Unifie les données ACD + Pennylane avec normalisation des comptes
-- ============================================================

USE transform_compta;

-- ─────────────────────────────────────────────────────────────
-- Table : dossiers_acd
-- Copie normalisée des adresses ACD (depuis raw_dia.adresse)
-- Adaptée de ta procédure creationCompanyACD
-- ─────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS dossiers_acd;
CREATE TABLE dossiers_acd (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    adr_id BIGINT NOT NULL,
    code_dia VARCHAR(50) NOT NULL,
    nom VARCHAR(255),
    siren VARCHAR(9) COMMENT 'LEFT(ADR_SIRET, 9)',
    siret VARCHAR(14),
    titre VARCHAR(255),
    forme_juridique VARCHAR(255),
    categorie_fiscale VARCHAR(255),
    regime_fiscal VARCHAR(255),
    ville VARCHAR(255),
    code_postal VARCHAR(10),
    code_naf VARCHAR(10),
    naf_description VARCHAR(255),
    email VARCHAR(255),
    telephone VARCHAR(32),
    directeur_comptable VARCHAR(255),
    chef_de_mission VARCHAR(255),
    collaborateur_comptable VARCHAR(255),
    entite_valoxy VARCHAR(40) COMMENT 'SOC_NOM (VALOXY Lille, VALOXY Flandres, etc.)',
    region VARCHAR(100),
    compte_compta_interne VARCHAR(64),
    date_entree VARCHAR(10),
    date_creation DATETIME,
    date_modification DATETIME,
    synchro_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_adr_id (adr_id),
    UNIQUE KEY uk_code_dia (code_dia),
    INDEX idx_siren (siren),
    INDEX idx_entite (entite_valoxy),
    INDEX idx_code_naf (code_naf)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─────────────────────────────────────────────────────────────
-- Table : dossiers_pennylane
-- Copie normalisée des companies Pennylane
-- ─────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS dossiers_pennylane;
CREATE TABLE dossiers_pennylane (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    company_id BIGINT NOT NULL,
    name VARCHAR(255) NOT NULL,
    siren VARCHAR(9) COMMENT 'LEFT(registration_number, 9)',
    external_id VARCHAR(255) COMMENT 'Potentiellement = Code_DIA',
    firm_name VARCHAR(255),
    trade_name VARCHAR(255),
    forme_juridique VARCHAR(255),
    categorie_fiscale VARCHAR(50),
    regime_fiscal VARCHAR(50),
    ville VARCHAR(255),
    code_postal VARCHAR(20),
    code_naf VARCHAR(20),
    secteur_activite VARCHAR(255),
    directeur_comptable VARCHAR(100),
    chef_de_mission VARCHAR(100),
    collaborateur_comptable VARCHAR(100),
    entite_valoxy VARCHAR(255) COMMENT 'firm_name',
    date_creation DATETIME,
    date_modification DATETIME,
    synchro_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_company_id (company_id),
    INDEX idx_siren (siren),
    INDEX idx_external_id (external_id),
    INDEX idx_entite (entite_valoxy)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─────────────────────────────────────────────────────────────
-- Table : ecritures_mensuelles
-- Agrégation mensuelle de TOUTES les écritures (ACD + Pennylane)
-- Avec comptes C/F agrégés (comme ta comptes_row_flux)
-- ─────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS ecritures_mensuelles;
CREATE TABLE ecritures_mensuelles (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    source ENUM('ACD', 'PENNYLANE') NOT NULL,
    code_dossier VARCHAR(64) NOT NULL COMMENT 'Code_DIA pour ACD, name pour Pennylane',
    siren VARCHAR(9) COMMENT 'Pour jointure MDM',
    period_month DATE NOT NULL COMMENT 'Premier jour du mois',
    compte VARCHAR(64) NOT NULL COMMENT 'Comptes C*/F* agrégés en Cxxxxx/Fxxxxx',
    compte_normalized VARCHAR(4) NOT NULL COMMENT '4 premiers chars (4110 pour C*, 4100 pour F* en ACD)',
    compte_libelle VARCHAR(255),
    journal_code VARCHAR(32) NOT NULL DEFAULT '',
    journal_libelle VARCHAR(255),
    debits DECIMAL(18,2) NOT NULL DEFAULT 0,
    credits DECIMAL(18,2) NOT NULL DEFAULT 0,
    solde DECIMAL(18,2) AS (debits - credits) STORED,
    nb_ecritures INT NOT NULL DEFAULT 0,
    date_derniere_saisie DATETIME,
    synchro_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_ecriture (source, code_dossier, period_month, compte, journal_code),
    INDEX idx_source (source),
    INDEX idx_dossier (code_dossier),
    INDEX idx_siren (siren),
    INDEX idx_period (period_month),
    INDEX idx_compte (compte),
    INDEX idx_compte_normalized (compte_normalized),
    INDEX idx_journal (journal_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─────────────────────────────────────────────────────────────
-- Table : ecritures_tiers_detaillees
-- Détail des comptes clients (411/C*) et fournisseurs (401/F*)
-- Avec normalisation : C* → 411, F* → 401
-- Comme ta comptes_row_flux_fournisseur_client mais normalisé
-- ─────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS ecritures_tiers_detaillees;
CREATE TABLE ecritures_tiers_detaillees (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    source ENUM('ACD', 'PENNYLANE') NOT NULL,
    code_dossier VARCHAR(64) NOT NULL,
    siren VARCHAR(9),
    period_month DATE NOT NULL,
    type_tiers ENUM('CLIENT', 'FOURNISSEUR') NOT NULL,
    compte_origine VARCHAR(64) NOT NULL COMMENT 'Compte original (C00123, F00456, 401000, 411000)',
    compte_normalise VARCHAR(20) NOT NULL COMMENT '401 ou 411',
    compte_libelle VARCHAR(255),
    journal_code VARCHAR(32) NOT NULL DEFAULT '',
    journal_libelle VARCHAR(255),
    debits DECIMAL(18,2) NOT NULL DEFAULT 0,
    credits DECIMAL(18,2) NOT NULL DEFAULT 0,
    solde DECIMAL(18,2) AS (debits - credits) STORED,
    nb_ecritures INT NOT NULL DEFAULT 0,
    date_derniere_saisie DATETIME,
    synchro_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_tiers (source, code_dossier, period_month, compte_origine, journal_code),
    INDEX idx_source (source),
    INDEX idx_dossier (code_dossier),
    INDEX idx_siren (siren),
    INDEX idx_period (period_month),
    INDEX idx_type_tiers (type_tiers),
    INDEX idx_compte_normalise (compte_normalise),
    INDEX idx_compte_origine (compte_origine)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─────────────────────────────────────────────────────────────
-- Table : exercices
-- Consolidation des exercices ACD + Pennylane
-- Adaptée de ta procédure creationExerciceACD
-- ─────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS exercices;
CREATE TABLE exercices (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    source ENUM('ACD', 'PENNYLANE') NOT NULL,
    exo_id BIGINT COMMENT 'ID origine',
    code_dossier VARCHAR(64) NOT NULL,
    siren VARCHAR(9),
    exercice_code VARCHAR(32),
    date_debut DATE,
    date_fin DATE,
    date_cloture DATE,
    synchro_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_exercice (source, code_dossier, date_debut),
    INDEX idx_source (source),
    INDEX idx_dossier (code_dossier),
    INDEX idx_siren (siren),
    INDEX idx_dates (date_debut, date_fin)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─────────────────────────────────────────────────────────────
-- Table : temps_collaborateurs
-- Temps passés par collaborateur et dossier
-- Adaptée de ta procédure temps_collab
-- ─────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS temps_collaborateurs;
CREATE TABLE temps_collaborateurs (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    temps_id INT COMMENT 'ID origine DIA',
    code_dossier VARCHAR(64),
    siren VARCHAR(9),
    collab_nom VARCHAR(255),
    collab_prenom VARCHAR(255),
    collab_societe VARCHAR(255) COMMENT 'Entité Valoxy',
    collab_service VARCHAR(255),
    collab_poste VARCHAR(255),
    mission_libelle VARCHAR(255),
    prestation_libelle VARCHAR(255),
    memo TEXT,
    duree_heures DECIMAL(10,2),
    date_mission DATE,
    date_saisie DATETIME,
    debut_mission DATE,
    fin_mission DATE,
    exercice_code VARCHAR(10),
    synchro_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_dossier (code_dossier),
    INDEX idx_siren (siren),
    INDEX idx_collab (collab_nom, collab_prenom),
    INDEX idx_date_mission (date_mission),
    INDEX idx_service (collab_service),
    INDEX idx_exercice (exercice_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─────────────────────────────────────────────────────────────
-- Table : comptabilite_interne
-- Écritures comptables internes du cabinet (compta_valoxys)
-- ─────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS comptabilite_interne;
CREATE TABLE comptabilite_interne (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    entite_valoxy VARCHAR(40),
    compte VARCHAR(20),
    libelle_compte VARCHAR(50),
    code_dia VARCHAR(10),
    genre_libelle VARCHAR(50),
    libelle_code_societe VARCHAR(40),
    libelle_ecriture VARCHAR(50),
    date_ecriture DATE,
    debit_origine DECIMAL(18,2),
    credit_origine DECIMAL(18,2),
    journal_code VARCHAR(20),
    journal_libelle VARCHAR(30),
    lettrage VARCHAR(20),
    lettrage_n BOOLEAN,
    lettrage_n_1 BOOLEAN,
    libelle_reglement VARCHAR(50),
    directeur_de_mission VARCHAR(101),
    chef_de_mission VARCHAR(101),
    groupe VARCHAR(50),
    synchro_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_compte (compte),
    INDEX idx_code_dia (code_dia),
    INDEX idx_date_ecriture (date_ecriture),
    INDEX idx_entite (entite_valoxy)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SELECT '✅ Tables TRANSFORM créées avec succès !' AS status;
