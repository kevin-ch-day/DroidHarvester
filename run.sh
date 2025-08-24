#!/usr/bin/env bash
# ---------------------------------------------------
# run.sh - DroidHarvester Interactive APK Harvester
# ---------------------------------------------------
# Entry point: manages menu loop and dispatches actions.
# ---------------------------------------------------

set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND" >&2' ERR

# Optional: allow log cleanup via flag (safe to remove if you want no-args only)
CLEAN_LOGS=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--clean-logs) CLEAN_LOGS=1 ;;
        *) echo "Usage: $0 [--clean-logs]" >&2; exit 64 ;;
    esac
    shift
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"
SCRIPT_DIR="$REPO_ROOT"

DEVICE=""
LOG_LEVEL=${LOG_LEVEL:-INFO}
DH_DEBUG=${DH_DEBUG:-0}

# Load error/logging helpers early
# shellcheck disable=SC1090
source "$REPO_ROOT/lib/core/errors.sh"
# shellcheck disable=SC1090
source "$REPO_ROOT/lib/core/logging.sh"

export LOG_LEVEL DH_DEBUG

# Load config
# shellcheck disable=SC1090
source "$REPO_ROOT/config.sh"
validate_config

# Core + IO + menu libs
# shellcheck disable=SC1090
for lib in core/trace core/deps core/device core/session menu/menu_util menu/header io/apk_utils io/report io/find_latest; do
    # shellcheck disable=SC1090
    source "$REPO_ROOT/lib/$lib.sh"
done

# Actions
# shellcheck disable=SC1090
for action in choose_device scan_apps add_custom_package harvest list_apps search_apps view_report export_bundle resume cleanup; do
    # shellcheck disable=SC1090
    source "$REPO_ROOT/lib/actions/$action.sh"
done

init_session
log_file_init "$LOGFILE"

check_dependencies

# One-time optional cleanup if requested
if (( CLEAN_LOGS == 1 )); then
    # Use the existing action to purge partial runs/logs as implemented in your repo
    cleanup_partial_run || true
fi

# Resolve device if pre-set or auto-pick single attached device
if [[ -n "${DEVICE}" ]]; then
    DEVICE="$(printf '%s' "$DEVICE" | tr -d '\r' | xargs)"
    DEVICE="$(device_pick_or_fail "$DEVICE")"
else
    mapfile -t _devs < <(device_list_connected)
    if (( ${#_devs[@]} == 1 )); then
        DEVICE="${_devs[0]}"
    fi
fi

if [[ -n "$DEVICE" ]]; then
    # Ensure it's really usable
    if ! assert_device_ready "$DEVICE"; then
        DEVICE=""
    else
        # Set common ADB flags if helper exists
        if type update_adb_flags >/dev/null 2>&1; then
            update_adb_flags
        fi
    fi
fi

session_metadata

if [[ $DH_DEBUG -eq 1 ]]; then
    enable_xtrace_to_file "$LOGS_DIR/trace_$TIMESTAMP.log"
fi

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
        11) LOG_COMP="core" log INFO "Exiting DroidHarvester."; exit 0 ;;
    esac

    draw_menu_footer
    pause
done
