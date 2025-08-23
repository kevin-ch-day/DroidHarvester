#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# device.sh - ADB helpers with retry/backoff
# ---------------------------------------------------


adb_healthcheck() {
    LOG_COMP="adb" log INFO "adb get-state" && adb get-state || true
    LOG_COMP="adb" log INFO "adb -s $DEVICE shell echo OK" && adb -s "$DEVICE" shell echo OK || true
    LOG_COMP="adb" log INFO "device df" && adb -s "$DEVICE" shell df -h /data || true
    LOG_COMP="host" log INFO "host df" && df -h . || true
}

adb_run() {
    local comp="adb"
    with_trace "$comp" -- adb -s "$DEVICE" "$@"
}

adb_retry() {
    local max=${1:-$DH_RETRIES}; shift
    local backoff=${1:-$DH_BACKOFF}; shift
    local label
    local -a cmd
    if ! parse_wrapper_args label cmd "$@"; then
        return 127
    fi
    local attempt=0 rc
    while (( attempt < max )); do
        if adb_run "${cmd[@]}"; then
            return 0
        fi
        rc=$?
        attempt=$((attempt+1))
        sleep "$(awk -v b="$backoff" -v a="$attempt" 'BEGIN{print b^a}')"
    done
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
