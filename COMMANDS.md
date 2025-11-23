# 🎮 GUIDE DES COMMANDES - Data Pipeline

Guide complet de toutes les commandes disponibles pour gérer votre pipeline de données.

---

## 📋 Table des matières

1. [Clean complet de la BDD](#1-clean-complet-de-la-bdd)
2. [Clean import ACD](#2-clean-import-acd)
3. [Clean import Pennylane](#3-clean-import-pennylane)
4. [Import TOUT (DIA + ACD + Pennylane)](#4-import-tout)
5. [Import DIA uniquement](#5-import-dia-uniquement)
6. [Import Pennylane uniquement](#6-import-pennylane-uniquement)
7. [Import ACD depuis une date](#7-import-acd-depuis-une-date)
8. [Import Pennylane depuis une date](#8-import-pennylane-depuis-une-date)
9. [Import incrémental (dernier import)](#9-import-incrémental-depuis-le-dernier-import)

---

## 1. Clean complet de la BDD

**Supprime TOUT:** raw_dia, raw_pennylane, raw_acd, anciennes compta_*, transform, mdm, mart

```bash
bash bash/util/clean_all.sh
```

⚠️ **ATTENTION:** Nécessite confirmation `oui` (pas `yes` ou `y`)

**Ce qui est supprimé:**
- ✅ raw_dia
- ✅ raw_pennylane
- ✅ raw_acd
- ✅ Toutes les anciennes bases compta_* (si présentes)
- ✅ transform_compta
- ✅ mdm
- ✅ mart_pilotage_cabinet
- ✅ mart_controle_gestion
- ✅ mart_production_client

---

## 2. Clean import ACD

### 2.1 Vider complètement raw_acd

```bash
bash bash/raw/02c_cleanup_acd.sh --full
```

⚠️ Nécessite confirmation: Tapez `DELETE ALL`

### 2.2 Supprimer un dossier spécifique

```bash
bash bash/raw/02c_cleanup_acd.sh --dossier 00123
```

### 2.3 Supprimer une année

```bash
bash bash/raw/02c_cleanup_acd.sh --year 2020
```

### 2.4 Supprimer avant une date

```bash
bash bash/raw/02c_cleanup_acd.sh --before 2022-01-01
```

### 2.5 Optimiser les tables (récupérer espace)

```bash
bash bash/raw/02c_cleanup_acd.sh --optimize
```

### 2.6 Afficher les statistiques

```bash
bash bash/raw/02c_cleanup_acd.sh --stats
```

---

## 3. Clean import Pennylane

### 3.1 Vider toutes les tables raw_pennylane

```bash
bash bash/raw/03b_cleanup_pennylane.sh --truncate
```

⚠️ Nécessite confirmation: `y` ou `Y`

### 3.2 Supprimer complètement le schéma

```bash
bash bash/raw/03b_cleanup_pennylane.sh --drop
```

⚠️ Nécessite confirmation: Tapez `DELETE`

### 3.3 Afficher les statistiques

```bash
bash bash/raw/03b_cleanup_pennylane.sh --stats
```

---

## 4. Import TOUT

### 4.1 Import complet FULL (TRUNCATE + réimport)

```bash
# Pipeline complet avec import full de ACD
./run_pipeline.sh

# ou explicitement
./run_pipeline.sh --acd-full
```

**Ce qui est fait:**
1. ✅ Création des schémas/tables (si --skip-init non spécifié)
2. ✅ Import raw_dia (TRUNCATE + réimport)
3. ✅ Import raw_acd (TRUNCATE + réimport de 3500 bases)
4. ✅ Import raw_pennylane (TRUNCATE + export Redshift)
5. ✅ Couches TRANSFORM, MDM, MART

⏱️ **Durée:** ~60-90 minutes

### 4.2 Import complet INCREMENTAL

```bash
./run_pipeline.sh --acd-incremental
```

**Ce qui est fait:**
1. Import raw_dia (full)
2. Import raw_acd (incrémental depuis last_sync_date)
3. Import raw_pennylane (full)
4. Couches TRANSFORM, MDM, MART

⏱️ **Durée:** ~20-30 minutes

### 4.3 Import SANS recréer les tables

```bash
./run_pipeline.sh --data-only

# Avec ACD incrémental
./run_pipeline.sh --data-only --acd-incremental
```

---

## 5. Import DIA uniquement

```bash
bash bash/raw/01_import_raw_dia.sh
```

**Ce qui est fait:**
- Export depuis valoxy (serveur DIA_HOST)
- TRUNCATE raw_dia
- Import toutes les tables (sauf doc*, blob*, test*, tmp*, web*, email_log)

⏱️ **Durée:** ~2-5 minutes

---

## 6. Import Pennylane uniquement

### 6.1 Import FULL (réimport complet)

```bash
bash bash/raw/03_import_raw_pennylane.sh --full

# ou sans argument (full par défaut)
bash bash/raw/03_import_raw_pennylane.sh
```

**Ce qui est fait:**
1. Export depuis Redshift
2. TRUNCATE toutes les tables
3. Import pl_companies, pl_fiscal_years, pl_general_ledger, acc_companies_identification

⏱️ **Durée:** ~10-20 minutes (selon taille du general_ledger)

### 6.2 Import INCREMENTAL (depuis dernier import)

```bash
bash bash/raw/03_import_raw_pennylane.sh --incremental
```

**Ce qui est fait:**
1. Lit `last_sync_date` depuis `raw_pennylane.sync_tracking`
2. Exporte uniquement les lignes modifiées depuis cette date
3. REPLACE INTO (gère les doublons)
4. Met à jour sync_tracking

⏱️ **Durée:** ~2-5 minutes

### 6.3 Import depuis une date spécifique

```bash
bash bash/raw/03_import_raw_pennylane.sh --since "01/01/2025 00:00:00"
```

**Format de date:** `"DD/MM/YYYY HH:MM:SS"` (entre guillemets)

**Exemples:**
```bash
# Depuis le 1er janvier 2025
bash bash/raw/03_import_raw_pennylane.sh --since "01/01/2025 00:00:00"

# Depuis le 15 juin 2025 à 10h30
bash bash/raw/03_import_raw_pennylane.sh --since "15/06/2025 10:30:00"

# Depuis hier 00h00 (adapter la date)
bash bash/raw/03_import_raw_pennylane.sh --since "22/11/2025 00:00:00"
```

---

## 7. Import ACD depuis une date

### 7.1 Import FULL (réimport complet)

```bash
bash bash/raw/02_import_raw_compta.sh --full

# ou sans argument (full par défaut)
bash bash/raw/02_import_raw_compta.sh
```

**Ce qui est fait:**
1. Vérifie que les 6 tables requises existent dans chaque base compta_*
2. TRUNCATE raw_acd
3. Import parallèle (3 jobs) de toutes les bases éligibles
4. Ajout automatique de la colonne `dossier_code`

⏱️ **Durée:** ~45-60 minutes (3500 bases)

### 7.2 Import INCREMENTAL (depuis dernier import)

```bash
bash bash/raw/02_import_raw_compta.sh --incremental

# ou via le wrapper
bash bash/raw/02b_import_incremental_acd.sh
```

**Ce qui est fait:**
1. Lit `last_sync_date` depuis `raw_acd.sync_tracking`
2. Import uniquement lignes avec `HE_DATE_SAI` > last_sync_date
3. ON DUPLICATE KEY UPDATE (gère les doublons)
4. Met à jour sync_tracking

⏱️ **Durée:** ~5-10 minutes

### 7.3 Import depuis une date spécifique

```bash
bash bash/raw/02_import_raw_compta.sh --since "01/01/2025 00:00:00"
```

**Format de date:** `"DD/MM/YYYY HH:MM:SS"` (entre guillemets)

**Exemples:**
```bash
# Depuis le 1er janvier 2025
bash bash/raw/02_import_raw_compta.sh --since "01/01/2025 00:00:00"

# Depuis le 15 novembre 2025 à 14h30
bash bash/raw/02_import_raw_compta.sh --since "15/11/2025 14:30:00"

# Depuis hier (adapter la date)
bash bash/raw/02_import_raw_compta.sh --since "22/11/2025 00:00:00"
```

### 7.4 Augmenter le parallélisme

```bash
# 5 jobs simultanés au lieu de 3
bash bash/raw/02_import_raw_compta.sh --full --jobs 5

# Incrémental avec 8 jobs
bash bash/raw/02_import_raw_compta.sh --incremental --jobs 8

# Depuis date avec 10 jobs
bash bash/raw/02_import_raw_compta.sh --since "01/01/2025 00:00:00" --jobs 10
```

---

## 8. Import Pennylane depuis une date

```bash
bash bash/raw/03_import_raw_pennylane.sh --since "01/01/2025 00:00:00"
```

**Format de date:** `"DD/MM/YYYY HH:MM:SS"` (entre guillemets)

**Exemples:**
```bash
# Depuis le 1er novembre 2025
bash bash/raw/03_import_raw_pennylane.sh --since "01/11/2025 00:00:00"

# Depuis le 20 octobre 2025 à 15h00
bash bash/raw/03_import_raw_pennylane.sh --since "20/10/2025 15:00:00"
```

**Ce qui est fait:**
1. Exporte depuis Redshift avec filtre `WHERE updated_at >= 'DATE'`
2. REPLACE INTO (gère les doublons)
3. Met à jour sync_tracking

---

## 9. Import incrémental (depuis le dernier import)

### 9.1 Import ACD incrémental

```bash
# Via le wrapper (recommandé)
bash bash/raw/02b_import_incremental_acd.sh

# ou directement
bash bash/raw/02_import_raw_compta.sh --incremental
```

**Automatiquement:**
- Lit `raw_acd.sync_tracking.last_sync_date`
- Import uniquement les données modifiées depuis cette date
- Met à jour le timestamp après import réussi

### 9.2 Import Pennylane incrémental

```bash
bash bash/raw/03_import_raw_pennylane.sh --incremental
```

**Automatiquement:**
- Lit `raw_pennylane.sync_tracking.last_sync_date`
- Exporte uniquement les données modifiées depuis cette date
- Met à jour le timestamp après import réussi

### 9.3 Import TOUT en incrémental

```bash
./run_pipeline.sh --acd-incremental
```

**Ce qui est fait:**
1. raw_dia: FULL (toujours)
2. raw_acd: INCREMENTAL (depuis last_sync_date)
3. raw_pennylane: FULL (pas encore d'intégration dans le pipeline)
4. Couches TRANSFORM, MDM, MART

---

## 🔍 Vérifier l'état des imports

### Statistiques raw_acd

```bash
bash bash/raw/02c_cleanup_acd.sh --stats
```

**Affiche:**
- Nombre de lignes par table
- Taille des données et index
- Dernière synchronisation
- Durée du dernier import
- Nombre de dossiers centralisés

### Statistiques raw_pennylane

```bash
bash bash/raw/03b_cleanup_pennylane.sh --stats
```

**Affiche:**
- Nombre de lignes par table
- Taille des données et index
- Historique des imports

### Vérifier manuellement les timestamps

```sql
-- ACD
SELECT * FROM raw_acd.sync_tracking;

-- Pennylane
SELECT * FROM raw_pennylane.sync_tracking;
```

---

## ⚡ Commandes rapides quotidiennes

### Import quotidien recommandé

```bash
# Import incrémental ACD + Pennylane + pipeline complet
./run_pipeline.sh --acd-incremental
```

⏱️ **Durée:** ~20-30 minutes

### Import hebdomadaire recommandé (dimanche)

```bash
# Import complet (TRUNCATE + réimport)
./run_pipeline.sh --acd-full
```

⏱️ **Durée:** ~60-90 minutes

---

## 🔧 Commandes de maintenance

### Optimiser raw_acd après suppression

```bash
bash bash/raw/02c_cleanup_acd.sh --optimize
```

### Nettoyer les anciennes années

```bash
bash bash/raw/02c_cleanup_acd.sh --year 2019
bash bash/raw/02c_cleanup_acd.sh --year 2020
bash bash/raw/02c_cleanup_acd.sh --optimize
```

### Réinitialiser complètement

```bash
# 1. Clean complet
bash bash/util/clean_all.sh

# 2. Recréer les schémas
./run_pipeline.sh --init-only

# 3. Import full
./run_pipeline.sh --acd-full
```

---

## 📊 Format de date

**IMPORTANT:** Le format de date attendu est **`"DD/MM/YYYY HH:MM:SS"`**

### Exemples valides

```bash
"23/11/2025 13:32:43"   # ✅ Format correct
"01/01/2025 00:00:00"   # ✅ Minuit le 1er janvier
"15/06/2025 10:30:00"   # ✅ 15 juin à 10h30
```

### Exemples invalides

```bash
"2025-11-23 13:32:43"   # ❌ Format MySQL (sera converti automatiquement en interne)
"23/11/2025"            # ❌ Manque l'heure
"23-11-2025 13:32:43"   # ❌ Mauvais séparateur
```

---

## ⚙️ Automatisation (cron)

### Import quotidien à 2h00

```cron
0 2 * * * cd /path/to/tps_get_data && ./run_pipeline.sh --acd-incremental 2>&1 | logger -t data_pipeline
```

### Import complet hebdomadaire (dimanche 1h00)

```cron
0 1 * * 0 cd /path/to/tps_get_data && ./run_pipeline.sh --acd-full 2>&1 | logger -t data_pipeline
```

### Import Pennylane seul (toutes les 6h)

```cron
0 */6 * * * cd /path/to/tps_get_data && bash bash/raw/03_import_raw_pennylane.sh --incremental 2>&1 | logger -t pennylane
```

---

## 📝 Logs

Les logs sont disponibles dans :
```
logs/pipeline_YYYYMMDD.log
```

Rotation automatique : conservation de 30 jours

---

## 🆘 Aide

Pour afficher l'aide de chaque script :

```bash
bash bash/raw/02_import_raw_compta.sh --help
bash bash/raw/03_import_raw_pennylane.sh --help
./run_pipeline.sh --help
```

---

## 📞 Support

En cas de problème :

1. Vérifier les logs : `tail -f logs/pipeline_*.log`
2. Vérifier les stats : `bash bash/raw/02c_cleanup_acd.sh --stats`
3. Vérifier les timestamps : `SELECT * FROM raw_acd.sync_tracking;`
4. Relancer en mode full si données incohérentes
