#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR

# Run adb shell commands with retry and disconnect handling
adb_shell() {
    local attempts=0
    local output
    while (( attempts < 3 )); do
        if output=$(adb -s "$DEVICE" shell "$@" 2>/dev/null); then
            printf '%s\n' "$output"
            return 0
        fi
        ((attempts++))
        if ! adb devices | awk 'NR>1 && $2=="device" {print $1}' | grep -qx "$DEVICE"; then
            read -rp "Device disconnected. retry or reselect device? [r/s]: " ans
            case "$ans" in
                r|R) continue ;;
                s|S) choose_device; return 1 ;;
                *)   log ERROR "E_NO_DEVICE: device unavailable"; return 1 ;;
            esac
        fi
        sleep 1
    done
    log ERROR "E_DUMPSYS_FAIL: adb shell $* failed"
    return 1
}

# Device selection helper
# Presents connected devices in a menu and initializes reporting
# for the chosen device.

choose_device() {
    local devices
    devices=$(adb devices | awk 'NR>1 && $2=="device" {print $1}')
    if [[ -z "$devices" ]]; then
        log ERROR "E_NO_DEVICE: no devices detected"
        return
    fi

    draw_menu_header "Device Selection"
    local i=1
    for d in $devices; do
        echo "  [$i] $d"
        ((i++))
    done
    echo "--------------------------------------------------"
    read -rp "Select device [1-$((i-1))]: " choice
    DEVICE=$(echo "$devices" | sed -n "${choice}p")

    if [[ -z "$DEVICE" ]]; then
        log ERROR "Invalid device choice."
        return
    fi

    DEVICE_DIR="$RESULTS_DIR/$DEVICE"
    mkdir -p "$DEVICE_DIR"
    DEVICE_FINGERPRINT="$(adb_shell getprop ro.product.manufacturer | tr -d '\r') $(adb_shell getprop ro.product.model | tr -d '\r')"
    export DEVICE_FINGERPRINT
    init_report
    log SUCCESS "Using device: $DEVICE"
    log INFO "Output directory: $DEVICE_DIR"

    if [[ "${INCLUDE_DEVICE_PROFILE:-false}" == "true" ]]; then
        adb -s "$DEVICE" shell getprop | tee -a "$LOGFILE" > "$DEVICE_DIR/device_profile.txt"
        log INFO "Device profile saved: $DEVICE_DIR/device_profile.txt"
    fi
}
