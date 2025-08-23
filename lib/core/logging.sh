#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# logging.sh - Logging and Usage Helpers
# ---------------------------------------------------
# Provides standardized log output with levels and colors.
# All logs are written to logs/ (not results/).

source "$SCRIPT_DIR/lib/ui/colors.sh"

LOGS_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOGS_DIR"

if [[ -z "${LOGFILE:-}" ]]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    LOGFILE="$LOGS_DIR/harvest_log_$TIMESTAMP.txt"
fi

log() {
    local prev_status=$?
    local level="$1"; shift
    local msg="$*"
    local ts_human="$(date +'%H:%M:%S')"
    local ts_iso="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    local structured="ts=$ts_iso lvl=$level sid=${SESSION_ID:- -} code=${LOG_CODE:- -} comp=${LOG_COMP:- -} func=${LOG_FUNC:- -} dev=${DEVICE:- -} pkg=${LOG_PKG:- -} apk=${LOG_APK:- -} dur_ms=${LOG_DUR_MS:- -} rc=${LOG_RC:- -} msg=\"$msg\""

    case "$level" in
        INFO)
            echo -e "${BLUE}[INFO]${NC}    [$ts_human] $msg"
            echo "[INFO]    [$ts_human] $msg | $structured" >> "$LOGFILE"
            ;;
        SUCCESS)
            echo -e "${GREEN}[ OK ]${NC}    [$ts_human] $msg"
            echo "[ OK ]    [$ts_human] $msg | $structured" >> "$LOGFILE"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC}    [$ts_human] $msg"
            echo "[WARN]    [$ts_human] $msg | $structured" >> "$LOGFILE"
            ;;
        ERROR)
            echo -e "${RED}[ERR ]${NC}    [$ts_human] $msg"
            echo "[ERR ]    [$ts_human] $msg | $structured" >> "$LOGFILE"
            ;;
        DEBUG)
            if [[ "${LOG_LEVEL:-INFO}" == "DEBUG" ]]; then
                echo -e "${CYAN}[DBG ]${NC}    [$ts_human] $msg"
                echo "[DBG ]    [$ts_human] $msg | $structured" >> "$LOGFILE"
            fi
            ;;
        *)
            echo -e "[$ts_human] $msg"
            echo "[$ts_human] $msg | $structured" >> "$LOGFILE"
            ;;
    esac
    return "$prev_status"
}

print_only() {
    echo -e "[$(date +'%H:%M:%S')] $*"
}

usage() {
    cat <<USAGE
============================================================
DroidHarvester - APK Collection & Metadata Reporting Tool
============================================================
Usage:
  $(basename "$0") [options]

Options:
  -d, --device <DEVICE_ID>   Specify Android device ID (from 'adb devices')
  -h, --help                 Show this help message
  -v, --verbose              Enable DEBUG logging

Examples:
  $(basename "$0") --device emulator-5554
  $(basename "$0") -d 0123456789ABCDEF

Notes:
  - If no device is specified, you will be prompted to choose.
  - Reports are stored in the 'results/' directory.
  - Logs are written to the 'logs/' directory.
============================================================
USAGE
    exit 1
}
