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
-- Charge les écritures agrégées depuis raw_acd centralisée
-- NOUVELLE VERSION : 1 requête au lieu de 3500 boucles
-- Utilise les 18 indexes optimisés sur raw_acd
-- Comptes C*/F* → 4110/4100 dans compte_normalized
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS transform_compta.load_ecritures_acd//
CREATE PROCEDURE transform_compta.load_ecritures_acd()
BEGIN
    DECLARE v_errno INT;
    DECLARE v_sqlstate CHAR(5);
    DECLARE v_message TEXT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_errno = MYSQL_ERRNO,
            v_sqlstate = RETURNED_SQLSTATE,
            v_message = MESSAGE_TEXT;
        SELECT CONCAT('❌ Erreur load_ecritures_acd: ', v_message) AS error_detail;
        ROLLBACK;
    END;

    SELECT '🔄 Chargement ecritures_mensuelles (ACD)...' AS status;

    -- Suppression des données ACD existantes
    DELETE FROM transform_compta.ecritures_mensuelles WHERE source = 'ACD';

    SET FOREIGN_KEY_CHECKS = 0;
    SET UNIQUE_CHECKS = 0;

    -- ══════════════════════════════════════════════════════════════
    -- AGRÉGATION DIRECTE DEPUIS raw_acd (1 requête au lieu de 3500)
    -- Utilise les 18 indexes optimisés
    -- ══════════════════════════════════════════════════════════════
    INSERT INTO transform_compta.ecritures_mensuelles (
        source,
        code_dossier,
        siren,
        period_month,
        compte,
        compte_normalized,
        compte_libelle,
        journal_code,
        journal_libelle,
        debits,
        credits,
        nb_ecritures,
        date_derniere_saisie
    )
    SELECT
        'ACD' AS source,
        agg.dossier_code AS code_dossier,
        da.siren,
        agg.period_month,
        agg.compte,
        -- 🎯 Normalisation des comptes (C* → 4110, F* → 4100)
        CASE
            WHEN agg.compte LIKE 'C%' THEN '4110'
            WHEN agg.compte LIKE 'F%' THEN '4100'
            ELSE LEFT(agg.compte, 4)
        END AS compte_normalized,
        agg.compte_libelle,
        agg.journal_code,
        agg.journal_libelle,
        ROUND(SUM(agg.debit_ligne), 2) AS debits,
        ROUND(SUM(agg.credit_ligne), 2) AS credits,
        COUNT(*) AS nb_ecritures,
        MAX(agg.date_saisie) AS date_derniere_saisie
    FROM (
        -- ───────────────────────────────────────────────────────────
        -- Historique (histo_ligne_ecriture + histo_ecriture)
        -- ───────────────────────────────────────────────────────────
        SELECT
            hle.dossier_code,
            STR_TO_DATE(CONCAT(he.HE_ANNEE, LPAD(he.HE_MOIS, 2, '0'), '01'), '%Y%m%d') AS period_month,
            he.HE_ANNEE AS annee,
            COALESCE(he.JNL_CODE, 'UNKNOWN') AS journal_code,
            j.JNL_LIB AS journal_libelle,
            hle.CPT_CODE AS compte,
            c.CPT_LIB AS compte_libelle,
            hle.HLE_CRE_ORG AS credit_ligne,
            hle.HLE_DEB_ORG AS debit_ligne,
            he.HE_DATE_SAI AS date_saisie
        FROM raw_acd.histo_ligne_ecriture hle
        INNER JOIN raw_acd.histo_ecriture he
            ON he.dossier_code = hle.dossier_code
            AND he.HE_CODE = hle.HE_CODE
        LEFT JOIN raw_acd.compte c
            ON c.dossier_code = hle.dossier_code
            AND c.CPT_CODE = hle.CPT_CODE
        LEFT JOIN raw_acd.journal j
            ON j.dossier_code = he.dossier_code
            AND j.JNL_CODE = he.JNL_CODE
        WHERE he.HE_ANNEE >= YEAR(CURDATE()) - 3

        UNION ALL

        -- ───────────────────────────────────────────────────────────
        -- Courant (ligne_ecriture + ecriture)
        -- ───────────────────────────────────────────────────────────
        SELECT
            le.dossier_code,
            STR_TO_DATE(CONCAT(e.ECR_ANNEE, LPAD(e.ECR_MOIS, 2, '0'), '01'), '%Y%m%d') AS period_month,
            e.ECR_ANNEE AS annee,
            COALESCE(e.JNL_CODE, 'UNKNOWN') AS journal_code,
            j.JNL_LIB AS journal_libelle,
            le.CPT_CODE AS compte,
            c.CPT_LIB AS compte_libelle,
            le.LE_CRE_ORG AS credit_ligne,
            le.LE_DEB_ORG AS debit_ligne,
            e.ECR_DATE_SAI AS date_saisie
        FROM raw_acd.ligne_ecriture le
        INNER JOIN raw_acd.ecriture e
            ON e.dossier_code = le.dossier_code
            AND e.ECR_CODE = le.ECR_CODE
        LEFT JOIN raw_acd.compte c
            ON c.dossier_code = le.dossier_code
            AND c.CPT_CODE = le.CPT_CODE
        LEFT JOIN raw_acd.journal j
            ON j.dossier_code = e.dossier_code
            AND j.JNL_CODE = e.JNL_CODE
        WHERE e.ECR_ANNEE >= YEAR(CURDATE()) - 3
    ) AS agg
    LEFT JOIN transform_compta.dossiers_acd da
        ON da.code_dia COLLATE utf8mb4_unicode_ci = agg.dossier_code
    WHERE agg.annee >= YEAR(CURDATE()) - 3
    GROUP BY
        agg.dossier_code,
        agg.period_month,
        agg.compte,
        agg.journal_code,
        agg.journal_libelle,
        agg.compte_libelle,
        da.siren
    ON DUPLICATE KEY UPDATE
        debits = VALUES(debits),
        credits = VALUES(credits),
        nb_ecritures = VALUES(nb_ecritures),
        date_derniere_saisie = VALUES(date_derniere_saisie),
        compte_libelle = COALESCE(VALUES(compte_libelle), compte_libelle),
        journal_libelle = COALESCE(VALUES(journal_libelle), journal_libelle);

    SET FOREIGN_KEY_CHECKS = 1;
    SET UNIQUE_CHECKS = 1;

    SELECT CONCAT('✅ ecritures_mensuelles (ACD): ',
                  (SELECT COUNT(*) FROM transform_compta.ecritures_mensuelles WHERE source = 'ACD'),
                  ' lignes') AS resultat;
END//

-- ─────────────────────────────────────────────────────────────
-- TRANSFORM : load_ecritures_pennylane
-- Charge les écritures agrégées depuis raw_pennylane
-- Inspiré de creationPennyLaneMonthlyBalances
-- Ajoute compte_normalized (LEFT(compte, 4))
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS transform_compta.load_ecritures_pennylane//
CREATE PROCEDURE transform_compta.load_ecritures_pennylane()
BEGIN
    DECLARE v_errno INT;
    DECLARE v_sqlstate CHAR(5);
    DECLARE v_message TEXT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_errno = MYSQL_ERRNO,
            v_sqlstate = RETURNED_SQLSTATE,
            v_message = MESSAGE_TEXT;
        SELECT CONCAT('❌ Erreur load_ecritures_pennylane: ', v_message) AS error_detail;
        ROLLBACK;
    END;

    SELECT '🔄 Chargement ecritures_mensuelles (PENNYLANE)...' AS status;

    -- Suppression des données PENNYLANE existantes
    DELETE FROM transform_compta.ecritures_mensuelles WHERE source = 'PENNYLANE';

    SET FOREIGN_KEY_CHECKS = 0;
    SET UNIQUE_CHECKS = 0;

    -- ══════════════════════════════════════════════════════════════
    -- AGRÉGATION DIRECTE depuis raw_pennylane.pl_general_ledger
    -- Inspiré de creationPennyLaneMonthlyBalances
    -- ══════════════════════════════════════════════════════════════
    INSERT INTO transform_compta.ecritures_mensuelles (
        source,
        code_dossier,
        siren,
        period_month,
        compte,
        compte_normalized,
        compte_libelle,
        journal_code,
        journal_libelle,
        debits,
        credits,
        nb_ecritures,
        date_derniere_saisie
    )
    SELECT
        'PENNYLANE' AS source,
        CAST(gl.company_id AS CHAR) AS code_dossier,
        dp.siren,
        DATE_FORMAT(gl.txn_date, '%Y-%m-01') AS period_month,
        gl.compte,
        -- 🎯 Normalisation PennyLane : toujours LEFT(compte, 4)
        LEFT(gl.compte, 4) AS compte_normalized,
        MAX(gl.compte_label) AS compte_libelle,
        COALESCE(gl.journal_code, '') AS journal_code,
        MAX(gl.journal_label) AS journal_libelle,
        SUM(COALESCE(gl.debit, 0)) AS debits,
        SUM(COALESCE(gl.credit, 0)) AS credits,
        COUNT(*) AS nb_ecritures,
        MAX(gl.document_updated_at) AS date_derniere_saisie
    FROM raw_pennylane.pl_general_ledger gl
    LEFT JOIN transform_compta.dossiers_pennylane dp
        ON dp.company_id = gl.company_id
    -- Pas de filtre sur les 3 dernières années pour PennyLane (garder tout l'historique)
    GROUP BY
        gl.company_id,
        DATE_FORMAT(gl.txn_date, '%Y-%m-01'),
        gl.compte,
        COALESCE(gl.journal_code, '')
    ON DUPLICATE KEY UPDATE
        debits = VALUES(debits),
        credits = VALUES(credits),
        nb_ecritures = VALUES(nb_ecritures),
        date_derniere_saisie = VALUES(date_derniere_saisie),
        compte_libelle = COALESCE(VALUES(compte_libelle), compte_libelle),
        journal_libelle = COALESCE(VALUES(journal_libelle), journal_libelle);

    SET FOREIGN_KEY_CHECKS = 1;
    SET UNIQUE_CHECKS = 1;

    SELECT CONCAT('✅ ecritures_mensuelles (PENNYLANE): ',
                  (SELECT COUNT(*) FROM transform_compta.ecritures_mensuelles WHERE source = 'PENNYLANE'),
                  ' lignes') AS resultat;
END//

DELIMITER ;
