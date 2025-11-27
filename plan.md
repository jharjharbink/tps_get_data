# Plan de Refactoring : CLI Unifiée `./data` avec Factorisation du Code

## Contexte

Le projet `projet_test` contient **334+ lignes de code dupliqué** dans les scripts d'import bash (`01_import_raw_dia.sh`, `02_import_raw_compta.sh`, `03_import_raw_pennylane.sh`). L'objectif est de :
1. **Factoriser** le code dupliqué dans une bibliothèque réutilisable
2. **Créer une CLI unifiée** `./data` avec 3 commandes : `clean`, `create-db`, `import-data`
3. **Vérification de dépendances** automatique
4. **Tests automatisés** (ShellCheck + tests d'intégration)
5. **Remplacer** les anciens scripts par des wrappers deprecated
6. **Optimiser le scan ACD** : 7 minutes → ~10 secondes (requête SQL groupée)
7. **Export Pennylane via S3** : Redshift UNLOAD → S3 → MariaDB (plus rapide et fiable)
8. **Import Pennylane par dossier** : Ajouter modes `--dossier-full` et `--dossier-incremental`

Architecture cible documentée dans `claude.md` Phase 7.

---

## Architecture Finale

```
projet_test/
├── data                              # ✨ Script principal (CLI entry point NOUVEAU)
├── run_pipeline.sh                   # ⚠️ DEPRECATED (wrapper vers ./data)
│
├── bash/
│   ├── lib/                          # ✨ NOUVEAU : Bibliothèque de fonctions réutilisables
│   │   ├── db_utils.sh              # Connexion, LOAD DATA, sync_tracking
│   │   ├── arg_parser.sh            # Parsing arguments communs
│   │   ├── file_utils.sh            # Gestion fichiers tmp, cleanup (trap)
│   │   ├── validators.sh            # Validation input, checks
│   │   ├── deps.sh                  # Vérification dépendances
│   │   └── s3_utils.sh              # ✨ NOUVEAU : Gestion AWS S3
│   │
│   ├── sources/                      # ✨ NOUVEAU : Configuration par source de données
│   │   ├── acd.sh                   # Config ACD (SUPPORTS_INCREMENTAL=true)
│   │   ├── dia.sh                   # Config DIA
│   │   └── pennylane.sh             # Config Pennylane + S3
│   │
│   ├── commands/                     # ✨ NOUVEAU : Implémentation des 3 commandes CLI
│   │   ├── clean.sh                 # ./data clean [--all|--raw|--acd|--transform|--mdm|--mart]
│   │   ├── create_db.sh             # ./data create-db [--all|--raw|--transform|--mdm|--mart]
│   │   └── import_data.sh           # ./data import-data [sources + couches + modes]
│   │
│   ├── raw/                          # Scripts d'import RAW (refactorisés avec bash/lib/)
│   │   ├── 01_import_raw_dia.sh     # Refactorisé pour utiliser bash/lib/db_utils.sh
│   │   ├── 02_import_raw_compta.sh  # ✨ Optimisé (scan 7min → 10s) + bash/lib/
│   │   ├── 03_import_raw_pennylane.sh # ✨ Réécriture S3 + modes dossier + bash/lib/
│   │   └── run_all_raw.sh           # ⚠️ DEPRECATED (wrapper vers ./data import-data --all)
│   │
│   ├── transform/                    # ⚠️ CONSERVÉ TEL QUEL (scripts existants)
│   │   ├── 01_load_dossiers.sh      # Appelé par ./data import-data --transform
│   │   ├── 02_load_ecritures.sh
│   │   ├── 03_load_tiers.sh
│   │   └── orchestrator_transform.sh # Appelle toutes les procédures TRANSFORM
│   │
│   ├── mdm/                          # ⚠️ CONSERVÉ TEL QUEL (scripts existants)
│   │   ├── 01_merge_dossiers.sh     # Appelé par ./data import-data --mdm
│   │   ├── 02_merge_collaborateurs.sh
│   │   └── orchestrator_mdm.sh      # Appelle toutes les procédures MDM
│   │
│   ├── mart/                         # ⚠️ CONSERVÉ TEL QUEL (scripts existants)
│   │   └── refresh_mart.sh          # Appelé par ./data import-data --mart (stats vues)
│   │
│   ├── util/                         # Scripts utilitaires (conservés)
│   │   ├── clean_all.sh             # ⚠️ DEPRECATED (wrapper vers ./data clean --all)
│   │   └── benchmark_import_acd.sh  # Conservé pour tests performance
│   │
│   ├── config.sh                     # Configuration globale (+ config S3)
│   └── logging.sh                    # Logging uniforme (inchangé)
│
├── sql/                              # Scripts SQL (inchangés)
│   ├── 01_create_schemas.sql
│   ├── 02b_raw_acd_tables.sql       # Tables RAW ACD
│   ├── 02_raw_dia_tables.sql
│   ├── 02_raw_pennylane_tables.sql
│   ├── 03_transform_tables.sql      # Tables TRANSFORM
│   ├── 04_mdm_tables.sql            # Tables MDM
│   ├── 05_mart_views.sql            # Vues MART
│   ├── 06_procedures_transform_*.sql # Procédures TRANSFORM
│   ├── 07_procedures_mdm.sql        # Procédures MDM
│   └── 08_procedures_orchestrator.sql # Orchestrateur global
│
├── tests/                            # ✨ NOUVEAU : Tests automatisés
│   ├── shellcheck.sh                 # Tests ShellCheck sur tous les bash
│   └── integration_test.sh           # Tests d'intégration end-to-end
│
├── logs/                             # Logs (inchangé)
│   └── pipeline_*.log
│
├── README.md                         # ✨ Mis à jour avec CLI ./data
├── claude.md                         # Documentation technique (inchangé)
└── COMMANDS.md                       # Guide commandes (inchangé)
```

**Légende :**
- ✨ **NOUVEAU** : Fichiers/dossiers créés pour la refactorisation
- ⚠️ **CONSERVÉ TEL QUEL** : Scripts existants TRANSFORM/MDM/MART inchangés
- ⚠️ **DEPRECATED** : Anciens scripts remplacés par wrappers vers ./data

---

## Phase 1 : Création de la Bibliothèque `bash/lib/`

### 1.1 `bash/lib/db_utils.sh` (Fonctions DB)

**Fonctions à implémenter :**

```bash
# Test connexion MySQL distant
check_db_connection() {
    local HOST="$1"
    local PORT="$2"
    local USER="$3"
    local PASS="$4"
    local DISPLAY_NAME="${5:-$HOST:$PORT}"
}

# Création schéma avec charset
create_schema_if_not_exists() {
    local SCHEMA_NAME="$1"
    local CHARSET="${2:-utf8mb4}"
    local COLLATE="${3:-utf8mb4_unicode_ci}"
}

# LOAD DATA wrapper unifié (supporte CSV S3 avec NULL normalisé)
load_data_from_file() {
    local FILE="$1"
    local TARGET_TABLE="$2"
    local LOAD_MODE="${3:-INTO}"          # INTO ou REPLACE INTO
    local FIELD_TERM="${4:-\t}"
    local ENCLOSED_BY="${5:-}"
    local IGNORE_LINES="${6:-0}"
    local COLUMNS="${7:-}"
    local NORMALIZE_NULL="${8:-false}"    # Convertir \N en NULL
}

# Update sync_tracking générique
update_sync_tracking() {
    local SCHEMA="$1"
    local TABLE_NAME="$2"
    local ROWS_COUNT="$3"
    local SYNC_TYPE="${4:-full}"
    local STATUS="${5:-success}"
    local EXTRA_KEY="${6:-}"              # Pour dossier_code
    local EXTRA_VALUE="${7:-}"
}

# Truncate avec FK disable
truncate_tables_safe() {
    local SCHEMA="$1"
    shift
    local TABLES=("$@")
}

# Statistiques schéma
show_schema_stats() {
    local SCHEMA="$1"
}

# ✨ NOUVEAU : Scan rapide des bases ACD valides (7min → 10s)
get_valid_acd_databases() {
    local EXCLUDED_DBS="$1"  # Liste séparée par virgules: 'compta_000000','compta_zz'

    # Une seule requête groupée au lieu de N requêtes
    $MYSQL -h "$ACD_HOST" -P "$ACD_PORT" -u "$ACD_USER" -p"$ACD_PASS" -N -e "
        SELECT t.table_schema
        FROM information_schema.tables t
        WHERE t.table_schema LIKE 'compta_%'
          AND t.table_schema NOT IN ($EXCLUDED_DBS)
          AND t.table_name IN ('histo_ligne_ecriture', 'histo_ecriture',
                               'ligne_ecriture', 'ecriture', 'compte', 'journal')
        GROUP BY t.table_schema
        HAVING COUNT(DISTINCT t.table_name) = 6
        ORDER BY t.table_schema
    " 2>/dev/null
}

# ✨ NOUVEAU : Vérifier longueur dossier_code AVANT import
validate_dossier_code_length() {
    local DOSSIER_CODE="$1"
    local MAX_LENGTH="${2:-20}"

    if [ ${#DOSSIER_CODE} -gt $MAX_LENGTH ]; then
        return 1
    fi
    return 0
}
```

**Duplications résolues :**
- Test connexion DB (2 occurrences → 1 fonction)
- Création schéma (2 occurrences → 1 fonction)
- LOAD DATA (7 occurrences → 1 fonction)
- Update tracking (2 variantes → 1 fonction paramétrable)
- Truncate (2 occurrences → 1 fonction)
- Stats (2 occurrences → 1 fonction)
- **Scan ACD** (logique répétée → 1 requête optimisée)
- **Validation dossier_code** (check pendant import → check pendant scan)

---

### 1.2 `bash/lib/arg_parser.sh` (Parsing Arguments)

**Fonctions à implémenter :**

```bash
# Parse arguments communs (--full, --incremental, --debug, -h)
parse_common_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --full)        MODE="full"; shift ;;
            --incremental) MODE="incremental"; shift ;;
            --debug)       DEBUG=true; shift ;;
            -h|--help)     return 1 ;;
            *)             return 2 ;;  # Argument inconnu
        esac
    done
}

# Parse flags multi-sources (--acd, --dia, --pennylane)
parse_source_flags() {
    SOURCES=()
    while [[ $# -gt 0 ]]; do
        case $1 in
            --acd)        SOURCES+=("acd"); shift ;;
            --dia)        SOURCES+=("dia"); shift ;;
            --pennylane)  SOURCES+=("pennylane"); shift ;;
            --all)        SOURCES=("acd" "dia" "pennylane"); shift ;;
            *)            return 2 ;;
        esac
    done
}

# Parse flags multi-couches (--raw, --transform, --mdm, --mart)
parse_layer_flags() {
    LAYERS=()
    while [[ $# -gt 0 ]]; do
        case $1 in
            --raw)       LAYERS+=("raw"); shift ;;
            --transform) LAYERS+=("transform"); shift ;;
            --mdm)       LAYERS+=("mdm"); shift ;;
            --mart)      LAYERS+=("mart"); shift ;;
            *)           return 2 ;;
        esac
    done
}
```

**Duplications résolues :** Parsing arguments (3 scripts → 3 fonctions réutilisables)

---

### 1.3 `bash/lib/file_utils.sh` (Gestion Fichiers)

**Fonctions à implémenter :**

```bash
# Export vers fichier tmp avec gestion erreurs
export_to_tmp_file() {
    local QUERY="$1"
    local OUTPUT_FILE="$2"
    local HOST="$3"
    local PORT="$4"
    local USER="$5"
    local PASS="$6"
    local ERR_FILE="/tmp/mysql_err_$$.log"
}

# Cleanup automatique avec trap
setup_cleanup_trap() {
    cleanup() {
        rm -f /tmp/acd_import_*.tsv /tmp/pl_*.csv /tmp/gl_batch_*.csv /tmp/mysql_err_*.log
    }
    trap cleanup EXIT
}
```

**Duplications résolues :** Gestion fichiers tmp (pattern répété 5+ fois)

---

### 1.4 `bash/lib/s3_utils.sh` (✨ NOUVEAU - Gestion S3)

**Fonctions à implémenter :**

```bash
# Vérifier AWS CLI installé et configuré
check_aws_cli() {
    command -v aws >/dev/null 2>&1 || {
        log "ERROR" "AWS CLI non installé"
        log "INFO" "Installation: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        return 1
    }

    # Vérifier credentials configurés
    if ! aws sts get-caller-identity &>/dev/null; then
        log "ERROR" "AWS credentials non configurées"
        log "INFO" "Configuration: aws configure"
        return 1
    fi

    return 0
}

# Créer bucket S3 si n'existe pas
create_s3_bucket_if_not_exists() {
    local BUCKET_NAME="$1"
    local REGION="${2:-us-east-1}"

    if aws s3 ls "s3://$BUCKET_NAME" 2>/dev/null; then
        log "INFO" "Bucket s3://$BUCKET_NAME existe déjà"
        return 0
    fi

    log "INFO" "Création bucket s3://$BUCKET_NAME..."
    if aws s3 mb "s3://$BUCKET_NAME" --region "$REGION"; then
        log "SUCCESS" "Bucket créé"
        return 0
    else
        log "ERROR" "Échec création bucket"
        return 1
    fi
}

# UNLOAD Redshift vers S3 (avec IAM role)
redshift_unload_to_s3() {
    local QUERY="$1"
    local S3_PATH="$2"           # s3://bucket/prefix/
    local IAM_ROLE="$3"          # arn:aws:iam::account:role/RedshiftS3Role
    local FORMAT="${4:-CSV}"     # CSV ou PARQUET
    local PARALLEL="${5:-ON}"    # ON ou OFF

    psql -h "$REDSHIFT_HOST" -p "$REDSHIFT_PORT" \
         -U "$REDSHIFT_USER" -d "$REDSHIFT_DB" <<EOF
UNLOAD ('$QUERY')
TO '$S3_PATH'
IAM_ROLE '$IAM_ROLE'
FORMAT AS $FORMAT
HEADER
PARALLEL $PARALLEL
ALLOWOVERWRITE
NULL AS 'NULL';
EOF
}

# Download fichiers S3 vers local
s3_download_files() {
    local S3_PREFIX="$1"         # s3://bucket/prefix/
    local LOCAL_DIR="$2"         # /tmp/pennylane/

    mkdir -p "$LOCAL_DIR"

    log "INFO" "Téléchargement depuis $S3_PREFIX..."
    if aws s3 sync "$S3_PREFIX" "$LOCAL_DIR" --quiet; then
        log "SUCCESS" "Fichiers téléchargés dans $LOCAL_DIR"
        return 0
    else
        log "ERROR" "Échec téléchargement S3"
        return 1
    fi
}

# Nettoyer bucket S3 (supprimer tous les fichiers d'un prefix)
s3_cleanup_prefix() {
    local S3_PREFIX="$1"

    log "INFO" "Nettoyage S3: $S3_PREFIX..."
    if aws s3 rm "$S3_PREFIX" --recursive --quiet; then
        log "SUCCESS" "S3 nettoyé"
        return 0
    else
        log "WARNING" "Échec nettoyage S3 (non bloquant)"
        return 1
    fi
}

# Normaliser fichier CSV Redshift (convertir \N en NULL pour MySQL)
normalize_redshift_csv() {
    local INPUT_FILE="$1"
    local OUTPUT_FILE="$2"

    # Remplacer \N par NULL (compatible MySQL LOAD DATA)
    sed 's/\\N/NULL/g' "$INPUT_FILE" > "$OUTPUT_FILE"
}
```

**Utilité :**
- Support export Pennylane via S3 (plus rapide et fiable que psql direct)
- Normalisation format Redshift UNLOAD → MySQL compatible
- Nettoyage automatique pour éviter coûts de stockage S3

---

### 1.4 `bash/lib/validators.sh` (Validation Input)

**Fonctions à implémenter :**

```bash
# Confirmation action destructive
confirm_destructive_action() {
    local MESSAGE="$1"
    local REQUIRED_INPUT="${2:-y}"
}

# Validation longueur code dossier
validate_dossier_code_length() {
    local CODE="$1"
    local MAX_LENGTH="${2:-20}"
}

# Check prérequis (mysql, psql clients)
check_prerequisites() {
    command -v mysql >/dev/null 2>&1 || { log "ERROR" "mysql client requis"; return 1; }
    command -v psql >/dev/null 2>&1 || { log "ERROR" "psql client requis"; return 1; }
}
```

**Duplications résolues :** Confirmation destructive (3 occurrences → 1 fonction)

---

### 1.5 `bash/lib/deps.sh` (Vérification Dépendances)

**Fonctions à implémenter :**

```bash
# Check si un schéma existe
schema_exists() {
    local SCHEMA="$1"
    $MYSQL $MYSQL_OPTS -e "USE $SCHEMA" 2>/dev/null
}

# Check si une table a des données
table_has_data() {
    local SCHEMA="$1"
    local TABLE="$2"
    local COUNT=$($MYSQL $MYSQL_OPTS -N -e "SELECT COUNT(*) FROM $SCHEMA.$TABLE LIMIT 1" 2>/dev/null || echo 0)
    [ "$COUNT" -gt 0 ]
}

# Vérifier dépendances d'une couche
check_layer_dependencies() {
    local LAYER="$1"
    case $LAYER in
        transform)
            schema_exists "raw_acd" || return 1
            schema_exists "raw_dia" || return 1
            ;;
        mdm)
            schema_exists "transform_compta" || return 1
            ;;
        mart)
            schema_exists "mdm" || return 1
            ;;
    esac
}

# Suggérer plan de résolution
suggest_dependency_resolution() {
    local LAYER="$1"
    # Affiche les commandes à exécuter pour résoudre les dépendances manquantes
}
```

---

## Phase 2 : Configuration par Source `bash/sources/`

### 2.1 `bash/sources/acd.sh`

```bash
#!/bin/bash
# Configuration pour source ACD

SOURCE_NAME="acd"
SOURCE_SCHEMA="raw_acd"
SOURCE_HOST="$ACD_HOST"
SOURCE_PORT="$ACD_PORT"
SOURCE_USER="$ACD_USER"
SOURCE_PASS="$ACD_PASS"

SUPPORTS_INCREMENTAL=true
INCREMENTAL_TABLES=("ecriture" "ligne_ecriture")

REQUIRED_TABLES=(
    "histo_ligne_ecriture"
    "histo_ecriture"
    "ligne_ecriture"
    "ecriture"
    "compte"
    "journal"
)

# Fonction d'import spécifique ACD
import_acd() {
    local MODE="$1"
    # Appelle bash/raw/02_import_raw_compta.sh (refactorisé pour utiliser bash/lib/)
}
```

### 2.2 `bash/sources/dia.sh`

```bash
#!/bin/bash
# Configuration pour source DIA

SOURCE_NAME="dia"
SOURCE_SCHEMA="raw_dia"
SOURCE_HOST="$DIA_HOST"
SOURCE_PORT="$DIA_PORT"
SOURCE_USER="$DIA_USER"
SOURCE_PASS="$DIA_PASS"

SUPPORTS_INCREMENTAL=false

# Fonction d'import spécifique DIA
import_dia() {
    local MODE="$1"
    # Appelle bash/raw/01_import_raw_dia.sh (refactorisé)
}
```

### 2.3 `bash/sources/pennylane.sh`

```bash
#!/bin/bash
# Configuration pour source Pennylane

SOURCE_NAME="pennylane"
SOURCE_SCHEMA="raw_pennylane"
SOURCE_HOST="$REDSHIFT_HOST"
SOURCE_PORT="$REDSHIFT_PORT"
SOURCE_USER="$REDSHIFT_USER"
SOURCE_PASS="$REDSHIFT_PASS"

SUPPORTS_INCREMENTAL=true
SUPPORTS_DOSSIER_MODE=true    # ✨ NOUVEAU : Import par dossier (company_id)
BATCH_SIZE=100000             # Config pagination
S3_BUCKET="data-pipeline-pennylane"  # Bucket S3 pour export
S3_REGION="eu-west-1"         # Région AWS
REDSHIFT_IAM_ROLE="arn:aws:iam::ACCOUNT_ID:role/RedshiftS3Role"  # À configurer

# Fonction d'import spécifique Pennylane
import_pennylane() {
    local MODE="$1"
    local COMPANY_ID="${2:-}"  # ✨ NOUVEAU : company_id optionnel
    # Appelle bash/raw/03_import_raw_pennylane.sh (refactorisé avec S3)
}
```

**Nouveaux modes supportés :**
```bash
# Import complet (toutes les companies)
./data import-data --pennylane --mode=full

# Import incrémental (toutes les companies depuis last_sync_date)
./data import-data --pennylane --mode=incremental

# Import depuis une date spécifique (toutes les companies)
./data import-data --pennylane --since "01/01/2025 00:00:00"

# ✨ NOUVEAU : Import complet d'une company spécifique
./data import-data --pennylane --dossier-full COMPANY_ID

# ✨ NOUVEAU : Import incrémental d'une company spécifique
./data import-data --pennylane --dossier-incremental COMPANY_ID
```

---

## Phase 3 : Implémentation des Commandes `bash/commands/`

### 3.1 `bash/commands/clean.sh`

**Signature :**
```bash
./data clean [OPTIONS]

OPTIONS GLOBALES:
  --all                  Supprimer TOUTES les couches (RAW + TRANSFORM + MDM + MART)
  --force                Pas de confirmation (dangereux)

OPTIONS COUCHE RAW:
  --raw                  Supprimer raw_acd + raw_dia + raw_pennylane
  --acd                  Supprimer raw_acd uniquement
  --dia                  Supprimer raw_dia uniquement
  --pennylane            Supprimer raw_pennylane uniquement

OPTIONS COUCHES ANALYTIQUES:
  --transform            Supprimer transform_compta
  --mdm                  Supprimer mdm
  --mart                 Supprimer mart_pilotage_cabinet + mart_controle_gestion + mart_production_client
```

**Exemples d'utilisation :**
```bash
# Nettoyage complet (tout supprimer)
./data clean --all --force

# Nettoyage RAW uniquement
./data clean --raw                    # Supprime raw_acd + raw_dia + raw_pennylane
./data clean --acd                    # Supprime raw_acd uniquement

# Nettoyage couches analytiques
./data clean --transform --mdm --mart # Supprime TRANSFORM + MDM + MART (garde RAW)
./data clean --mart                   # Supprime uniquement MART

# Sans confirmation (automatisation)
./data clean --all --force
```

**Logique :**
1. **Parser les flags** (--all, --raw, --acd, --transform, etc.)
2. **Construire la liste des schémas à supprimer** :
   ```
   - --all : ["raw_acd", "raw_dia", "raw_pennylane", "transform_compta", "mdm", "mart_*"]
   - --raw : ["raw_acd", "raw_dia", "raw_pennylane"]
   - --acd : ["raw_acd"]
   - --transform : ["transform_compta"]
   - --mdm : ["mdm"]
   - --mart : ["mart_pilotage_cabinet", "mart_controle_gestion", "mart_production_client"]
   ```
3. **Demander confirmation** (sauf si --force) :
   ```
   ⚠️  ATTENTION : Action destructive !

   Schémas à supprimer :
     - raw_acd (3.5 GB)
     - transform_compta (890 MB)
     - mdm (120 MB)

   Continuer ? [y/N]: _
   ```
4. **Supprimer les schémas** via `DROP DATABASE IF EXISTS`
5. **Logger les résultats**

**Utilise :**
- `bash/lib/arg_parser.sh::parse_layer_flags()`
- `bash/lib/validators.sh::confirm_destructive_action()`
- `bash/lib/db_utils.sh` pour DROP DATABASE

---

### 3.2 `bash/commands/create_db.sh`

**Signature :**
```bash
./data create-db [OPTIONS]

OPTIONS GLOBALES:
  --all         Créer TOUTES les couches (RAW + TRANSFORM + MDM + MART + procédures)

OPTIONS COUCHE RAW:
  --raw         Créer raw_acd + raw_dia + raw_pennylane
  --acd         Créer raw_acd
  --dia         Créer raw_dia
  --pennylane   Créer raw_pennylane

OPTIONS COUCHES ANALYTIQUES:
  --transform   Créer transform_compta (tables + procédures)
  --mdm         Créer mdm (tables + procédures)
  --mart        Créer mart_* (vues uniquement)
```

**Exemples d'utilisation :**
```bash
# Création complète (première installation)
./data create-db --all

# Création RAW uniquement
./data create-db --raw                      # Créer raw_acd + raw_dia + raw_pennylane
./data create-db --acd                      # Créer raw_acd uniquement

# Création couches analytiques
./data create-db --transform --mdm --mart   # Créer TRANSFORM + MDM + MART
./data create-db --transform                # Créer TRANSFORM uniquement
```

**Logique :**
1. **Parser les flags**

2. **Créer schémas et tables RAW** (si demandé) :
   ```bash
   # Pour chaque source : acd, dia, pennylane
   create_schema_if_not_exists "raw_acd" "utf8mb4" "utf8mb4_general_ci"
   $MYSQL < sql/02b_raw_acd_tables.sql

   create_schema_if_not_exists "raw_dia" "utf8mb4" "utf8mb4_general_ci"
   $MYSQL < sql/02_raw_dia_tables.sql

   create_schema_if_not_exists "raw_pennylane" "utf8mb4" "utf8mb4_general_ci"
   $MYSQL < sql/02_raw_pennylane_tables.sql
   ```

3. **Créer TRANSFORM** (si --transform ou --all) :
   ```bash
   create_schema_if_not_exists "transform_compta" "utf8mb4" "utf8mb4_general_ci"
   $MYSQL < sql/03_transform_tables.sql
   $MYSQL < sql/06_procedures_transform_part1.sql
   $MYSQL < sql/06_procedures_transform_part2.sql
   ```

4. **Créer MDM** (si --mdm ou --all) :
   ```bash
   create_schema_if_not_exists "mdm" "utf8mb4" "utf8mb4_general_ci"
   $MYSQL < sql/04_mdm_tables.sql
   $MYSQL < sql/07_procedures_mdm.sql
   ```

5. **Créer MART** (si --mart ou --all) :
   ```bash
   # Les schémas MART sont créés automatiquement par les vues
   $MYSQL < sql/05_mart_views.sql  # Crée mart_pilotage_cabinet, mart_controle_gestion, etc.
   ```

6. **Créer orchestrateur** (si --all) :
   ```bash
   $MYSQL < sql/08_procedures_orchestrator.sql
   ```

7. **Logger les résultats** à chaque étape

**Utilise :**
- `bash/lib/db_utils.sh::create_schema_if_not_exists()`
- Scripts SQL existants dans `sql/` :
  - `sql/01_create_schemas.sql` (schémas globaux)
  - `sql/02b_raw_acd_tables.sql`
  - `sql/02_raw_dia_tables.sql`
  - `sql/02_raw_pennylane_tables.sql`
  - `sql/03_transform_tables.sql`
  - `sql/04_mdm_tables.sql`
  - `sql/05_mart_views.sql`
  - `sql/06_procedures_transform_part1.sql`
  - `sql/06_procedures_transform_part2.sql`
  - `sql/07_procedures_mdm.sql`
  - `sql/08_procedures_orchestrator.sql`

---

### 3.3 `bash/commands/import_data.sh`

**Signature :**
```bash
./data import-data [OPTIONS]

OPTIONS SOURCES (couche RAW):
  --all                          Importer toutes les sources RAW
  --acd                          Importer ACD
  --dia                          Importer DIA
  --pennylane                    Importer Pennylane

OPTIONS COUCHES ANALYTIQUES:
  --transform                    Remplir TRANSFORM (dépend de RAW)
  --mdm                          Remplir MDM (dépend de TRANSFORM)
  --mart                         Remplir MART (dépend de MDM)
  --all-layers                   RAW + TRANSFORM + MDM + MART (pipeline complet)

OPTIONS MODES:
  --mode=<full|incremental>      Mode d'import RAW (défaut: full)
                                 • full: TRUNCATE + réimport complet
                                 • incremental: Import depuis last_sync_date
                                 Note: TRANSFORM/MDM/MART exécutent toujours les procédures complètes

OPTIONS AVANCÉES:
  --check-deps                   Vérifier dépendances avant import
  --auto-resolve                 Résoudre automatiquement les dépendances
  --skip-raw                     Sauter RAW (uniquement TRANSFORM/MDM/MART)
```

**Exemples d'utilisation :**
```bash
# Import RAW uniquement
./data import-data --all --mode=full             # DIA + ACD + Pennylane (full)
./data import-data --acd --mode=incremental      # ACD incrémental uniquement

# Import par dossier (ACD ou Pennylane)
./data import-data --acd --dossier-full SCIANNAFOO
./data import-data --pennylane --dossier-incremental COMPANY_123

# Pipeline complet RAW → TRANSFORM → MDM → MART
./data import-data --all-layers --mode=incremental

# Couches analytiques uniquement (sans RAW)
./data import-data --transform --mdm --mart --skip-raw

# Avec vérification dépendances
./data import-data --transform --check-deps      # Vérifie que RAW existe
./data import-data --mdm --check-deps --auto-resolve  # Résout automatiquement
```

**Logique :**
1. **Parser les flags** (sources + couches + mode)
2. **Vérifier dépendances** si `--check-deps` :
   ```
   - TRANSFORM dépend de : raw_acd, raw_dia, raw_pennylane
   - MDM dépend de : transform_compta
   - MART dépend de : mdm
   ```
   - Si manquantes : afficher plan de résolution
   - Si `--auto-resolve` : exécuter automatiquement

3. **Import RAW** (si sources spécifiées) :
   - Pour chaque source : ACD, DIA, Pennylane
   - Sourcer `bash/sources/<source>.sh`
   - Vérifier si `SUPPORTS_INCREMENTAL` et `MODE=incremental`
   - Vérifier si `SUPPORTS_DOSSIER_MODE` pour modes `--dossier-*`
   - Appeler `import_<source>()` (qui appelle les scripts refactorisés)

4. **Remplir TRANSFORM** (si `--transform` ou `--all-layers`) :
   - Appeler procédures stockées MySQL :
     ```sql
     CALL transform_compta.orchestrator_transform();
     ```
   - Inclut :
     - `load_dossiers_acd()`
     - `load_dossiers_pennylane()`
     - `load_ecritures_acd()`
     - `load_ecritures_pennylane()`
     - `load_ecritures_tiers_acd()`
     - `load_ecritures_tiers_pennylane()`
     - `load_exercices()`
     - `load_temps_collaborateurs()`

5. **Remplir MDM** (si `--mdm` ou `--all-layers`) :
   - Appeler procédures stockées :
     ```sql
     CALL mdm.orchestrator_mdm();
     ```
   - Inclut :
     - `merge_dossiers()`  - Jointure SIREN ACD ↔ Pennylane
     - `merge_collaborateurs()`
     - `merge_contacts()`

6. **Remplir MART** (si `--mart` ou `--all-layers`) :
   - Les vues MART sont automatiquement rafraîchies (vues SQL)
   - Statistiques optionnelles sur les vues si nécessaire

7. **Logger les résultats** à chaque étape

**Utilise :**
- `bash/lib/deps.sh::check_layer_dependencies()`
- `bash/lib/db_utils.sh` pour exécution procédures MySQL
- `bash/sources/*.sh` (config + fonctions d'import)
- Scripts d'import refactorisés (bash/raw/*.sh utilisant bash/lib/)
- Scripts TRANSFORM/MDM existants (`bash/transform/`, `bash/mdm/`, `bash/mart/`)

---

## Phase 4 : Script Principal `./data`

**Structure :**

```bash
#!/bin/bash
# Entry point CLI unifiée

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bash/config.sh"
source "$SCRIPT_DIR/bash/logging.sh"

# Charger toutes les libs
for lib in "$SCRIPT_DIR/bash/lib"/*.sh; do
    source "$lib"
done

# Setup cleanup automatique
setup_cleanup_trap

# Check prérequis
check_prerequisites || exit 1

# Routing vers commandes
case "${1:-}" in
    clean)
        shift
        source "$SCRIPT_DIR/bash/commands/clean.sh"
        cmd_clean "$@"
        ;;
    create-db)
        shift
        source "$SCRIPT_DIR/bash/commands/create_db.sh"
        cmd_create_db "$@"
        ;;
    import-data)
        shift
        source "$SCRIPT_DIR/bash/commands/import_data.sh"
        cmd_import_data "$@"
        ;;
    -h|--help|help|"")
        show_usage
        ;;
    *)
        log "ERROR" "Commande inconnue: $1"
        show_usage
        exit 1
        ;;
esac
```

---

## Phase 5 : Dépréciation des Anciens Scripts

### 5.1 `bash/raw/01_import_raw_dia.sh` (wrapper)

```bash
#!/bin/bash
# ⚠️ DEPRECATED - Utilisez ./data import-data --dia à la place

echo "⚠️  WARNING: Ce script est déprécié."
echo "   Nouvelle commande: ./data import-data --dia $*"
echo ""
read -p "Continuer avec l'ancien script ? (y/N) " -n 1 -r
echo
[[ ! $REPLY =~ ^[Yy]$ ]] && exit 0

# Rediriger vers la CLI unifiée
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
"$SCRIPT_DIR/data" import-data --dia "$@"
```

**Même logique pour :**
- `02_import_raw_compta.sh` → `./data import-data --acd`
- `03_import_raw_pennylane.sh` → `./data import-data --pennylane`

---

## Phase 6 : Tests Automatisés

### 6.1 `tests/shellcheck.sh`

```bash
#!/bin/bash
# Tests ShellCheck sur tous les scripts bash

echo "Running ShellCheck..."

ERRORS=0

for script in bash/**/*.sh bash/lib/*.sh bash/commands/*.sh bash/sources/*.sh; do
    if [ -f "$script" ]; then
        echo "Checking $script..."
        if ! shellcheck -x "$script"; then
            ERRORS=$((ERRORS + 1))
        fi
    fi
done

if [ $ERRORS -eq 0 ]; then
    echo "✅ ShellCheck passed!"
    exit 0
else
    echo "❌ ShellCheck failed with $ERRORS errors"
    exit 1
fi
```

### 6.2 `tests/integration_test.sh`

```bash
#!/bin/bash
# Tests d'intégration avec données sample

echo "Running integration tests..."

# Test 1: Création d'un schéma
./data create-db --acd
# Vérifier que raw_acd existe
mysql ... -e "USE raw_acd" || exit 1

# Test 2: Import avec mode=full (données sample)
./data import-data --acd --mode=full
# Vérifier qu'il y a des données
COUNT=$(mysql ... -N -e "SELECT COUNT(*) FROM raw_acd.compte")
[ "$COUNT" -gt 0 ] || exit 1

# Test 3: Vérification dépendances
./data import-data --transform --check-deps
# Devrait afficher plan de résolution si raw manquant

echo "✅ Integration tests passed!"
```

---

## Phase 7 : Documentation `README.md`

**Sections à ajouter :**

```markdown
# CLI Unifiée `./data`

## Installation

```bash
chmod +x ./data
```

## Commandes

### 1. Nettoyage
```bash
./data clean --all                  # Supprimer toutes les couches
./data clean --raw                  # Supprimer raw_*
./data clean --acd --force          # Supprimer raw_acd sans confirmation
```

### 2. Création de schémas
```bash
./data create-db --all              # Créer toutes les couches
./data create-db --acd              # Créer raw_acd uniquement
```

### 3. Import de données
```bash
./data import-data --all                       # Import complet
./data import-data --acd --mode=incremental    # Import incrémental ACD
./data import-data --transform --check-deps    # Avec vérification dépendances
```

## Tests

```bash
# Tests ShellCheck
./tests/shellcheck.sh

# Tests d'intégration
./tests/integration_test.sh
```

## Migration depuis anciens scripts

| Ancien | Nouveau |
|--------|---------|
| `bash/raw/01_import_raw_dia.sh` | `./data import-data --dia` |
| `bash/raw/02_import_raw_compta.sh --full` | `./data import-data --acd --mode=full` |
| `bash/raw/03_import_raw_pennylane.sh` | `./data import-data --pennylane` |
```

---

## Phase 0 : Optimisations et Infrastructure AWS (✨ NOUVEAU)

### 0.1 Installation et configuration AWS CLI

**Prérequis :**
```bash
# Installer AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Vérifier installation
aws --version
```

**Configuration :**
```bash
# Configurer credentials (interactif)
aws configure
# AWS Access Key ID: [à saisir]
# AWS Secret Access Key: [à saisir]
# Default region name: eu-west-1
# Default output format: json

# Vérifier connexion
aws sts get-caller-identity
```

**Ajout dans `bash/config.sh` :**
```bash
# ─── Configuration S3 ───────────────────────────────────────
S3_BUCKET="${S3_BUCKET:-data-pipeline-pennylane}"
S3_REGION="${S3_REGION:-eu-west-1}"
REDSHIFT_IAM_ROLE="${REDSHIFT_IAM_ROLE:-arn:aws:iam::ACCOUNT_ID:role/RedshiftS3Role}"
```

---

### 0.2 Création du rôle IAM Redshift → S3

**Politique IAM à créer :** `RedshiftS3AccessPolicy`
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::data-pipeline-pennylane",
        "arn:aws:s3:::data-pipeline-pennylane/*"
      ]
    }
  ]
}
```

**Rôle IAM à créer :** `RedshiftS3Role`
- Trust relationship : Redshift principal
- Attachez la politique `RedshiftS3AccessPolicy`
- Attachez le rôle au cluster Redshift

**Commandes AWS CLI :**
```bash
# Créer la politique
aws iam create-policy \
  --policy-name RedshiftS3AccessPolicy \
  --policy-document file://redshift-s3-policy.json

# Créer le rôle
aws iam create-role \
  --role-name RedshiftS3Role \
  --assume-role-policy-document file://redshift-trust-policy.json

# Attacher la politique au rôle
aws iam attach-role-policy \
  --role-name RedshiftS3Role \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/RedshiftS3AccessPolicy
```

---

### 0.3 Optimisation scan ACD

**Problème actuel :**
- Le scan des ~2000 bases `compta_*` prend **7 minutes**
- Cause : Boucle qui fait `check_database_has_required_tables()` → 6 requêtes par base = 12 000 requêtes

**Solution :**
```bash
# Ancienne méthode (7 minutes)
for DB in $(mysql -e "SHOW DATABASES LIKE 'compta_%'"); do
    if check_database_has_required_tables "$DB"; then
        DATABASES+=("$DB")
    fi
done

# ✅ Nouvelle méthode (10 secondes) - UNE SEULE REQUÊTE
DATABASES=($(get_valid_acd_databases "'compta_000000','compta_zz'"))
```

**Fonction `get_valid_acd_databases()` (dans `bash/lib/db_utils.sh`) :**
```sql
SELECT t.table_schema
FROM information_schema.tables t
WHERE t.table_schema LIKE 'compta_%'
  AND t.table_schema NOT IN ('compta_000000', 'compta_zz')
  AND t.table_name IN ('histo_ligne_ecriture', 'histo_ecriture',
                       'ligne_ecriture', 'ecriture', 'compte', 'journal')
GROUP BY t.table_schema
HAVING COUNT(DISTINCT t.table_name) = 6
ORDER BY t.table_schema
```

**Gain de performance :** 7 min → 10s = **42x plus rapide**

---

### 0.4 Export Pennylane via S3

**Architecture actuelle :**
```
Redshift → psql COPY → /tmp/*.csv (local) → LOAD DATA → MariaDB
         └─ Lent, risque timeout, pas de retry granulaire
```

**Nouvelle architecture S3 :**
```
Redshift → UNLOAD → S3 → aws s3 sync → /tmp/*.csv → LOAD DATA → MariaDB
         └─ Parallèle   └─ Durable   └─ Retry     └─ Normalisé
```

**Avantages :**
1. **UNLOAD parallélisé** : Redshift découpe automatiquement en plusieurs fichiers
2. **Persistance S3** : Pas besoin de tout refaire si MariaDB échoue
3. **Retry granulaire** : On peut recharger un batch sans tout refaire
4. **Normalisation** : Conversion `\N` → `NULL` avant import MySQL
5. **Fiabilité** : Plus de timeout réseau Redshift → serveur

**Workflow détaillé :**
```bash
# 1. UNLOAD Redshift → S3 (parallèle, rapide)
redshift_unload_to_s3 \
    "SELECT * FROM accounting.general_ledger_revision WHERE ..." \
    "s3://data-pipeline-pennylane/gl/2025-01-15/" \
    "$REDSHIFT_IAM_ROLE" \
    "CSV" \
    "ON"

# 2. Download S3 → Local
s3_download_files \
    "s3://data-pipeline-pennylane/gl/2025-01-15/" \
    "/tmp/pennylane_gl/"

# 3. Normaliser CSV (si nécessaire)
for file in /tmp/pennylane_gl/*.csv; do
    normalize_redshift_csv "$file" "$file.normalized"
done

# 4. Import MySQL (avec retry par fichier)
for file in /tmp/pennylane_gl/*.csv.normalized; do
    load_data_from_file "$file" "raw_pennylane.pl_general_ledger" ...
done

# 5. Cleanup S3 (économiser coûts)
s3_cleanup_prefix "s3://data-pipeline-pennylane/gl/2025-01-15/"
```

---

## Plan d'Exécution (Ordre des Étapes)

### Étape 0 : Infrastructure AWS et optimisations (2-3h) ✨ NOUVEAU
1. Installer AWS CLI v2 et configurer credentials
2. Créer politique IAM `RedshiftS3AccessPolicy`
3. Créer rôle IAM `RedshiftS3Role` et l'attacher au cluster Redshift
4. Créer bucket S3 `data-pipeline-pennylane`
5. Ajouter config S3 dans `bash/config.sh`
6. Créer `bash/lib/s3_utils.sh` avec les 6 fonctions S3
7. Tester connexion AWS et accès S3

### Étape 1 : Création de l'infrastructure lib (3-4h)
1. Créer `bash/lib/db_utils.sh` avec les 8 fonctions (+ 2 nouvelles pour ACD)
2. Créer `bash/lib/arg_parser.sh` avec les 3 fonctions
3. Créer `bash/lib/file_utils.sh` avec les 2 fonctions
4. Créer `bash/lib/validators.sh` avec les 3 fonctions
5. Créer `bash/lib/deps.sh` avec les 4 fonctions

### Étape 2 : Configuration par source (1h)
1. Créer `bash/sources/acd.sh`
2. Créer `bash/sources/dia.sh`
3. Créer `bash/sources/pennylane.sh`

### Étape 3 : Refactoriser scripts d'import (5-6h) ✨ Modifié
1. **Optimiser** `bash/raw/02_import_raw_compta.sh` :
   - Utiliser `get_valid_acd_databases()` (7min → 10s)
   - Utiliser `validate_dossier_code_length()` pendant le scan (pas à l'import)
   - Utiliser les fonctions `bash/lib/db_utils.sh`
2. Modifier `bash/raw/01_import_raw_dia.sh` pour utiliser `bash/lib/db_utils.sh`
3. **Réécrire** `bash/raw/03_import_raw_pennylane.sh` avec S3 :
   - Ajouter modes `--dossier-full` et `--dossier-incremental` (avec company_id)
   - Remplacer `psql → /tmp` par `UNLOAD → S3 → /tmp`
   - Utiliser `bash/lib/s3_utils.sh` pour tout le workflow S3
   - Normaliser CSV Redshift (`\N` → `NULL`)
   - Cleanup S3 après import réussi
4. Tester les 3 scripts refactorisés

### Étape 4 : Commandes CLI (2-3h)
1. Créer `bash/commands/clean.sh`
2. Créer `bash/commands/create_db.sh`
3. Créer `bash/commands/import_data.sh`

### Étape 5 : Script principal (1h)
1. Créer `./data` (entry point)
2. Implémenter routing
3. Tester toutes les commandes

### Étape 6 : Dépréciation (30min)
1. Transformer anciens scripts en wrappers deprecated
2. Ajouter warnings

### Étape 7 : Tests (1-2h)
1. Créer `tests/shellcheck.sh`
2. Créer `tests/integration_test.sh`
3. Exécuter tous les tests

### Étape 8 : Documentation (1-2h)
1. Mettre à jour `README.md` avec nouvelles commandes
2. Ajouter section AWS setup et configuration S3
3. Documenter modes dossier Pennylane
4. Documenter API des fonctions (commentaires JSDoc-like)
5. Ajouter guide de migration S3

**Durée totale estimée : 17-22h** (au lieu de 12-16h)
- +2-3h pour infrastructure AWS/S3 (Étape 0)
- +2h pour optimisation ACD et réécriture Pennylane S3 (Étape 3)
- +1h pour documentation AWS (Étape 8)

---

## Métriques de Factorisation et Performance

### Code Duplication
| Avant | Après | Gain |
|-------|-------|------|
| 334+ lignes dupliquées | ~250 lignes de lib | **60% réduction** |
| 3 scripts autonomes | 1 CLI unifiée | **Cohérence** |
| Parsing args répété 3x | 3 fonctions réutilisables | **DRY** |
| LOAD DATA répété 7x | 1 fonction paramétrable | **Maintenabilité** |

### Performance (✨ NOUVEAU)
| Opération | Avant | Après | Gain |
|-----------|-------|-------|------|
| Scan ACD (2000 bases) | 7 minutes | 10 secondes | **42x plus rapide** |
| Export Pennylane | psql direct (timeout) | UNLOAD → S3 (parallèle) | **Fiabilité + Vitesse** |
| Validation dossier_code | À l'import (après export) | Au scan (avant export) | **Économie CPU/réseau** |

### Nouvelles Fonctionnalités
- ✅ Import Pennylane par dossier (`--dossier-full`, `--dossier-incremental`)
- ✅ Export via S3 avec retry granulaire et nettoyage automatique
- ✅ Validation dossier_code anticipée (économise exports inutiles)
- ✅ Normalisation CSV Redshift → MySQL dans la couche RAW

---

## Fichiers Critiques à Modifier

### 1. Nouveaux fichiers
- `data` (script principal CLI)
- `bash/lib/*.sh` (6 fichiers) ✨ +1 pour s3_utils.sh
  - `db_utils.sh` (8 fonctions, +2 pour ACD)
  - `arg_parser.sh` (3 fonctions)
  - `file_utils.sh` (2 fonctions)
  - `validators.sh` (3 fonctions)
  - `deps.sh` (4 fonctions)
  - `s3_utils.sh` (6 fonctions) ✨ NOUVEAU
- `bash/sources/*.sh` (3 fichiers)
- `bash/commands/*.sh` (3 fichiers)
- `tests/*.sh` (2 fichiers)

### 2. Fichiers à refactoriser
- `bash/raw/01_import_raw_dia.sh` (factorisation basique)
- `bash/raw/02_import_raw_compta.sh` ✨ **Optimisation critique** (scan 7min → 10s)
- `bash/raw/03_import_raw_pennylane.sh` ✨ **Réécriture complète** (S3 + modes dossier)

### 3. Fichiers à mettre à jour
- `bash/config.sh` ✨ +config S3 (bucket, region, IAM role)
- `README.md` (CLI doc + AWS setup)
- `claude.md` (marquer Phase 7 comme implémentée)

### 4. Infrastructure AWS (✨ NOUVEAU)
- Bucket S3 : `data-pipeline-pennylane`
- Politique IAM : `RedshiftS3AccessPolicy`
- Rôle IAM : `RedshiftS3Role`

**Total : ~24 fichiers touchés** (+4 par rapport au plan initial)
