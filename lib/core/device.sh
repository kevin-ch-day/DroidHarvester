#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]:-?}:$LINENO" >&2' ERR
# ---------------------------------------------------
# device.sh - ADB helpers with retry/backoff
# ---------------------------------------------------

# Default retry/backoff values (override with env if needed)
: "${DH_RETRIES:=3}"
: "${DH_BACKOFF:=1}"

: "${DH_PULL_TIMEOUT:=60}"
: "${DH_SHELL_TIMEOUT:=15}"

# Refresh ADB_ARGS whenever DEVICE is set
update_adb_flags() {
    ADB_ARGS=(-s "$DEVICE")
    export ADB_ARGS
}

# Normalize a serial by stripping CR and surrounding whitespace
normalize_serial() {
    printf '%s' "$1" | tr -d '\r' | xargs
}

# Set global DEVICE after normalization
set_device() {
    local serial
    serial="$(normalize_serial "$1")"
    [[ -n "$serial" ]] || return 1
    DEVICE="$serial"
    update_adb_flags
    export DEVICE
    if [[ "${DEBUG:-0}" == "1" ]]; then
        printf '[DEBUG] DEV="%s"\n' "$DEVICE"
        printf '[DEBUG] DEV bytes: '
        printf '%s' "$DEVICE" | hexdump -C | sed -n '1p'
    fi
}

adb_healthcheck() {
    LOG_COMP="adb" log INFO "adb get-state" && adb get-state >/dev/null 2>&1 || true
    LOG_COMP="adb" log INFO "adb ${ADB_ARGS[*]} shell echo OK" && adb "${ADB_ARGS[@]}" shell echo OK >/dev/null 2>&1 || true
    LOG_COMP="adb" log INFO "device df" && adb "${ADB_ARGS[@]}" shell df -h /data >/dev/null 2>&1 || true
    LOG_COMP="host" log INFO "host df" && df -h . || true
}

# Wrapper that retries an adb subcommand with timeout
adb_retry() {
    local timeout="${1:-$DH_SHELL_TIMEOUT}"; shift
    local max="${1:-$DH_RETRIES}"; shift
    local backoff="${1:-$DH_BACKOFF}"; shift
    local label=""; local -a cmd
    if ! parse_wrapper_args label cmd "$@"; then
        return 127
    fi

    local attempt=0 rc=0 start end dur
    start=$(date +%s%3N)
    while (( attempt < max )); do
        with_trace "$label" -- timeout --preserve-status -- "$timeout" adb "${ADB_ARGS[@]}" "${cmd[@]}" && { rc=0; break; }
        rc=$?
        attempt=$((attempt+1))
        (( attempt < max )) && sleep "$backoff"
    done
    end=$(date +%s%3N)
    dur=$((end-start))
    LOG_COMP="$label" LOG_RC="$rc" LOG_DUR_MS="$dur" LOG_ATTEMPTS="$attempt" log DEBUG "adb_retry"
    return "$rc"
}

adb_shell() {
    adb_retry "$DH_SHELL_TIMEOUT" "$DH_RETRIES" "$DH_BACKOFF" adb_shell -- shell "$@"
}

adb_pull() {
    adb_retry "$DH_PULL_TIMEOUT" "$DH_RETRIES" "$DH_BACKOFF" adb_pull -- pull "$@"
}

adb_get_state() {
    if [[ $# -gt 0 ]]; then
        adb -s "$1" get-state
    else
        adb "${ADB_ARGS[@]}" get-state
    fi
}

# List connected device IDs, trimmed of whitespace/CR
device_list_connected() {
    adb devices | awk 'NR>1 && $2=="device" {print $1}' | tr -d '\r' | xargs -n1
}

# device_pick_or_fail [DEVICE]
device_pick_or_fail() {
    local specified="${1:-}"
    specified="$(normalize_serial "$specified")"
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
                devs+=("$(normalize_serial "$serial")")
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
    adb_get_state "$s" >/dev/null 2>&1 || {
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
