-- ============================================================
-- PROCÉDURES STOCKÉES : COUCHE TRANSFORM
-- Alimentation des tables TRANSFORM depuis RAW
-- ============================================================

DELIMITER //

-- ─────────────────────────────────────────────────────────────
-- TRANSFORM : load_dossiers_acd
-- Charge les dossiers depuis raw_dia.adresse
-- Adaptée de ta procédure creationCompanyACD
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS transform_compta.load_dossiers_acd//
CREATE PROCEDURE transform_compta.load_dossiers_acd()
BEGIN
    SELECT '🔄 Chargement dossiers_acd depuis raw_dia...' AS status;
    
    TRUNCATE TABLE transform_compta.dossiers_acd;
    
    INSERT INTO transform_compta.dossiers_acd (
        adr_id, code_dia, nom, siren, siret, titre, forme_juridique,
        categorie_fiscale, regime_fiscal, ville, code_postal,
        code_naf, naf_description, email, telephone,
        directeur_comptable, chef_de_mission, collaborateur_comptable,
        entite_valoxy, region, compte_compta_interne, date_entree,
        date_creation, date_modification
    )
    SELECT
        a.ADR_ID,
        a.ADR_CODE AS code_dia,
        a.ADR_NOM AS nom,
        LEFT(a.ADR_SIRET, 9) AS siren,
        a.ADR_SIRET AS siret,
        t.TITRE_COURT AS titre,
        fj.JUR_LIBELLE AS forme_juridique,
        a.ADR_TYP_REG AS categorie_fiscale,
        a.ADR_REG_FISCAL AS regime_fiscal,
        a.ADR_VILLE AS ville,
        a.POSTAL_CODE AS code_postal,
        a.NAF_CODE AS code_naf,
        n.NAF_DESCRIPTION AS naf_description,
        a.ADR_EMAIL AS email,
        REPLACE(a.ADR_TEL1, ' ', '') AS telephone,
        c1.COL_EMAIL AS directeur_comptable,
        c2.COL_EMAIL AS chef_de_mission,
        c3.COL_EMAIL AS collaborateur_comptable,
        s.SOC_NOM AS entite_valoxy,
        r.REGION_LIBELLE AS region,
        a.ADR_NUMCOMPTE AS compte_compta_interne,
        a.ADR_DATE_ENTREE AS date_entree,
        a.ADR_DATE_CREAT AS date_creation,
        a.ADR_DATE_MODIF AS date_modification
    FROM raw_dia.adresse a
    LEFT JOIN raw_dia.forme_juridique fj ON fj.JUR_CODE = a.JUR_CODE
    LEFT JOIN raw_dia.collab c1 ON c1.COL_CODE = a.COL_CODE_N1
    LEFT JOIN raw_dia.collab c2 ON c2.COL_CODE = a.COL_CODE_N2
    LEFT JOIN raw_dia.collab c3 ON c3.COL_CODE = a.COL_CODE_N3
    LEFT JOIN raw_dia.naf n ON n.NAF_CODE = a.NAF_CODE
    LEFT JOIN raw_dia.region r ON r.REGION_CODE = a.REGION_CODE
    LEFT JOIN raw_dia.societe s ON s.SOC_CODE = a.SOC_CODE
    LEFT JOIN raw_dia.titre t ON t.TITRE_CODE = a.TITRE_CODE
    WHERE a.GENRE_CODE = 'CLI_EC'
      AND (a.ADR_DATE_SORTIE IS NULL OR a.ADR_DATE_SORTIE = '');
    
    SELECT CONCAT('✅ dossiers_acd: ', ROW_COUNT(), ' lignes chargées') AS status;
END//

-- ─────────────────────────────────────────────────────────────
-- TRANSFORM : load_dossiers_pennylane
-- Charge les dossiers depuis raw_pennylane
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS transform_compta.load_dossiers_pennylane//
CREATE PROCEDURE transform_compta.load_dossiers_pennylane()
BEGIN
    SELECT '🔄 Chargement dossiers_pennylane depuis raw_pennylane...' AS status;
    
    TRUNCATE TABLE transform_compta.dossiers_pennylane;
    
    INSERT INTO transform_compta.dossiers_pennylane (
        company_id, name, siren, external_id, firm_name, trade_name,
        forme_juridique, categorie_fiscale, regime_fiscal, ville, code_postal,
        code_naf, secteur_activite, directeur_comptable,
        chef_de_mission, collaborateur_comptable, entite_valoxy,
        date_creation, date_modification
    )
    SELECT 
        c.company_id,
        c.name,
        LEFT(c.registration_number, 9) AS siren,
        ci.external_id,
        c.firm_name,
        c.trade_name,
        c.legal_form AS forme_juridique,
        c.fiscal_category AS categorie_fiscale,
        c.fiscal_regime AS regime_fiscal,
        c.city AS ville,
        c.postal_code,
        c.activity_code AS code_naf,
        c.activity_sector AS secteur_activite,
        ci.accounting_supervisor_email AS directeur_comptable,
        ci.accounting_manager_email AS chef_de_mission,
        ci.accountant_email AS collaborateur_comptable,
        c.firm_name AS entite_valoxy,
        c.created_at AS date_creation,
        c.updated_at AS date_modification
    FROM raw_pennylane.pl_companies c
    LEFT JOIN raw_pennylane.acc_companies_identification ci ON ci.company_id = c.company_id
    WHERE c.name NOT LIKE '%Test%'
      AND c.name NOT LIKE '%Sandbox%';
    
    SELECT CONCAT('✅ dossiers_pennylane: ', ROW_COUNT(), ' lignes chargées') AS status;
END//

-- ─────────────────────────────────────────────────────────────
-- TRANSFORM : load_ecritures_acd
-- Charge les écritures agrégées depuis les bases compta_*
-- Adaptée de ta procédure creationMonthlyBalanceACD
-- Comptes C/F agrégés en Cxxxxx/Fxxxxx
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS transform_compta.load_ecritures_acd//
CREATE PROCEDURE transform_compta.load_ecritures_acd()
BEGIN
    DECLARE done INT DEFAULT 0;
    DECLARE db_name VARCHAR(100);
    DECLARE sql_text LONGTEXT;
    DECLARE last_sql LONGTEXT;
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
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_eligible_schemas;
        SELECT CONCAT('❌ Erreur SQL #', v_errno, ' (SQLSTATE ', v_sqlstate, '): ', v_message) AS error_detail,
               db_name AS schema_en_cours,
               CONCAT('Bases traitées: ', db_count, '/', db_total) AS progression;
    END;

    SELECT '🔄 Chargement ecritures_mensuelles (ACD)...' AS status;

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
    SELECT CONCAT('📊 ', db_total, ' bases compta_* à traiter') AS status;

    -- Supprimer les données ACD existantes
    DELETE FROM transform_compta.ecritures_mensuelles WHERE source = 'ACD';
    
    SET FOREIGN_KEY_CHECKS = 0;
    SET UNIQUE_CHECKS = 0;

    OPEN cur;

    read_loop: LOOP
        FETCH cur INTO db_name;
        IF done THEN LEAVE read_loop; END IF;

        SET db_count = db_count + 1;

        IF db_count = 1 OR db_count % 50 = 0 OR db_count = db_total THEN
            SELECT CONCAT('[', db_count, '/', db_total, '] ', db_name, 
                          ' (', ROUND(db_count * 100 / db_total, 1), '%)') AS progression;
        END IF;

        -- INSERT avec comptes C/F agrégés en Cxxxxx/Fxxxxx
        SET sql_text = CONCAT("
            INSERT INTO transform_compta.ecritures_mensuelles (
                source, code_dossier, siren, period_month, compte, compte_libelle,
                journal_code, journal_libelle, debits, credits, nb_ecritures, date_derniere_saisie
            )
            SELECT
                'ACD' AS source,
                UPPER(SUBSTRING_INDEX('", db_name, "', '_', -1)) AS code_dossier,
                da.siren,
                prev.period_month,
                prev.compte,
                prev.libelle_compte,
                prev.journal_code,
                prev.journal_libelle,
                ROUND(SUM(prev.debit_ligne), 2) AS debits,
                ROUND(SUM(prev.credit_ligne), 2) AS credits,
                COUNT(*) AS nb_ecritures,
                MAX(prev.date_saisie) AS date_derniere_saisie
            FROM (
                SELECT
                    STR_TO_DATE(CONCAT(he.HE_ANNEE, LPAD(he.HE_MOIS,2,'0'), '01'), '%Y%m%d') AS period_month,
                    he.HE_ANNEE AS annee,
                    COALESCE(he.JNL_CODE, 'UNKNOWN') AS journal_code,
                    j.JNL_LIB AS journal_libelle,
                    CASE
                        WHEN hle.CPT_CODE LIKE 'C%' THEN 'Cxxxxx'
                        WHEN hle.CPT_CODE LIKE 'F%' THEN 'Fxxxxx'
                        ELSE hle.CPT_CODE
                    END AS compte,
                    CASE
                        WHEN hle.CPT_CODE LIKE 'C%' THEN 'Cxxxxx'
                        WHEN hle.CPT_CODE LIKE 'F%' THEN 'Fxxxxx'
                        ELSE c.CPT_LIB
                    END AS libelle_compte,
                    hle.HLE_CRE_ORG AS credit_ligne,
                    hle.HLE_DEB_ORG AS debit_ligne,
                    he.HE_DATE_SAI AS date_saisie
                FROM `", db_name, "`.histo_ligne_ecriture hle
                JOIN `", db_name, "`.histo_ecriture he ON he.HE_CODE = hle.HE_CODE
                LEFT JOIN `", db_name, "`.compte c ON c.CPT_CODE = hle.CPT_CODE
                LEFT JOIN `", db_name, "`.journal j ON j.JNL_CODE = he.JNL_CODE
                WHERE he.HE_ANNEE >= YEAR(CURDATE()) - 3
                
                UNION ALL
                
                SELECT
                    STR_TO_DATE(CONCAT(e.ECR_ANNEE, LPAD(e.ECR_MOIS,2,'0'), '01'), '%Y%m%d') AS period_month,
                    e.ECR_ANNEE AS annee,
                    COALESCE(e.JNL_CODE, 'UNKNOWN') AS journal_code,
                    j.JNL_LIB AS journal_libelle,
                    CASE
                        WHEN le.CPT_CODE LIKE 'C%' THEN 'Cxxxxx'
                        WHEN le.CPT_CODE LIKE 'F%' THEN 'Fxxxxx'
                        ELSE le.CPT_CODE
                    END AS compte,
                    CASE
                        WHEN le.CPT_CODE LIKE 'C%' THEN 'Cxxxxx'
                        WHEN le.CPT_CODE LIKE 'F%' THEN 'Fxxxxx'
                        ELSE c.CPT_LIB
                    END AS libelle_compte,
                    le.LE_CRE_ORG AS credit_ligne,
                    le.LE_DEB_ORG AS debit_ligne,
                    e.ECR_DATE_SAI AS date_saisie
                FROM `", db_name, "`.ligne_ecriture le
                JOIN `", db_name, "`.ecriture e ON e.ECR_CODE = le.ECR_CODE
                LEFT JOIN `", db_name, "`.compte c ON c.CPT_CODE = le.CPT_CODE
                LEFT JOIN `", db_name, "`.journal j ON j.JNL_CODE = e.JNL_CODE
                WHERE e.ECR_ANNEE >= YEAR(CURDATE()) - 3
            ) AS prev
            LEFT JOIN transform_compta.dossiers_acd da 
                ON da.code_dia = UPPER(SUBSTRING_INDEX('", db_name, "', '_', -1))
            WHERE prev.annee >= YEAR(CURDATE()) - 3
            GROUP BY
                prev.period_month, prev.journal_code, prev.journal_libelle, 
                prev.compte, prev.libelle_compte, da.siren
            ON DUPLICATE KEY UPDATE
                debits = VALUES(debits),
                credits = VALUES(credits),
                nb_ecritures = VALUES(nb_ecritures),
                date_derniere_saisie = VALUES(date_derniere_saisie),
                compte_libelle = COALESCE(VALUES(compte_libelle), compte_libelle),
                journal_libelle = COALESCE(VALUES(journal_libelle), journal_libelle)
        ");

        SET last_sql = sql_text;
        PREPARE stmt FROM sql_text;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

    END LOOP;

    CLOSE cur;
    DROP TEMPORARY TABLE IF EXISTS tmp_eligible_schemas;

    SET FOREIGN_KEY_CHECKS = 1;
    SET UNIQUE_CHECKS = 1;

    SELECT CONCAT('✅ ecritures_mensuelles (ACD): ', db_count, ' bases traitées, ',
                  (SELECT COUNT(*) FROM transform_compta.ecritures_mensuelles WHERE source = 'ACD'),
                  ' lignes') AS status;
END//

-- ─────────────────────────────────────────────────────────────
-- TRANSFORM : load_ecritures_pennylane
-- Charge les écritures agrégées depuis raw_pennylane
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS transform_compta.load_ecritures_pennylane//
CREATE PROCEDURE transform_compta.load_ecritures_pennylane()
BEGIN
    SELECT '🔄 Chargement ecritures_mensuelles (PENNYLANE)...' AS status;
    
    -- Supprimer les données Pennylane existantes
    DELETE FROM transform_compta.ecritures_mensuelles WHERE source = 'PENNYLANE';
    
    INSERT INTO transform_compta.ecritures_mensuelles (
        source, code_dossier, siren, period_month, compte, compte_libelle,
        journal_code, journal_libelle, debits, credits, nb_ecritures, date_derniere_saisie
    )
    SELECT 
        'PENNYLANE' AS source,
        gl.company_name AS code_dossier,
        LEFT(c.registration_number, 9) AS siren,
        DATE_FORMAT(gl.txn_date, '%Y-%m-01') AS period_month,
        gl.compte,
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
    GROUP BY 
        gl.company_name,
        LEFT(c.registration_number, 9),
        DATE_FORMAT(gl.txn_date, '%Y-%m-01'),
        gl.compte,
        COALESCE(gl.journal_code, '');
    
    SELECT CONCAT('✅ ecritures_mensuelles (PENNYLANE): ', ROW_COUNT(), ' lignes') AS status;
END//

DELIMITER ;
