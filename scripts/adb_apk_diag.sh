#!/usr/bin/env bash
# Minimal APK diagnostics using centralized helpers
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/lib/io/apk_utils.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/device.sh"
# Auto-detect device, handling multiple/unauthorized cases
if [[ -z "${DEV:-}" ]]; then
  if tmp_dev=$(get_normalized_serial); then
    DEV="$tmp_dev"
  else
    rc=$?
    case "$rc" in
      1) echo "[ERR] no devices detected." >&2 ;;
      2) echo "[ERR] multiple devices detected; set DEV=<serial>." >&2 ;;
      3) echo "[ERR] device unauthorized. run 'adb kill-server; adb devices; accept RSA prompt; re-run.'" >&2 ;;
    esac
    exit 1
  fi
else
  DEV="$(printf '%s' "$DEV" | tr -d '\r' | xargs)"
fi
DEVICE="$DEV"
assert_device_ready "$DEVICE"
update_adb_flags
if [[ "${DEBUG:-0}" == "1" ]]; then
  printf '[DEBUG] DEV="%s"\n' "$DEV"
  printf '[DEBUG] DEV bytes: '
  printf '%s' "$DEV" | hexdump -C | sed -n '1p'
fi

base="$ROOT/results/$DEVICE"
find "$base" -maxdepth 1 -type d -name 'manual_diag_*' -exec rm -rf {} + 2>/dev/null || true

RUN_DIR="$base/manual_diag_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RUN_DIR"

PKG="${1:-com.zhiliaoapp.musically}"

au_pm_path_raw "$PKG" > "$RUN_DIR/pm_path_raw.txt"
au_pm_path_raw "$PKG" | au_pm_path_sanitize > "$RUN_DIR/pm_path_san.txt"

BASE_APK="$(au_pick_base_apk "$RUN_DIR/pm_path_san.txt" || true)"
if [[ -n "$BASE_APK" ]]; then
  LOCAL="$(au_pull_one "$BASE_APK" "$RUN_DIR" || true)"
  au_dev_file_size "$BASE_APK" >/dev/null || true
  au_verify_hash "$BASE_APK" "$LOCAL" || true
fi

au_pkg_meta_csv_line "$PKG" > "$RUN_DIR/meta.csv" || true
au_scan_tiktok_family > "$RUN_DIR/tiktok_family.txt" || true
au_scan_tiktok_related > "$RUN_DIR/tiktok_related.txt" || true

echo "Artifacts in: $RUN_DIR"
