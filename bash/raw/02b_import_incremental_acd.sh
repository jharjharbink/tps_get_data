#!/bin/bash
# ============================================================
# IMPORT INCRÉMENTAL RAW_ACD
# Wrapper pour import incrémental quotidien
# Utilise la table sync_tracking pour ne récupérer que les
# écritures modifiées depuis la dernière synchro
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Appeler le script principal en mode incrémental
bash "$SCRIPT_DIR/raw/02_import_raw_compta.sh" --incremental
