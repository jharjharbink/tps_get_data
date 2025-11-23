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
BATCH_SIZE=100000  # Batching pour tables d'écritures
RESULTS_FILE="benchmark_results_$(date +%Y%m%d_%H%M%S).txt"

log_section "🔬 BENCHMARK IMPORT ACD"

# ─── Récupérer N bases compta_* pour le test ──────────────
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
echo "  - Parallélisme: P=1 (machine source 1 CPU)" >> "$RESULTS_FILE"
echo "  - Batch size: $BATCH_SIZE lignes (tables écritures)" >> "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"

# ─── MÉTHODE 1: INSERT SELECT standard SANS batching ──────
test_method_insert_select_no_batch() {
    local METHOD_NAME="INSERT_NO_BATCH"
    local PREFIX="test_m1"

    log_section "Test Méthode 1: INSERT SELECT SANS batching (script actuel)"

    # Créer schéma de test
    $MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS ${PREFIX}_raw_acd;"
    $MYSQL $MYSQL_OPTS -e "CREATE DATABASE ${PREFIX}_raw_acd;"

    # Modifier le fichier SQL pour utiliser la base de test
    sed "s/USE raw_acd;/USE ${PREFIX}_raw_acd;/" "$SCRIPT_DIR/../sql/02b_raw_acd_tables.sql" | $MYSQL $MYSQL_OPTS

    START=$(date +%s)

    # Fonction d'import standard SANS batching
    import_no_batch() {
        local DB="$1"
        local DOSSIER_CODE="${DB#compta_}"
        local PREFIX="$2"

        for TABLE in histo_ligne_ecriture histo_ecriture ligne_ecriture ecriture compte journal; do
            # INSERT SELECT complet (toute la table d'un coup - SANS batching)
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
    export ACD_HOST ACD_PORT ACD_USER ACD_PASS MYSQL

    # Import séquentiel (P=1)
    for DB in $TEST_DATABASES; do
        import_no_batch "$DB" "$PREFIX"
    done

    END=$(date +%s)
    DURATION=$((END - START))

    # Compter les lignes importées
    TOTAL_ROWS=$($MYSQL $MYSQL_OPTS -N -e "
        SELECT SUM(table_rows)
        FROM information_schema.tables
        WHERE table_schema = '${PREFIX}_raw_acd'
    " || echo "0")

    log "INFO" "Durée: ${DURATION}s - Lignes: $TOTAL_ROWS"

    # Retourner UNIQUEMENT le résultat (sans logs)
    RESULT="${METHOD_NAME}|${DURATION}|${TOTAL_ROWS}"

    # Nettoyer
    $MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS ${PREFIX}_raw_acd;"

    # Retourner le résultat
    echo "$RESULT"
}

# ─── MÉTHODE 2: INSERT SELECT AVEC batching 100k (toutes tables) ───
test_method_insert_batched_all() {
    local METHOD_NAME="INSERT_BATCHED_ALL"
    local PREFIX="test_m2"
    local BATCH_SIZE="$1"

    log_section "Test Méthode 2: INSERT SELECT avec batching TOUTES tables ($BATCH_SIZE lignes)"

    # Créer schéma de test
    $MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS ${PREFIX}_raw_acd;"
    $MYSQL $MYSQL_OPTS -e "CREATE DATABASE ${PREFIX}_raw_acd;"

    # Modifier le fichier SQL pour utiliser la base de test
    sed "s/USE raw_acd;/USE ${PREFIX}_raw_acd;/" "$SCRIPT_DIR/../sql/02b_raw_acd_tables.sql" | $MYSQL $MYSQL_OPTS

    START=$(date +%s)

    # Fonction d'import par batch (TOUTES les tables)
    import_batched_all() {
        local DB="$1"
        local DOSSIER_CODE="${DB#compta_}"
        local PREFIX="$2"
        local BATCH_SIZE="$3"

        for TABLE in histo_ligne_ecriture histo_ecriture ligne_ecriture ecriture compte journal; do
            # Batching pour TOUTES les tables (y compris compte/journal)
            TOTAL=$($MYSQL -h "$ACD_HOST" -P "$ACD_PORT" -u "$ACD_USER" -p"$ACD_PASS" -N -e "
                SELECT COUNT(*) FROM \`$DB\`.\`$TABLE\`
            " 2>/dev/null || echo "0")

            if [ "$TOTAL" -eq 0 ]; then
                continue
            fi

            # Importer par batch de 100k pour TOUTES les tables
            OFFSET=0
            while [ $OFFSET -lt $TOTAL ]; do
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
    export ACD_HOST ACD_PORT ACD_USER ACD_PASS MYSQL

    # Import séquentiel (P=1)
    for DB in $TEST_DATABASES; do
        import_batched_all "$DB" "$PREFIX" "$BATCH_SIZE"
    done

    END=$(date +%s)
    DURATION=$((END - START))

    TOTAL_ROWS=$($MYSQL $MYSQL_OPTS -N -e "
        SELECT SUM(table_rows)
        FROM information_schema.tables
        WHERE table_schema = '${PREFIX}_raw_acd'
    " || echo "0")

    log "INFO" "Durée: ${DURATION}s - Lignes: $TOTAL_ROWS"

    # Retourner UNIQUEMENT le résultat (sans logs)
    RESULT="${METHOD_NAME}|${DURATION}|${TOTAL_ROWS}"

    # Nettoyer
    $MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS ${PREFIX}_raw_acd;"

    # Retourner le résultat
    echo "$RESULT"
}

# ─── MÉTHODE 3: INSERT SELECT AVEC batching 100k (écritures seulement) ───
test_method_insert_batched_ecritures() {
    local METHOD_NAME="INSERT_BATCHED_ECRITURES"
    local PREFIX="test_m3"
    local BATCH_SIZE="$1"

    log_section "Test Méthode 3: INSERT SELECT avec batching écritures uniquement ($BATCH_SIZE lignes)"

    # Créer schéma de test
    $MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS ${PREFIX}_raw_acd;"
    $MYSQL $MYSQL_OPTS -e "CREATE DATABASE ${PREFIX}_raw_acd;"

    # Modifier le fichier SQL pour utiliser la base de test
    sed "s/USE raw_acd;/USE ${PREFIX}_raw_acd;/" "$SCRIPT_DIR/../sql/02b_raw_acd_tables.sql" | $MYSQL $MYSQL_OPTS

    START=$(date +%s)

    # Fonction d'import par batch (100k lignes pour écritures seulement)
    import_batched_ecritures() {
        local DB="$1"
        local DOSSIER_CODE="${DB#compta_}"
        local PREFIX="$2"
        local BATCH_SIZE="$3"

        for TABLE in histo_ligne_ecriture histo_ecriture ligne_ecriture ecriture compte journal; do
            # Batching uniquement pour les 4 tables d'écritures
            if [[ "$TABLE" == "compte" ]] || [[ "$TABLE" == "journal" ]]; then
                # Tables compte/journal : import complet SANS batching (petites tables)
                $MYSQL -h "$ACD_HOST" -P "$ACD_PORT" -u "$ACD_USER" -p"$ACD_PASS" \
                    --compress -e "
                    INSERT INTO ${PREFIX}_raw_acd.$TABLE
                    SELECT '$DOSSIER_CODE' as dossier_code, t.*
                    FROM \`$DB\`.\`$TABLE\` t;
                " 2>/dev/null || true
                continue
            fi

            # Tables d'écritures : batching par 100k lignes
            TOTAL=$($MYSQL -h "$ACD_HOST" -P "$ACD_PORT" -u "$ACD_USER" -p"$ACD_PASS" -N -e "
                SELECT COUNT(*) FROM \`$DB\`.\`$TABLE\`
            " 2>/dev/null || echo "0")

            if [ "$TOTAL" -eq 0 ]; then
                continue
            fi

            # Importer par batch de 100k
            OFFSET=0
            while [ $OFFSET -lt $TOTAL ]; do
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
    export ACD_HOST ACD_PORT ACD_USER ACD_PASS MYSQL

    # Import séquentiel (P=1)
    for DB in $TEST_DATABASES; do
        import_batched_ecritures "$DB" "$PREFIX" "$BATCH_SIZE"
    done

    END=$(date +%s)
    DURATION=$((END - START))

    TOTAL_ROWS=$($MYSQL $MYSQL_OPTS -N -e "
        SELECT SUM(table_rows)
        FROM information_schema.tables
        WHERE table_schema = '${PREFIX}_raw_acd'
    " || echo "0")

    log "INFO" "Durée: ${DURATION}s - Lignes: $TOTAL_ROWS"

    # Retourner UNIQUEMENT le résultat (sans logs)
    RESULT="${METHOD_NAME}|${DURATION}|${TOTAL_ROWS}"

    # Nettoyer
    $MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS ${PREFIX}_raw_acd;"

    # Retourner le résultat
    echo "$RESULT"
}

# ─── MÉTHODE 4: DUMP COMPLET (ancien script, référence) ───
test_method_dump_full() {
    local METHOD_NAME="DUMP_FULL_LEGACY"
    local PREFIX="test_m4"

    log_section "Test Méthode 4: DUMP COMPLET (ancien script - référence historique)"

    START=$(date +%s)

    # Fonction d'import avec mysqldump complet (comme l'ancien script)
    import_dump_full() {
        local DB="$1"
        local PREFIX="$2"
        local LOCAL_DB="${PREFIX}_${DB}"

        # Créer la base locale avec préfixe test_
        $MYSQL $MYSQL_OPTS -e "CREATE DATABASE IF NOT EXISTS \`$LOCAL_DB\`;"

        # Dump complet de la base (toutes les tables)
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

    # Import séquentiel (P=1)
    for DB in $TEST_DATABASES; do
        import_dump_full "$DB" "$PREFIX"
    done

    END=$(date +%s)
    DURATION=$((END - START))

    # Compter toutes les tables créées
    TOTAL_TABLES=$($MYSQL $MYSQL_OPTS -N -e "
        SELECT COUNT(*)
        FROM information_schema.tables
        WHERE table_schema LIKE '${PREFIX}_%'
    " || echo "0")

    # Compter les lignes totales (estimation)
    TOTAL_ROWS=$($MYSQL $MYSQL_OPTS -N -e "
        SELECT SUM(table_rows)
        FROM information_schema.tables
        WHERE table_schema LIKE '${PREFIX}_%'
    " || echo "0")

    log "INFO" "Durée: ${DURATION}s - Tables: $TOTAL_TABLES - Lignes: $TOTAL_ROWS"

    # Retourner UNIQUEMENT le résultat (sans logs)
    RESULT="${METHOD_NAME}|${DURATION}|${TOTAL_TABLES} tables|${TOTAL_ROWS} lignes"

    # Nettoyer toutes les bases test_m4_compta_*
    for DB in $TEST_DATABASES; do
        $MYSQL $MYSQL_OPTS -e "DROP DATABASE IF EXISTS ${PREFIX}_${DB};" 2>/dev/null || true
    done

    # Retourner le résultat
    echo "$RESULT"
}

# ─── Exécution des tests ───────────────────────────────────
echo "════════════════════════════════════════════════════════" >> "$RESULTS_FILE"
echo "RÉSULTATS DÉTAILLÉS" >> "$RESULTS_FILE"
echo "════════════════════════════════════════════════════════" >> "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"

declare -A RESULTS

# Test Méthode 1: INSERT SELECT SANS batching
RESULT=$(test_method_insert_select_no_batch 2>&1 | tail -1)
RESULTS["M1"]="$RESULT"
echo "Méthode 1: $RESULT" >> "$RESULTS_FILE"

# Test Méthode 2: INSERT SELECT avec batching TOUTES tables
RESULT=$(test_method_insert_batched_all "$BATCH_SIZE" 2>&1 | tail -1)
RESULTS["M2"]="$RESULT"
echo "Méthode 2: $RESULT" >> "$RESULTS_FILE"

# Test Méthode 3: INSERT SELECT avec batching écritures seulement
RESULT=$(test_method_insert_batched_ecritures "$BATCH_SIZE" 2>&1 | tail -1)
RESULTS["M3"]="$RESULT"
echo "Méthode 3: $RESULT" >> "$RESULTS_FILE"

# Test Méthode 4: DUMP COMPLET (référence)
RESULT=$(test_method_dump_full 2>&1 | tail -1)
RESULTS["M4"]="$RESULT"
echo "Méthode 4: $RESULT" >> "$RESULTS_FILE"

echo "" >> "$RESULTS_FILE"

# ─── Générer le tableau récapitulatif ─────────────────────
log_section "📊 GÉNÉRATION DU RAPPORT FINAL"

cat >> "$RESULTS_FILE" << 'EOF'

════════════════════════════════════════════════════════════════
  TABLEAU RÉCAPITULATIF
════════════════════════════════════════════════════════════════

EOF

# Parser les résultats
parse_duration() {
    echo "$1" | cut -d'|' -f2
}

M1=$(parse_duration "${RESULTS[M1]}")
M2=$(parse_duration "${RESULTS[M2]}")
M3=$(parse_duration "${RESULTS[M3]}")
M4=$(parse_duration "${RESULTS[M4]}")

cat >> "$RESULTS_FILE" << EOF
| Méthode                               | Durée  | Architecture          | Batching                       |
|---------------------------------------|--------|-----------------------|--------------------------------|
| INSERT SELECT (SANS batching)         | ${M1}s | ✅ raw_acd centralisé | Aucun                          |
| INSERT BATCHED (toutes tables)        | ${M2}s | ✅ raw_acd centralisé | 100k lignes (6 tables)         |
| INSERT BATCHED (écritures seulement)  | ${M3}s | ✅ raw_acd centralisé | 100k lignes (4 tables)         |
| DUMP COMPLET (ancien)                 | ${M4}s | ❌ Bases locales      | N/A                            |

════════════════════════════════════════════════════════════════
  ESTIMATION POUR 3500 BASES
════════════════════════════════════════════════════════════════

EOF

# Calculer les estimations pour 3500 bases
M1_ESTIMATE=$((M1 * 3500 / NB_FOUND))
M2_ESTIMATE=$((M2 * 3500 / NB_FOUND))
M3_ESTIMATE=$((M3 * 3500 / NB_FOUND))
M4_ESTIMATE=$((M4 * 3500 / NB_FOUND))

cat >> "$RESULTS_FILE" << EOF
Méthode 1 (SANS batching)            : $(($M1_ESTIMATE / 3600))h $(($M1_ESTIMATE % 3600 / 60))min
Méthode 2 (BATCHED toutes)           : $(($M2_ESTIMATE / 3600))h $(($M2_ESTIMATE % 3600 / 60))min
Méthode 3 (BATCHED écritures)        : $(($M3_ESTIMATE / 3600))h $(($M3_ESTIMATE % 3600 / 60))min
Méthode 4 (DUMP COMPLET)             : $(($M4_ESTIMATE / 3600))h $(($M4_ESTIMATE % 3600 / 60))min

════════════════════════════════════════════════════════════════
  ANALYSE COMPARATIVE
════════════════════════════════════════════════════════════════

EOF

# Trouver la méthode la plus rapide compatible raw_acd
BEST_TIME=$M1
BEST_METHOD="M1"
BEST_NAME="INSERT SELECT SANS batching"

if [ "$M2" -lt "$BEST_TIME" ]; then
    BEST_TIME=$M2
    BEST_METHOD="M2"
    BEST_NAME="INSERT BATCHED (toutes tables)"
fi

if [ "$M3" -lt "$BEST_TIME" ]; then
    BEST_TIME=$M3
    BEST_METHOD="M3"
    BEST_NAME="INSERT BATCHED (écritures seulement)"
fi

cat >> "$RESULTS_FILE" << EOF
✅ MÉTHODE LA PLUS RAPIDE (compatible raw_acd): $BEST_NAME
   Temps: ${BEST_TIME}s pour $NB_FOUND bases
   Estimation 3500 bases: $(($BEST_TIME * 3500 / NB_FOUND / 3600))h $(($BEST_TIME * 3500 / NB_FOUND % 3600 / 60))min

════════════════════════════════════════════════════════════════

Comparaison des variantes de batching:

EOF

# Comparer M1 vs M2
if [ "$M1" -lt "$M2" ]; then
    DIFF=$((M2 - M1))
    PERCENT=$(( (M2 - M1) * 100 / M1 ))
    echo "🔹 SANS batching vs BATCHED toutes tables:" >> "$RESULTS_FILE"
    echo "   SANS batching est ${PERCENT}% plus rapide (gain: ${DIFF}s)" >> "$RESULTS_FILE"
    echo "   ➜ Le batching sur TOUTES les tables ajoute de l'overhead" >> "$RESULTS_FILE"
else
    DIFF=$((M1 - M2))
    PERCENT=$(( (M1 - M2) * 100 / M2 ))
    echo "🔹 SANS batching vs BATCHED toutes tables:" >> "$RESULTS_FILE"
    echo "   BATCHED toutes tables est ${PERCENT}% plus rapide (gain: ${DIFF}s)" >> "$RESULTS_FILE"
    echo "   ➜ Le batching améliore les performances même sur petites tables" >> "$RESULTS_FILE"
fi

echo "" >> "$RESULTS_FILE"

# Comparer M1 vs M3
if [ "$M1" -lt "$M3" ]; then
    DIFF=$((M3 - M1))
    PERCENT=$(( (M3 - M1) * 100 / M1 ))
    echo "🔹 SANS batching vs BATCHED écritures seulement:" >> "$RESULTS_FILE"
    echo "   SANS batching est ${PERCENT}% plus rapide (gain: ${DIFF}s)" >> "$RESULTS_FILE"
    echo "   ➜ Le batching partiel n'améliore pas les performances" >> "$RESULTS_FILE"
else
    DIFF=$((M1 - M3))
    PERCENT=$(( (M1 - M3) * 100 / M3 ))
    echo "🔹 SANS batching vs BATCHED écritures seulement:" >> "$RESULTS_FILE"
    echo "   BATCHED écritures est ${PERCENT}% plus rapide (gain: ${DIFF}s)" >> "$RESULTS_FILE"
    echo "   ➜ Le batching sur grandes tables améliore les performances" >> "$RESULTS_FILE"
fi

echo "" >> "$RESULTS_FILE"

# Comparer M2 vs M3
if [ "$M2" -lt "$M3" ]; then
    DIFF=$((M3 - M2))
    PERCENT=$(( (M3 - M2) * 100 / M2 ))
    echo "🔹 BATCHED toutes tables vs BATCHED écritures seulement:" >> "$RESULTS_FILE"
    echo "   BATCHED toutes tables est ${PERCENT}% plus rapide (gain: ${DIFF}s)" >> "$RESULTS_FILE"
    echo "   ➜ Le batching sur compte/journal est bénéfique" >> "$RESULTS_FILE"
else
    DIFF=$((M2 - M3))
    PERCENT=$(( (M2 - M3) * 100 / M3 ))
    echo "🔹 BATCHED toutes tables vs BATCHED écritures seulement:" >> "$RESULTS_FILE"
    echo "   BATCHED écritures seulement est ${PERCENT}% plus rapide (gain: ${DIFF}s)" >> "$RESULTS_FILE"
    echo "   ➜ Le batching sur compte/journal ajoute de l'overhead inutile" >> "$RESULTS_FILE"
fi

cat >> "$RESULTS_FILE" << EOF

════════════════════════════════════════════════════════════════

Méthode DUMP COMPLET (Méthode 4 - ancien script):
  - Temps: ${M4}s pour $NB_FOUND bases
  - Estimation 3500 bases: $(($M4_ESTIMATE / 3600))h $(($M4_ESTIMATE % 3600 / 60))min
  - ⚠️  Incompatible avec raw_acd (créé ~50 tables × 3500 bases)
  - ⚠️  Stockage: Énorme espace disque requis
  - ❌ Architecture obsolète (non centralisée)

EOF

# Comparer meilleure méthode raw_acd vs ancien script
if [ "$BEST_TIME" -lt "$M4" ]; then
    GAIN=$((100 - (BEST_TIME * 100 / M4)))
    cat >> "$RESULTS_FILE" << EOF
✅ Gain architecture raw_acd vs ancien script: ${GAIN}% plus rapide
   Méthode optimale: $BEST_NAME
   + Centralisation + Moins stockage + Performance
EOF
else
    LOSS=$(((BEST_TIME * 100 / M4) - 100))
    cat >> "$RESULTS_FILE" << EOF
⚠️  Architecture raw_acd ${LOSS}% plus lente que ancien script
   MAIS: Centralisation indispensable pour architecture 4 couches
   Trade-off acceptable pour gain en maintenance/requêtes
EOF
fi

cat >> "$RESULTS_FILE" << EOF

════════════════════════════════════════════════════════════════
  RECOMMANDATION FINALE
════════════════════════════════════════════════════════════════

EOF

# Recommandation basée sur la méthode la plus rapide
if [ "$BEST_METHOD" = "M1" ]; then
    cat >> "$RESULTS_FILE" << 'EOF'
✅ MÉTHODE RECOMMANDÉE: INSERT SELECT SANS batching

Raison:
  - Plus simple et plus rapide
  - 1 requête par table (6 requêtes par base)
  - Moins d'overhead réseau
  - Code maintenable

Configuration:
  bash/raw/02_import_raw_compta.sh
  PARALLEL_JOBS=1
  Pas de batching nécessaire

Le batching n'apporte pas d'amélioration pour vos volumes de données.
EOF
elif [ "$BEST_METHOD" = "M2" ]; then
    cat >> "$RESULTS_FILE" << 'EOF'
✅ MÉTHODE RECOMMANDÉE: INSERT SELECT avec batching (TOUTES tables)

Raison:
  - Meilleure performance globale
  - Évite timeouts MySQL sur toutes les tables
  - Gestion mémoire optimisée

Configuration:
  bash/raw/02_import_raw_compta.sh
  PARALLEL_JOBS=1
  BATCH_SIZE=100000 (pour les 6 tables)

⚠️  Nécessite modification du script actuel.
EOF
else  # M3
    cat >> "$RESULTS_FILE" << 'EOF'
✅ MÉTHODE RECOMMANDÉE: INSERT SELECT avec batching (écritures seulement)

Raison:
  - Bon compromis performance/complexité
  - Batching uniquement pour grandes tables (écritures)
  - Tables compte/journal importées en 1 fois (petites)

Configuration:
  bash/raw/02_import_raw_compta.sh
  PARALLEL_JOBS=1
  BATCH_SIZE=100000 (pour histo_*, ligne_ecriture, ecriture)

Cette approche est déjà implémentée dans le script actuel.
EOF
fi

echo "" >> "$RESULTS_FILE"
echo "Rapport sauvegardé dans: $RESULTS_FILE" >> "$RESULTS_FILE"
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')" >> "$RESULTS_FILE"

# ─── Afficher le rapport ───────────────────────────────────
log_section "📄 RAPPORT FINAL"
cat "$RESULTS_FILE"

log "SUCCESS" "Benchmark terminé ! Résultats sauvegardés dans: $RESULTS_FILE"
