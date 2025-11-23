-- ============================================================
-- COUCHE MART : VUES MÉTIER POUR REPORTING
-- 3 sous-schémas :
--   - mart_pilotage_cabinet : pilotage stratégique
--   - mart_controle_gestion : tableaux de bord CDG  
--   - mart_production_client : livrables clients (vendus)
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- MART_PILOTAGE_CABINET
-- Vues pour le pilotage stratégique du cabinet
-- ════════════════════════════════════════════════════════════

USE mart_pilotage_cabinet;

-- ─────────────────────────────────────────────────────────────
-- VUE : v_clients_par_service
-- Matrice clients × services souscrits
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_clients_par_service AS
SELECT 
    d.id AS dossier_id,
    d.siren,
    d.code_dia,
    d.raison_sociale,
    d.entite_valoxy,
    d.directeur_comptable,
    d.chef_de_mission,
    d.collaborateur_comptable,
    d.actif,
    -- Services compta
    d.has_compta_acd,
    d.has_compta_pennylane,
    d.has_compta_tiime,
    (d.has_compta_acd OR d.has_compta_pennylane OR d.has_compta_tiime) AS has_compta,
    -- Services paye
    d.has_paye_silae,
    d.has_paye_openpaye,
    (d.has_paye_silae OR d.has_paye_openpaye) AS has_paye,
    -- Autres services
    d.has_juridique_polyacte AS has_juridique,
    d.has_audit_revisaudit AS has_audit,
    -- Comptage services
    (COALESCE(d.has_compta_acd, 0) + COALESCE(d.has_compta_pennylane, 0) + COALESCE(d.has_compta_tiime, 0) > 0) +
    (COALESCE(d.has_paye_silae, 0) + COALESCE(d.has_paye_openpaye, 0) > 0) +
    COALESCE(d.has_juridique_polyacte, 0) +
    COALESCE(d.has_audit_revisaudit, 0) AS nb_services
FROM mdm.dossiers d
WHERE d.actif = TRUE;

-- ─────────────────────────────────────────────────────────────
-- VUE : v_penetration_services
-- Taux de multi-équipement : % clients avec 1, 2, 3+ services
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_penetration_services AS
SELECT 
    nb_services,
    COUNT(*) AS nb_clients,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct_clients
FROM mart_pilotage_cabinet.v_clients_par_service
GROUP BY nb_services
ORDER BY nb_services;

-- ─────────────────────────────────────────────────────────────
-- VUE : v_portefeuille_collaborateur
-- Répartition des dossiers par collaborateur et service
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_portefeuille_collaborateur AS
SELECT 
    d.directeur_comptable,
    d.chef_de_mission,
    d.collaborateur_comptable,
    d.entite_valoxy,
    COUNT(*) AS nb_dossiers_total,
    SUM(CASE WHEN d.has_compta_acd OR d.has_compta_pennylane OR d.has_compta_tiime THEN 1 ELSE 0 END) AS nb_dossiers_compta,
    SUM(CASE WHEN d.has_paye_silae OR d.has_paye_openpaye THEN 1 ELSE 0 END) AS nb_dossiers_paye,
    SUM(CASE WHEN d.has_juridique_polyacte THEN 1 ELSE 0 END) AS nb_dossiers_juridique,
    SUM(CASE WHEN d.has_audit_revisaudit THEN 1 ELSE 0 END) AS nb_dossiers_audit
FROM mdm.dossiers d
WHERE d.actif = TRUE
GROUP BY 
    d.directeur_comptable,
    d.chef_de_mission,
    d.collaborateur_comptable,
    d.entite_valoxy;

-- ─────────────────────────────────────────────────────────────
-- VUE : v_entrees_sorties
-- Suivi des entrées/sorties de clients par période
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_entrees_sorties AS
SELECT 
    DATE_FORMAT(d.date_entree, '%Y-%m') AS mois,
    d.entite_valoxy,
    SUM(CASE WHEN d.date_sortie IS NULL THEN 1 ELSE 0 END) AS entrees,
    SUM(CASE WHEN d.date_sortie IS NOT NULL THEN 1 ELSE 0 END) AS sorties,
    SUM(CASE WHEN d.date_sortie IS NULL THEN 1 ELSE -1 END) AS solde_net
FROM mdm.dossiers d
WHERE d.date_entree IS NOT NULL
GROUP BY 
    DATE_FORMAT(d.date_entree, '%Y-%m'),
    d.entite_valoxy
ORDER BY mois DESC;

-- ─────────────────────────────────────────────────────────────
-- VUE : v_repartition_entites
-- Répartition des dossiers par entité Valoxy
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_repartition_entites AS
SELECT 
    d.entite_valoxy,
    COUNT(*) AS nb_dossiers,
    SUM(CASE WHEN d.has_compta_acd THEN 1 ELSE 0 END) AS nb_acd,
    SUM(CASE WHEN d.has_compta_pennylane THEN 1 ELSE 0 END) AS nb_pennylane,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct_total
FROM mdm.dossiers d
WHERE d.actif = TRUE
GROUP BY d.entite_valoxy
ORDER BY nb_dossiers DESC;

-- ════════════════════════════════════════════════════════════
-- MART_CONTROLE_GESTION
-- Vues pour les tableaux de bord du contrôle de gestion
-- ════════════════════════════════════════════════════════════

USE mart_controle_gestion;

-- ─────────────────────────────────────────────────────────────
-- VUE : v_company_ledger
-- Balance mensuelle unifiée ACD + Pennylane
-- Équivalent de ta vue company_ledger actuelle
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_company_ledger AS
SELECT 
    e.source AS Outil_Comptable,
    COALESCE(d.entite_valoxy, da.entite_valoxy, dp.entite_valoxy) AS Valoxy,
    e.code_dossier AS Code_Dossier,
    COALESCE(d.raison_sociale, da.nom, dp.name) AS Nom_Dossier,
    COALESCE(d.categorie_fiscale, da.categorie_fiscale, dp.categorie_fiscale) AS Categorie_Fiscale,
    COALESCE(d.regime_fiscal, da.regime_fiscal, dp.regime_fiscal) AS Regime_Fiscal,
    COALESCE(d.forme_juridique, da.forme_juridique, dp.forme_juridique) AS Forme_Legale,
    COALESCE(d.directeur_comptable, da.directeur_comptable, dp.directeur_comptable) AS Directeur_de_Mission,
    COALESCE(d.chef_de_mission, da.chef_de_mission, dp.chef_de_mission) AS Chef_de_Mission,
    COALESCE(d.collaborateur_comptable, da.collaborateur_comptable, dp.collaborateur_comptable) AS Comptable,
    e.period_month AS Periode,
    e.compte AS Compte,
    e.compte_libelle AS Compte_Label,
    e.journal_code AS Journal,
    e.journal_libelle AS Journal_Label,
    e.credits AS Credit,
    e.debits AS Debit,
    e.solde AS Balance_D_moins_C,
    e.nb_ecritures AS Nombre_Ecriture,
    e.date_derniere_saisie AS Derniere_Saisie
FROM transform_compta.ecritures_mensuelles e
LEFT JOIN mdm.dossiers d ON d.siren = e.siren AND e.siren IS NOT NULL AND e.siren != ''
LEFT JOIN transform_compta.dossiers_pennylane dp ON dp.name = e.code_dossier AND e.source = 'PENNYLANE'
LEFT JOIN transform_compta.dossiers_acd da ON da.code_dia = e.code_dossier AND e.source = 'ACD'
WHERE e.period_month > '2024-12-31';

-- ─────────────────────────────────────────────────────────────
-- VUE : v_tableau_bord_global
-- KPIs consolidés : nb dossiers actifs, heures produites
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_tableau_bord_global AS
SELECT 
    DATE_FORMAT(NOW(), '%Y-%m') AS periode_courante,
    (SELECT COUNT(*) FROM mdm.dossiers WHERE actif = TRUE) AS nb_dossiers_actifs,
    (SELECT COUNT(*) FROM mdm.dossiers WHERE actif = TRUE AND has_compta_acd) AS nb_dossiers_acd,
    (SELECT COUNT(*) FROM mdm.dossiers WHERE actif = TRUE AND has_compta_pennylane) AS nb_dossiers_pennylane,
    (SELECT SUM(duree_heures) FROM transform_compta.temps_collaborateurs 
     WHERE exercice_code = YEAR(CURDATE())) AS heures_produites_annee,
    (SELECT COUNT(DISTINCT code_dossier) FROM transform_compta.temps_collaborateurs 
     WHERE exercice_code = YEAR(CURDATE())) AS dossiers_avec_temps;

-- ─────────────────────────────────────────────────────────────
-- VUE : v_temps_par_dossier
-- Analyse des temps passés par dossier
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_temps_par_dossier AS
SELECT 
    t.code_dossier,
    d.raison_sociale,
    d.entite_valoxy,
    d.directeur_comptable,
    d.chef_de_mission,
    t.exercice_code,
    t.collab_service,
    SUM(t.duree_heures) AS total_heures,
    COUNT(DISTINCT CONCAT(t.collab_nom, '-', t.collab_prenom)) AS nb_collaborateurs,
    COUNT(*) AS nb_saisies
FROM transform_compta.temps_collaborateurs t
LEFT JOIN mdm.dossiers d ON d.code_dia = t.code_dossier
GROUP BY 
    t.code_dossier,
    d.raison_sociale,
    d.entite_valoxy,
    d.directeur_comptable,
    d.chef_de_mission,
    t.exercice_code,
    t.collab_service;

-- ─────────────────────────────────────────────────────────────
-- VUE : v_temps_par_collaborateur
-- Temps par collaborateur et service
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_temps_par_collaborateur AS
SELECT 
    t.collab_nom,
    t.collab_prenom,
    t.collab_societe AS entite_valoxy,
    t.collab_service,
    t.collab_poste,
    t.exercice_code,
    DATE_FORMAT(t.date_mission, '%Y-%m') AS mois,
    SUM(t.duree_heures) AS total_heures,
    COUNT(DISTINCT t.code_dossier) AS nb_dossiers
FROM transform_compta.temps_collaborateurs t
GROUP BY 
    t.collab_nom,
    t.collab_prenom,
    t.collab_societe,
    t.collab_service,
    t.collab_poste,
    t.exercice_code,
    DATE_FORMAT(t.date_mission, '%Y-%m');

-- ─────────────────────────────────────────────────────────────
-- VUE : v_exercices
-- Liste des exercices avec gestion des chevauchements ACD/Pennylane
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_exercices AS
SELECT 
    e.source,
    e.code_dossier,
    d.raison_sociale,
    d.entite_valoxy,
    e.exercice_code,
    e.date_debut,
    e.date_fin,
    e.date_cloture,
    CASE WHEN e.date_cloture IS NOT NULL THEN 'Clôturé' ELSE 'Ouvert' END AS statut,
    -- Flag si doublon potentiel (même SIREN, dates qui se chevauchent, sources différentes)
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM transform_compta.exercices e2 
            WHERE e2.siren = e.siren 
              AND e2.source != e.source
              AND e2.siren IS NOT NULL AND e2.siren != ''
              AND e2.date_debut <= e.date_fin 
              AND e2.date_fin >= e.date_debut
        ) THEN TRUE 
        ELSE FALSE 
    END AS doublon_potentiel
FROM transform_compta.exercices e
LEFT JOIN mdm.dossiers d ON d.siren = e.siren;

-- ════════════════════════════════════════════════════════════
-- MART_PRODUCTION_CLIENT
-- Vues destinées aux livrables clients (tableaux de bord vendus)
-- ════════════════════════════════════════════════════════════

USE mart_production_client;

-- ─────────────────────────────────────────────────────────────
-- VUE : v_tiers_detailles
-- Détail des comptes 401 (fournisseurs) et 411 (clients) normalisés
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_tiers_detailles AS
SELECT 
    t.source,
    t.code_dossier,
    d.raison_sociale,
    d.entite_valoxy,
    t.period_month,
    t.type_tiers,
    t.compte_origine,
    t.compte_normalise,
    t.compte_libelle,
    t.journal_code,
    t.journal_libelle,
    t.debits,
    t.credits,
    t.solde,
    t.nb_ecritures
FROM transform_compta.ecritures_tiers_detaillees t
LEFT JOIN mdm.dossiers d ON d.siren = t.siren;

-- ─────────────────────────────────────────────────────────────
-- VUE : v_tiers_agrege
-- Agrégation des comptes 401/411 par dossier et mois (Power BI)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_tiers_agrege AS
SELECT 
    t.source,
    t.code_dossier,
    d.raison_sociale,
    d.entite_valoxy,
    t.period_month,
    t.type_tiers,
    t.compte_normalise,
    SUM(t.debits) AS total_debits,
    SUM(t.credits) AS total_credits,
    SUM(t.solde) AS total_solde,
    SUM(t.nb_ecritures) AS total_ecritures
FROM transform_compta.ecritures_tiers_detaillees t
LEFT JOIN mdm.dossiers d ON d.siren = t.siren
GROUP BY 
    t.source,
    t.code_dossier,
    d.raison_sociale,
    d.entite_valoxy,
    t.period_month,
    t.type_tiers,
    t.compte_normalise;

-- ─────────────────────────────────────────────────────────────
-- VUE : v_evolution_ca
-- Évolution du CA par mois avec comparatif N-1
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_evolution_ca AS
SELECT 
    e.source,
    e.code_dossier,
    d.raison_sociale,
    d.entite_valoxy,
    e.period_month,
    YEAR(e.period_month) AS annee,
    MONTH(e.period_month) AS mois,
    SUM(CASE WHEN e.compte LIKE '7%' THEN e.credits - e.debits ELSE 0 END) AS ca_mois
FROM transform_compta.ecritures_mensuelles e
LEFT JOIN mdm.dossiers d ON d.siren = e.siren
WHERE e.compte LIKE '7%'
GROUP BY 
    e.source,
    e.code_dossier,
    d.raison_sociale,
    d.entite_valoxy,
    e.period_month;

-- ─────────────────────────────────────────────────────────────
-- VUE : v_top_clients_fournisseurs
-- Concentration clients/fournisseurs (top par montant)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_top_clients_fournisseurs AS
SELECT 
    t.source,
    t.code_dossier,
    d.raison_sociale AS dossier,
    d.entite_valoxy,
    t.type_tiers,
    t.compte_origine,
    t.compte_libelle AS tiers_libelle,
    SUM(ABS(t.solde)) AS montant_total,
    SUM(t.nb_ecritures) AS nb_mouvements
FROM transform_compta.ecritures_tiers_detaillees t
LEFT JOIN mdm.dossiers d ON d.siren = t.siren
WHERE t.period_month >= DATE_SUB(CURDATE(), INTERVAL 12 MONTH)
GROUP BY 
    t.source,
    t.code_dossier,
    d.raison_sociale,
    d.entite_valoxy,
    t.type_tiers,
    t.compte_origine,
    t.compte_libelle
ORDER BY montant_total DESC;

SELECT '✅ Vues MART créées avec succès !' AS status;
