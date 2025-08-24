#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# device.sh - ADB helpers with retry/backoff
# ---------------------------------------------------

# Default retry/backoff values (override with env if needed)
: "${DH_RETRIES:=3}"
: "${DH_BACKOFF:=1}"

: "${DH_PULL_TIMEOUT:=60}"
: "${DH_SHELL_TIMEOUT:=15}"

# Refresh ADB_FLAGS whenever DEVICE is set
update_adb_flags() {
    ADB_FLAGS="-s $DEVICE"
    export ADB_FLAGS
}

adb_healthcheck() {
    LOG_COMP="adb" log INFO "adb get-state" && adb get-state || true
    LOG_COMP="adb" log INFO "adb $ADB_FLAGS shell echo OK" && adb $ADB_FLAGS shell echo OK || true
    LOG_COMP="adb" log INFO "device df" && adb $ADB_FLAGS shell df -h /data || true
    LOG_COMP="host" log INFO "host df" && df -h . || true
}

# Wrapper with retries and exponential backoff
adb_retry() {
    local max=${1:-$DH_RETRIES}; shift
    local backoff=${1:-$DH_BACKOFF}; shift
    local label=""; local -a cmd
    if ! parse_wrapper_args label cmd "$@"; then
        return 127
    fi

    local attempt=0 rc=0 start end dur
    start=$(date +%s%3N)
    while (( attempt < max )); do
        with_trace "$label" -- adb $ADB_FLAGS "${cmd[@]}" && return 0
        rc=$?
        attempt=$((attempt+1))
        (( attempt < max )) && sleep "$backoff"
    done
    end=$(date +%s%3N)
    dur=$((end-start))
    LOG_COMP="$label" LOG_RC="$rc" LOG_DUR_MS="$dur" LOG_ATTEMPTS="$((attempt))" log DEBUG "adb_retry"
    return "$rc"
}

adb_shell() {
    adb_retry "$DH_RETRIES" "$DH_BACKOFF" adb_shell -- shell "$@"
}

# List connected device IDs, trimmed of whitespace/CR
device_list_connected() {
    adb devices | awk 'NR>1 && $2=="device" {print $1}' | tr -d '\r' | xargs -n1
}

# device_pick_or_fail [DEVICE]
device_pick_or_fail() {
    local specified="${1:-}"
    specified="$(printf '%s' "$specified" | tr -d '\r' | xargs)"
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

# Print first 'device' serial, trimmed; rc 1=no device, 2=multi, 3=unauthorized
get_normalized_serial() {
    local line serial state
    local -a devs
    while read -r line; do
        serial="${line%%[[:space:]]*}"
        state="${line##*$serial}"
        state="${state##*[[:space:]]}"
        case "$state" in
            device)
                devs+=("$(printf '%s' "$serial" | tr -d '\r' | xargs)")
                ;;
            unauthorized)
                printf '[ERR] device %q unauthorized\n' "$serial" >&2
                return 3
                ;;
        esac
    done < <(adb devices | tail -n +2)
    if (( ${#devs[@]} == 0 )); then
        return 1
    elif (( ${#devs[@]} > 1 )); then
        return 2
    fi
    printf '%s\n' "${devs[0]}"
}

# Ensure device is in state "device"
assert_device_ready() {
    local s="$1"
    adb -s "$s" get-state 1>/dev/null || {
        echo "[ERR] device '$s' not ready (need state=device)." >&2
        return 1
    }
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
