# 📊 TPS Data Architecture

Architecture data en 4 couches pour centraliser et analyser les données comptables de 3500+ dossiers clients.

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![MySQL](https://img.shields.io/badge/MySQL-8.0%2B-blue.svg)](https://www.mysql.com/)
[![Bash](https://img.shields.io/badge/Bash-5.0%2B-green.svg)](https://www.gnu.org/software/bash/)

---

## 🎯 Vue d'ensemble

Pipeline ETL 4 couches pour centraliser les données de 3500+ dossiers comptables depuis ACD, Pennylane et DIA Valoxy.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ RAW (copies brutes)                   🔧 EN COURS          │
├─────────────────────────────────────────────────────────────┤
│  ├── raw_dia         : Données cabinet (temps, exercices)  │
│  ├── raw_acd         : 6 tables centralisées (3500 bases)  │
│  └── raw_pennylane   : Export Redshift                     │
└─────────────────────────────────────────────────────────────┘
                            ⬇
┌─────────────────────────────────────────────────────────────┐
│ TRANSFORM (normalisation)             ⚠️ NE PAS MODIFIER   │
├─────────────────────────────────────────────────────────────┤
│  └── transform_compta                                       │
│       ├── dossiers_acd, dossiers_pennylane                 │
│       ├── ecritures_mensuelles (C*/F* agrégés)             │
│       ├── ecritures_tiers_detaillees (401/411)             │
│       └── exercices, temps_collaborateurs                  │
└─────────────────────────────────────────────────────────────┘
                            ⬇
┌─────────────────────────────────────────────────────────────┐
│ MDM (référentiel maître)              ⚠️ NE PAS MODIFIER   │
├─────────────────────────────────────────────────────────────┤
│  └── mdm                                                    │
│       ├── dossiers (jointure SIREN)                        │
│       ├── collaborateurs, contacts                         │
│       └── mapping_comptes_services                         │
└─────────────────────────────────────────────────────────────┘
                            ⬇
┌─────────────────────────────────────────────────────────────┐
│ MART (vues métier)                    ⚠️ NE PAS MODIFIER   │
├─────────────────────────────────────────────────────────────┤
│  ├── mart_pilotage_cabinet    : Directeurs, comptables    │
│  ├── mart_controle_gestion    : Contrôleurs de gestion    │
│  └── mart_production_client   : Clients (holdings)        │
└─────────────────────────────────────────────────────────────┘
```

### Sources de données

- **ACD/DIA** : 3500+ bases MySQL `compta_*` (serveur distant)
- **Pennylane** : Export Redshift (nouveau logiciel comptable)
- **DIA Valoxy** : Base locale pour données cabinet

---

## ⚠️ Règle importante

**⛔ NE PAS TOUCHER AUX COUCHES TRANSFORM / MDM / MART**

Actuellement en phase de **validation de la couche RAW** :
- Import ACD centralisé (raw_acd) en cours de test
- Import Pennylane en cours de validation
- Les couches supérieures ne doivent pas être modifiées tant que RAW n'est pas stable

---

## 🚀 Démarrage rapide

### Prérequis

```bash
# MySQL 8.0+
mysql --version

# Bash 5.0+
bash --version

# Outils requis
which mysqldump
which xargs
```

### Configuration

1. **Copier le fichier de configuration :**

```bash
cp bash/config.sh.example bash/config.sh
```

2. **Éditer bash/config.sh avec vos credentials :**

```bash
# Connexion ACD (serveur distant)
ACD_HOST="<IP_SERVEUR>"
ACD_PORT=3306
ACD_USER="<USER>"
ACD_PASS="<PASSWORD>"

# Connexion MySQL locale
LOCAL_USER="root"
LOCAL_PASS="<PASSWORD>"
```

⚠️ **Ce fichier est dans .gitignore** (ne jamais le commiter)

### Installation

```bash
# 1. Créer les schémas et tables
./run_pipeline.sh --init-only

# 2. Importer les données RAW (première fois)
./run_pipeline.sh --data-only --acd-full

# 3. Vérifier l'import
mysql -u root -p -e "SELECT COUNT(DISTINCT dossier_code) FROM raw_acd.histo_ligne_ecriture"
```

---

## 📚 Documentation

- **[COMMANDS.md](COMMANDS.md)** - Guide complet de toutes les commandes
- **[README_raw_acd.md](README_raw_acd.md)** - Documentation détaillée de l'import ACD
- **[claude.md](claude.md)** - Documentation projet et vision stratégique

---

## 🔧 Commandes principales

### Import RAW complet

```bash
# Import full (TRUNCATE + réimport 3500 bases)
./run_pipeline.sh --acd-full
# Durée: ~60-90 minutes

# Import incrémental (nouveautés uniquement)
./run_pipeline.sh --acd-incremental
# Durée: ~20-30 minutes
```

### Import RAW uniquement (sans TRANSFORM/MDM/MART)

```bash
# Import RAW avec ACD full
./run_pipeline.sh --data-only --acd-full

# Import RAW avec ACD incrémental
./run_pipeline.sh --data-only --acd-incremental
```

### Import ACD spécifique

```bash
# Import complet (TRUNCATE + 3500 bases)
bash bash/raw/02_import_raw_compta.sh --full

# Import incrémental (depuis last_sync_date)
bash bash/raw/02_import_raw_compta.sh --incremental

# Import depuis une date spécifique
bash bash/raw/02_import_raw_compta.sh --since "01/01/2025 00:00:00"
```

### Nettoyage

```bash
# Supprimer TOUTES les bases
bash bash/util/clean_all.sh

# Vider uniquement raw_acd
bash bash/raw/02c_cleanup_acd.sh --full

# Afficher les statistiques
bash bash/raw/02c_cleanup_acd.sh --stats
```

### Benchmark

```bash
# Tester les performances d'import sur 10 bases
bash bash/util/benchmark_import_acd.sh
```

**Résultat** : ✅ Méthode 1 (INSERT SELECT sans batching) est la plus rapide - **implémentée dans le script actuel**

---

## 👨‍💻 Guide Admin Système - Cas d'usage

### 🚀 Première installation

```bash
# 1. Cloner le projet
git clone https://github.com/jharjharbink/tps_get_data.git
cd tps_get_data

# 2. Configurer les credentials (créer bash/config.sh)
cp bash/config.sh.example bash/config.sh
nano bash/config.sh  # Adapter les credentials MySQL et ACD

# 3. Créer les schémas et tables
./run_pipeline.sh --init-only

# 4. Premier import complet
./run_pipeline.sh --data-only --acd-full
```

**Durée estimée** : ~4-6h pour 3500 bases ACD

---

### 🔄 Import quotidien automatique (cron)

**Recommandation** : Import incrémental tous les jours à 2h00

```bash
# Ajouter au crontab
crontab -e

# Ligne à ajouter :
0 2 * * * cd /chemin/vers/tps_get_data && ./run_pipeline.sh --skip-init --acd-incremental >> logs/cron.log 2>&1
```

**Avantages** :
- ✅ Rapide (quelques minutes au lieu de 4-6h)
- ✅ Capture uniquement les nouveautés depuis `last_sync_date`
- ✅ Pas de TRUNCATE, utilise `ON DUPLICATE KEY UPDATE`

**Limitations** :
- ⚠️ Les modifications d'écritures existantes ne sont pas capturées (seules les nouvelles)
- 💡 Solution : Import `--full` hebdomadaire le dimanche

---

### 🔧 Réimport complet hebdomadaire

**Recommandation** : Import complet tous les dimanches à 1h00

```bash
# Cron hebdomadaire
0 1 * * 0 cd /chemin/vers/tps_get_data && bash bash/util/clean_all.sh <<< "oui" && ./run_pipeline.sh --acd-full >> logs/cron_weekly.log 2>&1
```

**Cas d'usage** :
- Capturer les modifications d'écritures existantes
- Nettoyer d'éventuelles incohérences
- Reconstruire les partitions de manière propre

---

### 🚨 Gestion d'incidents

#### Incident 1 : Import planté à mi-parcours

```bash
# Vérifier l'état
mysql -u root -p -e "SELECT * FROM raw_acd.sync_tracking;"

# Option A : Reprendre l'import (si tables OK)
./run_pipeline.sh --skip-init --acd-full

# Option B : Tout recréer (si corruption)
bash bash/util/clean_all.sh
./run_pipeline.sh --acd-full
```

---

#### Incident 2 : Base ACD source inaccessible

```bash
# Test de connexion
mysql -h $ACD_HOST -P $ACD_PORT -u $ACD_USER -p$ACD_PASS -e "SELECT 1"

# Import RAW uniquement depuis sources accessibles (DIA + Pennylane)
bash bash/raw/01_import_raw_dia.sh
bash bash/raw/03_import_raw_pennylane.sh

# Rebuild TRANSFORM/MDM/MART avec données existantes
./run_pipeline.sh --skip-raw
```

---

#### Incident 3 : Données corrompues dans TRANSFORM/MDM

```bash
# Recréer uniquement les couches analytiques (sans retoucher RAW)
./run_pipeline.sh --skip-raw --skip-init

# Ou rebuild spécifique
./run_pipeline.sh --transform-only
./run_pipeline.sh --mdm-only
```

---

### 🐛 Debug et troubleshooting

#### Vérifier l'état des imports

```sql
-- État de raw_acd
SELECT
    table_name,
    FORMAT(rows_count, 0) as lignes,
    last_sync_type as mode,
    DATE_FORMAT(last_sync_date, '%Y-%m-%d %H:%i') as derniere_synchro,
    last_status,
    last_duration_sec
FROM raw_acd.sync_tracking
ORDER BY table_name;

-- Nombre de dossiers centralisés
SELECT COUNT(DISTINCT dossier_code) FROM raw_acd.histo_ligne_ecriture;

-- Volumétrie par partition
SELECT
    PARTITION_NAME,
    TABLE_ROWS,
    CONCAT(ROUND(DATA_LENGTH / 1024 / 1024, 2), ' MB') AS taille
FROM information_schema.PARTITIONS
WHERE TABLE_SCHEMA = 'raw_acd'
  AND TABLE_NAME = 'histo_ligne_ecriture'
ORDER BY PARTITION_ORDINAL_POSITION;
```

---

#### Logs en temps réel

```bash
# Suivre l'import en cours
tail -f logs/pipeline_*.log

# Filtrer les erreurs
grep -i "error\|erreur" logs/pipeline_*.log

# Nombre de bases importées
grep -c "OK: compta_" logs/pipeline_*.log
```

---

### 💾 Backup et restauration

#### Backup avant grosse opération

```bash
# Backup complet (RAW + TRANSFORM + MDM)
mysqldump \
    --single-transaction \
    --routines --triggers --events \
    raw_acd raw_dia raw_pennylane \
    transform_compta \
    mdm \
    > backup_full_$(date +%Y%m%d_%H%M%S).sql

# Compression
gzip backup_full_*.sql
```

---

#### Backup incrémental (raw_acd uniquement)

```bash
# Sauvegarde quotidienne de raw_acd
mysqldump --single-transaction raw_acd > backup_raw_acd_$(date +%Y%m%d).sql
gzip backup_raw_acd_*.sql

# Rotation : conserver 7 jours
find . -name "backup_raw_acd_*.sql.gz" -mtime +7 -delete
```

---

#### Restauration

```bash
# Restaurer depuis backup
gunzip -c backup_full_20250124.sql.gz | mysql -u root -p

# Vérifier la restauration
mysql -e "SELECT * FROM raw_acd.sync_tracking;"
```

---

### 🧪 Tests et validation

#### Test sur échantillon (20 bases)

```bash
# Créer branche de test
git checkout -b test/validation-import

# Modifier temporairement 02_import_raw_compta.sh
# (ajouter | head -20 après ${ELIGIBLE_DATABASES[@]})

# Lancer le test
./run_pipeline.sh --init-only
bash bash/raw/02_import_raw_compta.sh --full

# Vérifier résultat
mysql -e "SELECT COUNT(DISTINCT dossier_code) FROM raw_acd.histo_ligne_ecriture;"
# Devrait retourner : 20

# Revenir à main après validation
git checkout main
```

---

### 📊 Monitoring et alertes

#### Script de monitoring (monitoring.sh)

```bash
#!/bin/bash
# Vérifier l'état du dernier import

LAST_STATUS=$(mysql -N -e "SELECT last_status FROM raw_acd.sync_tracking LIMIT 1;")
LAST_DURATION=$(mysql -N -e "SELECT last_duration_sec FROM raw_acd.sync_tracking LIMIT 1;")

if [ "$LAST_STATUS" != "success" ]; then
    echo "❌ ALERTE : Dernier import en échec"
    # Envoyer notification (email, Slack, etc.)
    exit 1
fi

if [ "$LAST_DURATION" -gt 28800 ]; then  # Plus de 8h
    echo "⚠️  WARNING : Import anormalement long (${LAST_DURATION}s)"
fi

echo "✅ Import OK (durée: ${LAST_DURATION}s)"
```

---

### 🔍 Optimisations

#### Optimiser MySQL pour imports massifs

```sql
-- Avant import complet
SET GLOBAL innodb_buffer_pool_size = 8GB;
SET GLOBAL innodb_log_file_size = 512MB;
SET GLOBAL innodb_flush_log_at_trx_commit = 2;

-- Après import
SET GLOBAL innodb_flush_log_at_trx_commit = 1;
```

---

#### Surveiller l'espace disque

```bash
# Vérifier avant import
df -h /var/lib/mysql

# Taille des bases
mysql -e "
SELECT
    table_schema AS 'Base',
    CONCAT(ROUND(SUM(data_length + index_length) / 1024 / 1024 / 1024, 2), ' GB') AS 'Taille'
FROM information_schema.tables
WHERE table_schema IN ('raw_acd', 'raw_dia', 'raw_pennylane', 'transform_compta', 'mdm')
GROUP BY table_schema
ORDER BY SUM(data_length + index_length) DESC;
"
```

---

## 📁 Structure du projet

```
tps_get_data/
├── run_pipeline.sh              # 🎯 Orchestrateur principal
├── bash/
│   ├── config.sh                # Configuration (gitignored)
│   ├── logging.sh               # Fonctions log uniformes
│   ├── raw/                     # 🔧 Scripts d'import RAW (FOCUS ACTUEL)
│   │   ├── 01_import_raw_dia.sh
│   │   ├── 02_import_raw_compta.sh       # Import ACD centralisé ⭐
│   │   ├── 02b_import_incremental_acd.sh
│   │   ├── 02c_cleanup_acd.sh
│   │   ├── 03_import_raw_pennylane.sh
│   │   ├── 03b_cleanup_pennylane.sh
│   │   └── run_all_raw.sh
│   ├── transform/               # ⚠️ NE PAS MODIFIER
│   ├── mdm/                     # ⚠️ NE PAS MODIFIER
│   ├── mart/                    # ⚠️ NE PAS MODIFIER
│   └── util/
│       ├── clean_all.sh         # Suppression complète
│       └── benchmark_import_acd.sh  # Benchmark performance
├── sql/
│   ├── 01_create_schemas.sql
│   ├── 02b_raw_acd_tables.sql   # Tables raw_acd (partitionnement) ⭐
│   ├── 02_raw_pennylane_tables.sql
│   ├── 03_transform_tables.sql  # ⚠️ NE PAS MODIFIER
│   ├── 04_mdm_tables.sql        # ⚠️ NE PAS MODIFIER
│   ├── 05_mart_views.sql        # ⚠️ NE PAS MODIFIER
│   └── 06-08_procedures_*.sql   # ⚠️ NE PAS MODIFIER
├── logs/                        # Logs des exécutions
├── COMMANDS.md                  # Guide des commandes
├── README_raw_acd.md            # Doc import ACD
└── claude.md                    # Doc projet complète
```

---

## 🔍 Requêtes utiles

### Statistiques raw_acd

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
-- Dossiers avec le plus d'écritures
SELECT
    dossier_code,
    COUNT(*) as nb_ecritures
FROM raw_acd.histo_ligne_ecriture
GROUP BY dossier_code
ORDER BY nb_ecritures DESC
LIMIT 20;

-- Distribution par année
SELECT
    HE_ANNEE as annee,
    COUNT(*) as nb_lignes
FROM raw_acd.histo_ligne_ecriture
GROUP BY HE_ANNEE
ORDER BY HE_ANNEE;
```

---

## 🎯 Focus actuel : Couche RAW

### Import ACD centralisé (raw_acd)

**Problématique** : 3500 bases `compta_*` avec 50+ tables chacune → stockage énorme

**Solution** : Import sélectif de 6 tables dans `raw_acd` centralisée

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
- Import séquentiel (source ACD 1 CPU - pas de parallélisme)
- Compression MySQL : `--compress`
- **⚡ Optimisé** : Méthode 1 du benchmark (INSERT SELECT sans batching)
- **⚡ last_sync_date** : récupéré 1x au lieu de 3500x en mode incrémental
- Estimation : ~4-6h pour 3500 bases

---

## ⚡ Automatisation (cron)

### Import quotidien à 2h00

```cron
0 2 * * * cd /path/to/tps_get_data && ./run_pipeline.sh --acd-incremental 2>&1 | logger -t data_pipeline
```

### Import complet hebdomadaire (dimanche 1h00)

```cron
0 1 * * 0 cd /path/to/tps_get_data && ./run_pipeline.sh --acd-full 2>&1 | logger -t data_pipeline
```

---

## 🐛 Dépannage

### Problème : Connexion ACD échoue

```bash
# Tester la connexion
mysql -h <ACD_HOST> -P <ACD_PORT> -u <ACD_USER> -p<ACD_PASS> -e "SELECT 1"
```

### Problème : Import très lent

```bash
# Vérifier le nombre de bases à traiter
mysql -h <ACD_HOST> -u <ACD_USER> -p -e "
    SELECT COUNT(*) FROM information_schema.schemata
    WHERE schema_name LIKE 'compta_%'
"

# Lancer le benchmark pour comparer les méthodes
bash bash/util/benchmark_import_acd.sh
```

### Problème : Données manquantes

```bash
# Vérifier sync_tracking
mysql -u root -p raw_acd -e "SELECT * FROM sync_tracking"

# Relancer import complet
bash bash/raw/02_import_raw_compta.sh --full
```

---

## 📊 Logs

Les logs sont disponibles dans :
```
logs/pipeline_YYYYMMDD_HHMMSS.log
```

Rotation automatique : conservation de 30 jours

---

## 🎯 Roadmap

### Phase 1 : Stabilisation RAW (EN COURS)
- ✅ Import ACD centralisé (raw_acd)
- ✅ Optimisation performances (benchmark Méthode 1 appliqué)
- 🔄 Validation import incrémental en production
- ⏳ Tests sur 3500 bases

### Phase 2 : Adaptation TRANSFORM
1. Adapter les procédures pour utiliser raw_acd
2. Tester les agrégations ecritures_mensuelles
3. Valider la qualité des données transformées

### Phase 3 : Enrichissement MDM
1. Déduplication SIREN
2. Jointure multi-sources (ACD ↔ Pennylane ↔ Silae)
3. API backend pour synchronisation

### Phase 4 : Vues MART par profil utilisateur
- MART Comptables (directeurs, comptables)
- MART Contrôle de gestion (interne/externe)
- MART Production client (holdings)

---

## 📞 Support

- **Documentation** : Voir [COMMANDS.md](COMMANDS.md) et [README_raw_acd.md](README_raw_acd.md)
- **Logs** : `logs/pipeline_YYYYMMDD_HHMMSS.log`
- **Issues** : [GitHub Issues](https://github.com/jharjharbink/tps_get_data/issues)

---

## 📝 License

MIT License - voir [LICENSE](LICENSE) pour plus de détails

---

**⚠️ Focus actuel : VALIDATION DE LA COUCHE RAW UNIQUEMENT**
