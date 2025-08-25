#!/usr/bin/env bash
# ---------------------------------------------------
# run.sh - DroidHarvester Interactive APK Harvester
# ---------------------------------------------------
# Entry point: manages menu loop and dispatches actions.
# ---------------------------------------------------

set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND" >&2' ERR

# Optional: allow log cleanup via flag or env var
CLEAR_LOGS="${CLEAR_LOGS:-false}"
for arg in "$@"; do
    case "$arg" in
        --clear-logs) CLEAR_LOGS=true ;;
        *) echo "Usage: $0 [--clear-logs]" >&2; exit 64 ;;
    esac
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

# Load all config snippets from config/*.sh
for f in "$REPO_ROOT"/config/*.sh; do
    # shellcheck disable=SC1090
    [[ -r "$f" ]] && source "$f"
done
# Validate if helper exists
if declare -F validate_config >/dev/null 2>&1; then
    validate_config
fi

# Optionally clear logs when exiting
if [[ "$CLEAR_LOGS" == "true" ]]; then
    cleanup_logs_on_exit() {
        find "$LOG_DIR" "$REPO_ROOT/config/logs" "$REPO_ROOT/scripts/logs" -type f -name '*.txt' -delete 2>/dev/null || true
    }
    trap cleanup_logs_on_exit EXIT
fi

# Core + IO + menu libs
# shellcheck disable=SC1090
for lib in core/trace core/deps core/device core/session menu/menu_util menu/header io/apk_utils io/report io/find_latest; do
    # shellcheck disable=SC1090
    source "$REPO_ROOT/lib/$lib.sh"
done

# Actions
# shellcheck disable=SC1090
for action in choose_device scan_apps add_custom_package harvest list_apps search_apps capability_report view_report export_bundle resume cleanup; do
    # shellcheck disable=SC1090
    source "$REPO_ROOT/lib/actions/$action.sh"
done

init_session
log_file_init "$LOGFILE"

check_dependencies

# Resolve device if pre-set or auto-pick single attached device
if [[ -n "${DEVICE}" ]]; then
    DEVICE="$(normalize_serial "$DEVICE")"
    DEVICE="$(device_pick_or_fail "$DEVICE")"
    set_device "$DEVICE" || DEVICE=""
else
    mapfile -t _devs < <(device_list_connected)
    if (( ${#_devs[@]} == 1 )); then
        set_device "${_devs[0]}" || true
    fi
fi

if [[ -n "$DEVICE" ]]; then
    if ! assert_device_ready "$DEVICE"; then
        DEVICE=""
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
        "Device capability report" \
        "Export report bundle" \
        "Resume last session" \
        "Clean up partial run" \
        "Clear logs/results" \
        "Exit"
    choice=$(read_choice 13)

    case $choice in
        1) choose_device ;;
        2) scan_apps ;;
        3) add_custom_package ;;
        4) harvest ;;
        5) view_report ;;
        6) list_installed_apps ;;
        7) search_installed_apps ;;
        8) capability_report ;;
        9) export_report ;;
        10) resume_last_session ;;
        11) cleanup_partial_run ;;
        12) cleanup_all_artifacts ;;
        13) LOG_COMP="core" log INFO "Exiting DroidHarvester."; exit 0 ;;
    esac

    draw_menu_footer
    pause
done
