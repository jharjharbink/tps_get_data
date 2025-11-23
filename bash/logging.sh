#!/bin/bash
# ============================================================
# LOGGING.SH - Fonctions de logging
# ============================================================

# Initialisation du fichier log
LOG_FILE="${LOG_FILE:-$SCRIPT_DIR/logs/pipeline_$(date +%Y%m%d).log}"

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    case "$level" in
        "INFO")    prefix="ℹ️ " ;;
        "SUCCESS") prefix="✅" ;;
        "WARNING") prefix="⚠️ " ;;
        "ERROR")   prefix="❌" ;;
        *)         prefix="  " ;;
    esac
    
    echo "[$timestamp] [$level] $prefix $message" | tee -a "$LOG_FILE"
}

log_section() {
    local title="$1"
    echo "" | tee -a "$LOG_FILE"
    echo "════════════════════════════════════════════════════════" | tee -a "$LOG_FILE"
    echo "  $title" | tee -a "$LOG_FILE"
    echo "════════════════════════════════════════════════════════" | tee -a "$LOG_FILE"
}

log_subsection() {
    local title="$1"
    echo "──────────────────────────────────────────────────────" | tee -a "$LOG_FILE"
    echo "  $title" | tee -a "$LOG_FILE"
    echo "──────────────────────────────────────────────────────" | tee -a "$LOG_FILE"
}

# Rotation des logs (garder 30 jours)
rotate_logs() {
    find "$LOG_DIR" -name "pipeline_*.log" -mtime +30 -delete 2>/dev/null
}
