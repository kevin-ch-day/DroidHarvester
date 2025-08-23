#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# choose_device.sh - device selection action
# ---------------------------------------------------

# shellcheck disable=SC1090
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/core/trace.sh"
# shellcheck disable=SC1090
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/core/device.sh"

choose_device() {
    trace_enter "choose_device"
    local -a dev_array
    mapfile -t dev_array < <(device_list_connected)
    if (( ${#dev_array[@]} == 0 )); then
        LOG_CODE="$E_NO_DEVICE" log ERROR "no devices detected"
        return
    fi

    draw_menu_header "Device Selection"
    for idx in "${!dev_array[@]}"; do
        echo "  [$((idx+1))] ${dev_array[idx]}"
    done
    echo "--------------------------------------------------"
    read -rp "Select device [1-${#dev_array[@]}]: " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#dev_array[@]} )); then
        log ERROR "Invalid device choice."
        return
    fi
    DEVICE="${dev_array[choice-1]}"

    DEVICE_DIR="$RESULTS_DIR/$DEVICE"
    mkdir -p "$DEVICE_DIR"
    DEVICE_FINGERPRINT="$(adb_shell getprop ro.product.manufacturer | tr -d '\r') $(adb_shell getprop ro.product.model | tr -d '\r')"
    export DEVICE_FINGERPRINT
    init_report
    LOG_DEV="$DEVICE"
    log SUCCESS "Using device: $DEVICE"
    log INFO "Output directory: $DEVICE_DIR"

    if [[ "${INCLUDE_DEVICE_PROFILE:-false}" == "true" ]]; then
        adb -s "$DEVICE" shell getprop | tee -a "$LOGFILE" > "$DEVICE_DIR/device_profile.txt"
        log INFO "Device profile saved: $DEVICE_DIR/device_profile.txt"
    fi
    unset LOG_DEV
    trace_leave "choose_device"
}
