#!/usr/bin/env bash
# ---------------------------------------------------
# run.sh - DroidHarvester Interactive APK Harvester
# ---------------------------------------------------
# Main operator console for harvesting APKs, extracting
# metadata, and generating IEEE-style analyst reports.
# ---------------------------------------------------

set -euo pipefail
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

LOG_LEVEL="INFO"
if [[ "${1:-}" == "--debug" ]]; then
    LOG_LEVEL="DEBUG"
fi
export LOG_LEVEL

# ---------------------------------------------------
# Load config + libs
# ---------------------------------------------------
source "$SCRIPT_DIR/config.sh"

for lib in deps logging device apk_utils metadata report menu_util; do
    # shellcheck disable=SC1090
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
CUSTOM_PACKAGES_FILE="$SCRIPT_DIR/custom_packages.txt"
CUSTOM_PACKAGES=()
[[ -f "$CUSTOM_PACKAGES_FILE" ]] && mapfile -t CUSTOM_PACKAGES < "$CUSTOM_PACKAGES_FILE"

PKGS_FOUND=0
PKGS_PULLED=0
LAST_TXT_REPORT=""
DEVICE_FINGERPRINT=""
SESSION_ID="$TIMESTAMP"
export DEVICE_FINGERPRINT SESSION_ID

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

scan_apps() {
    [[ -z "$DEVICE" ]] && { log WARN "Choose a device first."; return; }
    log INFO "Scanning for target apps..."
    local pkg_list
    pkg_list=$(adb_shell pm list packages) || return
    for pkg in "${TARGET_PACKAGES[@]}"; do
        if grep -Fq -- "$pkg" <<< "$pkg_list"; then
            log SUCCESS "Found: $pkg"
        else
            log WARN "Not installed: $pkg" || true
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
        log WARN "No package entered." || true
    fi
}

harvest() {
    [[ -z "$DEVICE" ]] && { log WARN "Choose a device first."; return; }
    local all_pkgs=("${TARGET_PACKAGES[@]}" "${CUSTOM_PACKAGES[@]}")

    if [[ ${#all_pkgs[@]} -eq 0 ]]; then
        log WARN "No packages selected."
        return
    fi

    PKGS_FOUND=0
    PKGS_PULLED=0
    for pkg in "${all_pkgs[@]}"; do
        log INFO "Checking $pkg..."
        apk_paths=$(get_apk_paths "$pkg" || true)
        lookup_status=${PIPESTATUS[0]}
        if [[ $lookup_status -ne 0 || -z "$apk_paths" ]]; then
            log WARN "Not installed: $pkg" || true
            continue
        fi
        ((PKGS_FOUND++))
        local pulled=0
          while read -r path; do
              if [[ -z "$path" ]]; then
                  continue
              fi
              log INFO "Found APK: $path"
              outfile=$(pull_apk "$pkg" "$path")
              if [[ -n "$outfile" ]]; then
                  pulled=1
                  apk_metadata "$pkg" "$outfile"
              fi
          done <<< "$apk_paths"
        ((pulled)) && ((PKGS_PULLED++))
    done

    finalize_report "all"
    LAST_TXT_REPORT="$TXT_REPORT"
    log SUCCESS "Harvest complete. Reports written to $RESULTS_DIR"
}

list_installed_apps() {
    [[ -z "$DEVICE" ]] && { log WARN "Choose a device first."; return; }
    log INFO "Listing installed apps..."
    adb_shell pm list packages | sed 's/package://g' | sort
}

search_installed_apps() {
    [[ -z "$DEVICE" ]] && { log WARN "Choose a device first."; return; }
    read -rp "Enter search keyword: " keyword
    if [[ -z "$keyword" ]]; then
        log WARN "No keyword entered."
        return
    fi
    log INFO "Searching for '$keyword'..."
    local results
    results=$(adb_shell pm list packages | grep -Fi -- "$keyword" | sed 's/package://g')
    if [[ -n "$results" ]]; then
        echo "$results"
    else
        log WARN "No packages match '$keyword'" || true
    fi
}

view_report() {
    local latest
    latest=$(latest_report)
    if [[ -z "$latest" ]]; then
        log WARN "No reports found."
    else
        LAST_TXT_REPORT="$latest"
        echo
        echo "--------------------------------------------------"
        echo " Last Report (Preview)"
        echo "--------------------------------------------------"
        head -n 40 "$latest"
        echo "--------------------------------------------------"
        log INFO "Full report: $latest" || true
    fi
}

cleanup_partial_run() {
    if [[ -z "$DEVICE_DIR" || ! -d "$DEVICE_DIR" ]]; then
        log WARN "No device directory to clean."
        return
    fi
    read -rp "Remove $DEVICE_DIR? [y/N]: " ans
    case "$ans" in
        [Yy]*) rm -rf "$DEVICE_DIR"; log SUCCESS "Removed $DEVICE_DIR"; DEVICE="" ;; 
        *) log WARN "Cleanup cancelled." ;;
    esac
}

resume_last_session() {
    local last_dev
    last_dev=$(find "$RESULTS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | xargs -0 stat --printf '%Y\t%n\0' 2>/dev/null | sort -z -nr | head -z -n1 | cut -f2- | tr -d '\0')
    if [[ -z "$last_dev" ]]; then
        log WARN "No previous session found."
        return
    fi
    DEVICE=$(basename "$last_dev")
    DEVICE_DIR="$last_dev"
    init_report
    log SUCCESS "Resumed device: $DEVICE"
}

export_report() {
    local zipfile="$RESULTS_DIR/apk_harvest_${TIMESTAMP}.zip"
    local files=()
    for f in "$REPORT" "$JSON_REPORT" "$TXT_REPORT" "$LOGFILE"; do
        [[ -f "$f" ]] && files+=("$f")
    done
    if [[ ${#files[@]} -eq 0 ]]; then
        log WARN "No reports to export. Run a harvest first."
        return
    fi
    zip -j "$zipfile" "${files[@]}" >/dev/null
    log SUCCESS "Exported report bundle: $zipfile"
}

# ---------------------------------------------------
# Main
# ---------------------------------------------------
check_dependencies
session_metadata

while true; do
    LAST_TXT_REPORT=$(latest_report)
    header_report=""
    if [[ -n "$LAST_TXT_REPORT" ]]; then
        header_report="$(basename "$LAST_TXT_REPORT")"
    fi
    draw_menu_header "DroidHarvester Main Menu" "$DEVICE" "$header_report"
    echo " Harvested   : found $PKGS_FOUND pulled $PKGS_PULLED"
    echo " Targets     : ${#TARGET_PACKAGES[@]} default / ${#CUSTOM_PACKAGES[@]} custom"
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
        "Resume last session" \
        "Clean up partial run" \
        "Exit"
    choice=$(read_choice 11)

    case $choice in
        1) choose_device ;;
        2) scan_apps ;;
        3) add_custom_package ;;
        4) harvest ;;
        5) view_report ;;
        6) list_installed_apps ;;
        7) search_installed_apps ;;
        8) export_report ;;
        9) resume_last_session ;;
        10) cleanup_partial_run ;;
        11) log INFO "Exiting DroidHarvester."; exit 0 ;;
    esac

    draw_menu_footer
    pause
done
