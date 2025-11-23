-- ============================================================
-- COUCHE MDM : RÉFÉRENTIELS MAÎTRES UNIFIÉS
-- Jointure principale sur SIREN
-- ============================================================

USE mdm;

-- ─────────────────────────────────────────────────────────────
-- Table : dossiers
-- Référentiel unique des dossiers avec correspondance multi-sources
-- Jointure ACD ↔ Pennylane sur LEFT(SIRET,9) = LEFT(registration_number,9)
-- ─────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS dossiers;
CREATE TABLE dossiers (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    
    -- Identifiants par source
    siren VARCHAR(9) COMMENT 'Clé de jointure principale (9 premiers caractères SIRET)',
    code_dia VARCHAR(50) COMMENT 'Code dossier DIA/ACD (maître)',
    company_id_pennylane BIGINT COMMENT 'ID Pennylane',
    external_id_pennylane VARCHAR(255) COMMENT 'external_id Pennylane',
    
    -- Identifiants futurs (Phase 2+)
    id_tiime VARCHAR(50) COMMENT 'Futur - ID Tiime',
    id_silae VARCHAR(50) COMMENT 'Futur - ID Silae',
    id_openpaye VARCHAR(50) COMMENT 'Futur - ID OpenPaye',
    id_polyacte VARCHAR(50) COMMENT 'Futur - ID PolyActe',
    id_revisaudit VARCHAR(50) COMMENT 'Futur - ID Revis Audit',
    
    -- Données de référence (DIA = source maître)
    raison_sociale VARCHAR(255),
    siret VARCHAR(14),
    titre VARCHAR(255),
    forme_juridique VARCHAR(255),
    categorie_fiscale VARCHAR(255),
    regime_fiscal VARCHAR(255),
    code_naf VARCHAR(10),
    naf_description VARCHAR(255),
    ville VARCHAR(255),
    code_postal VARCHAR(10),
    region VARCHAR(100),
    email VARCHAR(255),
    telephone VARCHAR(32),
    
    -- Équipe assignée
    directeur_comptable VARCHAR(255),
    chef_de_mission VARCHAR(255),
    collaborateur_comptable VARCHAR(255),
    
    -- Métadonnées
    entite_valoxy VARCHAR(100) COMMENT 'VALOXY Lille, VALOXY Flandres, COMMUN, etc.',
    compte_compta_interne VARCHAR(64) COMMENT 'Compte client dans compta Valoxy',
    date_entree DATE,
    date_sortie DATE,
    actif BOOLEAN AS (date_sortie IS NULL) STORED,
    
    -- Sources présentes (flags pour v_clients_par_service)
    has_compta_acd BOOLEAN DEFAULT FALSE,
    has_compta_pennylane BOOLEAN DEFAULT FALSE,
    has_compta_tiime BOOLEAN DEFAULT FALSE,
    has_paye_silae BOOLEAN DEFAULT FALSE,
    has_paye_openpaye BOOLEAN DEFAULT FALSE,
    has_juridique_polyacte BOOLEAN DEFAULT FALSE,
    has_audit_revisaudit BOOLEAN DEFAULT FALSE,
    
    -- Timestamps
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_siren (siren),
    INDEX idx_code_dia (code_dia),
    INDEX idx_company_id_pennylane (company_id_pennylane),
    INDEX idx_entite (entite_valoxy),
    INDEX idx_actif (actif)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─────────────────────────────────────────────────────────────
-- Table : collaborateurs
-- Référentiel des collaborateurs du cabinet
-- ─────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS collaborateurs;
CREATE TABLE collaborateurs (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    
    -- Identifiants
    col_code_dia VARCHAR(20) COMMENT 'Code collaborateur DIA (maître)',
    email VARCHAR(255),
    
    -- Données de référence
    nom VARCHAR(255),
    prenom VARCHAR(255),
    
    -- Organisation
    entite_valoxy VARCHAR(100) COMMENT 'Société Valoxy (SOC_NOM)',
    service VARCHAR(50) COMMENT 'Comptabilité, Paye, Juridique, Audit, etc.',
    poste VARCHAR(255),
    
    -- Statut
    date_entree DATE,
    date_sortie DATE,
    actif BOOLEAN AS (date_sortie IS NULL) STORED,
    
    -- Timestamps
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_col_code (col_code_dia),
    INDEX idx_email (email),
    INDEX idx_service (service),
    INDEX idx_entite (entite_valoxy),
    INDEX idx_actif (actif)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─────────────────────────────────────────────────────────────
-- Table : contacts
-- Référentiel des contacts (personnes physiques liées aux dossiers)
-- ─────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS contacts;
CREATE TABLE contacts (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    
    -- Lien MDM
    dossier_id BIGINT COMMENT 'FK vers mdm.dossiers',
    siren VARCHAR(9) COMMENT 'Pour jointure alternative',
    
    -- Identifiants source
    cor_id_dia BIGINT COMMENT 'ID contact DIA (COR_ID)',
    
    -- Données de référence
    nom VARCHAR(255),
    prenom VARCHAR(255),
    email VARCHAR(255),
    telephone VARCHAR(32),
    fonction VARCHAR(255) COMMENT 'Dirigeant, DAF, Gérant, etc.',
    
    -- Timestamps
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_dossier_id (dossier_id),
    INDEX idx_siren (siren),
    INDEX idx_email (email),
    INDEX idx_nom_prenom (nom, prenom),
    
    CONSTRAINT fk_contact_dossier FOREIGN KEY (dossier_id) 
        REFERENCES dossiers(id) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─────────────────────────────────────────────────────────────
-- Table : mapping_comptes_services
-- Mapping des comptes de produits DIA vers les services
-- Pour détecter automatiquement quels clients ont quels services
-- ─────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS mapping_comptes_services;
CREATE TABLE mapping_comptes_services (
    id INT AUTO_INCREMENT PRIMARY KEY,
    compte_pattern VARCHAR(20) NOT NULL COMMENT 'Pattern de compte (ex: 706100%)',
    service ENUM('COMPTA', 'PAYE', 'JURIDIQUE', 'AUDIT') NOT NULL,
    description VARCHAR(255),
    actif BOOLEAN DEFAULT TRUE,
    UNIQUE KEY uk_pattern (compte_pattern)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Données initiales (à adapter selon votre plan comptable DIA)
INSERT INTO mapping_comptes_services (compte_pattern, service, description) VALUES
('706100%', 'COMPTA', 'Honoraires comptabilité'),
('706110%', 'COMPTA', 'Honoraires tenue comptable'),
('706120%', 'COMPTA', 'Honoraires révision'),
('706200%', 'PAYE', 'Honoraires paye/social'),
('706210%', 'PAYE', 'Honoraires bulletins de paie'),
('706300%', 'JURIDIQUE', 'Honoraires juridique'),
('706310%', 'JURIDIQUE', 'Honoraires assemblées'),
('706400%', 'AUDIT', 'Honoraires audit'),
('706410%', 'AUDIT', 'Honoraires CAC');

SELECT '✅ Tables MDM créées avec succès !' AS status;
