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
DEVICE_LABEL=""
LOG_LEVEL="${LOG_LEVEL:-INFO}"
DH_DEBUG="${DH_DEBUG:-0}"

# --- Load config first so logging picks up overrides ---
# shellcheck disable=SC1090
source "$REPO_ROOT/config/config.sh"

# --- Core logging/errors ---
# shellcheck disable=SC1090
source "$REPO_ROOT/lib/logging/logging_engine.sh"
# shellcheck disable=SC1090
source "$REPO_ROOT/lib/core/errors.sh"

export LOG_LEVEL DH_DEBUG

# --- Core + IO + menu libs ---
for lib in \
  core/trace core/deps core/device core/session \
  menu/menu_util menu/header menu/main_menu \
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
  else
    gather_device_profile "$DEVICE"
    init_report
  fi
fi

session_metadata
[[ "$DH_DEBUG" == "1" ]] && enable_xtrace_to_file "$(_log_path trace)"

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

  render_main_menu "DroidHarvester Main Menu" "${DEVICE_LABEL:-}" "$header_report"
  choice="$(read_choice_range 0 14)"
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
        if [[ -x "$REPO_ROOT/scripts/finalize_quickpull.sh" ]]; then
          echo "[INFO] Finalizing quick pull (friendly names + manifest)..."
          "$REPO_ROOT/scripts/finalize_quickpull.sh" || true
          qdir="$DEVICE_DIR/quick_pull_results"
          if [[ -f "$qdir/manifest.csv" ]]; then
            QUICK_PULL_DIR="$(basename "$qdir")"
            PKGS_FOUND=$(tail -n +2 "$qdir/manifest.csv" | cut -d, -f3 | sort -u | wc -l | tr -d ' ')
            PKGS_PULLED=$(( $(wc -l < "$qdir/manifest.csv" | tr -d ' ') - 1 ))
          fi
        fi
      else
        LOG_COMP="core" log WARN "scripts/grab_apks.sh missing or not executable."
        echo "Hint: chmod +x scripts/grab_apks.sh"
      fi
      ;;

    5)
      # Show latest quick-pull
      if [[ -x "$REPO_ROOT/scripts/show_latest_quickpull.sh" ]]; then
        "$REPO_ROOT/scripts/show_latest_quickpull.sh" || true
      else
        echo "[ERR] scripts/show_latest_quickpull.sh missing or not executable." >&2
      fi
      ;;

    6)
      # Full pipeline (metadata, reports)
      ensure_device_selected
      harvest
      ;;
    7) view_report ;;
    8) list_installed_apps ;;
    9) search_installed_apps ;;
    10) capability_report ;;
    11) export_report ;;
    12) resume_last_session ;;
    13) cleanup_partial_run ;;
    14) cleanup_all_artifacts ;;

    0)
      LOG_COMP="core" log INFO "Exiting DroidHarvester."
      exit 0
      ;;
  esac

  draw_menu_footer
  pause
done
