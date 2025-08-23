#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# trace.sh - tracing helpers
# ---------------------------------------------------

split_label_cmd() {
    WRAP_LABEL="$1"
    shift || return 127
    [[ "${1:-}" == "--" ]] || return 127
    shift
    WRAP_CMD=("$@")
}

with_trace() {
    split_label_cmd "$@" || return 127
    local start end dur rc
    start=$(date +%s%3N)
    "${WRAP_CMD[@]}" > >(tee -a "$LOGFILE") 2> >(tee -a "$LOGFILE" >&2)
    rc=$?
    end=$(date +%s%3N)
    dur=$((end-start))
    LOG_COMP="$WRAP_LABEL" LOG_DUR_MS="$dur" LOG_RC="$rc" log DEBUG "cmd: ${WRAP_CMD[*]}"
    return "$rc"
}

with_timeout() {
    local secs="$1"; shift
    split_label_cmd "$@" || return 127
    with_trace "$WRAP_LABEL" -- timeout --preserve-status "$secs" "${WRAP_CMD[@]}"
    local rc=$?
    if [[ $rc -eq 124 ]]; then
        LOG_COMP="$WRAP_LABEL" LOG_CODE="$E_TIMEOUT" LOG_RC="$rc" log ERROR "timeout after ${secs}s: ${WRAP_CMD[*]}"
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
