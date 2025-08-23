#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# device.sh - ADB helpers with retry/backoff
# ---------------------------------------------------

: "${DH_RETRIES:=3}"
: "${DH_BACKOFF:=1}"
: "${DH_PULL_TIMEOUT:=60}"
: "${DH_SHELL_TIMEOUT:=15}"

adb_healthcheck() {
    LOG_COMP="adb" log INFO "adb get-state" && adb get-state || true
    LOG_COMP="adb" log INFO "adb -s $DEVICE shell echo OK" && adb -s "$DEVICE" shell echo OK || true
    LOG_COMP="adb" log INFO "device df" && adb -s "$DEVICE" shell df -h /data || true
    LOG_COMP="host" log INFO "host df" && df -h . || true
}

adb_retry() {
    local max=${1:-$DH_RETRIES}; shift
    local backoff=${1:-$DH_BACKOFF}; shift
    split_label_cmd "$@" || return 127
    local attempt=0 rc=0 start end dur
    start=$(date +%s%3N)
    while (( attempt < max )); do
        with_trace "$WRAP_LABEL" -- adb -s "$DEVICE" "${WRAP_CMD[@]}"
        rc=$?
        [[ $rc -eq 0 ]] && break
        attempt=$((attempt+1))
        (( attempt < max )) && sleep "$backoff"
    done
    end=$(date +%s%3N)
    dur=$((end-start))
    LOG_COMP="$WRAP_LABEL" LOG_RC="$rc" LOG_DUR_MS="$dur" LOG_ATTEMPTS="$((attempt+1))" log DEBUG "adb_retry"
    return "$rc"
}

adb_shell() {
    adb_retry "$DH_RETRIES" "$DH_BACKOFF" adb_shell -- shell "$@"
}

# List connected device IDs
device_list_connected() {
    adb devices | awk 'NR>1 && $2=="device" {print $1}'
}

# device_pick_or_fail [DEVICE]
device_pick_or_fail() {
    local specified="${1:-}"
    mapfile -t devs < <(device_list_connected)
    if [[ -n "$specified" ]]; then
        if printf '%s\n' "${devs[@]}" | grep -Fxq "$specified"; then
            echo "$specified"
            return 0
        fi
        die "$E_NO_DEVICE" "Device '$specified' not found"
    fi
    if (( ${#devs[@]} == 0 )); then
        die "$E_NO_DEVICE" "No devices detected"
    elif (( ${#devs[@]} > 1 )); then
        die "$E_MULTI_DEVICE" "Multiple devices detected; use --device"
    fi
    echo "${devs[0]}"
}

# adb wrapper that logs on failure but does not exit
adbq() {
    local dev="$1"; shift
    adb -s "$dev" "$@" || {
        local rc=$?
        LOG_RC="$rc" log WARN "adb $* failed"
        return "$rc"
    }
}
