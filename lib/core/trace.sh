#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# trace.sh - tracing helpers
# ---------------------------------------------------

# Parse wrapper arguments into a label and command array
parse_wrapper_args() {
    local _label_var="$1" _cmd_var="$2"; shift 2
    [[ $# -ge 1 ]] || return 127
    local label="$1"; shift
    [[ "${1:-}" == "--" ]] || return 127
    shift
    [[ $# -gt 0 ]] || return 127
    printf -v "$_label_var" '%s' "$label"
    eval "$_cmd_var=(\"\$@\")"
    return 0
}

with_trace() {
    local label
    local -a cmd
    if ! parse_wrapper_args label cmd "$@"; then
        return 127
    fi

    local start end dur rc
    start=$(date +%s%3N)
    "${cmd[@]}" 2>&1 | tee -a "$LOGFILE"
    rc=${PIPESTATUS[0]}
    end=$(date +%s%3N)
    dur=$((end-start))

    LOG_COMP="$label" LOG_DUR_MS="$dur" LOG_RC="$rc" log DEBUG "cmd: ${cmd[*]}"
    return "$rc"
}

with_timeout() {
    local secs="$1"; shift
    local label
    local -a cmd
    if ! parse_wrapper_args label cmd "$@"; then
        return 127
    fi

    with_trace "$label" -- timeout --preserve-status -- "$secs" "${cmd[@]}"
    local rc=$?
    if [[ $rc -eq 124 || $rc -eq 137 || $rc -eq 143 ]]; then
        LOG_COMP="$label" LOG_CODE="$E_TIMEOUT" LOG_RC="$rc" log ERROR "timeout after ${secs}s: ${cmd[*]}"
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
