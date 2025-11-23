#!/bin/bash
# ============================================================
# CLEANUP RAW_PENNYLANE - Nettoyage et maintenance
# Options:
#   --stats    : Afficher les statistiques
#   --truncate : Vider toutes les tables
#   --drop     : Supprimer complètement le schéma
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/logging.sh"

# ─── Fonctions ─────────────────────────────────────────────

show_stats() {
    log_section "STATISTIQUES RAW_PENNYLANE"

    log "INFO" "Volumétrie des tables:"
    $MYSQL $MYSQL_OPTS raw_pennylane -t -e "
        SELECT
            'pl_companies' AS 'Table',
            FORMAT(COUNT(*), 0) AS 'Nb lignes'
        FROM pl_companies
        UNION ALL
        SELECT 'acc_companies_identification', FORMAT(COUNT(*), 0)
        FROM acc_companies_identification
        UNION ALL
        SELECT 'pl_fiscal_years', FORMAT(COUNT(*), 0)
        FROM pl_fiscal_years
        UNION ALL
        SELECT 'pl_general_ledger', FORMAT(COUNT(*), 0)
        FROM pl_general_ledger;
    "

    log "INFO" "Taille des données:"
    $MYSQL $MYSQL_OPTS -t -e "
        SELECT
            table_name AS 'Table',
            CONCAT(ROUND(data_length / 1024 / 1024, 2), ' MB') AS 'Données',
            CONCAT(ROUND(index_length / 1024 / 1024, 2), ' MB') AS 'Index',
            CONCAT(ROUND((data_length + index_length) / 1024 / 1024, 2), ' MB') AS 'Total'
        FROM information_schema.tables
        WHERE table_schema = 'raw_pennylane'
        ORDER BY (data_length + index_length) DESC;
    "

    # Si la table sync_tracking existe
    if $MYSQL $MYSQL_OPTS -e "USE raw_pennylane; SHOW TABLES LIKE 'sync_tracking';" 2>/dev/null | grep -q sync_tracking; then
        log "INFO" "Historique des imports:"
        $MYSQL $MYSQL_OPTS raw_pennylane -t -e "
            SELECT
                table_name AS 'Table',
                last_sync_type AS 'Mode',
                DATE_FORMAT(last_sync_date, '%d/%m/%Y %H:%i:%s') AS 'Dernier import',
                last_status AS 'Statut'
            FROM sync_tracking
            ORDER BY last_sync_date DESC;
        "
    fi
}

truncate_tables() {
    log "WARNING" "Vidage de toutes les tables raw_pennylane..."

    read -p "Êtes-vous sûr ? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "Annulé"
        exit 0
    fi

    $MYSQL $MYSQL_OPTS raw_pennylane -e "
        SET FOREIGN_KEY_CHECKS=0;
        TRUNCATE TABLE pl_companies;
        TRUNCATE TABLE acc_companies_identification;
        TRUNCATE TABLE pl_fiscal_years;
        TRUNCATE TABLE pl_general_ledger;
        SET FOREIGN_KEY_CHECKS=1;
    "

    log "SUCCESS" "Tables vidées"
}

drop_schema() {
    log "WARNING" "ATTENTION : Suppression complète du schéma raw_pennylane !"
    read -p "Tapez 'DELETE' pour confirmer : " -r
    echo

    if [ "$REPLY" != "DELETE" ]; then
        log "INFO" "Annulé"
        exit 0
    fi

    $MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS raw_pennylane;"
    log "SUCCESS" "Schéma raw_pennylane supprimé"
}

# ─── Arguments ─────────────────────────────────────────────

if [ $# -eq 0 ]; then
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  --stats     Afficher les statistiques"
    echo "  --truncate  Vider toutes les tables (avec confirmation)"
    echo "  --drop      Supprimer complètement le schéma (avec confirmation)"
    echo ""
    echo "Exemples:"
    echo "  $0 --stats"
    echo "  $0 --truncate"
    echo "  $0 --drop"
    exit 0
fi

case $1 in
    --stats)
        show_stats
        ;;
    --truncate)
        truncate_tables
        ;;
    --drop)
        drop_schema
        ;;
    *)
        echo "Option inconnue: $1"
        echo "Utilisez sans argument pour l'aide"
        exit 1
        ;;
esac
