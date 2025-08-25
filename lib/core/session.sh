#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# session.sh - session bootstrap and metadata
# ---------------------------------------------------

init_session() {
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    RESULTS_DIR="${RESULTS_DIR:-$REPO_ROOT/results}"
    LOG_ROOT="${LOG_ROOT:-$REPO_ROOT/logs}"
    LOG_DIR="$LOG_ROOT"  # Backwards compatibility
    mkdir -p "$RESULTS_DIR" "$LOG_ROOT"
    logging_rotate
    RESULTS_RETENTION_DAYS=${RESULTS_RETENTION_DAYS:-30}
    find "$RESULTS_DIR" -mindepth 1 -mtime +"$RESULTS_RETENTION_DAYS" -print -delete 2>/dev/null || true

    LOGFILE="$(_log_path harvest_log)"
    REPORT="$RESULTS_DIR/apks_report_$TIMESTAMP.csv"
    JSON_REPORT="$RESULTS_DIR/apks_report_$TIMESTAMP.json"
    TXT_REPORT="$RESULTS_DIR/apks_report_$TIMESTAMP.txt"

    trap cleanup_reports EXIT

    DEVICE=""
    DEVICE_LABEL=""
    DEVICE_SERIAL=""
    DEVICE_VENDOR=""
    DEVICE_MODEL=""
    DEVICE_ANDROID_VERSION=""
    DEVICE_BUILD_ID=""
    DEVICE_DIR=""
    DEVICE_DIR_NAME=""
    CUSTOM_PACKAGES=()
    CUSTOM_PACKAGES_FILE="$REPO_ROOT/custom_packages.txt"
    [[ -f "$CUSTOM_PACKAGES_FILE" ]] && mapfile -t CUSTOM_PACKAGES < "$CUSTOM_PACKAGES_FILE"

    PKGS_FOUND=0
    PKGS_PULLED=0
    LAST_TXT_REPORT=""
    DEVICE_FINGERPRINT=""
    SESSION_ID="$TIMESTAMP"
    export DEVICE_FINGERPRINT SESSION_ID LOGFILE RESULTS_DIR LOG_ROOT REPORT JSON_REPORT TXT_REPORT
    export LOG_DIR="$LOG_ROOT"
}

session_metadata() {
    {
        echo "=================================================="
        echo " DroidHarvester Session Metadata"
        echo " Host       : $(hostname)"
        echo " User       : $(whoami)"
        echo " Date       : $(date)"
        echo " OS         : $(uname -srvmo)"
        if [[ -n "${DEVICE_LABEL:-}" ]]; then
            echo " Device     : $DEVICE_LABEL"
            echo " Android    : ${DEVICE_ANDROID_VERSION:-unknown}"
            echo " Build ID   : ${DEVICE_BUILD_ID:-unknown}"
        fi
        echo "=================================================="
    } >> "$LOGFILE"
    log INFO "Session initialized (log: $LOGFILE)"
}
