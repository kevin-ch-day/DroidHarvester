#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# trace.sh - tracing helpers
# ---------------------------------------------------

with_trace() {
    local comp="$1"; shift
    [[ "$1" == "--" ]] && shift
    local start=$(date +%s%3N)
    "$@" 2>&1 | tee -a "$LOGFILE"
    local rc=${PIPESTATUS[0]}
    local end=$(date +%s%3N)
    local dur=$((end-start))
    LOG_COMP="$comp" LOG_DUR_MS="$dur" LOG_RC="$rc" log DEBUG "cmd: $*"
    return "$rc"
}

with_timeout() {
    local secs="$1"; shift
    local comp="$1"; shift
    [[ "$1" == "--" ]] && shift
    with_trace "$comp" timeout "$secs" "$@"
    local rc=$?
    if [[ $rc -eq 124 ]]; then
        LOG_COMP="$comp" LOG_CODE="$E_TIMEOUT" LOG_RC="$rc" log ERROR "timeout after ${secs}s: $*"
    fi
    return $rc
}

enable_xtrace_to_file() {
    local path="$1"
    exec 9>>"$path"
    export PS4='+ $(date +%H:%M:%S) ${BASH_SOURCE##*/}:${LINENO} ${FUNCNAME[0]:-main}() '
    export BASH_XTRACEFD=9
    set -x
}
