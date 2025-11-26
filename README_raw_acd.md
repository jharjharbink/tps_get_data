# 📦 RAW_ACD - Import centralisé des données comptables ACD

## 🎯 Vue d'ensemble

Ce module remplace l'import des bases `compta_*` complètes par un **import sélectif** de 6 tables dans une base centralisée `raw_acd`.

### Avant / Après

**AVANT :**
```
├── compta_00001 (base complète copiée)
├── compta_00002 (base complète copiée)
└── ... (3500+ bases)
```
❌ Import lourd et lent
❌ Stockage multiplié
❌ Impossible à requêter efficacement

**APRÈS :**
```
raw_acd (base unique centralisée)
├── histo_ligne_ecriture (avec colonne dossier_code)
├── histo_ecriture
├── ligne_ecriture
├── ecriture
├── compte
└── journal
```
✅ Import sélectif de 6 tables uniquement
✅ Requêtes SQL simples
✅ Compatible Power BI
✅ Mode incrémental pour mises à jour rapides

---

## 📁 Fichiers créés/modifiés

### Nouveaux fichiers SQL
- **`sql/02b_raw_acd_tables.sql`** : Création des 6 tables avec partitionnement par année

### Nouveaux scripts Bash
- **`bash/raw/02_import_raw_compta.sh`** : Import principal (modes --full / --incremental)
- **`bash/raw/02b_import_incremental_acd.sh`** : Wrapper pour import quotidien
- **`bash/raw/02c_cleanup_acd.sh`** : Nettoyage et maintenance

### Fichiers modifiés
- **`sql/01_create_schemas.sql`** : Ajout du schéma `raw_acd`
- **`bash/raw/run_all_raw.sh`** : Support options `--acd-full` / `--acd-incremental`
- **`run_pipeline.sh`** : Intégration complète dans le pipeline

---

## ⚙️ Configuration requise

Ajoutez ces variables dans votre `bash/config.sh` local (non versionné) :

```bash
# ─── SERVEUR ACD (pour raw_acd) ────────────────────────────
export ACD_HOST="192.168.20.24"
export ACD_PORT="3306"
export ACD_USER="root"
export ACD_PASS="admin-2019"

# ─── TABLES REQUISES POUR RAW_ACD ──────────────────────────
export REQUIRED_TABLES=(
    "histo_ligne_ecriture"
    "histo_ecriture"
    "ligne_ecriture"
    "ecriture"
    "compte"
    "journal"
)

# ─── BASES COMPTA_* À EXCLURE ──────────────────────────────
export EXCLUDED_DATABASES=(
    "compta_000000"
    "compta_zz"
    "compta_gombertcOLD"
    "compta_gombertcold"
)
```

---

## 🚀 Installation

### 1. Créer le schéma et les tables

```bash
./run_pipeline.sh --init-only
```

Cela crée automatiquement :
- Le schéma `raw_acd`
- Les 6 tables avec partitionnement
- La table `sync_tracking` pour l'incrémental
- La vue unifiée `v_ligne_ecriture_unified`

---

## 📖 Utilisation

### Import initial (première fois)

```bash
# Via le pipeline complet
./run_pipeline.sh

# Ou seulement l'import raw_acd
bash bash/raw/02_import_raw_compta.sh --full
```

**Durée estimée :** ~45-60 minutes pour 3500 bases (avec 3 jobs parallèles)

**Ce qui est fait :**
1. Vérification de la connexion ACD
2. Récupération de toutes les bases `compta_*`
3. **Vérification que les 6 tables requises existent** dans chaque base
4. Filtrage des bases éligibles
5. Import parallèle (3 jobs) vers `raw_acd`
6. Ajout automatique de la colonne `dossier_code`

---

### Import incrémental (quotidien)

```bash
# Via le wrapper
bash bash/raw/02b_import_incremental_acd.sh

# Ou via le script principal
bash bash/raw/02_import_raw_compta.sh --incremental

# Ou via le pipeline complet
./run_pipeline.sh --acd-incremental
```

**Durée estimée :** ~5-10 minutes (selon volume de modifications)

**Ce qui est fait :**
1. Lecture de `last_sync_date` depuis `sync_tracking`
2. Import uniquement des lignes modifiées (basé sur `HE_DATE_SAI` / `ECR_DATE_SAI`)
3. Utilisation de `ON DUPLICATE KEY UPDATE` pour éviter les doublons
4. Mise à jour automatique de `sync_tracking`

---

### Nettoyage et maintenance

```bash
# Afficher les statistiques
bash bash/raw/02c_cleanup_acd.sh --stats

# Supprimer un dossier spécifique
bash bash/raw/02c_cleanup_acd.sh --dossier 00123

# Supprimer une année complète
bash bash/raw/02c_cleanup_acd.sh --year 2020

# Supprimer avant une date
bash bash/raw/02c_cleanup_acd.sh --before 2022-01-01

# Optimiser les tables (récupérer l'espace disque)
bash bash/raw/02c_cleanup_acd.sh --optimize

# Vider complètement raw_acd (avec confirmation)
bash bash/raw/02c_cleanup_acd.sh --full
```

---

## 🔧 Options du pipeline

### Options générales

```bash
./run_pipeline.sh                    # Pipeline complet (mode full ACD)
./run_pipeline.sh --skip-raw         # Sans réimport RAW
./run_pipeline.sh --init-only        # Créer uniquement les schémas
./run_pipeline.sh --data-only        # Importer uniquement les données
```

### Options spécifiques ACD

```bash
./run_pipeline.sh --acd-full         # Import complet (TRUNCATE + réimport)
./run_pipeline.sh --acd-incremental  # Import incrémental (nouveautés uniquement)
```

### Combinaisons utiles

```bash
# Import quotidien rapide (incrémental)
./run_pipeline.sh --acd-incremental

# Réinitialisation complète hebdomadaire
./run_pipeline.sh --acd-full

# Import données sans recréer les tables
./run_pipeline.sh --data-only --acd-incremental
```

---

## 📊 Structure des tables

### Tables principales (avec partitionnement)

```sql
CREATE TABLE raw_acd.histo_ligne_ecriture (
    dossier_code VARCHAR(20),        -- '00123' (extrait de compta_00123)
    HLE_CODE BIGINT,
    HE_CODE BIGINT,
    CPT_CODE VARCHAR(32),
    HLE_CRE_ORG DECIMAL(18,2),
    HLE_DEB_ORG DECIMAL(18,2),
    HE_DATE_SAI DATE,                -- Pour incrémental
    HE_ANNEE SMALLINT,               -- Pour partitionnement
    HE_MOIS TINYINT,
    JNL_CODE VARCHAR(32),
    PRIMARY KEY (dossier_code, HLE_CODE, HE_ANNEE)
) PARTITION BY RANGE (HE_ANNEE);
```

### Table de tracking

```sql
SELECT * FROM raw_acd.sync_tracking;
```

| table_name | last_sync_date | last_sync_type | rows_count | last_status |
|------------|----------------|----------------|------------|-------------|
| histo_ligne_ecriture | 2025-11-23 02:00 | incremental | 12548732 | success |

### Vue unifiée

```sql
SELECT * FROM raw_acd.v_ligne_ecriture_unified
WHERE dossier_code = '00123'
AND annee = 2024;
```

---

## 🔍 Requêtes utiles

### Compter les dossiers centralisés

```sql
SELECT COUNT(DISTINCT dossier_code) as nb_dossiers
FROM raw_acd.histo_ligne_ecriture;
```

### Balance mensuelle pour un dossier

```sql
SELECT
    DATE_FORMAT(date_saisie, '%Y-%m-01') as period_month,
    CPT_CODE,
    SUM(debit) as debits,
    SUM(credit) as credits,
    SUM(debit - credit) as solde
FROM raw_acd.v_ligne_ecriture_unified
WHERE dossier_code = '00123'
  AND annee >= 2024
GROUP BY period_month, CPT_CODE;
```

### Top 10 des dossiers par volume

```sql
SELECT
    dossier_code,
    COUNT(*) as nb_ecritures,
    SUM(HLE_DEB_ORG + HLE_CRE_ORG) as volume_total
FROM raw_acd.histo_ligne_ecriture
GROUP BY dossier_code
ORDER BY nb_ecritures DESC
LIMIT 10;
```

---

## ⚡ Performances

### Volumes estimés (3500 bases)

| Table | Lignes | Taille |
|-------|--------|--------|
| histo_ligne_ecriture | ~12M | ~1.5 GB |
| ligne_ecriture | ~2M | ~250 MB |
| histo_ecriture | ~4M | ~400 MB |
| ecriture | ~800K | ~80 MB |
| compte | ~150K | ~15 MB |
| journal | ~20K | ~2 MB |
| **TOTAL** | **~19M** | **~2.3 GB** |

### Temps d'exécution

| Opération | Durée |
|-----------|-------|
| Import full (3500 bases, 3 jobs) | ~45-60 min |
| Import incrémental quotidien | ~5-10 min |
| Requête balance mensuelle | < 5 sec |

### 🔬 Benchmark de performance

Pour mesurer les performances réelles sur votre environnement et choisir la meilleure méthode d'import :

```bash
bash bash/util/benchmark_import_acd.sh
```

Ce script teste **4 méthodes** sur 10 bases pour comparer les performances :

**Méthodes testées :**
1. **Méthode 1 : INSERT SELECT SANS batching** ⭐ **LA PLUS RAPIDE**
   - Requête directe : `INSERT INTO raw_acd.table SELECT 'dossier', t.* FROM compta_*.table t`
   - 1 requête par table (6 requêtes par base)
   - Moins d'overhead réseau
   - **✅ IMPLÉMENTÉE dans le script actuel**

2. **Méthode 2 : INSERT SELECT AVEC batching (toutes tables)**
   - Batching de 100k lignes pour les 6 tables
   - Plus de requêtes mais chunks plus petits
   - Peut être utile pour très grosses tables

3. **Méthode 3 : INSERT SELECT AVEC batching (écritures seulement)**
   - Batching uniquement pour les 4 tables d'écritures
   - compte/journal importés en 1 fois

4. **Méthode 4 : DUMP COMPLET** (ancien script - référence)
   - Clone complet des bases avec mysqldump
   - ❌ Incompatible avec architecture raw_acd
   - Conservé pour référence historique

**Résultat du benchmark** :
- ✅ **Méthode 1 (INSERT SELECT sans batching) est la plus rapide**
- Le batching n'apporte pas d'amélioration pour les volumes actuels
- Code plus simple et maintenable

Le benchmark génère un rapport détaillé (`benchmark_results_YYYYMMDD_HHMMSS.txt`) avec :
- Tableau comparatif des temps d'exécution
- Estimation pour 3500 bases
- Analyse comparative entre méthodes
- Recommandation finale

**Durée du benchmark :** ~5-15 minutes selon les volumes

**⚡ Optimisations appliquées dans le script actuel** :
- ✅ Méthode 1 implémentée (INSERT SELECT sans batching)
- ✅ Récupération `last_sync_date` UNE SEULE FOIS (au lieu de 3500+ requêtes en mode incrémental)
- ✅ Requêtes SQL simplifiées et inline
- ✅ Moins d'overhead et meilleure performance

---

## ✅ Vérifications

### Vérifier que les 6 tables existent

Le script `02_import_raw_compta.sh` vérifie automatiquement que chaque base `compta_*` possède les 6 tables requises. Les bases sans toutes les tables sont **automatiquement exclues** et un warning est affiché.

### Logs d'exclusion

```
[2025-11-23 10:15:32] [WARNING] ⚠️  Base compta_test ignorée : tables manquantes
[2025-11-23 10:15:33] [INFO] ℹ️  3452 bases éligibles trouvées (48 exclues)
```

---

## 🛠️ Dépannage

### Erreur "raw_acd n'existe pas"

```bash
./run_pipeline.sh --init-only
```

### Import incrémental ne trouve rien

Vérifier la dernière synchro :
```sql
SELECT * FROM raw_acd.sync_tracking;
```

### Bases manquent des tables requises

Vérifier quelles tables existent :
```sql
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'compta_00123';
```

### Relancer un import complet

```bash
bash bash/raw/02_import_raw_compta.sh --full
```

---

## 🔮 Prochaines étapes (Next Steps)

Une fois `raw_acd` en place, vous pourrez :

1. **Supprimer les anciennes bases `compta_*` locales** (libérer ~50GB+)
2. **Migrer vers transform_compta** : Utiliser `raw_acd` au lieu de boucler sur les bases
3. **Créer des dashboards Power BI** : Requêtes directes sur `raw_acd`
4. **Automatiser avec cron** :
   ```bash
   # Import incrémental quotidien à 2h00
   0 2 * * * /path/to/bash/raw/02b_import_incremental_acd.sh

   # Import complet hebdomadaire le dimanche à 1h00
   0 1 * * 0 /path/to/bash/raw/02_import_raw_compta.sh --full
   ```

### ⚠️ Améliorations prioritaires

#### 1. ✅ **Horodatage par base compta_* lors de l'import** (IMPLÉMENTÉ)

**Problème initial** : Si un import dure plusieurs heures pour 3500 bases, les bases ACD source peuvent être modifiées pendant le traitement. La date `last_sync_date` dans `sync_tracking` était mise à jour **à la fin** de tout l'import.

**✅ Solution implémentée** :
- Nouvelle table `sync_tracking_by_dossier` créée (préserve l'ancienne table `sync_tracking`)
- Enregistrement de la date d'import **par dossier** au fur et à mesure
- Structure de la table :
  ```sql
  CREATE TABLE sync_tracking_by_dossier (
      table_name VARCHAR(50) NOT NULL,
      dossier_code VARCHAR(20) NOT NULL,
      last_sync_date DATETIME NOT NULL,
      last_sync_type ENUM('full', 'incremental', 'since'),
      last_status VARCHAR(20) DEFAULT 'success',
      rows_imported INT DEFAULT 0,
      PRIMARY KEY (table_name, dossier_code)
  );
  ```

**✅ Bénéfices obtenus** :
- Import incrémental plus précis (par dossier)
- Traçabilité exacte de chaque base
- Reprise possible après crash sans tout réimporter
- Double tracking : global (`sync_tracking`) + granulaire (`sync_tracking_by_dossier`)

---

#### 2. ✅ **Optimisation import incrémental : filtrer par dossiers déjà importés** (IMPLÉMENTÉ)

**Problème initial** : En mode `--incremental`, le script traitait **tous les dossiers** trouvés sur le serveur ACD, même ceux qui n'avaient jamais été importés auparavant.

**Conséquence** :
- Si un nouveau dossier `compta_99999` était créé sur ACD, il aurait été importé en mode incrémental
- Mais la date de référence aurait été `last_sync_date` globale → risque de manquer des données historiques
- Pas de traçabilité des nouveaux dossiers détectés

**✅ Solution implémentée** :
```bash
# Dans 02_import_raw_compta.sh, après récupération des bases éligibles

if [ "$MODE" = "incremental" ]; then
    log "INFO" "Mode incrémental : filtrage des dossiers déjà connus..."

    # Récupérer les dossiers déjà importés (présents dans raw_acd)
    KNOWN_DOSSIERS=$($MYSQL $MYSQL_OPTS raw_acd -N -e "
        SELECT DISTINCT dossier_code
        FROM sync_tracking_by_dossier
    ")

    # Détecter les nouveaux dossiers
    NEW_DOSSIERS=()
    KNOWN_DOSSIERS_ARRAY=()

    for DB in "${ELIGIBLE_DATABASES[@]}"; do
        DOSSIER_CODE="${DB#compta_}"

        if echo "$KNOWN_DOSSIERS" | grep -qx "$DOSSIER_CODE"; then
            KNOWN_DOSSIERS_ARRAY+=("$DB")
        else
            NEW_DOSSIERS+=("$DB")
        fi
    done

    # Logger les nouveaux dossiers détectés
    if [ ${#NEW_DOSSIERS[@]} -gt 0 ]; then
        log "WARNING" "🆕 ${#NEW_DOSSIERS[@]} nouveaux dossiers détectés (non importés en incrémental) :"
        for NEW_DB in "${NEW_DOSSIERS[@]}"; do
            log "WARNING" "   - $NEW_DB (nécessite un import --full pour historique complet)"
        done
    fi

    # Utiliser uniquement les dossiers connus pour l'import incrémental
    ELIGIBLE_DATABASES=("${KNOWN_DOSSIERS_ARRAY[@]}")
    log "INFO" "Import incrémental limité à ${#ELIGIBLE_DATABASES[@]} dossiers connus"
fi
```

**✅ Bénéfices obtenus** :
- ✅ **Performance** : Import incrémental plus rapide (ne traite que les dossiers déjà connus)
- ✅ **Traçabilité** : Log WARNING avec liste des nouveaux dossiers détectés
- ✅ **Sécurité** : Évite d'importer partiellement un nouveau dossier (risque de données manquantes)
- ✅ **Workflow clair** :
  - Import `--incremental` = mise à jour uniquement des dossiers existants
  - Import `--full` = ajout de nouveaux dossiers + mise à jour complète de tous les dossiers

**Exemple de log attendu** :
```
[2025-01-25 14:30:00] [INFO] ℹ️  Mode incrémental : filtrage des dossiers déjà connus...
[2025-01-25 14:30:02] [WARNING] ⚠️  🆕 3 nouveaux dossiers détectés (non importés en incrémental) :
[2025-01-25 14:30:02] [WARNING] ⚠️     - compta_99999 (nécessite un import --full pour historique complet)
[2025-01-25 14:30:02] [WARNING] ⚠️     - compta_88888 (nécessite un import --full pour historique complet)
[2025-01-25 14:30:02] [WARNING] ⚠️     - compta_77777 (nécessite un import --full pour historique complet)
[2025-01-25 14:30:02] [INFO] ℹ️  Import incrémental limité à 3497 dossiers connus
```

---

#### 3. **Vérification du mécanisme d'import incrémental** (PARTIELLEMENT VALIDÉ)

**Prompt de vérification** :
> "Analyser le mécanisme d'import incrémental dans `02_import_raw_compta.sh` (lignes 221-255) pour vérifier :
>
> 1. **Pas de perte de données** :
>    - Les écritures modifiées entre deux imports sont bien capturées ?
>    - Le filtre `WHERE t.DATE_FIELD > '$LAST_SYNC'` est-il strict ou inclusif ?
>    - Que se passe-t-il si une écriture est modifiée **pendant** l'import ?
>
> 2. **Pas de doublons** :
>    - La clause `ON DUPLICATE KEY UPDATE` fonctionne-t-elle correctement ?
>    - Les clés primaires `(dossier_code, CODE, ANNEE)` sont-elles suffisantes ?
>    - Les données de la table `compte` et `journal` (sans filtre date) peuvent-elles créer des doublons ?
>
> 3. **Gestion des suppressions** :
>    - Si une écriture est **supprimée** dans ACD, elle reste dans `raw_acd` ?
>    - Faut-il ajouter un soft delete ou un mécanisme de purge ?
>
> 4. **Tests recommandés** :
>    - Créer une base de test `compta_test` avec quelques écritures
>    - Lancer un import full
>    - Modifier/ajouter/supprimer des écritures dans `compta_test`
>    - Lancer un import incrémental
>    - Vérifier que les modifications sont bien reflétées dans `raw_acd`"

**Actions suggérées** :
- Implémenter des tests unitaires pour l'import incrémental
- Ajouter un système de logs détaillé (nombre de lignes insérées/mises à jour par base)
- Créer une table `sync_audit` pour tracer tous les imports :
  ```sql
  CREATE TABLE raw_acd.sync_audit (
      id BIGINT AUTO_INCREMENT PRIMARY KEY,
      table_name VARCHAR(50),
      dossier_code VARCHAR(20),
      sync_date DATETIME,
      sync_type ENUM('full', 'incremental'),
      rows_inserted INT,
      rows_updated INT,
      duration_sec INT,
      status VARCHAR(20)
  );
  ```

---

#### 3. **Optimisation de l'import pour 3500 bases**

**Problèmes actuels** :
- Import séquentiel = ~19 heures
- Pas de monitoring en temps réel du transfert réseau
- Pas de vérification de l'espace disque avant import

**Solutions** :
- ✅ **FAIT** : Barre de progression avec timestamps toutes les 10 bases
- **TODO** : Ajouter une vérification d'espace disque avant `--full`
- **TODO** : Implémenter un système de reprise en cas d'erreur (checkpoint)
- **TODO** : Ajouter des statistiques de transfert réseau (MB transférés par base)

---

## 🔬 Optimisations avancées (non implémentées)

Cette section documente des optimisations qui n'ont **pas été implémentées** mais qui pourraient être utiles dans des cas spécifiques.

### 1. Mode staging avec swap atomique

**Problème** : En cas de crash durant l'import, les données peuvent être partiellement importées, créant un état incohérent.

**Solution** :
```bash
# 1. Import dans des tables temporaires
LOAD DATA LOCAL INFILE '/tmp/data.tsv'
REPLACE INTO TABLE raw_acd.histo_ligne_ecriture_tmp ...

# 2. Vérifier la cohérence des données
if [ validation OK ]; then
    # 3. Swap atomique
    RENAME TABLE
        histo_ligne_ecriture TO histo_ligne_ecriture_old,
        histo_ligne_ecriture_tmp TO histo_ligne_ecriture;

    DROP TABLE histo_ligne_ecriture_old;
fi
```

**Avantages** :
- ✅ Rollback automatique en cas d'erreur
- ✅ Pas d'état intermédiaire incohérent
- ✅ Les utilisateurs voient toujours des données complètes

**Inconvénients** :
- ❌ Complexité élevée de mise en œuvre
- ❌ Double espace disque nécessaire pendant l'import
- ❌ Nécessite de dupliquer toutes les structures (tables, index, partitions)

**Statut** : Non implémenté
- Gain marginal pour le contexte actuel (volumétrie <200k lignes/dossier)
- Mécanisme de reprise après crash via `sync_tracking_by_dossier` suffit

---

### 2. Fallback pour requêtes lentes

**Problème** : Les requêtes avec `WHERE EXISTS` sur les jointures `HE_CODE`/`ECR_CODE` peuvent être lentes si les tables sources ACD n'ont pas d'index sur ces colonnes.

**Exemple de requête potentiellement lente** :
```sql
SELECT * FROM ligne_ecriture
WHERE EXISTS (
    SELECT 1 FROM ecriture e
    WHERE e.ECR_CODE = ligne_ecriture.ECR_CODE
    AND e.ECR_DATE_SAI > '2025-01-01'
)
```

**Solution** :
```bash
# Timeout de 30 secondes sur l'extraction
timeout 30s $MYSQL -h "$ACD_HOST" ... || {
    log "WARNING" "Requête lente détectée pour $DB.$TABLE, fallback import complet"
    WHERE_CLAUSE=""  # Import complet pour cette table
}
```

**Avantages** :
- ✅ Évite de bloquer l'import sur une base problématique
- ✅ Garantit la progression même en cas de problème de performance

**Inconvénients** :
- ❌ Perte de l'optimisation incrémentale pour cette base
- ❌ Augmentation du temps d'import pour les bases concernées

**Statut** : Non implémenté
- Aucune compta ne dépasse 200 000 lignes actuellement
- Performance acceptable dans tous les cas observés
- À considérer si volumétrie augmente significativement

---

### 3. Approche en 2 temps pour jointures

**Alternative aux `WHERE EXISTS`** si problèmes de performance :

```bash
# 1. Récupérer les codes d'écritures modifiées
MODIFIED_ECR_CODES=$($MYSQL -h "$ACD_HOST" -N -e "
    SELECT GROUP_CONCAT(ECR_CODE)
    FROM \`$DB\`.ecriture
    WHERE ECR_DATE_SAI > '$SYNC_DATE'
")

# 2. Filtrer les lignes avec IN clause
WHERE_CLAUSE="WHERE ECR_CODE IN ($MODIFIED_ECR_CODES)"

# 3. Extraction avec filtre direct
$MYSQL -h "$ACD_HOST" -e "
    SELECT $SELECT_COLS
    FROM \`$DB\`.ligne_ecriture
    $WHERE_CLAUSE
"
```

**Avantages** :
- ✅ Plus rapide si pas d'index sur colonne de jointure
- ✅ Requête plus simple sans sous-requête corrélée
- ✅ Peut bénéficier du cache MySQL

**Inconvénients** :
- ❌ Deux requêtes au lieu d'une (overhead réseau)
- ❌ Limite de taille pour la clause `IN` (~1000-10000 valeurs selon config MySQL)
- ❌ Peut échouer si trop d'écritures modifiées

**Statut** : Non implémenté
- Approche actuelle avec `WHERE EXISTS` suffisante
- À considérer uniquement si problèmes de performance avérés
- Nécessiterait gestion du chunking pour grandes volumétries

---

### 4. Compression réseau avancée

**Problème** : Le transfert réseau peut être lent entre le serveur ACD et le serveur local, surtout pour les imports full.

**Solutions possibles** :
```bash
# Option 1 : SSH tunnel avec compression
ssh -C -L 3307:localhost:3306 user@acd-server

# Option 2 : Compression MySQL native (déjà utilisée)
$MYSQL --compress -h "$ACD_HOST" ...

# Option 3 : Compression ZSTD (MySQL 8.0.18+)
$MYSQL --compression-algorithms=zstd -h "$ACD_HOST" ...
```

**Statut** : Partiellement implémenté
- ✅ `--compress` déjà utilisé dans le script actuel
- ⏳ Compression ZSTD à tester si disponible sur serveur source

---

### 5. Parallélisme intelligent par volumétrie

**Problème** : Toutes les bases sont traitées séquentiellement, même si certaines sont très petites.

**Solution** :
```bash
# Trier les bases par volumétrie estimée
SORTED_DATABASES=$(for DB in "${ELIGIBLE_DATABASES[@]}"; do
    SIZE=$($MYSQL -h "$ACD_HOST" -N -e "
        SELECT SUM(data_length)
        FROM information_schema.tables
        WHERE table_schema = '$DB'
        AND table_name IN ('ecriture', 'ligne_ecriture')
    ")
    echo "$SIZE|$DB"
done | sort -rn | cut -d'|' -f2)

# Traiter les grosses bases en premier (optimisation du temps total)
```

**Avantages** :
- ✅ Meilleure estimation du temps restant
- ✅ Échecs précoces sur bases problématiques

**Inconvénients** :
- ❌ Requête supplémentaire par base avant import
- ❌ Complexité accrue

**Statut** : Non implémenté
- Source ACD à 1 CPU : parallélisme limité de toute façon
- Traitement séquentiel plus simple et prévisible

---

## 📞 Support

Pour toute question, vérifiez :
1. Les logs dans `logs/pipeline_YYYYMMDD.log`
2. Les statistiques : `bash bash/raw/02c_cleanup_acd.sh --stats`
3. La table de tracking : `SELECT * FROM raw_acd.sync_tracking;`
4. La table de tracking par dossier : `SELECT * FROM raw_acd.sync_tracking_by_dossier LIMIT 20;`
