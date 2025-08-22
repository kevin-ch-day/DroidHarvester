#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# logging.sh - Logging and Usage Helpers
# ---------------------------------------------------
# Provides standardized log output with levels and colors.
# All logs are written to logs/ (not results/).

source "$SCRIPT_DIR/lib/colors.sh"

# Ensure logs directory exists
LOGS_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOGS_DIR"

# Default logfile (timestamped if not already set)
if [[ -z "${LOGFILE:-}" ]]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    LOGFILE="$LOGS_DIR/harvest_log_$TIMESTAMP.txt"
fi

export E_NO_DEVICE=1
export E_PULL_FAIL=2
export E_DUMPSYS_FAIL=3

# ---------------------------------------------------
# Logging Function
# ---------------------------------------------------
log() {
    local prev_status=$?
    local level="$1"; shift
    local msg
    msg="[$(date +'%H:%M:%S')] $*"

    # Strip ANSI codes before writing to logfile (clean text log)
    local clean_msg
    clean_msg=$(echo -e "$msg" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g')

    case "$level" in
        INFO)
            echo -e "${BLUE}[INFO]${NC}    $msg"
            echo "[INFO]    $clean_msg" >> "$LOGFILE"
            ;;
        SUCCESS)
            echo -e "${GREEN}[ OK ]${NC}    $msg"
            echo "[ OK ]    $clean_msg" >> "$LOGFILE"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC}    $msg"
            echo "[WARN]    $clean_msg" >> "$LOGFILE"
            ;;
        ERROR)
            echo -e "${RED}[ERR ]${NC}    $msg"
            echo "[ERR ]    $clean_msg" >> "$LOGFILE"
            ;;
        DEBUG)
            if [[ "${LOG_LEVEL:-INFO}" == "DEBUG" ]]; then
                echo -e "${CYAN}[DBG ]${NC}    $msg"
                echo "[DBG ]    $clean_msg" >> "$LOGFILE"
            fi
            ;;
        *)
            echo -e "$msg"
            echo "$clean_msg" >> "$LOGFILE"
            ;;
    esac
    return "$prev_status"
}

# ---------------------------------------------------
# Print to Console Only (no logfile)
# ---------------------------------------------------
print_only() {
    echo -e "[$(date +'%H:%M:%S')] $*"
}

# ---------------------------------------------------
# Usage / Help
# ---------------------------------------------------
usage() {
    cat <<EOF
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
EOF
    exit 1
}
