-- ============================================================
-- PROCÉDURES STOCKÉES : COUCHE MDM
-- Alimentation du référentiel maître avec jointure sur SIREN
-- ============================================================

DELIMITER //

-- ─────────────────────────────────────────────────────────────
-- MDM : load_dossiers
-- Construit le référentiel unifié des dossiers
-- Jointure ACD ↔ Pennylane sur SIREN
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS mdm.load_dossiers//
CREATE PROCEDURE mdm.load_dossiers()
BEGIN
    DECLARE v_acd_only INT DEFAULT 0;
    DECLARE v_pennylane_only INT DEFAULT 0;
    DECLARE v_both INT DEFAULT 0;
    DECLARE v_total INT DEFAULT 0;

    SELECT '🔄 Construction référentiel mdm.dossiers...' AS status;
    
    TRUNCATE TABLE mdm.dossiers;
    
    -- Étape 1 : Insérer tous les dossiers ACD (source maître)
    INSERT INTO mdm.dossiers (
        siren, code_dia, raison_sociale, siret, titre, forme_juridique,
        categorie_fiscale, regime_fiscal, code_naf, naf_description,
        ville, code_postal, region, email, telephone,
        directeur_comptable, chef_de_mission, collaborateur_comptable,
        entite_valoxy, compte_compta_interne, date_entree,
        has_compta_acd, has_compta_pennylane
    )
    SELECT 
        da.siren,
        da.code_dia,
        da.nom AS raison_sociale,
        da.siret,
        da.titre,
        da.forme_juridique,
        da.categorie_fiscale,
        da.regime_fiscal,
        da.code_naf,
        da.naf_description,
        da.ville,
        da.code_postal,
        da.region,
        da.email,
        da.telephone,
        da.directeur_comptable,
        da.chef_de_mission,
        da.collaborateur_comptable,
        da.entite_valoxy,
        da.compte_compta_interne,
        STR_TO_DATE(da.date_entree, '%Y%m%d') AS date_entree,
        TRUE AS has_compta_acd,
        FALSE AS has_compta_pennylane
    FROM transform_compta.dossiers_acd da
    WHERE da.siren IS NOT NULL AND da.siren != '' AND LENGTH(da.siren) = 9;
    
    -- Ajouter les dossiers ACD sans SIREN valide (avec code_dia comme clé)
    INSERT INTO mdm.dossiers (
        code_dia, raison_sociale, siret, titre, forme_juridique,
        categorie_fiscale, regime_fiscal, code_naf, naf_description,
        ville, code_postal, region, email, telephone,
        directeur_comptable, chef_de_mission, collaborateur_comptable,
        entite_valoxy, compte_compta_interne, date_entree,
        has_compta_acd, has_compta_pennylane
    )
    SELECT 
        da.code_dia,
        da.nom AS raison_sociale,
        da.siret,
        da.titre,
        da.forme_juridique,
        da.categorie_fiscale,
        da.regime_fiscal,
        da.code_naf,
        da.naf_description,
        da.ville,
        da.code_postal,
        da.region,
        da.email,
        da.telephone,
        da.directeur_comptable,
        da.chef_de_mission,
        da.collaborateur_comptable,
        da.entite_valoxy,
        da.compte_compta_interne,
        STR_TO_DATE(da.date_entree, '%Y%m%d') AS date_entree,
        TRUE AS has_compta_acd,
        FALSE AS has_compta_pennylane
    FROM transform_compta.dossiers_acd da
    WHERE da.siren IS NULL OR da.siren = '' OR LENGTH(da.siren) != 9;
    
    -- Étape 2 : Mettre à jour avec les données Pennylane (jointure SIREN)
    UPDATE mdm.dossiers d
    INNER JOIN transform_compta.dossiers_pennylane dp ON dp.siren = d.siren
    SET 
        d.company_id_pennylane = dp.company_id,
        d.external_id_pennylane = dp.external_id,
        d.has_compta_pennylane = TRUE,
        -- Compléter les champs vides avec Pennylane
        d.forme_juridique = COALESCE(NULLIF(d.forme_juridique, ''), dp.forme_juridique),
        d.categorie_fiscale = COALESCE(NULLIF(d.categorie_fiscale, ''), dp.categorie_fiscale),
        d.regime_fiscal = COALESCE(NULLIF(d.regime_fiscal, ''), dp.regime_fiscal)
    WHERE dp.siren IS NOT NULL AND dp.siren != '' AND LENGTH(dp.siren) = 9;
    
    -- Étape 3 : Ajouter les dossiers Pennylane sans correspondance ACD
    INSERT INTO mdm.dossiers (
        siren, company_id_pennylane, external_id_pennylane,
        raison_sociale, forme_juridique, categorie_fiscale, regime_fiscal,
        code_naf, ville, code_postal,
        directeur_comptable, chef_de_mission, collaborateur_comptable,
        entite_valoxy,
        has_compta_acd, has_compta_pennylane
    )
    SELECT 
        dp.siren,
        dp.company_id,
        dp.external_id,
        dp.name AS raison_sociale,
        dp.forme_juridique,
        dp.categorie_fiscale,
        dp.regime_fiscal,
        dp.code_naf,
        dp.ville,
        dp.code_postal,
        dp.directeur_comptable,
        dp.chef_de_mission,
        dp.collaborateur_comptable,
        dp.entite_valoxy,
        FALSE AS has_compta_acd,
        TRUE AS has_compta_pennylane
    FROM transform_compta.dossiers_pennylane dp
    WHERE NOT EXISTS (
        SELECT 1 FROM mdm.dossiers d 
        WHERE d.siren = dp.siren 
          AND dp.siren IS NOT NULL 
          AND dp.siren != '' 
          AND LENGTH(dp.siren) = 9
    )
    AND dp.name NOT LIKE '%Test%'
    AND dp.name NOT LIKE '%Sandbox%';
    
    -- Statistiques
    SELECT COUNT(*) INTO v_acd_only FROM mdm.dossiers WHERE has_compta_acd = TRUE AND has_compta_pennylane = FALSE;
    SELECT COUNT(*) INTO v_pennylane_only FROM mdm.dossiers WHERE has_compta_acd = FALSE AND has_compta_pennylane = TRUE;
    SELECT COUNT(*) INTO v_both FROM mdm.dossiers WHERE has_compta_acd = TRUE AND has_compta_pennylane = TRUE;
    SELECT COUNT(*) INTO v_total FROM mdm.dossiers;
    
    SELECT '✅ mdm.dossiers chargé' AS status,
           v_total AS total,
           v_acd_only AS acd_uniquement,
           v_pennylane_only AS pennylane_uniquement,
           v_both AS les_deux_sources;
END//

-- ─────────────────────────────────────────────────────────────
-- MDM : load_collaborateurs
-- Charge le référentiel des collaborateurs depuis raw_dia
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS mdm.load_collaborateurs//
CREATE PROCEDURE mdm.load_collaborateurs()
BEGIN
    SELECT '🔄 Chargement mdm.collaborateurs...' AS status;
    
    TRUNCATE TABLE mdm.collaborateurs;
    
    INSERT INTO mdm.collaborateurs (
        col_code_dia, email, nom, prenom,
        entite_valoxy, service, poste,
        date_entree, date_sortie
    )
    SELECT 
        c.COL_CODE AS col_code_dia,
        c.COL_EMAIL AS email,
        c.COL_NOM AS nom,
        c.COL_PRENOM AS prenom,
        s.SOC_NOM AS entite_valoxy,
        sv.SERV_LIBELLE AS service,
        f.FONC_LIBELLE AS poste,
        STR_TO_DATE(c.COL_DATE_ENTREE, '%Y%m%d') AS date_entree,
        CASE WHEN c.COL_DATE_SORTIE != '' 
             THEN STR_TO_DATE(c.COL_DATE_SORTIE, '%Y%m%d') 
             ELSE NULL 
        END AS date_sortie
    FROM raw_dia.collab c
    LEFT JOIN raw_dia.societe s ON s.SOC_CODE = c.SOC_CODE
    LEFT JOIN raw_dia.service sv ON sv.SERV_CODE = c.SERV_CODE
    LEFT JOIN raw_dia.fonction f ON f.FONC_CODE = c.FONC_CODE;
    
    SELECT CONCAT('✅ mdm.collaborateurs: ', ROW_COUNT(), ' lignes') AS status;
END//

-- ─────────────────────────────────────────────────────────────
-- MDM : load_contacts
-- Charge le référentiel des contacts depuis raw_dia
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS mdm.load_contacts//
CREATE PROCEDURE mdm.load_contacts()
BEGIN
    SELECT '🔄 Chargement mdm.contacts...' AS status;
    
    TRUNCATE TABLE mdm.contacts;
    
    INSERT INTO mdm.contacts (
        dossier_id, siren, cor_id_dia, nom, prenom, email, telephone, fonction
    )
    SELECT 
        d.id AS dossier_id,
        LEFT(a.ADR_SIRET, 9) AS siren,
        c.COR_ID AS cor_id_dia,
        c.COR_NOM AS nom,
        c.COR_PRENOM AS prenom,
        c.COR_EMAIL AS email,
        REPLACE(c.COR_TEL1, ' ', '') AS telephone,
        f.FONC_LIBELLE AS fonction
    FROM raw_dia.corresp c
    INNER JOIN raw_dia.adr_cor ac ON ac.COR_ID = c.COR_ID
    INNER JOIN raw_dia.adresse a ON a.ADR_ID = ac.ADR_ID
    LEFT JOIN raw_dia.fonction f ON f.FONC_CODE = ac.FONC_CODE
    LEFT JOIN mdm.dossiers d ON d.siren = LEFT(a.ADR_SIRET, 9)
    WHERE a.GENRE_CODE = 'CLI_EC'
      AND (a.ADR_DATE_SORTIE IS NULL OR a.ADR_DATE_SORTIE = '');
    
    SELECT CONCAT('✅ mdm.contacts: ', ROW_COUNT(), ' lignes') AS status;
END//

-- ─────────────────────────────────────────────────────────────
-- MDM : detect_services_from_compta
-- Détecte les services souscrits à partir des comptes de produits
-- Met à jour les flags has_* dans mdm.dossiers
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS mdm.detect_services_from_compta//
CREATE PROCEDURE mdm.detect_services_from_compta()
BEGIN
    SELECT '🔄 Détection des services depuis la comptabilité interne...' AS status;
    
    -- Cette procédure analyse les comptes de produits (706*) 
    -- dans la comptabilité interne Valoxy pour détecter les services souscrits
    -- TODO Phase 2 : Implémenter quand la comptabilité interne sera intégrée
    
    SELECT '⏳ detect_services_from_compta: À implémenter en Phase 2' AS status;
END//

-- ─────────────────────────────────────────────────────────────
-- MDM : run_all
-- Exécute toutes les procédures MDM dans l'ordre
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS mdm.run_all//
CREATE PROCEDURE mdm.run_all()
BEGIN
    SELECT '════════════════════════════════════════════════════════' AS sep;
    SELECT '🚀 DÉBUT CHARGEMENT MDM' AS status, NOW() AS datetime;
    SELECT '════════════════════════════════════════════════════════' AS sep;
    
    CALL mdm.load_dossiers();
    CALL mdm.load_collaborateurs();
    CALL mdm.load_contacts();
    
    SELECT '════════════════════════════════════════════════════════' AS sep;
    SELECT '✅ FIN CHARGEMENT MDM' AS status, NOW() AS datetime;
    SELECT '════════════════════════════════════════════════════════' AS sep;
END//

DELIMITER ;
