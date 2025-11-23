#!/bin/bash
# ============================================================
# BENCHMARK IMPORT ACD - Test de performance
# Compare différentes méthodes d'import pour 10 bases
# Génère un rapport détaillé des temps d'exécution
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/logging.sh"

# ─── Configuration du benchmark ────────────────────────────
NB_BASES_TEST=10
RESULTS_FILE="benchmark_results_$(date +%Y%m%d_%H%M%S).txt"

log_section "🔬 BENCHMARK IMPORT ACD - 10 BASES"

# ─── Récupérer 10 bases compta_* pour le test ─────────────
log "INFO" "Sélection de $NB_BASES_TEST bases pour le benchmark..."

TEST_DATABASES=$($MYSQL -h "$ACD_HOST" -P "$ACD_PORT" -u "$ACD_USER" -p"$ACD_PASS" --skip-column-names -e "
    SELECT schema_name
    FROM information_schema.schemata
    WHERE schema_name LIKE 'compta_%'
    AND schema_name NOT IN ('compta_000000', 'compta_zz')
    LIMIT $NB_BASES_TEST
" | grep "compta_")

if [ -z "$TEST_DATABASES" ]; then
    log "ERROR" "Aucune base trouvée pour le test"
    exit 1
fi

NB_FOUND=$(echo "$TEST_DATABASES" | wc -l)
log "INFO" "$NB_FOUND bases sélectionnées pour le benchmark"
echo "$TEST_DATABASES" | while read db; do echo "  - $db"; done

# Créer le fichier de résultats
cat > "$RESULTS_FILE" << 'EOF'
════════════════════════════════════════════════════════════════
  BENCHMARK IMPORT ACD - RÉSULTATS
════════════════════════════════════════════════════════════════

Configuration du test:
EOF

echo "  - Nombre de bases: $NB_FOUND" >> "$RESULTS_FILE"
echo "  - Serveur source: $ACD_HOST:$ACD_PORT" >> "$RESULTS_FILE"
echo "  - Date: $(date '+%Y-%m-%d %H:%M:%S')" >> "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"

# ─── MÉTHODE 1: INSERT SELECT (actuel) ────────────────────
test_method_1() {
    local PARALLEL="$1"
    local METHOD_NAME="INSERT_SELECT"
    local PREFIX="test_m1_p${PARALLEL}"

    log "INFO" "Test Méthode 1 (INSERT SELECT) - Parallélisme: $PARALLEL"

    # Créer schéma de test
    $MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS ${PREFIX}_raw_acd;"
    $MYSQL $MYSQL_OPTS -e "CREATE DATABASE ${PREFIX}_raw_acd;"
    $MYSQL $MYSQL_OPTS ${PREFIX}_raw_acd < "$SCRIPT_DIR/../sql/02b_raw_acd_tables.sql"

    START=$(date +%s)

    # Fonction d'import (comme le script actuel)
    import_insert_select() {
        local DB="$1"
        local DOSSIER_CODE="${DB#compta_}"
        local PREFIX="$2"

        for TABLE in histo_ligne_ecriture histo_ecriture ligne_ecriture ecriture compte journal; do
            $MYSQL -h "$ACD_HOST" -P "$ACD_PORT" -u "$ACD_USER" -p"$ACD_PASS" \
                --compress -e "
                INSERT INTO ${PREFIX}_raw_acd.$TABLE
                SELECT '$DOSSIER_CODE' as dossier_code, t.*
                FROM \`$DB\`.\`$TABLE\` t;
            " 2>/dev/null
        done
        echo "OK: $DB"
    }

    export -f import_insert_select
    export ACD_HOST ACD_PORT ACD_USER ACD_PASS MYSQL

    echo "$TEST_DATABASES" | xargs -P "$PARALLEL" -I {} bash -c \
        "import_insert_select '{}' '$PREFIX'" 2>&1 | grep -c "OK:" > /dev/null

    END=$(date +%s)
    DURATION=$((END - START))

    # Compter les lignes importées
    TOTAL_ROWS=$($MYSQL $MYSQL_OPTS -N -e "
        SELECT SUM(table_rows)
        FROM information_schema.tables
        WHERE table_schema = '${PREFIX}_raw_acd'
    ")

    echo "${METHOD_NAME}_P${PARALLEL}|${DURATION}|${TOTAL_ROWS}"

    # Nettoyer
    $MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS ${PREFIX}_raw_acd;"
}

# ─── MÉTHODE 2: MYSQLDUMP SÉLECTIF (6 tables) ─────────────
test_method_2() {
    local PARALLEL="$1"
    local METHOD_NAME="DUMP_SELECTIVE"
    local PREFIX="test_m2_p${PARALLEL}"

    log "INFO" "Test Méthode 2 (MYSQLDUMP SÉLECTIF) - Parallélisme: $PARALLEL"

    # Créer schéma de test
    $MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS ${PREFIX}_raw_acd;"
    $MYSQL $MYSQL_OPTS -e "CREATE DATABASE ${PREFIX}_raw_acd;"
    $MYSQL $MYSQL_OPTS ${PREFIX}_raw_acd < "$SCRIPT_DIR/../sql/02b_raw_acd_tables.sql"

    START=$(date +%s)

    # Fonction d'import avec mysqldump sélectif
    import_dump_selective() {
        local DB="$1"
        local DOSSIER_CODE="${DB#compta_}"
        local PREFIX="$2"

        # Dump seulement les 6 tables
        for TABLE in histo_ligne_ecriture histo_ecriture ligne_ecriture ecriture compte journal; do
            $MYSQLDUMP -h "$ACD_HOST" -P "$ACD_PORT" -u "$ACD_USER" -p"$ACD_PASS" \
                --compress \
                --no-create-info \
                --skip-triggers \
                --complete-insert \
                "$DB" "$TABLE" 2>/dev/null \
            | sed "s/INSERT INTO \`$TABLE\`/INSERT INTO \`${PREFIX}_raw_acd\`.\`$TABLE\`/g" \
            | sed "s/VALUES (/VALUES ('$DOSSIER_CODE',/g" \
            | $MYSQL $MYSQL_OPTS 2>/dev/null
        done
        echo "OK: $DB"
    }

    export -f import_dump_selective
    export ACD_HOST ACD_PORT ACD_USER ACD_PASS MYSQL MYSQLDUMP

    echo "$TEST_DATABASES" | xargs -P "$PARALLEL" -I {} bash -c \
        "import_dump_selective '{}' '$PREFIX'" 2>&1 | grep -c "OK:" > /dev/null

    END=$(date +%s)
    DURATION=$((END - START))

    TOTAL_ROWS=$($MYSQL $MYSQL_OPTS -N -e "
        SELECT SUM(table_rows)
        FROM information_schema.tables
        WHERE table_schema = '${PREFIX}_raw_acd'
    ")

    echo "${METHOD_NAME}_P${PARALLEL}|${DURATION}|${TOTAL_ROWS}"

    # Nettoyer
    $MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS ${PREFIX}_raw_acd;"
}

# ─── MÉTHODE 3: MYSQLDUMP COMPLET (toutes tables) ─────────
test_method_3() {
    local PARALLEL="$1"
    local METHOD_NAME="DUMP_FULL"
    local PREFIX="test_m3_p${PARALLEL}"

    log "INFO" "Test Méthode 3 (MYSQLDUMP COMPLET) - Parallélisme: $PARALLEL"

    START=$(date +%s)

    # Fonction d'import avec mysqldump complet (comme l'ancien script)
    import_dump_full() {
        local DB="$1"
        local PREFIX="$2"
        local LOCAL_DB="${PREFIX}_${DB}"

        # Créer la base locale
        $MYSQL $MYSQL_OPTS -e "CREATE DATABASE IF NOT EXISTS \`$LOCAL_DB\`;"

        # Dump complet de la base
        $MYSQLDUMP -h "$ACD_HOST" -P "$ACD_PORT" -u "$ACD_USER" -p"$ACD_PASS" \
            --compress \
            --databases "$DB" 2>/dev/null \
        | sed "s/CREATE DATABASE.*\`$DB\`/CREATE DATABASE IF NOT EXISTS \`$LOCAL_DB\`/g" \
        | sed "s/USE \`$DB\`/USE \`$LOCAL_DB\`/g" \
        | $MYSQL $MYSQL_OPTS 2>/dev/null

        echo "OK: $DB"
    }

    export -f import_dump_full
    export ACD_HOST ACD_PORT ACD_USER ACD_PASS MYSQL MYSQLDUMP

    echo "$TEST_DATABASES" | xargs -P "$PARALLEL" -I {} bash -c \
        "import_dump_full '{}' '$PREFIX'" 2>&1 | grep -c "OK:" > /dev/null

    END=$(date +%s)
    DURATION=$((END - START))

    # Compter toutes les tables créées
    TOTAL_TABLES=$($MYSQL $MYSQL_OPTS -N -e "
        SELECT COUNT(*)
        FROM information_schema.tables
        WHERE table_schema LIKE '${PREFIX}_%'
    ")

    echo "${METHOD_NAME}_P${PARALLEL}|${DURATION}|${TOTAL_TABLES} tables"

    # Nettoyer
    for DB in $TEST_DATABASES; do
        $MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS ${PREFIX}_${DB};"
    done
}

# ─── Exécution des tests ───────────────────────────────────
echo "════════════════════════════════════════════════════════" >> "$RESULTS_FILE"
echo "RÉSULTATS DÉTAILLÉS" >> "$RESULTS_FILE"
echo "════════════════════════════════════════════════════════" >> "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"

declare -A RESULTS

# Test toutes les combinaisons
for PARALLEL in 1 2 3; do
    log_section "Tests avec parallélisme = $PARALLEL"

    # Méthode 1: INSERT SELECT
    RESULT=$(test_method_1 $PARALLEL)
    RESULTS["M1_P${PARALLEL}"]="$RESULT"
    echo "$RESULT" >> "$RESULTS_FILE"

    # Méthode 2: MYSQLDUMP SÉLECTIF
    RESULT=$(test_method_2 $PARALLEL)
    RESULTS["M2_P${PARALLEL}"]="$RESULT"
    echo "$RESULT" >> "$RESULTS_FILE"

    # Méthode 3: MYSQLDUMP COMPLET
    RESULT=$(test_method_3 $PARALLEL)
    RESULTS["M3_P${PARALLEL}"]="$RESULT"
    echo "$RESULT" >> "$RESULTS_FILE"

    echo "" >> "$RESULTS_FILE"
done

# ─── Générer le tableau récapitulatif ─────────────────────
log_section "📊 GÉNÉRATION DU RAPPORT FINAL"

cat >> "$RESULTS_FILE" << 'EOF'

════════════════════════════════════════════════════════════════
  TABLEAU RÉCAPITULATIF (temps en secondes)
════════════════════════════════════════════════════════════════

| Méthode                    | P=1 | P=2 | P=3 | Meilleur | Recommandation |
|----------------------------|-----|-----|-----|----------|----------------|
EOF

# Parser les résultats pour créer le tableau
parse_duration() {
    echo "$1" | cut -d'|' -f2
}

# Méthode 1
M1P1=$(parse_duration "${RESULTS[M1_P1]}")
M1P2=$(parse_duration "${RESULTS[M1_P2]}")
M1P3=$(parse_duration "${RESULTS[M1_P3]}")
M1_BEST=$(printf "%s\n" "$M1P1" "$M1P2" "$M1P3" | sort -n | head -1)

# Méthode 2
M2P1=$(parse_duration "${RESULTS[M2_P1]}")
M2P2=$(parse_duration "${RESULTS[M2_P2]}")
M2P3=$(parse_duration "${RESULTS[M2_P3]}")
M2_BEST=$(printf "%s\n" "$M2P1" "$M2P2" "$M2P3" | sort -n | head -1)

# Méthode 3
M3P1=$(parse_duration "${RESULTS[M3_P1]}")
M3P2=$(parse_duration "${RESULTS[M3_P2]}")
M3P3=$(parse_duration "${RESULTS[M3_P3]}")
M3_BEST=$(printf "%s\n" "$M3P1" "$M3P2" "$M3P3" | sort -n | head -1)

cat >> "$RESULTS_FILE" << EOF
| INSERT SELECT (actuel)     | ${M1P1}s | ${M1P2}s | ${M1P3}s | ${M1_BEST}s | $([ "$M1_BEST" = "$M1P1" ] && echo "P=1 ⭐" || ([ "$M1_BEST" = "$M1P2" ] && echo "P=2 ⭐" || echo "P=3 ⭐")) |
| MYSQLDUMP Sélectif (6 tbl) | ${M2P1}s | ${M2P2}s | ${M2P3}s | ${M2_BEST}s | $([ "$M2_BEST" = "$M2P1" ] && echo "P=1 ⭐" || ([ "$M2_BEST" = "$M2P2" ] && echo "P=2 ⭐" || echo "P=3 ⭐")) |
| MYSQLDUMP Complet (ancien) | ${M3P1}s | ${M3P2}s | ${M3P3}s | ${M3_BEST}s | $([ "$M3_BEST" = "$M3P1" ] && echo "P=1 ⭐" || ([ "$M3_BEST" = "$M3P2" ] && echo "P=2 ⭐" || echo "P=3 ⭐")) |

════════════════════════════════════════════════════════════════
  ESTIMATION POUR 3500 BASES
════════════════════════════════════════════════════════════════

EOF

# Calculer les estimations pour 3500 bases
M1_ESTIMATE=$((M1_BEST * 3500 / NB_FOUND))
M2_ESTIMATE=$((M2_BEST * 3500 / NB_FOUND))
M3_ESTIMATE=$((M3_BEST * 3500 / NB_FOUND))

cat >> "$RESULTS_FILE" << EOF
Méthode 1 (INSERT SELECT)      : $(($M1_ESTIMATE / 3600))h $(($M1_ESTIMATE % 3600 / 60))min
Méthode 2 (MYSQLDUMP Sélectif) : $(($M2_ESTIMATE / 3600))h $(($M2_ESTIMATE % 3600 / 60))min
Méthode 3 (MYSQLDUMP Complet)  : $(($M3_ESTIMATE / 3600))h $(($M3_ESTIMATE % 3600 / 60))min

════════════════════════════════════════════════════════════════
  RECOMMANDATION FINALE
════════════════════════════════════════════════════════════════

EOF

# Trouver la méthode la plus rapide
OVERALL_BEST=$(printf "%s\n" "$M1_BEST" "$M2_BEST" "$M3_BEST" | sort -n | head -1)

if [ "$OVERALL_BEST" = "$M1_BEST" ]; then
    cat >> "$RESULTS_FILE" << 'EOF'
✅ MÉTHODE RECOMMANDÉE: INSERT SELECT (script actuel)

Avantages:
- Import sélectif (6 tables uniquement)
- Moins de stockage
- Compatible avec la structure raw_acd

Configuration optimale:
EOF
    if [ "$M1_BEST" = "$M1P1" ]; then
        echo "  PARALLEL_JOBS=1 (machine source avec 1 CPU)" >> "$RESULTS_FILE"
    elif [ "$M1_BEST" = "$M1P2" ]; then
        echo "  PARALLEL_JOBS=2 (bon compromis)" >> "$RESULTS_FILE"
    else
        echo "  PARALLEL_JOBS=3 (performance maximale)" >> "$RESULTS_FILE"
    fi
elif [ "$OVERALL_BEST" = "$M2_BEST" ]; then
    echo "✅ MÉTHODE RECOMMANDÉE: MYSQLDUMP SÉLECTIF" >> "$RESULTS_FILE"
elif [ "$OVERALL_BEST" = "$M3_BEST" ]; then
    echo "⚠️  MÉTHODE LA PLUS RAPIDE: MYSQLDUMP COMPLET (ancien script)" >> "$RESULTS_FILE"
    echo "" >> "$RESULTS_FILE"
    echo "Attention: Cette méthode copie TOUTES les tables, pas seulement les 6 requises." >> "$RESULTS_FILE"
    echo "Incompatible avec l'architecture raw_acd centralisée." >> "$RESULTS_FILE"
fi

echo "" >> "$RESULTS_FILE"
echo "Rapport sauvegardé dans: $RESULTS_FILE" >> "$RESULTS_FILE"

# ─── Afficher le rapport ───────────────────────────────────
log_section "📄 RAPPORT FINAL"
cat "$RESULTS_FILE"

log "SUCCESS" "Benchmark terminé ! Résultats sauvegardés dans: $RESULTS_FILE"
