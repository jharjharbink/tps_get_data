-- ============================================================
-- PROCÉDURES ORCHESTRATEUR : COUCHE TRANSFORM
-- Exécution séquentielle de toutes les procédures TRANSFORM
-- ============================================================

DELIMITER //

-- ─────────────────────────────────────────────────────────────
-- TRANSFORM : run_all
-- Exécute toutes les procédures TRANSFORM dans l'ordre
-- ─────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS transform_compta.run_all//
CREATE PROCEDURE transform_compta.run_all()
BEGIN
    DECLARE v_start DATETIME;
    DECLARE v_end DATETIME;
    
    SET v_start = NOW();
    
    SELECT '════════════════════════════════════════════════════════' AS sep;
    SELECT '🚀 DÉBUT CHARGEMENT TRANSFORM' AS status, v_start AS datetime;
    SELECT '════════════════════════════════════════════════════════' AS sep;
    
    -- 1. Dossiers (référentiels)
    SELECT '──────────────────────────────────────────────────────' AS sep;
    SELECT '📁 Étape 1/6 : Dossiers' AS etape;
    CALL transform_compta.load_dossiers_acd();
    CALL transform_compta.load_dossiers_pennylane();
    
    -- 2. Écritures agrégées
    SELECT '──────────────────────────────────────────────────────' AS sep;
    SELECT '📊 Étape 2/6 : Écritures agrégées ACD' AS etape;
    CALL transform_compta.load_ecritures_acd();
    
    SELECT '──────────────────────────────────────────────────────' AS sep;
    SELECT '📊 Étape 3/6 : Écritures agrégées Pennylane' AS etape;
    CALL transform_compta.load_ecritures_pennylane();
    
    -- 3. Tiers détaillés
    SELECT '──────────────────────────────────────────────────────' AS sep;
    SELECT '👥 Étape 4/6 : Tiers détaillés ACD' AS etape;
    CALL transform_compta.load_ecritures_tiers_acd();
    
    SELECT '──────────────────────────────────────────────────────' AS sep;
    SELECT '👥 Étape 5/6 : Tiers détaillés Pennylane' AS etape;
    CALL transform_compta.load_ecritures_tiers_pennylane();
    
    -- 4. Exercices et temps
    SELECT '──────────────────────────────────────────────────────' AS sep;
    SELECT '📅 Étape 6/6 : Exercices et Temps' AS etape;
    CALL transform_compta.load_exercices();
    CALL transform_compta.load_temps_collaborateurs();
    
    SET v_end = NOW();
    
    SELECT '════════════════════════════════════════════════════════' AS sep;
    SELECT '✅ FIN CHARGEMENT TRANSFORM' AS status, 
           v_end AS datetime,
           TIMEDIFF(v_end, v_start) AS duree;
    SELECT '════════════════════════════════════════════════════════' AS sep;
    
    -- Résumé des volumes
    SELECT 
        (SELECT COUNT(*) FROM transform_compta.dossiers_acd) AS dossiers_acd,
        (SELECT COUNT(*) FROM transform_compta.dossiers_pennylane) AS dossiers_pennylane,
        (SELECT COUNT(*) FROM transform_compta.ecritures_mensuelles) AS ecritures_mensuelles,
        (SELECT COUNT(*) FROM transform_compta.ecritures_tiers_detaillees) AS ecritures_tiers,
        (SELECT COUNT(*) FROM transform_compta.exercices) AS exercices,
        (SELECT COUNT(*) FROM transform_compta.temps_collaborateurs) AS temps_collab;
END//

DELIMITER ;
