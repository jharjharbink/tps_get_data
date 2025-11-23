#!/bin/bash
# ============================================================
# CLEANUP RAW_ACD - Nettoyage et maintenance
# Options:
#   --stats           : Afficher les statistiques
#   --dossier CODE    : Supprimer un dossier spécifique
#   --year YYYY       : Supprimer une année complète
#   --before DATE     : Supprimer avant une date
#   --optimize        : Optimiser les tables
#   --full            : Vider complètement raw_acd
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/logging.sh"

# ─── Fonctions ─────────────────────────────────────────────

show_stats() {
    log_section "STATISTIQUES RAW_ACD"

    log "INFO" "Volumétrie des tables:"
    $MYSQL $MYSQL_OPTS raw_acd -t -e "
        SELECT
            table_name AS 'Table',
            FORMAT(rows_count, 0) AS 'Nb lignes',
            last_sync_type AS 'Mode',
            DATE_FORMAT(last_sync_date, '%Y-%m-%d %H:%i') AS 'Dernière synchro',
            CONCAT(last_duration_sec, 's') AS 'Durée',
            last_status AS 'Statut'
        FROM sync_tracking
        ORDER BY table_name;
    "

    log "INFO" "Taille des données:"
    $MYSQL $MYSQL_OPTS -t -e "
        SELECT
            table_name AS 'Table',
            CONCAT(ROUND(data_length / 1024 / 1024, 2), ' MB') AS 'Données',
            CONCAT(ROUND(index_length / 1024 / 1024, 2), ' MB') AS 'Index',
            CONCAT(ROUND((data_length + index_length) / 1024 / 1024, 2), ' MB') AS 'Total'
        FROM information_schema.tables
        WHERE table_schema = 'raw_acd'
        AND table_name IN ('histo_ligne_ecriture', 'histo_ecriture', 'ligne_ecriture', 'ecriture', 'compte', 'journal')
        ORDER BY (data_length + index_length) DESC;
    "

    NB_DOSSIERS=$($MYSQL $MYSQL_OPTS -N -e "SELECT COUNT(DISTINCT dossier_code) FROM raw_acd.histo_ligne_ecriture")
    log "INFO" "Nombre de dossiers centralisés : $NB_DOSSIERS"
}

delete_dossier() {
    local DOSSIER="$1"
    log "WARNING" "Suppression du dossier $DOSSIER..."

    read -p "Êtes-vous sûr ? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "Annulé"
        exit 0
    fi

    for TABLE in histo_ligne_ecriture histo_ecriture ligne_ecriture ecriture compte journal; do
        $MYSQL $MYSQL_OPTS raw_acd -e "DELETE FROM $TABLE WHERE dossier_code = '$DOSSIER';"
    done

    log "SUCCESS" "Dossier $DOSSIER supprimé"
}

delete_year() {
    local YEAR="$1"
    log "WARNING" "Suppression de l'année $YEAR..."

    read -p "Êtes-vous sûr ? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "Annulé"
        exit 0
    fi

    for TABLE in histo_ligne_ecriture histo_ecriture ligne_ecriture ecriture; do
        if [[ "$TABLE" == histo_* ]]; then
            YEAR_FIELD="HE_ANNEE"
        else
            YEAR_FIELD="ECR_ANNEE"
        fi

        $MYSQL $MYSQL_OPTS raw_acd -e "DELETE FROM $TABLE WHERE $YEAR_FIELD = $YEAR;"
    done

    log "SUCCESS" "Année $YEAR supprimée"
}

delete_before() {
    local DATE="$1"
    log "WARNING" "Suppression des écritures avant $DATE..."

    read -p "Êtes-vous sûr ? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "Annulé"
        exit 0
    fi

    for TABLE in histo_ligne_ecriture histo_ecriture ligne_ecriture ecriture; do
        if [[ "$TABLE" == histo_* ]]; then
            DATE_FIELD="HE_DATE_SAI"
        else
            DATE_FIELD="ECR_DATE_SAI"
        fi

        $MYSQL $MYSQL_OPTS raw_acd -e "DELETE FROM $TABLE WHERE $DATE_FIELD < '$DATE';"
    done

    log "SUCCESS" "Écritures avant $DATE supprimées"
}

optimize_tables() {
    log "INFO" "Optimisation des tables raw_acd..."

    for TABLE in histo_ligne_ecriture histo_ecriture ligne_ecriture ecriture compte journal; do
        log "INFO" "Optimisation de $TABLE..."
        $MYSQL $MYSQL_OPTS raw_acd -e "OPTIMIZE TABLE $TABLE;"
    done

    log "SUCCESS" "Tables optimisées"
}

full_cleanup() {
    log "WARNING" "ATTENTION : Vous allez vider complètement raw_acd !"
    read -p "Tapez 'DELETE ALL' pour confirmer : " -r
    echo

    if [ "$REPLY" != "DELETE ALL" ]; then
        log "INFO" "Annulé"
        exit 0
    fi

    $MYSQL $MYSQL_OPTS raw_acd -e "
        SET FOREIGN_KEY_CHECKS=0;
        TRUNCATE TABLE histo_ligne_ecriture;
        TRUNCATE TABLE histo_ecriture;
        TRUNCATE TABLE ligne_ecriture;
        TRUNCATE TABLE ecriture;
        TRUNCATE TABLE compte;
        TRUNCATE TABLE journal;
        UPDATE sync_tracking SET rows_count = 0, last_status = 'pending';
        SET FOREIGN_KEY_CHECKS=1;
    "

    log "SUCCESS" "raw_acd complètement vidée"
}

# ─── Arguments ─────────────────────────────────────────────

if [ $# -eq 0 ]; then
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  --stats              Afficher les statistiques"
    echo "  --dossier CODE       Supprimer un dossier (ex: 00123)"
    echo "  --year YYYY          Supprimer une année complète"
    echo "  --before DATE        Supprimer avant une date (YYYY-MM-DD)"
    echo "  --optimize           Optimiser les tables"
    echo "  --full               Vider complètement raw_acd (avec confirmation)"
    echo ""
    echo "Exemples:"
    echo "  $0 --stats"
    echo "  $0 --dossier 00123"
    echo "  $0 --year 2020"
    echo "  $0 --before 2022-01-01"
    echo "  $0 --optimize"
    exit 0
fi

case $1 in
    --stats)
        show_stats
        ;;
    --dossier)
        delete_dossier "$2"
        ;;
    --year)
        delete_year "$2"
        ;;
    --before)
        delete_before "$2"
        ;;
    --optimize)
        optimize_tables
        ;;
    --full)
        full_cleanup
        ;;
    *)
        echo "Option inconnue: $1"
        echo "Utilisez --help pour l'aide"
        exit 1
        ;;
esac
