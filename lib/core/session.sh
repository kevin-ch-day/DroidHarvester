#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# session.sh - session bootstrap and metadata
# ---------------------------------------------------

init_session() {
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    RESULTS_DIR="$SCRIPT_DIR/results"
    LOGS_DIR="$SCRIPT_DIR/logs"
    mkdir -p "$RESULTS_DIR" "$LOGS_DIR"

    LOGFILE="$LOGS_DIR/harvest_log_$TIMESTAMP.txt"
    REPORT="$RESULTS_DIR/apks_report_$TIMESTAMP.csv"
    JSON_REPORT="$RESULTS_DIR/apks_report_$TIMESTAMP.json"
    TXT_REPORT="$RESULTS_DIR/apks_report_$TIMESTAMP.txt"

    trap cleanup_reports EXIT

    DEVICE=""
    CUSTOM_PACKAGES=()
    CUSTOM_PACKAGES_FILE="$SCRIPT_DIR/custom_packages.txt"
    [[ -f "$CUSTOM_PACKAGES_FILE" ]] && mapfile -t CUSTOM_PACKAGES < "$CUSTOM_PACKAGES_FILE"

    PKGS_FOUND=0
    PKGS_PULLED=0
    LAST_TXT_REPORT=""
    DEVICE_FINGERPRINT=""
    SESSION_ID="$TIMESTAMP"
    export DEVICE_FINGERPRINT SESSION_ID LOGFILE RESULTS_DIR LOGS_DIR REPORT JSON_REPORT TXT_REPORT
}

session_metadata() {
    {
        echo "=================================================="
        echo " DroidHarvester Session Metadata"
        echo " Host       : $(hostname)"
        echo " User       : $(whoami)"
        echo " Date       : $(date)"
        echo " OS         : $(uname -srvmo)"
        echo "=================================================="
    } >> "$LOGFILE"
    log INFO "Session initialized (log: $LOGFILE)"
}
