#!/usr/bin/env bash
# Minimal APK diagnostics using centralized helpers
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load configs if present
for f in "$ROOT"/config/*.sh; do
  # shellcheck disable=SC1090
  [[ -r "$f" ]] && source "$f"
done

# Shared helpers
# shellcheck disable=SC1090
source "$ROOT/lib/core/logging.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/errors.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/trace.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/device/env.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/device/select.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/device/wrappers.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/device/pm.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/io/apk_utils.sh"

# ---- Device resolution -------------------------------------------------------
SERIAL="$(device_pick_or_fail "${DEV:-}")"
set_device "$SERIAL"
assert_device_ready "$DEVICE"

# ---- Arg parsing -------------------------------------------------------------
PULL=0
LIMIT=1
PKG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pull) PULL=1; shift ;;
    --limit) LIMIT="$2"; shift 2 ;;
    *) PKG="$1"; shift ;;
  esac
done
PKG="${PKG:-com.zhiliaoapp.musically}"

# ---- Working dirs ------------------------------------------------------------
base="$ROOT/results/$DEVICE"
find "$base" -maxdepth 1 -type d -name 'manual_diag_*' -exec rm -rf {} + 2>/dev/null || true

RUN_DIR="$base/manual_diag_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RUN_DIR"

# ---- Collect paths + sanitize ------------------------------------------------
au_pm_path_raw "$PKG" > "$RUN_DIR/pm_path_raw.txt"
au_pm_path_raw "$PKG" | au_pm_path_sanitize > "$RUN_DIR/pm_path_san.txt"

# ---- Optional pull and verify ------------------------------------------------
pulled=0
pulled_files=()
if (( PULL )); then
  mapfile -t _paths < "$RUN_DIR/pm_path_san.txt"
  BASE_APK="$(au_pick_base_apk "$RUN_DIR/pm_path_san.txt" || true)"
  ordered=()
  [[ -n "$BASE_APK" ]] && ordered+=("$BASE_APK")
  for p in "${_paths[@]}"; do
    [[ "$p" == "$BASE_APK" ]] && continue
    ordered+=("$p")
  done
  pull_dir="$RUN_DIR/pulled"
  mkdir -p "$pull_dir"
  remote_sizes=()
  local_sizes=()
  for p in "${ordered[@]}"; do
    (( pulled >= LIMIT )) && break
    REMOTE_SIZE="$(au_dev_file_size "$p" 2>/dev/null || true)"
    LOCAL="$(au_pull_one "$p" "$pull_dir" || true)"
    LOCAL_SIZE=""
    [[ -n "${LOCAL:-}" ]] && LOCAL_SIZE="$(stat -c%s "$LOCAL" 2>/dev/null || true)"
    if [[ -n "${LOCAL:-}" && -s "$LOCAL" ]]; then
      au_verify_hash "$p" "$LOCAL" || true
      if [[ -n "$REMOTE_SIZE" && -n "$LOCAL_SIZE" && "$REMOTE_SIZE" != "$LOCAL_SIZE" ]]; then
        LOG_APK="$(basename "$LOCAL")" log WARN "size mismatch (remote $REMOTE_SIZE vs local $LOCAL_SIZE)"
      fi
    fi
    pulled_files+=("$LOCAL")
    remote_sizes+=("$REMOTE_SIZE")
    local_sizes+=("$LOCAL_SIZE")
    ((pulled++))
  done
fi

# ---- Metadata + related scans ------------------------------------------------
au_pkg_meta_csv_line "$PKG" > "$RUN_DIR/meta.csv" || true
au_scan_tiktok_family   > "$RUN_DIR/tiktok_family.txt"   || true
au_scan_tiktok_related  > "$RUN_DIR/tiktok_related.txt"  || true

# ---- Summary log -------------------------------------------------------------
LOG_DIR="$ROOT/logs"
mkdir -p "$LOG_DIR"
SUMMARY="$LOG_DIR/adb_apk_diag_$(date +%Y%m%d_%H%M%S).txt"
{
  echo "package=$PKG"
  echo "device=$DEVICE"
  echo "run_dir=$RUN_DIR"
  echo "paths=$(wc -l < "$RUN_DIR/pm_path_san.txt" 2>/dev/null)"
  if (( PULL )); then
    echo "pulled=$pulled"
    for i in "${!pulled_files[@]}"; do
      f="${pulled_files[i]}"
      r="${remote_sizes[i]}"
      l="${local_sizes[i]}"
      [[ -n "$f" ]] || continue
      status="remote=${r:-?} local=${l:-?}"
      [[ -n "$r" && -n "$l" && "$r" != "$l" ]] && status+=" mismatch"
      echo "  $(basename "$f") $status"
    done
  fi
} > "$SUMMARY"

echo "Artifacts in: $RUN_DIR"
echo "Summary: $SUMMARY"
