# 📊 TPS Data Architecture - Documentation Claude

## 🎯 Vue d'ensemble du projet

Architecture data en 4 couches pour centraliser et analyser les données comptables de 3500+ dossiers clients.

### Sources de données
- **ACD/DIA** : 3500+ bases MySQL `compta_*` (serveur distant 192.168.20.24)
- **Pennylane** : Export Redshift (nouveau logiciel comptable)
- **DIA Valoxy** : Base locale pour données cabinet

### Architecture 4 couches

```
RAW (copies brutes) ← 🔧 EN COURS DE VALIDATION
├── raw_dia          : Données cabinet (collaborateurs, temps, exercices)
├── raw_acd          : 6 tables centralisées depuis compta_* (histo_*, ligne_*, ecriture, compte, journal)
└── raw_pennylane    : Export Redshift (pl_*, acc_*, etl_*, pm_*)

TRANSFORM (normalisation) ⚠️ NE PAS MODIFIER TANT QUE RAW N'EST PAS VALIDÉ
└── transform_compta
    ├── dossiers_acd, dossiers_pennylane
    ├── ecritures_mensuelles (C*/F* agrégés)
    ├── ecritures_tiers_detaillees (401/411 normalisés)
    ├── exercices, temps_collaborateurs
    └── 🎯 FUTUR : Containerisation pour tableaux de bord clients isolés

MDM (référentiel maître) ⚠️ NE PAS MODIFIER TANT QUE RAW N'EST PAS VALIDÉ
└── mdm
    ├── dossiers (jointure SIREN : ACD ↔ Pennylane ↔ Silae...)
    ├── collaborateurs, contacts
    ├── mapping_comptes_services
    └── 🎯 FUTUR : API backend pour synchronisation multi-outils

MART (vues métier) ⚠️ NE PAS MODIFIER TANT QUE RAW N'EST PAS VALIDÉ
├── mart_pilotage_cabinet    : 👥 Directeurs de mission, comptables
├── mart_controle_gestion    : 📊 Contrôleurs de gestion (interne/externe)
├── mart_production_client   : 📈 Clients (holdings, entreprises)
├── 🎯 FUTUR : mart_daf       : 💰 DAF - Pilotage financier cabinet
└── 🎯 FUTUR : mart_direction : 🎯 Dirigeants - Vision stratégique
```

---

## ⚠️ RÈGLE IMPORTANTE : Validation en cascade

**⛔ NE PAS TOUCHER AUX COUCHES TRANSFORM / MDM / MART**

Actuellement, nous sommes en phase de **validation de la couche RAW** :
- Import ACD centralisé (raw_acd) en cours de test et optimisation
- Import Pennylane (raw_pennylane) en cours de validation
- Import DIA (raw_dia) stable

**Les couches supérieures (TRANSFORM, MDM, MART) ne doivent pas être modifiées** tant que :
1. La couche RAW n'est pas validée et stable
2. Les imports incrémentaux ne sont pas testés
3. Les performances ne sont pas optimisées
4. Les mécanismes de tracking ne sont pas vérifiés

**Raison** : Les couches supérieures dépendent des données RAW. Toute modification dans TRANSFORM/MDM/MART serait à refaire si la structure RAW change.

---

## 🔧 Focus actuel : Couche RAW

### Import ACD centralisé (raw_acd) ⭐ EN COURS

**Problématique** : Avant, on clonait 3500+ bases complètes (50+ tables chacune) → stockage énorme et requêtes impossibles.

**Solution** : Import sélectif de 6 tables dans une base centralisée `raw_acd` avec colonne `dossier_code`.

**Tables importées** :
1. `histo_ligne_ecriture` - Lignes écritures historiques (partitionné par année)
2. `histo_ecriture` - En-têtes écritures historiques
3. `ligne_ecriture` - Lignes écritures courantes
4. `ecriture` - En-têtes écritures courantes
5. `compte` - Plan comptable
6. `journal` - Journaux

**Mécanisme** :
- Mode `--full` : TRUNCATE + réimport complet
- Mode `--incremental` : Import avec filtre `WHERE date > last_sync_date` + `ON DUPLICATE KEY UPDATE`
- Tracking via `sync_tracking` (last_sync_date, rows_count, duration)

**Performance** :
- Import séquentiel (machine source avec 1 CPU - pas de parallélisme possible)
- Compression MySQL : `--compress`
- Estimation : ~4-6h pour 3500 bases

**Points à valider** :
- ✅ Structure des tables (partitionnement, clés primaires)
- ✅ Mécanisme d'import full
- 🔄 Mécanisme d'import incrémental (à tester)
- 🔄 Performance (benchmark en cours)
- 🔄 Gestion des erreurs et reprises
- ❌ Tracking par dossier (à implémenter)

---

## 📁 Structure du projet

```
tps_get_data/
├── run_pipeline.sh              # Orchestrateur principal
├── bash/
│   ├── config.sh                # Configuration (gitignored, contient credentials)
│   ├── logging.sh               # Fonctions log uniformes
│   ├── raw/                     # Scripts d'import RAW ← 🔧 FOCUS ACTUEL
│   │   ├── 01_import_raw_dia.sh
│   │   ├── 02_import_raw_compta.sh      # Import ACD centralisé ⭐
│   │   ├── 02b_import_incremental_acd.sh
│   │   ├── 02c_cleanup_acd.sh
│   │   ├── 03_import_raw_pennylane.sh
│   │   └── run_all_raw.sh
│   ├── transform/               # ⚠️ NE PAS MODIFIER
│   ├── mdm/                     # ⚠️ NE PAS MODIFIER
│   ├── mart/                    # ⚠️ NE PAS MODIFIER
│   └── util/
│       ├── clean_all.sh         # Suppression complète de la BDD
│       └── benchmark_import_acd.sh  # Benchmark méthodes import
├── sql/
│   ├── 01_create_schemas.sql
│   ├── 02b_raw_acd_tables.sql   # Tables raw_acd avec partitionnement ⭐
│   ├── 02_raw_pennylane_tables.sql
│   ├── 03_transform_tables.sql  # ⚠️ NE PAS MODIFIER
│   ├── 04_mdm_tables.sql        # ⚠️ NE PAS MODIFIER
│   ├── 05_mart_views.sql        # ⚠️ NE PAS MODIFIER
│   ├── 06_procedures_transform_part1.sql  # ⚠️ NE PAS MODIFIER
│   ├── 06_procedures_transform_part2.sql  # ⚠️ NE PAS MODIFIER
│   ├── 07_procedures_mdm.sql    # ⚠️ NE PAS MODIFIER
│   └── 08_procedures_orchestrator.sql     # ⚠️ NE PAS MODIFIER
└── docs/
    ├── README.md                # Doc architecture générale
    └── README_raw_acd.md        # Doc spécifique raw_acd ⭐
```

---

## 🚀 Commandes principales (couche RAW uniquement)

### Initialisation
```bash
./run_pipeline.sh --init-only    # Créer schémas, tables, procédures
```

### Import RAW uniquement
```bash
./run_pipeline.sh --data-only              # Import RAW (DIA + ACD + Pennylane)
./run_pipeline.sh --data-only --acd-full   # Import RAW avec ACD complet
bash bash/raw/run_all_raw.sh               # Lancer tous les imports RAW
```

### Import ACD spécifique
```bash
bash bash/raw/02_import_raw_compta.sh --full         # Import complet
bash bash/raw/02_import_raw_compta.sh --incremental  # Import incrémental
bash bash/raw/02b_import_incremental_acd.sh          # Wrapper incrémental
```

### Nettoyage
```bash
bash bash/util/clean_all.sh              # Supprimer toutes les bases
bash bash/raw/02c_cleanup_acd.sh --full  # Vider raw_acd uniquement
bash bash/raw/02c_cleanup_acd.sh --stats # Afficher statistiques
```

### Benchmark
```bash
bash bash/util/benchmark_import_acd.sh   # Tester méthodes d'import sur 10 bases
```

---

## ⚠️ Points d'attention (couche RAW)

### Problèmes à résoudre avant validation

1. **Import ACD long (~4-6h pour 3500 bases)**
   - Source ACD avec 1 CPU (nproc=1) → pas de parallélisme possible
   - Solution actuelle : Import séquentiel optimisé avec barre de progression
   - À tester : Benchmark pour confirmer les performances

2. **Horodatage global vs par dossier**
   - Actuellement : `last_sync_date` mise à jour en fin d'import
   - Problème : Si import dure 4h, les premières bases peuvent être modifiées pendant le traitement
   - Solution à implémenter : Colonne `dossier_code` dans `sync_tracking`

3. **Vérification mécanisme incrémental**
   - Filtre `WHERE date > last_sync_date` : est-ce strict ou inclusif ?
   - ON DUPLICATE KEY UPDATE : fonctionne correctement ?
   - Gestion des suppressions : pas de soft delete

4. **Gestion des erreurs**
   - Pas de système de checkpoint/reprise
   - Si une base échoue, le script continue mais pas de rollback

### Bonnes pratiques

- **Toujours vérifier la connexion** avant lancement (`SELECT 1`)
- **Monitorer l'espace disque** avant un `--full`
- **Vérifier sync_tracking** après chaque import
- **Tester sur 10 bases** avant de lancer sur 3500

---

## 🔍 Requêtes utiles (couche RAW)

### Vérifier l'état de raw_acd
```sql
-- Derniers imports
SELECT * FROM raw_acd.sync_tracking;

-- Nombre de dossiers centralisés
SELECT COUNT(DISTINCT dossier_code) FROM raw_acd.histo_ligne_ecriture;

-- Volumétrie par table
SELECT
    table_name,
    FORMAT(rows_count, 0) as nb_lignes,
    last_sync_type as mode,
    DATE_FORMAT(last_sync_date, '%Y-%m-%d %H:%i') as derniere_synchro
FROM raw_acd.sync_tracking
ORDER BY table_name;

-- Taille des données
SELECT
    table_name,
    CONCAT(ROUND(data_length / 1024 / 1024, 2), ' MB') AS donnees,
    CONCAT(ROUND(index_length / 1024 / 1024, 2), ' MB') AS index,
    CONCAT(ROUND((data_length + index_length) / 1024 / 1024, 2), ' MB') AS total
FROM information_schema.tables
WHERE table_schema = 'raw_acd'
ORDER BY (data_length + index_length) DESC;
```

### Vérifier la qualité des données
```sql
-- Dossiers avec des données
SELECT
    dossier_code,
    COUNT(*) as nb_ecritures
FROM raw_acd.histo_ligne_ecriture
GROUP BY dossier_code
ORDER BY nb_ecritures DESC
LIMIT 20;

-- Années présentes
SELECT
    HE_ANNEE as annee,
    COUNT(*) as nb_lignes
FROM raw_acd.histo_ligne_ecriture
GROUP BY HE_ANNEE
ORDER BY HE_ANNEE;
```

---

## 🎯 Roadmap (après validation RAW)

### Phase 1 : Stabilisation RAW (EN COURS)
- ✅ Import ACD centralisé (raw_acd)
- 🔄 Validation import incrémental
- 🔄 Optimisation performances
- ⏳ Tests sur 3500 bases

### Phase 2 : Adaptation TRANSFORM
1. **Adapter les procédures** pour utiliser raw_acd au lieu de boucler sur compta_*
2. **Tester les agrégations** ecritures_mensuelles
3. **Valider la qualité** des données transformées

### Phase 3 : Enrichissement MDM
1. **Déduplication SIREN** (gestion des doublons)
2. **Jointure multi-sources** : ACD ↔ Pennylane ↔ Silae
3. **API backend** pour synchronisation des entités (collaborateurs, dossiers)
4. **Gestion des droits** : qui peut créer/modifier quoi dans quel outil

### Phase 4 : Vues MART par profil utilisateur

#### MART Comptables (mart_pilotage_cabinet)
**Directeurs de mission** :
- Vue globale sur leur service (6-8 comptables)
- Répartition de la charge par collaborateur
- Suivi des deadlines et retards
- KPI par comptable (nb dossiers, temps passé, CA généré)

**Comptables** :
- Vue portefeuille multi-outils (ACD, Pennylane, Silae)
- Liste des dossiers à traiter (priorisation)
- Temps passé vs budgété
- Alertes et notifications

#### MART Contrôle de gestion (mart_controle_gestion)
**Missions internes** :
- Analyse des charges par service
- Rentabilité par dossier/client
- Temps passés vs facturation
- Écarts budgétaires

**Missions externes** :
- Tableaux de bord pour missions chez clients
- Analyse financière multi-exercices
- Ratios et indicateurs métier
- Comparaisons sectorielles

#### MART DAF (🎯 FUTUR : mart_daf)
- Pilotage financier du cabinet
- CA par service/collaborateur/client
- Charges de personnel (global, sans détail individuel)
- Trésorerie et prévisions
- Rentabilité globale

#### MART Direction (🎯 FUTUR : mart_direction)
**Dirigeants** :
- Vision stratégique
- KPI cabinet (nb clients, CA, marge)
- Évolution du portefeuille
- Pénétration services (multi-équipement clients)
- Indicateurs RH (hors salaires individuels)

### Phase 5 : Containerisation TRANSFORM
1. **Isolation par client** : 1 container = 1 client/holding
2. **Réplication partielle** : Uniquement les données nécessaires
3. **Interface graphique** dédiée par client
4. **Sécurité** : Données anonymisées et cloisonnées

### Phase 6 : Intégration sources futures
- Silae (paie)
- Tiime (comptabilité TPE)
- OpenPaye (gestion paie)
- PolyActe (juridique)
- RevisAudit (révision CAC)

---

**⚠️ Mais pour l'instant : FOCUS sur RAW uniquement**

---

## 📞 Support

- **Logs** : `logs/pipeline_YYYYMMDD_HHMMSS.log`
- **Git** : https://github.com/jharjharbink/tps_get_data
- **Doc ACD** : README_raw_acd.md
