#!/usr/bin/env bash
# ---------------------------------------------------
# run.sh - DroidHarvester Interactive APK Harvester
# ---------------------------------------------------
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND" >&2' ERR

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

DEVICE=""
LOG_LEVEL="${LOG_LEVEL:-INFO}"
DH_DEBUG="${DH_DEBUG:-0}"

# --- Load config first so logging picks up overrides ---
# shellcheck disable=SC1090
source "$REPO_ROOT/config/config.sh"

# --- Core logging/errors ---
# shellcheck disable=SC1090
source "$REPO_ROOT/lib/core/logging.sh"
# shellcheck disable=SC1090
source "$REPO_ROOT/lib/core/errors.sh"

export LOG_LEVEL DH_DEBUG

# --- Core + IO + menu libs ---
for lib in \
  core/trace core/deps core/device core/session \
  menu/menu_util menu/header \
  io/apk_utils io/report io/find_latest
do
  # shellcheck disable=SC1090
  source "$REPO_ROOT/lib/$lib.sh"
done

# --- Actions (unchanged full pipeline lives here) ---
for action in \
  choose_device scan_apps add_custom_package harvest \
  list_apps search_apps capability_report view_report \
  export_bundle resume cleanup
do
  # shellcheck disable=SC1090
  source "$REPO_ROOT/lib/actions/$action.sh"
done

# --- Session init & dependency checks ---
init_session
log_file_init "$LOGFILE"
logging_rotate
check_dependencies

# --- Resolve device if single attached or pre-set ---
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
[[ "$DH_DEBUG" == "1" ]] && enable_xtrace_to_file "$(_log_path trace)"

# --- Helpers for menu rendering ---
print_menu() {
  local title="$1" device="$2" last_report="$3"

  # Safe counts even with `set -u`
  local custom_count=0
  if declare -p CUSTOM_PACKAGES >/dev/null 2>&1; then
    set +u
    custom_count=${#CUSTOM_PACKAGES[@]}
    set -u
  fi

  draw_menu_header "$title" "$device" "$last_report"
  echo " Harvested   : found ${PKGS_FOUND:-0} pulled ${PKGS_PULLED:-0}"
  echo " Targets     : ${#TARGET_PACKAGES[@]} default / ${custom_count} custom"
  echo
  cat <<'MENU'
   [ 1] Choose device
   [ 2] Scan for target apps
   [ 3] Add custom package
   [ 4] Quick APK Harvest
   [ 5] Harvest APKs + metadata
   [ 6] View last report
   [ 7] List ALL installed apps
   [ 8] Search installed apps
   [ 9] Device capability report
   [10] Export report bundle
   [11] Resume last session
   [12] Clean up partial run
   [13] Clear log/results
   [ 0] Exit
MENU
}

read_choice_0_13() {
  local choice
  while true; do
    read -rp "Enter selection [0-13]: " choice
    [[ "$choice" =~ ^[0-9]+$ ]] || { echo "[ERR ] Invalid selection."; continue; }
    (( choice >= 0 && choice <= 13 )) && { printf '%s' "$choice"; return 0; }
    echo "[ERR ] Choice out of range."
  done
}

ensure_device_selected() {
  if [[ -z "$DEVICE" ]]; then
    echo "[INFO] No device selected; opening selector..."
    choose_device || true
  fi
}

# --- Main loop ---
while true; do
  LAST_TXT_REPORT="$(latest_report || true)"
  header_report=""
  [[ -n "$LAST_TXT_REPORT" ]] && header_report="$(basename "$LAST_TXT_REPORT")"

  print_menu "DroidHarvester Main Menu" "$DEVICE" "$header_report"
  choice="$(read_choice_0_13)"
  echo

  case "$choice" in
    1) choose_device ;;
    2) scan_apps ;;
    3) add_custom_package ;;

    4)
      # Quick APK Harvest (no-args)
      ensure_device_selected
      if [[ -x "$REPO_ROOT/scripts/grab_apks.sh" ]]; then
        echo "[INFO] Pulling APKs for default targets..."
        "$REPO_ROOT/scripts/grab_apks.sh" || true
      else
        LOG_COMP="core" log WARN "scripts/grab_apks.sh missing or not executable."
        echo "Hint: chmod +x scripts/grab_apks.sh"
      fi
      ;;

    5)
      # Full pipeline (metadata, reports)
      ensure_device_selected
      harvest
      ;;
    6) view_report ;;
    7) list_installed_apps ;;
    8) search_installed_apps ;;
    9) capability_report ;;
    10) export_report ;;
    11) resume_last_session ;;
    12) cleanup_partial_run ;;
    13) cleanup_all_artifacts ;;

    0)
      LOG_COMP="core" log INFO "Exiting DroidHarvester."
      exit 0
      ;;
  esac

  draw_menu_footer
  pause
done
