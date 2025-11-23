-- ============================================================
-- PHASE 1 : CRÉATION DES SCHÉMAS
-- Architecture 4 couches : RAW → TRANSFORM → MDM → MART
-- ============================================================

-- ─── COUCHE RAW ───────────────────────────────────────────
-- Copies brutes des sources (DIA, Pennylane)
-- Note: Les bases compta_* sont copiées directement par mysqldump

CREATE DATABASE IF NOT EXISTS raw_dia
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE DATABASE IF NOT EXISTS raw_pennylane
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- ─── COUCHE TRANSFORM ─────────────────────────────────────
-- Données nettoyées, normalisées, agrégées

CREATE DATABASE IF NOT EXISTS transform_compta
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- ─── COUCHE MDM ───────────────────────────────────────────
-- Référentiels maîtres unifiés (jointure sur SIREN)

CREATE DATABASE IF NOT EXISTS mdm
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- ─── COUCHE MART ──────────────────────────────────────────
-- Vues métier pour reporting (3 sous-schémas)

CREATE DATABASE IF NOT EXISTS mart_pilotage_cabinet
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE DATABASE IF NOT EXISTS mart_controle_gestion
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE DATABASE IF NOT EXISTS mart_production_client
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- ─── VÉRIFICATION ─────────────────────────────────────────
SELECT 'Schémas créés avec succès !' AS status;
SHOW DATABASES LIKE 'raw_%';
SHOW DATABASES LIKE 'transform_%';
SHOW DATABASES LIKE 'mdm';
SHOW DATABASES LIKE 'mart_%';
