#!/bin/bash
# ============================================================
# PIPELINE COMPLET - ORCHESTRATEUR PRINCIPAL
# Exécute le pipeline complet : RAW → TRANSFORM → MDM → MART
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bash/config.sh"
source "$SCRIPT_DIR/bash/logging.sh"

# ─── Arguments ─────────────────────────────────────────────
SKIP_RAW=false
SKIP_TRANSFORM=false
SKIP_MDM=false
SKIP_MART=false
SKIP_INIT=false
INIT_ONLY=false
DATA_ONLY=false
ACD_MODE="--full"  # Par défaut: import complet ACD

usage() {
    cat <<'EOF'
Usage: ./run_pipeline.sh [OPTIONS]

┌─────────────────────────────────────────────────────────────────┐
│ OPTIONS GÉNÉRALES                                               │
└─────────────────────────────────────────────────────────────────┘
  --skip-raw        Sauter l'import RAW
  --skip-transform  Sauter la couche TRANSFORM
  --skip-mdm        Sauter la couche MDM
  --skip-mart       Sauter la couche MART
  --skip-init       Sauter la création des schémas/tables/procédures

┌─────────────────────────────────────────────────────────────────┐
│ OPTIONS RACCOURCIS                                              │
└─────────────────────────────────────────────────────────────────┘
  --transform-only  Exécuter uniquement TRANSFORM
  --mdm-only        Exécuter uniquement MDM
  --mart-only       Exécuter uniquement MART

┌─────────────────────────────────────────────────────────────────┐
│ OPTIONS SPÉCIALES                                               │
└─────────────────────────────────────────────────────────────────┘
  --init-only       Créer schémas/tables/procédures (sans données)
  --data-only       Import données uniquement (sans création)

┌─────────────────────────────────────────────────────────────────┐
│ OPTIONS RAW ACD                                                 │
└─────────────────────────────────────────────────────────────────┘
  --acd-full        Import complet (TRUNCATE + réimport) [défaut]
  --acd-incremental Import incrémental (nouveautés uniquement)

┌─────────────────────────────────────────────────────────────────┐
│ EXEMPLES - CAS D'USAGE ADMIN SYSTÈME                           │
└─────────────────────────────────────────────────────────────────┘

📦 INSTALLATION INITIALE (première fois)
  ./run_pipeline.sh --init-only
  ./run_pipeline.sh --data-only --acd-full

🔄 IMPORT QUOTIDIEN (cron 2h00 du matin)
  ./run_pipeline.sh --skip-init --acd-incremental

🔧 RÉIMPORT COMPLET (hebdomadaire ou après incident)
  bash bash/util/clean_all.sh
  ./run_pipeline.sh --acd-full

⚡ IMPORT RAW UNIQUEMENT (sans TRANSFORM/MDM/MART)
  ./run_pipeline.sh --skip-init --skip-transform --skip-mdm --skip-mart

🐛 DEBUG : Recréer uniquement les procédures stockées
  ./run_pipeline.sh --init-only --skip-raw

🚨 URGENCE : Import ACD sans toucher au reste
  bash bash/raw/02_import_raw_compta.sh --full

📊 REBUILD couches analytiques (RAW OK, refaire le reste)
  ./run_pipeline.sh --skip-raw --skip-init

🧪 TEST : Valider structure avant import massif
  ./run_pipeline.sh --init-only
  # Vérifier manuellement avec SELECT * FROM sync_tracking;

💾 BACKUP avant grosse opération
  mysqldump raw_acd transform_compta mdm > backup_$(date +%Y%m%d).sql
  ./run_pipeline.sh --acd-full

🔍 MONITORING : Vérifier l'état
  mysql -e "SELECT * FROM raw_acd.sync_tracking;"
  tail -f logs/pipeline_*.log

EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-raw)        SKIP_RAW=true; shift ;;
        --skip-transform)  SKIP_TRANSFORM=true; shift ;;
        --skip-mdm)        SKIP_MDM=true; shift ;;
        --skip-mart)       SKIP_MART=true; shift ;;
        --skip-init)       SKIP_INIT=true; shift ;;
        --transform-only)  SKIP_RAW=true; SKIP_MDM=true; SKIP_MART=true; shift ;;
        --mdm-only)        SKIP_RAW=true; SKIP_TRANSFORM=true; SKIP_MART=true; shift ;;
        --mart-only)       SKIP_RAW=true; SKIP_TRANSFORM=true; SKIP_MDM=true; shift ;;
        --init-only)       INIT_ONLY=true; shift ;;
        --data-only)       DATA_ONLY=true; SKIP_INIT=true; shift ;;
        --acd-full)        ACD_MODE="--acd-full"; shift ;;
        --acd-incremental) ACD_MODE="--acd-incremental"; shift ;;
        -h|--help)         usage ;;
        *)                 echo "Option inconnue: $1"; usage ;;
    esac
done

# ─── Démarrage ─────────────────────────────────────────────
log_section "🚀 PIPELINE DATA ARCHITECTURE - PHASE 1"
PIPELINE_START=$(date +%s)

log "INFO" "Configuration:"
echo "  SKIP_RAW:       $SKIP_RAW"
echo "  SKIP_TRANSFORM: $SKIP_TRANSFORM"
echo "  SKIP_MDM:       $SKIP_MDM"
echo "  SKIP_MART:      $SKIP_MART"
echo "  SKIP_INIT:      $SKIP_INIT"
echo "  INIT_ONLY:      $INIT_ONLY"
echo "  DATA_ONLY:      $DATA_ONLY"
echo "  ACD_MODE:       $ACD_MODE"

# ─── Initialisation (création des schémas) ─────────────────
if [ "$SKIP_INIT" = false ]; then
    log_subsection "Initialisation des schémas, tables et procédures"
    
    log "INFO" "Création des schémas..."
    $MYSQL $MYSQL_OPTS < "$SCRIPT_DIR/sql/01_create_schemas.sql"

    log "INFO" "Création des tables RAW Pennylane..."
    $MYSQL $MYSQL_OPTS < "$SCRIPT_DIR/sql/02_raw_pennylane_tables.sql"

    log "INFO" "Création des tables RAW ACD..."
    $MYSQL $MYSQL_OPTS < "$SCRIPT_DIR/sql/02b_raw_acd_tables.sql"

    log "INFO" "Création des tables TRANSFORM..."
    $MYSQL $MYSQL_OPTS < "$SCRIPT_DIR/sql/03_transform_tables.sql"

    log "INFO" "Création des tables MDM..."
    $MYSQL $MYSQL_OPTS < "$SCRIPT_DIR/sql/04_mdm_tables.sql"

    log "INFO" "Création des vues MART..."
    $MYSQL $MYSQL_OPTS < "$SCRIPT_DIR/sql/05_mart_views.sql"

    log "INFO" "Création des procédures TRANSFORM..."
    $MYSQL $MYSQL_OPTS < "$SCRIPT_DIR/sql/06_procedures_transform_part1.sql"
    $MYSQL $MYSQL_OPTS < "$SCRIPT_DIR/sql/06_procedures_transform_part2.sql"
    $MYSQL $MYSQL_OPTS < "$SCRIPT_DIR/sql/08_procedures_orchestrator.sql"

    log "INFO" "Création des procédures MDM..."
    $MYSQL $MYSQL_OPTS < "$SCRIPT_DIR/sql/07_procedures_mdm.sql"

    log "SUCCESS" "Schémas, tables et procédures initialisés"
    
    # Si --init-only, on s'arrête là
    if [ "$INIT_ONLY" = true ]; then
        PIPELINE_END=$(date +%s)
        PIPELINE_DURATION=$((PIPELINE_END - PIPELINE_START))
        log_section "✅ INITIALISATION TERMINÉE (--init-only)"
        log "SUCCESS" "Durée: $(($PIPELINE_DURATION / 60)) min $(($PIPELINE_DURATION % 60)) sec"
        log "INFO" "Schémas créés: raw_dia, raw_pennylane, transform_compta, mdm, mart_*"
        exit 0
    fi
else
    log "INFO" "⏭️  Initialisation ignorée (--skip-init ou --data-only)"
fi

# ─── Mode DATA_ONLY : Import RAW uniquement ────────────────
if [ "$DATA_ONLY" = true ]; then
    log_subsection "MODE DATA-ONLY : Import des données RAW"

    log "INFO" "Import raw_acd (ACD - mode: $ACD_MODE)..."
    bash "$SCRIPT_DIR/bash/raw/02_import_raw_compta.sh" "$ACD_MODE"

    log "INFO" "Import raw_dia (DIA/valoxy)..."
    bash "$SCRIPT_DIR/bash/raw/01_import_raw_dia.sh"

    log "INFO" "Import raw_pennylane (Redshift)..."
    bash "$SCRIPT_DIR/bash/raw/03_import_raw_pennylane.sh"
    
    PIPELINE_END=$(date +%s)
    PIPELINE_DURATION=$((PIPELINE_END - PIPELINE_START))
    log_section "✅ IMPORT DONNÉES TERMINÉ (--data-only)"
    log "SUCCESS" "Durée: $(($PIPELINE_DURATION / 60)) min $(($PIPELINE_DURATION % 60)) sec"
    
    log "INFO" "Résumé des imports:"
    $MYSQL $MYSQL_OPTS -t -e "
    SELECT 'raw_dia' AS source, COUNT(*) AS nb_tables
    FROM information_schema.tables WHERE table_schema = 'raw_dia'
    UNION ALL
    SELECT 'raw_acd', COUNT(DISTINCT dossier_code)
    FROM raw_acd.histo_ligne_ecriture
    UNION ALL
    SELECT 'raw_pennylane', COUNT(*)
    FROM information_schema.tables WHERE table_schema = 'raw_pennylane';
    "
    exit 0
fi

# ─── Couche RAW ────────────────────────────────────────────
if [ "$SKIP_RAW" = false ]; then
    log_subsection "COUCHE RAW"
    bash "$SCRIPT_DIR/bash/raw/run_all_raw.sh" "$ACD_MODE"
else
    log "INFO" "⏭️  RAW ignoré (--skip-raw)"
fi

# ─── Couche TRANSFORM ──────────────────────────────────────
if [ "$SKIP_TRANSFORM" = false ]; then
    log_subsection "COUCHE TRANSFORM"
    bash "$SCRIPT_DIR/bash/transform/run_transform.sh"
else
    log "INFO" "⏭️  TRANSFORM ignoré (--skip-transform)"
fi

# ─── Couche MDM ────────────────────────────────────────────
if [ "$SKIP_MDM" = false ]; then
    log_subsection "COUCHE MDM"
    bash "$SCRIPT_DIR/bash/mdm/run_mdm.sh"
else
    log "INFO" "⏭️  MDM ignoré (--skip-mdm)"
fi

# ─── Couche MART ───────────────────────────────────────────
if [ "$SKIP_MART" = false ]; then
    log_subsection "COUCHE MART"
    bash "$SCRIPT_DIR/bash/mart/run_mart.sh"
else
    log "INFO" "⏭️  MART ignoré (--skip-mart)"
fi

# ─── Résumé final ──────────────────────────────────────────
PIPELINE_END=$(date +%s)
PIPELINE_DURATION=$((PIPELINE_END - PIPELINE_START))

log_section "✅ PIPELINE TERMINÉ"
log "SUCCESS" "Durée totale: $(($PIPELINE_DURATION / 60)) min $(($PIPELINE_DURATION % 60)) sec"

log "INFO" "Résumé des volumes:"
$MYSQL $MYSQL_OPTS -t -e "
SELECT 'RAW' AS couche, 'raw_dia' AS schema_name, COUNT(*) AS nb_tables
FROM information_schema.tables WHERE table_schema = 'raw_dia'
UNION ALL
SELECT 'RAW', 'raw_acd', COUNT(DISTINCT dossier_code)
FROM raw_acd.histo_ligne_ecriture
UNION ALL
SELECT 'RAW', 'raw_pennylane', COUNT(*)
FROM information_schema.tables WHERE table_schema = 'raw_pennylane'
UNION ALL
SELECT 'TRANSFORM', 'ecritures_mensuelles', COUNT(*)
FROM transform_compta.ecritures_mensuelles
UNION ALL
SELECT 'MDM', 'dossiers', COUNT(*)
FROM mdm.dossiers
UNION ALL
SELECT 'MART', 'vues pilotage', COUNT(*)
FROM information_schema.views WHERE table_schema = 'mart_pilotage_cabinet';
"

log "INFO" "Logs disponibles dans: $LOG_DIR"
