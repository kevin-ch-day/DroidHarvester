#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND" >&2' ERR
# ---------------------------------------------------
# logging.sh - lightweight structured logging
# ---------------------------------------------------

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
NC="\033[0m"

: "${LOG_LEVEL:=INFO}"
: "${SCRIPT_DIR:=$(pwd)}"
LOGS_DIR="${LOGS_DIR:-$SCRIPT_DIR/logs}"
mkdir -p "$LOGS_DIR"
if [[ -z "${LOGFILE:-}" ]]; then
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    LOGFILE="$LOGS_DIR/harvest_log_$TIMESTAMP.txt"
fi

# Initialize logging to a specific file
log_file_init() {
    LOGFILE="$1"
    : > "$LOGFILE"
    log INFO "transcript: $LOGFILE"
}

log() {
    local level="$1"; shift
    local msg="$*"
    local ts_human="$(date +'%H:%M:%S')"
    local ts_iso="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    local dev_field="${LOG_DEV:-${DEVICE:- -}}"
    local structured="ts=$ts_iso lvl=$level sid=${SESSION_ID:- -} code=${LOG_CODE:- -} comp=${LOG_COMP:- -} func=${LOG_FUNC:- -} dev=${dev_field} pkg=${LOG_PKG:- -} apk=${LOG_APK:- -} dur_ms=${LOG_DUR_MS:- -} attempts=${LOG_ATTEMPTS:- -} rc=${LOG_RC:- -} msg=\"$msg\""
    local color prefix
    case "$level" in
        DEBUG)
            [[ "$LOG_LEVEL" == "DEBUG" ]] || return 0
            color=$CYAN; prefix="DBG " ;;
        INFO)
            color=$BLUE; prefix="INFO" ;;
        WARN)
            color=$YELLOW; prefix="WARN" ;;
        ERROR)
            color=$RED; prefix="ERR " ;;
        SUCCESS)
            color=$GREEN; prefix=" OK " ;;
        *)
            color=""; prefix="$level" ;;
    esac
    echo -e "${color}[${prefix}]${NC} [$ts_human] $msg" >&2
    if [[ -n "${LOGFILE:-}" ]]; then
        echo "[${prefix}] [$ts_human] $msg | $structured" >> "$LOGFILE"
    fi
}
