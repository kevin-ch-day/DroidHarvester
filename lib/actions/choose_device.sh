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

to_safe() { echo "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '_'; }

gather_device_profile() {
    local serial="$1"
    DEVICE_SERIAL="$serial"
    DEVICE_VENDOR="$(adb -s "$serial" shell getprop ro.product.manufacturer | tr -d '\r')"
    DEVICE_MODEL="$(adb -s "$serial" shell getprop ro.product.model | tr -d '\r')"
    DEVICE_ANDROID_VERSION="$(adb -s "$serial" shell getprop ro.build.version.release | tr -d '\r')"
    DEVICE_BUILD_ID="$(adb -s "$serial" shell getprop ro.build.id | tr -d '\r')"
    local safe_vendor safe_model
    safe_vendor="$(to_safe "$DEVICE_VENDOR")"
    safe_model="$(to_safe "$DEVICE_MODEL")"
    DEVICE_DIR_NAME="${safe_vendor}_${safe_model}_${DEVICE_SERIAL}"
    DEVICE_DIR="$RESULTS_DIR/$DEVICE_DIR_NAME"
    DEVICE_FINGERPRINT="$DEVICE_VENDOR $DEVICE_MODEL"
    DEVICE_LABEL="$DEVICE_VENDOR $DEVICE_MODEL [$DEVICE_SERIAL]"
    mkdir -p "$DEVICE_DIR"
    export DEVICE_SERIAL DEVICE_VENDOR DEVICE_MODEL DEVICE_ANDROID_VERSION DEVICE_BUILD_ID \
           DEVICE_DIR DEVICE_DIR_NAME DEVICE_FINGERPRINT DEVICE_LABEL
    LOG_DEV="$DEVICE_LABEL"
    export LOG_DEV
}

device_label_for_serial() {
    local s="$1" v m
    v="$(adb -s "$s" shell getprop ro.product.manufacturer | tr -d '\r')"
    m="$(adb -s "$s" shell getprop ro.product.model | tr -d '\r')"
    echo "$v $m [$s]"
}

choose_device() {
    trace_enter "choose_device"
    local -a dev_array label_array
    mapfile -t dev_array < <(device_list_connected)
    if (( ${#dev_array[@]} == 0 )); then
        LOG_CODE="$E_NO_DEVICE" log ERROR "no devices detected"
        return
    fi

    draw_menu_header "Device Selection"
    for idx in "${!dev_array[@]}"; do
        label_array[idx]="$(device_label_for_serial "${dev_array[idx]}")"
        echo "  [$((idx+1))] ${label_array[idx]}"
    done
    echo "--------------------------------------------------"
    read -rp "Select device [1-${#dev_array[@]}]: " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#dev_array[@]} )); then
        log ERROR "Invalid device choice."
        return
    fi
    DEVICE="${dev_array[choice-1]}"
    set_device "$DEVICE" || { log ERROR "failed to set device"; return; }

    gather_device_profile "$DEVICE"
    init_report
    log SUCCESS "Using device: $DEVICE_LABEL"
    log INFO "Output directory: $DEVICE_DIR"

    if [[ "${INCLUDE_DEVICE_PROFILE:-false}" == "true" ]]; then
        {
            echo "serial=$DEVICE_SERIAL"
            echo "vendor=$DEVICE_VENDOR"
            echo "model=$DEVICE_MODEL"
            echo "android_version=$DEVICE_ANDROID_VERSION"
            echo "build_id=$DEVICE_BUILD_ID"
            adb_shell getprop
        } | tee -a "$LOGFILE" > "$DEVICE_DIR/device_profile.txt"
        log INFO "Device profile saved: $DEVICE_DIR/device_profile.txt"
    fi
    trace_leave "choose_device"
}
