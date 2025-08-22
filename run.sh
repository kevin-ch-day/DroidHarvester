#!/bin/bash
# ---------------------------------------------------
# run.sh - DroidHarvester Interactive APK Harvester
# ---------------------------------------------------
# Main operator console for harvesting APKs, extracting
# metadata, and generating IEEE-style analyst reports.
# ---------------------------------------------------

set -euo pipefail
trap 'echo "ERROR: Aborted at line $LINENO" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# ---------------------------------------------------
# Load config + libs
# ---------------------------------------------------
source "$SCRIPT_DIR/config.sh"

for lib in logging device apk_utils metadata report menu_util; do
    source "$SCRIPT_DIR/lib/$lib.sh"
done

# ---------------------------------------------------
# Globals
# ---------------------------------------------------
RESULTS_DIR="$SCRIPT_DIR/results"
LOGS_DIR="$SCRIPT_DIR/logs"
mkdir -p "$RESULTS_DIR" "$LOGS_DIR"

LOGFILE="$LOGS_DIR/harvest_log_$TIMESTAMP.txt"
REPORT="$RESULTS_DIR/apks_report_$TIMESTAMP.csv"
JSON_REPORT="$RESULTS_DIR/apks_report_$TIMESTAMP.json"
TXT_REPORT="$RESULTS_DIR/apks_report_$TIMESTAMP.txt"

DEVICE=""
DEVICE_DIR=""
CUSTOM_PACKAGES_FILE="$SCRIPT_DIR/custom_packages.txt"
CUSTOM_PACKAGES=()
[[ -f "$CUSTOM_PACKAGES_FILE" ]] && mapfile -t CUSTOM_PACKAGES < "$CUSTOM_PACKAGES_FILE"

# ---------------------------------------------------
# Setup / Checks
# ---------------------------------------------------
check_dependencies() {
    for cmd in adb jq sha256sum md5sum sha1sum zip column; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log ERROR "Missing dependency: $cmd"
            exit 1
        fi
    done
}

session_metadata() {
    {
        echo "=================================================="
        echo " DroidHarvester Session Metadata"
        echo " Host       : $(hostname)"
        echo " User       : $(whoami)"
        echo " Date       : $(date)"
        echo " OS         : $(uname -srvmo)"
        echo "=================================================="
    } >> "$LOGFILE"
    log INFO "Session initialized (log: $LOGFILE)"
}

# ---------------------------------------------------
# Menu functions
# ---------------------------------------------------
choose_device() {
    local devices
    devices=$(adb devices | awk 'NR>1 && $2=="device" {print $1}')
    if [[ -z "$devices" ]]; then
        log WARN "No devices detected."
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
    init_report
    log SUCCESS "Using device: $DEVICE"
    log INFO "Output directory: $DEVICE_DIR"

    if [[ "${INCLUDE_DEVICE_PROFILE:-false}" == "true" ]]; then
        adb -s "$DEVICE" shell getprop | tee -a "$LOGFILE" > "$DEVICE_DIR/device_profile.txt"
        log INFO "Device profile saved: $DEVICE_DIR/device_profile.txt"
    fi
}

scan_apps() {
    [[ -z "$DEVICE" ]] && { log WARN "Choose a device first."; return; }
    log INFO "Scanning for target apps..."
    for pkg in "${TARGET_PACKAGES[@]}"; do
        if adb -s "$DEVICE" shell pm list packages | grep -q "$pkg"; then
            log SUCCESS "Found: $pkg"
        else
            log WARN "Not installed: $pkg"
        fi
    done
}

add_custom_package() {
    read -rp "Enter package name (e.g., com.example.app): " pkg
    if [[ -n "$pkg" ]]; then
        CUSTOM_PACKAGES+=("$pkg")
        echo "$pkg" >> "$CUSTOM_PACKAGES_FILE"
        log SUCCESS "Added custom package: $pkg"
    else
        log WARN "No package entered."
    fi
}

harvest() {
    [[ -z "$DEVICE" ]] && { log WARN "Choose a device first."; return; }
    local all_pkgs=("${TARGET_PACKAGES[@]}" "${CUSTOM_PACKAGES[@]}")

    if [[ ${#all_pkgs[@]} -eq 0 ]]; then
        log WARN "No packages selected."
        return
    fi

    for pkg in "${all_pkgs[@]}"; do
        log INFO "Checking $pkg..."
        apk_paths=$(get_apk_paths "$pkg")
        if [[ -n "$apk_paths" ]]; then
            while read -r path; do
                [[ -z "$path" ]] && continue
                log INFO "Found APK: $path"
                outfile=$(pull_apk "$pkg" "$path")
                [[ -n "$outfile" ]] && apk_metadata "$pkg" "$outfile"
            done <<< "$apk_paths"
        else
            log WARN "Not installed: $pkg"
        fi
    done

    finalize_report "all"
    log SUCCESS "Harvest complete. Reports written to $RESULTS_DIR"
}

list_installed_apps() {
    [[ -z "$DEVICE" ]] && { log WARN "Choose a device first."; return; }
    log INFO "Listing installed apps..."
    adb -s "$DEVICE" shell pm list packages | sed 's/package://g' | sort
}

search_installed_apps() {
    [[ -z "$DEVICE" ]] && { log WARN "Choose a device first."; return; }
    read -rp "Enter search keyword: " keyword
    log INFO "Searching for '$keyword'..."
    adb -s "$DEVICE" shell pm list packages | grep -i "$keyword" | sed 's/package://g'
}

view_report() {
    latest=$(ls -t "$RESULTS_DIR"/apks_report_*.txt  2>/dev/null | head -n1 || true)
    if [[ -z "$latest" ]]; then
        log WARN "No reports found."
    else
        echo
        echo "--------------------------------------------------"
        echo " Last Report (Preview)"
        echo "--------------------------------------------------"
        head -n 40 "$latest"
        echo "--------------------------------------------------"
        log INFO "Full report: $latest"
    fi
}

export_report() {
    local zipfile="$RESULTS_DIR/apk_harvest_${TIMESTAMP}.zip"
    zip -j "$zipfile" "$REPORT" "$JSON_REPORT" "$TXT_REPORT" "$LOGFILE" >/dev/null
    log SUCCESS "Exported report bundle: $zipfile"
}

# ---------------------------------------------------
# Main
# ---------------------------------------------------
check_dependencies
session_metadata

while true; do
    draw_menu_header "DroidHarvester Main Menu"
    echo " Device: ${DEVICE:-Not selected}"
    echo
    show_menu \
        "Choose device" \
        "Scan for target apps" \
        "Add custom package" \
        "Harvest APKs + metadata" \
        "View last report" \
        "List ALL installed apps" \
        "Search installed apps" \
        "Export report bundle" \
        "Exit"
    choice=$(read_choice 9)

    case $choice in
        1) choose_device ;;
        2) scan_apps ;;
        3) add_custom_package ;;
        4) harvest ;;
        5) view_report ;;
        6) list_installed_apps ;;
        7) search_installed_apps ;;
        8) export_report ;;
        9) log INFO "Exiting DroidHarvester."; exit 0 ;;
    esac

    draw_menu_footer
    pause
done
