#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]:-?}:$LINENO: $BASH_COMMAND" >&2' ERR
# ---------------------------------------------------
# logging.sh - lightweight structured logging
# ---------------------------------------------------

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
NC="\033[0m"

# Default log level controls noise.  Levels are ordered by severity
# and can be overridden via the environment (e.g. LOG_LEVEL=DEBUG).
: "${LOG_LEVEL:=INFO}"
# Numeric mapping for easy comparisons
declare -A _LOG_LEVELS=(
    [DEBUG]=0
    [INFO]=1
    [SUCCESS]=1
    [WARN]=2
    [ERROR]=3
)
: "${REPO_ROOT:="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"}"
: "${LOG_ROOT:="$REPO_ROOT/logs"}"
LOG_DIR="$LOG_ROOT"  # Backwards compatibility

logging_init() {
    mkdir -p "$LOG_ROOT"
    if [[ "${CLEAR_LOGS:-false}" == true ]]; then
        rm -f "$LOG_ROOT"/*.txt 2>/dev/null || true
    fi
    logging_rotate
    if [[ -z "${LOGFILE:-}" ]]; then
        LOGFILE="$(_log_path harvest_log)"
    fi
    # Dedicated error transcript
    if [[ -z "${ERRORFILE:-}" ]]; then
        ERRORFILE="$(_log_path error_log)"
    fi
}

_log_path() {
    local prefix="$1"
    local ts="$(date +%Y%m%d_%H%M%S)"
    local epoch="$(date +%s)"
    echo "$LOG_ROOT/${prefix}_${ts}_${epoch}.txt"
}

# Check if a level should be printed according to LOG_LEVEL
_log_should_print() {
    local lvl="${_LOG_LEVELS[$1]:-}"
    local cur="${_LOG_LEVELS[$LOG_LEVEL]:-1}"
    [[ "$lvl" -ge "$cur" ]]
}

logging_rotate() {
    local keep="${LOG_KEEP_N:-}"
    [[ -n "$keep" && "$keep" =~ ^[0-9]+$ ]] || return 0
    mapfile -t _files < <(ls -1t "$LOG_ROOT"/*.txt 2>/dev/null || true)
    (( ${#_files[@]} > keep )) || return 0
    for f in "${_files[@]:$keep}"; do
        rm -f "$f"
    done
}

# Initialize logging to a specific file
log_file_init() {
    LOGFILE="$1"
    : > "$LOGFILE"
    log INFO "transcript: $LOGFILE"
    # ensure error file exists when explicitly setting log file
    if [[ -z "${ERRORFILE:-}" ]]; then
        ERRORFILE="$(_log_path error_log)"
    fi
}

log() {
    local level="$1"; shift
    local msg="$*"
    _log_should_print "$level" || return 0

    local ts_human="$(date +'%H:%M:%S')"
    local ts_iso="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    local dev_field="${LOG_DEV:-${DEVICE:- -}}"
    local structured="ts=$ts_iso lvl=$level sid=${SESSION_ID:- -} code=${LOG_CODE:- -} comp=${LOG_COMP:- -} func=${LOG_FUNC:- -} dev=${dev_field} pkg=${LOG_PKG:- -} apk=${LOG_APK:- -} dur_ms=${LOG_DUR_MS:- -} attempts=${LOG_ATTEMPTS:- -} rc=${LOG_RC:- -} msg=\"$msg\""

    local color prefix
    case "$level" in
        DEBUG)
            color=$CYAN; prefix="DBG " ;;
        INFO)
            color=$BLUE; prefix="INFO" ;;
        SUCCESS)
            color=$GREEN; prefix=" OK " ;;
        WARN)
            color=$YELLOW; prefix="WARN" ;;
        ERROR)
            color=$RED; prefix="ERR " ;;
        *)
            color=""; prefix="$level" ;;
    esac

    echo -e "${color}[${prefix}]${NC} [$ts_human] $msg" >&2
    if [[ -n "${LOGFILE:-}" ]]; then
        echo "[${prefix}] [$ts_human] $msg | $structured" >> "$LOGFILE"
    fi
    if [[ "$level" == "ERROR" && -n "${ERRORFILE:-}" ]]; then
        echo "[${prefix}] [$ts_human] $msg | $structured" >> "$ERRORFILE"
    fi
}

# Convenience wrappers for clarity
log_debug() { log DEBUG "$@"; }
log_info()  { log INFO  "$@"; }
log_warn()  { log WARN  "$@"; }
log_error() { log ERROR "$@"; }
