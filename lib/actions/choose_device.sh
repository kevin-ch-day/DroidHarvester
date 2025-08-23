#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# choose_device.sh - device selection action
# ---------------------------------------------------

choose_device() {
    local devices
    devices=$(with_trace adb_list -- adb devices | awk 'NR>1 && $2=="device" {print $1}')
    if [[ -z "$devices" ]]; then
        LOG_CODE="$E_NO_DEVICE" log ERROR "no devices detected"
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
    LOG_DEV="$DEVICE" log SUCCESS "Using device: $DEVICE"
    LOG_DEV="$DEVICE" log INFO "Output directory: $DEVICE_DIR"

    if [[ "${INCLUDE_DEVICE_PROFILE:-false}" == "true" ]]; then
        adb -s "$DEVICE" shell getprop | tee -a "$LOGFILE" > "$DEVICE_DIR/device_profile.txt"
        LOG_DEV="$DEVICE" log INFO "Device profile saved: $DEVICE_DIR/device_profile.txt"
    fi
}
