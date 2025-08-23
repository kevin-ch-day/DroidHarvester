#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# device.sh - ADB helpers with retry/backoff
# ---------------------------------------------------

: "${DH_RETRIES:=3}"
: "${DH_BACKOFF:=1.5}"
: "${DH_PULL_TIMEOUT:=120}"
: "${DH_SHELL_TIMEOUT:=20}"

adb_healthcheck() {
    LOG_COMP="adb" log INFO "adb get-state" && adb get-state || true
    LOG_COMP="adb" log INFO "adb -s $DEVICE shell echo OK" && adb -s "$DEVICE" shell echo OK || true
    LOG_COMP="adb" log INFO "device df" && adb -s "$DEVICE" shell df -h /data || true
    LOG_COMP="host" log INFO "host df" && df -h . || true
}

adb_run() {
    local comp="adb"
    with_trace "$comp" adb -s "$DEVICE" "$@"
}

adb_retry() {
    local max=${1:-$DH_RETRIES}; shift
    local backoff=${1:-$DH_BACKOFF}; shift
    [[ "$1" == "--" ]] && shift
    local attempt=0 rc
    while (( attempt < max )); do
        if adb_run "$@"; then
            return 0
        fi
        rc=$?
        attempt=$((attempt+1))
        sleep "$(awk -v b="$backoff" -v a="$attempt" 'BEGIN{print b^a}')"
    done
    return "$rc"
}

adb_shell() {
    adb_retry "$DH_RETRIES" "$DH_BACKOFF" -- shell "$@"
}
