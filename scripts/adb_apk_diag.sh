#!/usr/bin/env bash
# Minimal APK diagnostics using centralized helpers
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/lib/io/apk_utils.sh"

DEV="${DEV:-$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}') }"
[[ -n "$DEV" ]] || { echo "No device" >&2; exit 1; }

base="scripts/results/$DEV"
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
