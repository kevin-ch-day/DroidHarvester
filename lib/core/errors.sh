#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND" >&2' ERR
# ---------------------------------------------------
# errors.sh - central error codes and helpers
# ---------------------------------------------------

# Generic error codes
export E_NO_DEVICE=10
export E_MULTI_DEVICE=11
export E_DEPS=12
export E_ADB=13
export E_IO=14
export E_USAGE=15
export E_INTERNAL=99

# Project-specific/legacy codes
export E_PM_LIST=20
export E_PM_PATH=21
export E_PULL_FAIL=22
export E_APK_MISSING=23
export E_APK_EMPTY=24
export E_HASH_FAIL=25
export E_DUMPSYS_FAIL=26
export E_REPORT_FAIL=27
export E_EXPORT_SKIP=28
export E_TIMEOUT=29

# Fatal error handler
# Usage: die <code> "message"
die() {
    local code="$1"; shift
    log ERROR "$*"
    exit "$code"
}

# Run a command and return its status without exiting
try() {
    "$@"
    return $?
}

# with_backoff <attempts> <sleep> -- <cmd...>
# Retries a command with fixed backoff between attempts.
with_backoff() {
    local attempts="$1"; shift
    local delay="$1"; shift
    [[ "${1:-}" == "--" ]] && shift
    local i rc
    for ((i=1; i<=attempts; i++)); do
        "$@"
        rc=$?
        [[ $rc -eq 0 ]] && return 0
        (( i < attempts )) && sleep "$delay"
    done
    return "$rc"
}
