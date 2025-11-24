#!/bin/bash
# ============================================================
# BENCHMARK IMPORT ACD - Test de performance (10 scénarios)
#
# Méthode 1 : INSERT SELECT SANS batching
#   - M1   : sans batching
#   - M1-2 : batching 50k sur histo_ligne_ecriture / histo_ecriture / ligne_ecriture / ecriture
#   - M1-3 : batching 100k sur ces mêmes 4 tables
#
# Méthode 2 : INSERT SELECT AVEC batching sur TOUTES les tables
#   - M2   : batching 50k
#   - M2-2 : batching 50k (2e run)
#   - M2-3 : batching 100k
#
# Méthode 3 : INSERT SELECT AVEC batching sur tables d'écritures uniquement
#   - M3   : batching 50k
#   - M3-2 : batching 50k (2e run)
#   - M3-3 : batching 100k
#
# Méthode 4 : DUMP COMPLET (référence)
#
# Parallélisme : P=1 (séquentiel)
# Bases testées : 9 bases lourdes ACD
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/logging.sh"

# ─── Configuration générale ─────────────────────────────────

BATCH_50K=50000
BATCH_100K=100000
RESULTS_FILE="benchmark_results_$(date +%Y%m%d_%H%M%S).txt"

# Bases lourdes à utiliser
TEST_DATABASES="
compta_assculfort
compta_cashparis
compta_ctabilan
compta_formnf
compta_linkuma
compta_movitex
compta_proc1
compta_sasauxsecr
compta_stli
"

NB_FOUND=$(echo "$TEST_DATABASES" | sed '/^$/d' | wc -l)

log_section "🔬 BENCHMARK IMPORT ACD - 10 tests (P=1, bases lourdes)"
log "INFO" "Nombre de bases utilisées : $NB_FOUND"
echo "$TEST_DATABASES" | sed '/^$/d' | while read -r db; do echo "  - $db"; done

# ─── SQL d'index et de partitions (config) ──────────────────

SQL_INDEXES="
ALTER TABLE histo_ligne_ecriture
    ADD KEY idx_date_sai (HE_DATE_SAI),
    ADD KEY idx_compte (CPT_CODE),
    ADD KEY idx_journal (JNL_CODE);

ALTER TABLE histo_ecriture
    ADD KEY idx_date_sai (HE_DATE_SAI),
    ADD KEY idx_date_ecr (HE_DATE_ECR);

ALTER TABLE ligne_ecriture
    ADD KEY idx_date_sai (ECR_DATE_SAI),
    ADD KEY idx_compte (CPT_CODE),
    ADD KEY idx_journal (JNL_CODE);

ALTER TABLE ecriture
    ADD KEY idx_date_sai (ECR_DATE_SAI),
    ADD KEY idx_date_ecr (ECR_DATE_ECR);

ALTER TABLE compte
    ADD KEY idx_type (CPT_TYPE);

ALTER TABLE journal
    ADD KEY idx_type (JNL_TYPE);
"

SQL_PARTITIONS="
ALTER TABLE histo_ligne_ecriture
    PARTITION BY RANGE (HE_ANNEE) (
        PARTITION p2020 VALUES LESS THAN (2021),
        PARTITION p2021 VALUES LESS THAN (2022),
        PARTITION p2022 VALUES LESS THAN (2023),
        PARTITION p2023 VALUES LESS THAN (2024),
        PARTITION p2024 VALUES LESS THAN (2025),
        PARTITION p2025 VALUES LESS THAN (2026),
        PARTITION p_future VALUES LESS THAN MAXVALUE
    );

ALTER TABLE histo_ecriture
    PARTITION BY RANGE (HE_ANNEE) (
        PARTITION p2020 VALUES LESS THAN (2021),
        PARTITION p2021 VALUES LESS THAN (2022),
        PARTITION p2022 VALUES LESS THAN (2023),
        PARTITION p2023 VALUES LESS THAN (2024),
        PARTITION p2024 VALUES LESS THAN (2025),
        PARTITION p2025 VALUES LESS THAN (2026),
        PARTITION p_future VALUES LESS THAN MAXVALUE
    );

ALTER TABLE ligne_ecriture
    PARTITION BY RANGE (ECR_ANNEE) (
        PARTITION p2020 VALUES LESS THAN (2021),
        PARTITION p2021 VALUES LESS THAN (2022),
        PARTITION p2022 VALUES LESS THAN (2023),
        PARTITION p2023 VALUES LESS THAN (2024),
        PARTITION p2024 VALUES LESS THAN (2025),
        PARTITION p2025 VALUES LESS THAN (2026),
        PARTITION p_future VALUES LESS THAN MAXVALUE
    );

ALTER TABLE ecriture
    PARTITION BY RANGE (ECR_ANNEE) (
        PARTITION p2020 VALUES LESS THAN (2021),
        PARTITION p2021 VALUES LESS THAN (2022),
        PARTITION p2022 VALUES LESS THAN (2023),
        PARTITION p2023 VALUES LESS THAN (2024),
        PARTITION p2024 VALUES LESS THAN (2025),
        PARTITION p2025 VALUES LESS THAN (2026),
        PARTITION p_future VALUES LESS THAN MAXVALUE
    );
"

create_indexes() {
    local DB="$1"

    local START_IDX END_IDX DURATION_IDX
    START_IDX=$(date +%s)

    echo "$SQL_INDEXES"    | $MYSQL $MYSQL_OPTS "$DB"
    echo "$SQL_PARTITIONS" | $MYSQL $MYSQL_OPTS "$DB"

    END_IDX=$(date +%s)
    DURATION_IDX=$((END_IDX - START_IDX))

    log "INFO" "[${DB}] Création index/partitions : ${DURATION_IDX}s"

    echo "$DURATION_IDX"
}

# ─── Fichier de résultats ───────────────────────────────────

cat > "$RESULTS_FILE" << EOF
════════════════════════════════════════════════════════════════
  BENCHMARK IMPORT ACD - RÉSULTATS
════════════════════════════════════════════════════════════════

Configuration du test:
  - Nombre de bases: $NB_FOUND
  - Serveur source: $ACD_HOST:$ACD_PORT
  - Date: $(date '+%Y-%m-%d %H:%M:%S')
  - Parallélisme: P=1 (séquentiel)
  - Batchs testés: 50 000 et 100 000 lignes
  - Bases: $(echo "$TEST_DATABASES" | tr '\n' ' ' | sed 's/  */ /g')
EOF

echo "" >> "$RESULTS_FILE"

# ─── Helpers communs ────────────────────────────────────────

create_schema_raw_acd() {
    local PREFIX="$1"
    $MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS ${PREFIX}_raw_acd;"
    $MYSQL $MYSQL_OPTS -e "CREATE DATABASE ${PREFIX}_raw_acd;"
    $MYSQL $MYSQL_OPTS "${PREFIX}_raw_acd" < "$SCRIPT_DIR/../sql/02b_raw_acd_tables.sql"
}

count_rows_raw_acd() {
    local PREFIX="$1"
    $MYSQL $MYSQL_OPTS -N -e "
        SELECT COALESCE(SUM(table_rows),0)
        FROM information_schema.tables
        WHERE table_schema = '${PREFIX}_raw_acd'
    " || echo "0"
}

# ────────────────────────────────────────────────────────────
# MÉTHODE 1 : INSERT SELECT SANS batching
# ────────────────────────────────────────────────────────────
test_method_insert_select_no_batch() {
    local METHOD_NAME="$1"   # M1
    local PREFIX="$2"        # test_m1

    log_section "Test $METHOD_NAME : INSERT SELECT SANS batching"

    create_schema_raw_acd "$PREFIX"

    local START IMPORT_END END
    START=$(date +%s)

    import_no_batch() {
        local DB="$1"
        local DOSSIER_CODE="${DB#compta_}"
        local PREFIX="$2"

        for TABLE in histo_ligne_ecriture histo_ecriture ligne_ecriture ecriture compte journal; do
            $MYSQL -h "$ACD_HOST" -P "$ACD_PORT" -u "$ACD_USER" -p"$ACD_PASS" \
                --compress -e "
                INSERT INTO ${PREFIX}_raw_acd.$TABLE
                SELECT '$DOSSIER_CODE' as dossier_code, t.*
                FROM \`$DB\`.\`$TABLE\` t;
            " 2>/dev/null || true
        done
        echo "OK: $DB"
    }

    export -f import_no_batch
    export ACD_HOST ACD_PORT ACD_USER ACD_PASS MYSQL MYSQL_OPTS

    for DB in $TEST_DATABASES; do
        import_no_batch "$DB" "$PREFIX"
    done

    IMPORT_END=$(date +%s)

    local IDX_DURATION
    IDX_DURATION=$(create_indexes "${PREFIX}_raw_acd")

    END=$(date +%s)

    local IMPORT_DURATION=$((IMPORT_END - START))
    local TOTAL_DURATION=$((END - START))

    local TOTAL_ROWS
    TOTAL_ROWS=$(count_rows_raw_acd "$PREFIX")

    log "INFO" "[$METHOD_NAME] Import=${IMPORT_DURATION}s + Index=${IDX_DURATION}s -> Total=${TOTAL_DURATION}s - Lignes: $TOTAL_ROWS"
    echo "Résultat $METHOD_NAME: ${TOTAL_DURATION}s - $TOTAL_ROWS lignes"

    local RESULT="${METHOD_NAME}|${TOTAL_DURATION}|${TOTAL_ROWS}"

    $MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS ${PREFIX}_raw_acd;"

    echo "$RESULT"
}

# ────────────────────────────────────────────────────────────
# MÉTHODE 2 : batching TOUTES les tables
# ────────────────────────────────────────────────────────────
test_method_insert_batched_all() {
    local METHOD_NAME="$1"   # M2, M2-2, M2-3
    local PREFIX="$2"
    local BATCH_SIZE="$3"

    log_section "Test $METHOD_NAME : INSERT SELECT batching TOUTES tables (batch=${BATCH_SIZE})"

    create_schema_raw_acd "$PREFIX"

    local START IMPORT_END END
    START=$(date +%s)

    import_batched_all() {
        local DB="$1"
        local DOSSIER_CODE="${DB#compta_}"
        local PREFIX="$2"
        local BATCH_SIZE="$3"

        for TABLE in histo_ligne_ecriture histo_ecriture ligne_ecriture ecriture compte journal; do
            local TOTAL OFFSET
            TOTAL=$($MYSQL -h "$ACD_HOST" -P "$ACD_PORT" -u "$ACD_USER" -p"$ACD_PASS" -N -e "
                SELECT COUNT(*) FROM \`$DB\`.\`$TABLE\`
            " 2>/dev/null || echo "0")

            if [ "$TOTAL" -eq 0 ]; then
                continue
            fi

            OFFSET=0
            while [ "$OFFSET" -lt "$TOTAL" ]; do
                $MYSQL -h "$ACD_HOST" -P "$ACD_PORT" -u "$ACD_USER" -p"$ACD_PASS" \
                    --compress -e "
                    INSERT INTO ${PREFIX}_raw_acd.$TABLE
                    SELECT '$DOSSIER_CODE' as dossier_code, t.*
                    FROM \`$DB\`.\`$TABLE\` t
                    LIMIT $OFFSET, $BATCH_SIZE;
                " 2>/dev/null || true

                OFFSET=$((OFFSET + BATCH_SIZE))
            done
        done
        echo "OK: $DB"
    }

    export -f import_batched_all
    export ACD_HOST ACD_PORT ACD_USER ACD_PASS MYSQL MYSQL_OPTS

    for DB in $TEST_DATABASES; do
        import_batched_all "$DB" "$PREFIX" "$BATCH_SIZE"
    done

    IMPORT_END=$(date +%s)

    local IDX_DURATION
    IDX_DURATION=$(create_indexes "${PREFIX}_raw_acd")

    END=$(date +%s)

    local IMPORT_DURATION=$((IMPORT_END - START))
    local TOTAL_DURATION=$((END - START))

    local TOTAL_ROWS
    TOTAL_ROWS=$(count_rows_raw_acd "$PREFIX")

    log "INFO" "[$METHOD_NAME] Import=${IMPORT_DURATION}s + Index=${IDX_DURATION}s -> Total=${TOTAL_DURATION}s - Lignes: $TOTAL_ROWS"
    echo "Résultat $METHOD_NAME: ${TOTAL_DURATION}s - $TOTAL_ROWS lignes"

    local RESULT="${METHOD_NAME}|${TOTAL_DURATION}|${TOTAL_ROWS}"

    $MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS ${PREFIX}_raw_acd;"

    echo "$RESULT"
}

# ────────────────────────────────────────────────────────────
# MÉTHODE 3 : batching sur tables d'écritures uniquement
# ────────────────────────────────────────────────────────────
test_method_insert_batched_ecritures() {
    local METHOD_NAME="$1"   # M1-2, M1-3, M3, M3-2, M3-3
    local PREFIX="$2"
    local BATCH_SIZE="$3"

    log_section "Test $METHOD_NAME : INSERT SELECT batching ÉCRITURES (batch=${BATCH_SIZE})"

    create_schema_raw_acd "$PREFIX"

    local START IMPORT_END END
    START=$(date +%s)

    import_batched_ecritures() {
        local DB="$1"
        local DOSSIER_CODE="${DB#compta_}"
        local PREFIX="$2"
        local BATCH_SIZE="$3"

        for TABLE in histo_ligne_ecriture histo_ecriture ligne_ecriture ecriture compte journal; do

            if [[ "$TABLE" == "compte" ]] || [[ "$TABLE" == "journal" ]]; then
                $MYSQL -h "$ACD_HOST" -P "$ACD_PORT" -u "$ACD_USER" -p"$ACD_PASS" \
                    --compress -e "
                    INSERT INTO ${PREFIX}_raw_acd.$TABLE
                    SELECT '$DOSSIER_CODE' as dossier_code, t.*
                    FROM \`$DB\`.\`$TABLE\` t;
                " 2>/dev/null || true
                continue
            fi

            local TOTAL OFFSET
            TOTAL=$($MYSQL -h "$ACD_HOST" -P "$ACD_PORT" -u "$ACD_USER" -p"$ACD_PASS" -N -e "
                SELECT COUNT(*) FROM \`$DB\`.\`$TABLE\`
            " 2>/dev/null || echo "0")

            if [ "$TOTAL" -eq 0 ]; then
                continue
            fi

            OFFSET=0
            while [ "$OFFSET" -lt "$TOTAL" ]; do
                $MYSQL -h "$ACD_HOST" -P "$ACD_PORT" -u "$ACD_USER" -p"$ACD_PASS" \
                    --compress -e "
                    INSERT INTO ${PREFIX}_raw_acd.$TABLE
                    SELECT '$DOSSIER_CODE' as dossier_code, t.*
                    FROM \`$DB\`.\`$TABLE\` t
                    LIMIT $OFFSET, $BATCH_SIZE;
                " 2>/dev/null || true

                OFFSET=$((OFFSET + BATCH_SIZE))
            done
        done
        echo "OK: $DB"
    }

    export -f import_batched_ecritures
    export ACD_HOST ACD_PORT ACD_USER ACD_PASS MYSQL MYSQL_OPTS

    for DB in $TEST_DATABASES; do
        import_batched_ecritures "$DB" "$PREFIX" "$BATCH_SIZE"
    done

    IMPORT_END=$(date +%s)

    local IDX_DURATION
    IDX_DURATION=$(create_indexes "${PREFIX}_raw_acd")

    END=$(date +%s)

    local IMPORT_DURATION=$((IMPORT_END - START))
    local TOTAL_DURATION=$((END - START))

    local TOTAL_ROWS
    TOTAL_ROWS=$(count_rows_raw_acd "$PREFIX")

    log "INFO" "[$METHOD_NAME] Import=${IMPORT_DURATION}s + Index=${IDX_DURATION}s -> Total=${TOTAL_DURATION}s - Lignes: $TOTAL_ROWS"
    echo "Résultat $METHOD_NAME: ${TOTAL_DURATION}s - $TOTAL_ROWS lignes"

    local RESULT="${METHOD_NAME}|${TOTAL_DURATION}|${TOTAL_ROWS}"

    $MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS ${PREFIX}_raw_acd;"

    echo "$RESULT"
}

# ────────────────────────────────────────────────────────────
# MÉTHODE 4 : DUMP COMPLET (mysqldump)
# ────────────────────────────────────────────────────────────
test_method_dump_full() {
    local METHOD_NAME="$1"   # M4
    local PREFIX="$2"        # test_m4

    log_section "Test $METHOD_NAME : DUMP COMPLET (mysqldump --databases)"

    local START END DURATION
    START=$(date +%s)

    import_dump_full() {
        local DB="$1"
        local PREFIX="$2"
        local LOCAL_DB="${PREFIX}_${DB}"

        $MYSQL $MYSQL_OPTS -e "CREATE DATABASE IF NOT EXISTS \`$LOCAL_DB\`;"

        $MYSQLDUMP -h "$ACD_HOST" -P "$ACD_PORT" -u "$ACD_USER" -p"$ACD_PASS" \
            --compress \
            --databases "$DB" 2>/dev/null \
        | sed "s/CREATE DATABASE.*\`$DB\`/CREATE DATABASE IF NOT EXISTS \`$LOCAL_DB\`/g" \
        | sed "s/USE \`$DB\`/USE \`$LOCAL_DB\`/g" \
        | $MYSQL $MYSQL_OPTS 2>/dev/null || true

        echo "OK: $DB"
    }

    export -f import_dump_full
    export ACD_HOST ACD_PORT ACD_USER ACD_PASS MYSQL MYSQLDUMP MYSQL_OPTS

    for DB in $TEST_DATABASES; do
        import_dump_full "$DB" "$PREFIX"
    done

    END=$(date +%s)
    DURATION=$((END - START))

    local TOTAL_TABLES TOTAL_ROWS
    TOTAL_TABLES=$($MYSQL $MYSQL_OPTS -N -e "
        SELECT COUNT(*)
        FROM information_schema.tables
        WHERE table_schema LIKE '${PREFIX}_%'
    " || echo "0")

    TOTAL_ROWS=$($MYSQL $MYSQL_OPTS -N -e "
        SELECT COALESCE(SUM(table_rows),0)
        FROM information_schema.tables
        WHERE table_schema LIKE '${PREFIX}_%'
    " || echo "0")

    log "INFO" "[$METHOD_NAME] Total=${DURATION}s - Tables: $TOTAL_TABLES - Lignes: $TOTAL_ROWS"
    echo "Résultat $METHOD_NAME: ${DURATION}s - ${TOTAL_TABLES} tables - ${TOTAL_ROWS} lignes"

    local RESULT="${METHOD_NAME}|${DURATION}|${TOTAL_TABLES} tables|${TOTAL_ROWS} lignes"

    for DB in $TEST_DATABASES; do
        $MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS ${PREFIX}_${DB};" 2>/dev/null || true
    done

    echo "$RESULT"
}

# ─── Exécution des 10 tests ────────────────────────────────

echo "════════════════════════════════════════════════════════" >> "$RESULTS_FILE"
echo "RÉSULTATS DÉTAILLÉS" >> "$RESULTS_FILE"
echo "════════════════════════════════════════════════════════" >> "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"

declare -A RESULTS

RESULT=$(test_method_insert_select_no_batch "M1" "test_m1" 2>&1 | tail -n 1)
RESULTS["M1"]="$RESULT"
echo "M1  : $RESULT" >> "$RESULTS_FILE"

RESULT=$(test_method_insert_batched_ecritures "M1-2" "test_m1_2" "$BATCH_50K" 2>&1 | tail -n 1)
RESULTS["M1-2"]="$RESULT"
echo "M1-2: $RESULT" >> "$RESULTS_FILE"

RESULT=$(test_method_insert_batched_ecritures "M1-3" "test_m1_3" "$BATCH_100K" 2>&1 | tail -n 1)
RESULTS["M1-3"]="$RESULT"
echo "M1-3: $RESULT" >> "$RESULTS_FILE"

RESULT=$(test_method_insert_batched_all "M2" "test_m2" "$BATCH_50K" 2>&1 | tail -n 1)
RESULTS["M2"]="$RESULT"
echo "M2  : $RESULT" >> "$RESULTS_FILE"

RESULT=$(test_method_insert_batched_all "M2-2" "test_m2_2" "$BATCH_50K" 2>&1 | tail -n 1)
RESULTS["M2-2"]="$RESULT"
echo "M2-2: $RESULT" >> "$RESULTS_FILE"

RESULT=$(test_method_insert_batched_all "M2-3" "test_m2_3" "$BATCH_100K" 2>&1 | tail -n 1)
RESULTS["M2-3"]="$RESULT"
echo "M2-3: $RESULT" >> "$RESULTS_FILE"

RESULT=$(test_method_insert_batched_ecritures "M3" "test_m3" "$BATCH_50K" 2>&1 | tail -n 1)
RESULTS["M3"]="$RESULT"
echo "M3  : $RESULT" >> "$RESULTS_FILE"

RESULT=$(test_method_insert_batched_ecritures "M3-2" "test_m3_2" "$BATCH_50K" 2>&1 | tail -n 1)
RESULTS["M3-2"]="$RESULT"
echo "M3-2: $RESULT" >> "$RESULTS_FILE"

RESULT=$(test_method_insert_batched_ecritures "M3-3" "test_m3_3" "$BATCH_100K" 2>&1 | tail -n 1)
RESULTS["M3-3"]="$RESULT"
echo "M3-3: $RESULT" >> "$RESULTS_FILE"

RESULT=$(test_method_dump_full "M4" "test_m4" 2>&1 | tail -n 1)
RESULTS["M4"]="$RESULT"
echo "M4  : $RESULT" >> "$RESULTS_FILE"

echo "" >> "$RESULTS_FILE"

# ─── Synthèse simple sur les durées ────────────────────────

log_section "📊 RÉCAPITULATIF DES DURÉES"

parse_duration() { echo "$1" | cut -d'|' -f2; }

M1_DUR=$(parse_duration "${RESULTS[M1]}")
M1_2_DUR=$(parse_duration "${RESULTS[M1-2]}")
M1_3_DUR=$(parse_duration "${RESULTS[M1-3]}")
M2_DUR=$(parse_duration "${RESULTS[M2]}")
M2_2_DUR=$(parse_duration "${RESULTS[M2-2]}")
M2_3_DUR=$(parse_duration "${RESULTS[M2-3]}")
M3_DUR=$(parse_duration "${RESULTS[M3]}")
M3_2_DUR=$(parse_duration "${RESULTS[M3-2]}")
M3_3_DUR=$(parse_duration "${RESULTS[M3-3]}")
M4_DUR=$(parse_duration "${RESULTS[M4]}")

cat >> "$RESULTS_FILE" << EOF
════════════════════════════════════════════════════════════════
  RÉCAPITULATIF DES DURÉES (en secondes)
════════════════════════════════════════════════════════════════

| ID   | Méthode                                    | Batch       | Durée (s) |
|------|--------------------------------------------|-------------|-----------|
| M1   | INSERT SELECT SANS batching                | Aucun       | ${M1_DUR} |
| M1-2 | Méthode 1 - batching ÉCRITURES             | 50 000      | ${M1_2_DUR} |
| M1-3 | Méthode 1 - batching ÉCRITURES             | 100 000     | ${M1_3_DUR} |
| M2   | Méthode 2 - batching TOUTES tables         | 50 000      | ${M2_DUR} |
| M2-2 | Méthode 2 - batching TOUTES tables (bis)   | 50 000      | ${M2_2_DUR} |
| M2-3 | Méthode 2 - batching TOUTES tables         | 100 000     | ${M2_3_DUR} |
| M3   | Méthode 3 - batching ÉCRITURES             | 50 000      | ${M3_DUR} |
| M3-2 | Méthode 3 - batching ÉCRITURES (bis)       | 50 000      | ${M3_2_DUR} |
| M3-3 | Méthode 3 - batching ÉCRITURES             | 100 000     | ${M3_3_DUR} |
| M4   | DUMP COMPLET (référence)                   | N/A         | ${M4_DUR} |

EOF

log_section "📄 RAPPORT FINAL"
cat "$RESULTS_FILE"

log "SUCCESS" "Benchmark terminé. Résultats : $RESULTS_FILE"
