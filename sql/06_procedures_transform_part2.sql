-- ============================================================
-- PROCÉDURES STOCKÉES : COUCHE TRANSFORM (suite)
-- Tiers détaillés, exercices, temps collaborateurs
-- ============================================================

DELIMITER //

-- ─────────────────────────────────────────────────────────────
-- TRANSFORM : load_ecritures_tiers_acd
-- Charge les comptes C/F DÉTAILLÉS depuis les bases compta_*
-- Normalise C* → 411 (clients) et F* → 401 (fournisseurs)
-- Adaptée de ta procédure creationMonthlyBalanceACDCompteFournisseurClient
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS transform_compta.load_ecritures_tiers_acd//
CREATE PROCEDURE transform_compta.load_ecritures_tiers_acd()
BEGIN
    DECLARE done INT DEFAULT 0;
    DECLARE db_name VARCHAR(100);
    DECLARE sql_text LONGTEXT;
    DECLARE db_count INT DEFAULT 0;
    DECLARE db_total INT DEFAULT 0;
    DECLARE v_errno INT;
    DECLARE v_sqlstate CHAR(5);
    DECLARE v_message TEXT;

    DECLARE cur CURSOR FOR
        SELECT schema_name FROM tmp_eligible_schemas ORDER BY schema_name;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_errno = MYSQL_ERRNO,
            v_sqlstate = RETURNED_SQLSTATE,
            v_message = MESSAGE_TEXT;
        DROP TEMPORARY TABLE IF EXISTS tmp_eligible_schemas;
        SELECT CONCAT('❌ Erreur: ', v_message) AS error_detail,
               db_name AS schema_en_cours;
    END;

    SELECT '🔄 Chargement ecritures_tiers_detaillees (ACD)...' AS status;

    -- Créer table temporaire des bases éligibles
    DROP TEMPORARY TABLE IF EXISTS tmp_eligible_schemas;
    CREATE TEMPORARY TABLE tmp_eligible_schemas (
        schema_name VARCHAR(100) PRIMARY KEY
    );

    INSERT INTO tmp_eligible_schemas (schema_name)
    SELECT TABLE_SCHEMA
    FROM information_schema.TABLES
    WHERE TABLE_SCHEMA LIKE 'compta\_%'
      AND TABLE_SCHEMA NOT IN ('compta_000000', 'compta_zz', 'compta_gombertcOLD', 'compta_gombertcold')
      AND TABLE_NAME IN ('histo_ligne_ecriture', 'histo_ecriture', 'ligne_ecriture', 'ecriture', 'compte', 'journal')
    GROUP BY TABLE_SCHEMA
    HAVING COUNT(DISTINCT TABLE_NAME) = 6;

    SELECT COUNT(*) INTO db_total FROM tmp_eligible_schemas;
    SELECT CONCAT('📊 ', db_total, ' bases compta_* à traiter pour tiers') AS status;

    -- Supprimer les données ACD existantes
    DELETE FROM transform_compta.ecritures_tiers_detaillees WHERE source = 'ACD';
    
    SET FOREIGN_KEY_CHECKS = 0;
    SET UNIQUE_CHECKS = 0;

    OPEN cur;

    read_loop: LOOP
        FETCH cur INTO db_name;
        IF done THEN LEAVE read_loop; END IF;

        SET db_count = db_count + 1;

        IF db_count = 1 OR db_count % 50 = 0 OR db_count = db_total THEN
            SELECT CONCAT('[', db_count, '/', db_total, '] Tiers ', db_name) AS progression;
        END IF;

        -- INSERT des comptes C* et F* avec normalisation
        SET sql_text = CONCAT("
            INSERT INTO transform_compta.ecritures_tiers_detaillees (
                source, code_dossier, siren, period_month, type_tiers,
                compte_origine, compte_normalise, compte_libelle,
                journal_code, journal_libelle, debits, credits, nb_ecritures, date_derniere_saisie
            )
            SELECT
                'ACD' AS source,
                UPPER(SUBSTRING_INDEX('", db_name, "', '_', -1)) AS code_dossier,
                da.siren,
                prev.period_month,
                prev.type_tiers,
                prev.compte_origine,
                prev.compte_normalise,
                prev.libelle_compte,
                prev.journal_code,
                prev.journal_libelle,
                ROUND(SUM(prev.debit_ligne), 2) AS debits,
                ROUND(SUM(prev.credit_ligne), 2) AS credits,
                COUNT(*) AS nb_ecritures,
                MAX(prev.date_saisie) AS date_derniere_saisie
            FROM (
                -- Historique (exercices clôturés)
                SELECT
                    STR_TO_DATE(CONCAT(he.HE_ANNEE, LPAD(he.HE_MOIS,2,'0'), '01'), '%Y%m%d') AS period_month,
                    he.HE_ANNEE AS annee,
                    COALESCE(he.JNL_CODE, 'UNKNOWN') AS journal_code,
                    j.JNL_LIB AS journal_libelle,
                    hle.CPT_CODE AS compte_origine,
                    CASE 
                        WHEN hle.CPT_CODE LIKE 'C%' THEN 'CLIENT'
                        WHEN hle.CPT_CODE LIKE 'F%' THEN 'FOURNISSEUR'
                    END AS type_tiers,
                    CASE 
                        WHEN hle.CPT_CODE LIKE 'C%' THEN '411'
                        WHEN hle.CPT_CODE LIKE 'F%' THEN '401'
                    END AS compte_normalise,
                    c.CPT_LIB AS libelle_compte,
                    hle.HLE_CRE_ORG AS credit_ligne,
                    hle.HLE_DEB_ORG AS debit_ligne,
                    he.HE_DATE_SAI AS date_saisie
                FROM `", db_name, "`.histo_ligne_ecriture hle
                JOIN `", db_name, "`.histo_ecriture he ON he.HE_CODE = hle.HE_CODE
                LEFT JOIN `", db_name, "`.compte c ON c.CPT_CODE = hle.CPT_CODE
                LEFT JOIN `", db_name, "`.journal j ON j.JNL_CODE = he.JNL_CODE
                WHERE he.HE_ANNEE >= YEAR(CURDATE()) - 3
                  AND (hle.CPT_CODE LIKE 'C%' OR hle.CPT_CODE LIKE 'F%')
                
                UNION ALL
                
                -- Courant (exercices ouverts)
                SELECT
                    STR_TO_DATE(CONCAT(e.ECR_ANNEE, LPAD(e.ECR_MOIS,2,'0'), '01'), '%Y%m%d') AS period_month,
                    e.ECR_ANNEE AS annee,
                    COALESCE(e.JNL_CODE, 'UNKNOWN') AS journal_code,
                    j.JNL_LIB AS journal_libelle,
                    le.CPT_CODE AS compte_origine,
                    CASE 
                        WHEN le.CPT_CODE LIKE 'C%' THEN 'CLIENT'
                        WHEN le.CPT_CODE LIKE 'F%' THEN 'FOURNISSEUR'
                    END AS type_tiers,
                    CASE 
                        WHEN le.CPT_CODE LIKE 'C%' THEN '411'
                        WHEN le.CPT_CODE LIKE 'F%' THEN '401'
                    END AS compte_normalise,
                    c.CPT_LIB AS libelle_compte,
                    le.LE_CRE_ORG AS credit_ligne,
                    le.LE_DEB_ORG AS debit_ligne,
                    e.ECR_DATE_SAI AS date_saisie
                FROM `", db_name, "`.ligne_ecriture le
                JOIN `", db_name, "`.ecriture e ON e.ECR_CODE = le.ECR_CODE
                LEFT JOIN `", db_name, "`.compte c ON c.CPT_CODE = le.CPT_CODE
                LEFT JOIN `", db_name, "`.journal j ON j.JNL_CODE = e.JNL_CODE
                WHERE e.ECR_ANNEE >= YEAR(CURDATE()) - 3
                  AND (le.CPT_CODE LIKE 'C%' OR le.CPT_CODE LIKE 'F%')
            ) AS prev
            LEFT JOIN transform_compta.dossiers_acd da 
                ON da.code_dia = UPPER(SUBSTRING_INDEX('", db_name, "', '_', -1))
            WHERE prev.annee >= YEAR(CURDATE()) - 3
              AND prev.type_tiers IS NOT NULL
            GROUP BY
                prev.period_month, prev.journal_code, prev.journal_libelle,
                prev.compte_origine, prev.type_tiers, prev.compte_normalise, 
                prev.libelle_compte, da.siren
            ON DUPLICATE KEY UPDATE
                debits = VALUES(debits),
                credits = VALUES(credits),
                nb_ecritures = VALUES(nb_ecritures),
                date_derniere_saisie = VALUES(date_derniere_saisie)
        ");

        PREPARE stmt FROM sql_text;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

    END LOOP;

    CLOSE cur;
    DROP TEMPORARY TABLE IF EXISTS tmp_eligible_schemas;

    SET FOREIGN_KEY_CHECKS = 1;
    SET UNIQUE_CHECKS = 1;

    SELECT CONCAT('✅ ecritures_tiers_detaillees (ACD): ', db_count, ' bases, ',
                  (SELECT COUNT(*) FROM transform_compta.ecritures_tiers_detaillees WHERE source = 'ACD'),
                  ' lignes') AS status;
END//

-- ─────────────────────────────────────────────────────────────
-- TRANSFORM : load_ecritures_tiers_pennylane
-- Charge les comptes 401/411 depuis raw_pennylane
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS transform_compta.load_ecritures_tiers_pennylane//
CREATE PROCEDURE transform_compta.load_ecritures_tiers_pennylane()
BEGIN
    SELECT '🔄 Chargement ecritures_tiers_detaillees (PENNYLANE)...' AS status;
    
    DELETE FROM transform_compta.ecritures_tiers_detaillees WHERE source = 'PENNYLANE';
    
    INSERT INTO transform_compta.ecritures_tiers_detaillees (
        source, code_dossier, siren, period_month, type_tiers,
        compte_origine, compte_normalise, compte_libelle,
        journal_code, journal_libelle, debits, credits, nb_ecritures, date_derniere_saisie
    )
    SELECT 
        'PENNYLANE' AS source,
        gl.company_name AS code_dossier,
        LEFT(c.registration_number, 9) AS siren,
        DATE_FORMAT(gl.txn_date, '%Y-%m-01') AS period_month,
        CASE 
            WHEN gl.compte LIKE '411%' THEN 'CLIENT'
            WHEN gl.compte LIKE '401%' THEN 'FOURNISSEUR'
        END AS type_tiers,
        gl.compte AS compte_origine,
        CASE 
            WHEN gl.compte LIKE '411%' THEN '411'
            WHEN gl.compte LIKE '401%' THEN '401'
        END AS compte_normalise,
        MAX(gl.compte_label) AS compte_libelle,
        COALESCE(gl.journal_code, '') AS journal_code,
        MAX(gl.journal_label) AS journal_libelle,
        SUM(COALESCE(gl.debit, 0)) AS debits,
        SUM(COALESCE(gl.credit, 0)) AS credits,
        COUNT(*) AS nb_ecritures,
        MAX(gl.document_updated_at) AS date_derniere_saisie
    FROM raw_pennylane.pl_general_ledger gl
    LEFT JOIN raw_pennylane.pl_companies c ON c.company_id = gl.company_id
    WHERE gl.txn_date >= DATE_SUB(CURDATE(), INTERVAL 3 YEAR)
      AND (gl.compte LIKE '401%' OR gl.compte LIKE '411%')
    GROUP BY 
        gl.company_name,
        LEFT(c.registration_number, 9),
        DATE_FORMAT(gl.txn_date, '%Y-%m-01'),
        gl.compte,
        COALESCE(gl.journal_code, '');
    
    SELECT CONCAT('✅ ecritures_tiers_detaillees (PENNYLANE): ', ROW_COUNT(), ' lignes') AS status;
END//

-- ─────────────────────────────────────────────────────────────
-- TRANSFORM : load_exercices
-- Charge les exercices ACD + Pennylane
-- Adaptée de ta procédure creationExerciceACD
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS transform_compta.load_exercices//
CREATE PROCEDURE transform_compta.load_exercices()
BEGIN
    SELECT '🔄 Chargement exercices...' AS status;
    
    TRUNCATE TABLE transform_compta.exercices;
    
    -- Exercices ACD (depuis raw_dia)
    INSERT INTO transform_compta.exercices (
        source, exo_id, code_dossier, siren, exercice_code, date_debut, date_fin, date_cloture
    )
    SELECT 
        'ACD' AS source,
        e.EXO_ID,
        a.ADR_CODE AS code_dossier,
        LEFT(a.ADR_SIRET, 9) AS siren,
        e.EXO_CODE,
        STR_TO_DATE(e.EXO_DATE_DEB, '%Y%m%d') AS date_debut,
        STR_TO_DATE(e.EXO_DATE_FIN, '%Y%m%d') AS date_fin,
        CASE WHEN e.EXO_DATE_CLOTURE != '' 
             THEN STR_TO_DATE(e.EXO_DATE_CLOTURE, '%Y%m%d') 
             ELSE NULL 
        END AS date_cloture
    FROM raw_dia.exercice e
    LEFT JOIN raw_dia.adresse a ON a.ADR_ID = e.ADR_ID
    WHERE a.GENRE_CODE = 'CLI_EC'
      AND (a.ADR_DATE_SORTIE IS NULL OR a.ADR_DATE_SORTIE = '');
    
    -- Exercices Pennylane
    INSERT INTO transform_compta.exercices (
        source, code_dossier, siren, exercice_code, date_debut, date_fin, date_cloture
    )
    SELECT 
        'PENNYLANE' AS source,
        fy.company_name AS code_dossier,
        LEFT(c.registration_number, 9) AS siren,
        fy.start_year AS exercice_code,
        fy.start_date AS date_debut,
        fy.end_date AS date_fin,
        fy.closed_at AS date_cloture
    FROM raw_pennylane.pl_fiscal_years fy
    LEFT JOIN raw_pennylane.pl_companies c ON c.company_id = fy.company_id;
    
    SELECT CONCAT('✅ exercices: ', ROW_COUNT(), ' lignes (ACD + Pennylane)') AS status;
END//

-- ─────────────────────────────────────────────────────────────
-- TRANSFORM : load_temps_collaborateurs
-- Charge les temps depuis raw_dia
-- Adaptée de ta procédure temps_collab
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS transform_compta.load_temps_collaborateurs//
CREATE PROCEDURE transform_compta.load_temps_collaborateurs()
BEGIN
    SELECT '🔄 Chargement temps_collaborateurs...' AS status;
    
    TRUNCATE TABLE transform_compta.temps_collaborateurs;
    
    INSERT INTO transform_compta.temps_collaborateurs (
        temps_id, code_dossier, siren, collab_nom, collab_prenom,
        collab_societe, collab_service, collab_poste,
        mission_libelle, prestation_libelle, memo, duree_heures,
        date_mission, date_saisie, debut_mission, fin_mission, exercice_code
    )
    SELECT 
        t.TEMPS_ID,
        a.ADR_CODE AS code_dossier,
        LEFT(a.ADR_SIRET, 9) AS siren,
        c.COL_NOM AS collab_nom,
        c.COL_PRENOM AS collab_prenom,
        s.SOC_NOM AS collab_societe,
        s2.SERV_LIBELLE AS collab_service,
        f.FONC_LIBELLE AS collab_poste,
        m.MISS_LIBELLE AS mission_libelle,
        p.PREST_LIBELLE AS prestation_libelle,
        t.TEMPS_MEMO AS memo,
        t.TEMPS_DUREE AS duree_heures,
        t.TEMPS_DATE AS date_mission,
        t.TEMPS_TIMESTP_PSYNC AS date_saisie,
        STR_TO_DATE(m.MISS_DATE_DEB, '%Y%m%d') AS debut_mission,
        STR_TO_DATE(m.MISS_DATE_FIN, '%Y%m%d') AS fin_mission,
        t.EXO_CODE AS exercice_code
    FROM raw_dia.temps t
    LEFT JOIN raw_dia.mission m ON m.MISS_ID = t.MISS_ID
    LEFT JOIN raw_dia.collab c ON c.COL_CODE = t.COL_CODE
    LEFT JOIN raw_dia.societe s ON s.SOC_CODE = c.SOC_CODE
    LEFT JOIN raw_dia.service s2 ON s2.SERV_CODE = c.SERV_CODE
    LEFT JOIN raw_dia.fonction f ON f.FONC_CODE = c.FONC_CODE
    LEFT JOIN raw_dia.prestation p ON p.PREST_CODE = t.PREST_CODE
    LEFT JOIN raw_dia.adresse a ON a.ADR_ID = t.ADR_ID
    WHERE CAST(LEFT(TRIM(t.EXO_CODE), 4) AS UNSIGNED) > YEAR(CURDATE()) - 2
      AND (c.COL_DATE_SORTIE = '' OR c.COL_DATE_SORTIE IS NULL);
    
    SELECT CONCAT('✅ temps_collaborateurs: ', ROW_COUNT(), ' lignes') AS status;
END//

DELIMITER ;
