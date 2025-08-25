#!/usr/bin/env bash
# Minimal APK diagnostics using centralized helpers (Fedora/Linux)
# - Collects pm path (raw + sanitized)
# - Optionally pulls up to N APKs (base first), compares sizes, verifies hashes
# - Writes summary to root log/ and artifacts to results/<DEVICE>/
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]:-?}:$LINENO: $BASH_COMMAND" >&2' ERR

usage() {
  cat <<'EOF'
Usage: ./adb_apk_diag.sh [--pkg PKG|<pkg>] [--pull] [--limit N] [--device SERIAL] [--debug] [-h|--help]

Examples:
  ./adb_apk_diag.sh com.zhiliaoapp.musically
  ./adb_apk_diag.sh --pkg com.zhiliaoapp.musically --pull --limit 2
  DEV=ZY22JK89DR ./adb_apk_diag.sh --pkg com.twitter.android

Notes:
- Writes artifacts to results/<DEVICE>/manual_diag_<ts>/
  - Writes a summary to log/adb_apk_diag_<ts>_<pkg>.txt
EOF
}

# ---- Bootstrap ---------------------------------------------------------------
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load configs if present (idempotent)
if [[ -d "$ROOT/config" ]]; then
  for f in "$ROOT"/config/*.sh; do
    # shellcheck disable=SC1090
    [[ -r "$f" ]] && source "$f"
  done
fi
mkdir -p "$LOG_DIR"

# Shared libs (ordered: logging/errors → trace → device → pm/apk utils)
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

# ---- CLI ---------------------------------------------------------------------
PULL=0
LIMIT=1
PKG=""
OVERRIDE_DEV=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pkg)     PKG="${2:-}"; shift 2 ;;
    --pull)    PULL=1; shift ;;
    --limit)   LIMIT="${2:-}"; shift 2 ;;
    --device)  OVERRIDE_DEV="${2:-}"; shift 2 ;;
    --debug)   LOG_LEVEL=DEBUG; shift ;;
    -h|--help) usage; exit 0 ;;
    --)        shift; break ;;
    *)         if [[ -z "$PKG" ]]; then PKG="$1"; shift; else echo "Unknown arg: $1"; usage; exit 1; fi ;;
  esac
done
PKG="${PKG:-com.zhiliaoapp.musically}"

# Validate LIMIT numeric
if ! [[ "$LIMIT" =~ ^[0-9]+$ ]]; then
  die "${E_USAGE:-15}" "--limit must be an integer (got: $LIMIT)"
fi

# ---- Device resolution -------------------------------------------------------
SERIAL="$(device_pick_or_fail "${OVERRIDE_DEV:-${DEV:-}}")"
set_device "$SERIAL"
assert_device_ready "$DEVICE"

# ---- Working dirs ------------------------------------------------------------
TS="$(date +%Y%m%d_%H%M%S)"
PKG_ESC="${PKG//./_}"
BASE_DIR="$ROOT/results/$DEVICE"
RUN_DIR="$BASE_DIR/manual_diag_${TS}"
mkdir -p "$RUN_DIR"

# ---- Collect paths (raw + sanitize) -----------------------------------------
have_func() { [[ $(type -t "$1" 2>/dev/null) == function ]]; }

RAW_FILE="$RUN_DIR/pm_path_raw.txt"
SAN_FILE="$RUN_DIR/pm_path_san.txt"

if have_func au_pm_path_raw && have_func au_pm_path_sanitize; then
  au_pm_path_raw "$PKG" >"$RAW_FILE"
  au_pm_path_raw "$PKG" | au_pm_path_sanitize >"$SAN_FILE"
elif have_func pm_path_raw && have_func pm_path_sanitize; then
  pm_path_raw "$PKG" >"$RAW_FILE"
  pm_path_raw "$PKG" | pm_path_sanitize >"$SAN_FILE"
else
  # Very last-resort fallback (should not be needed if libs are wired)
  adb -s "$DEVICE" shell pm path "$PKG" >"$RAW_FILE" || true
  tr -d '\r' <"$RAW_FILE" | sed -n 's/^package://p' >"$SAN_FILE"
fi

PATHS_N="$(wc -l <"$SAN_FILE" 2>/dev/null || echo 0)"

# ---- Optional pull + verification -------------------------------------------
pulled=0
declare -a pulled_files=() remote_sizes=() local_sizes=()

if (( PULL )) && (( PATHS_N > 0 )); then
  mapfile -t ALL_PATHS <"$SAN_FILE"
  BASE_APK=""
  if have_func au_pick_base_apk; then
    BASE_APK="$(au_pick_base_apk "$SAN_FILE" || true)"
  else
    BASE_APK="$(grep '/base\.apk$' "$SAN_FILE" | head -1 || true)"
  fi

  declare -a ORDERED=()
  [[ -n "$BASE_APK" ]] && ORDERED+=("$BASE_APK")
  for p in "${ALL_PATHS[@]}"; do
    [[ "$p" == "$BASE_APK" ]] && continue
    ORDERED+=("$p")
  done

  PULL_DIR="$RUN_DIR/pulled"
  mkdir -p "$PULL_DIR"

  # Sandbox the pull loop: disable -e and ERR trap so best-effort checks don't abort
  __old_err_trap="$(trap -p ERR || true)"
  trap - ERR
  set +e

  for p in "${ORDERED[@]}"; do
    (( pulled >= LIMIT )) && break

    # remote size (best effort)
    REMOTE_SZ=""
    if have_func au_dev_file_size; then
      if ! REMOTE_SZ="$(au_dev_file_size "$p" 2>/dev/null)"; then REMOTE_SZ=""; fi
    fi

    # pull (prefer helper; fallback to raw adb pull)
    LOCAL=""
    if have_func au_pull_one; then
      if ! LOCAL="$(au_pull_one "$p" "$PULL_DIR")"; then LOCAL=""; fi
    else
      b="$(basename "$p")"
      adb -s "$DEVICE" pull "$p" "$PULL_DIR/$b" >/dev/null 2>&1
      [[ -s "$PULL_DIR/$b" ]] && LOCAL="$PULL_DIR/$b" || LOCAL=""
    fi

    LOCAL_SZ=""
    if [[ -n "$LOCAL" ]]; then
      LOCAL_SZ="$(stat -c%s "$LOCAL" 2>/dev/null || true)"
    fi

    # hash verification (best effort)
    if [[ -n "$LOCAL" && -s "$LOCAL" ]] && have_func au_verify_hash; then
      au_verify_hash "$p" "$LOCAL" >/dev/null 2>&1 || true
    fi

    # warn on size mismatch (if both sides known)
    if [[ -n "$REMOTE_SZ" && -n "$LOCAL_SZ" && "$REMOTE_SZ" != "$LOCAL_SZ" ]]; then
      LOG_APK="$(basename "$LOCAL")" log WARN "size mismatch: remote=$REMOTE_SZ local=$LOCAL_SZ"
    fi

    pulled_files+=("${LOCAL:-}")
    remote_sizes+=("${REMOTE_SZ:-}")
    local_sizes+=("${LOCAL_SZ:-}")
    ((pulled++))
  done

  # Restore strict mode + trap
  set -e
  [[ -n "$__old_err_trap" ]] && eval "$__old_err_trap" || true
fi

# ---- Optional metadata/scans -------------------------------------------------
OUT_META="$RUN_DIR/meta.csv"
OUT_FAM="$RUN_DIR/tiktok_family.txt"
OUT_REL="$RUN_DIR/tiktok_related.txt"

have_func au_pkg_meta_csv_line && au_pkg_meta_csv_line "$PKG" >"$OUT_META" || true
have_func au_scan_tiktok_family  && au_scan_tiktok_family  >"$OUT_FAM" || true
have_func au_scan_tiktok_related && au_scan_tiktok_related >"$OUT_REL" || true

# ---- Summary log -------------------------------------------------------------
SUMMARY="$(_log_path "adb_apk_diag_${PKG_ESC}")"
log_file_init "$SUMMARY"
{
  echo "package=$PKG"
  echo "device=$DEVICE"
  echo "run_dir=$RUN_DIR"
  echo "paths=$PATHS_N"
  if (( PATHS_N == 0 )); then
    echo "note=no_sanitized_paths_found"
  fi
  if (( PULL )); then
    echo "pulled=$pulled"
    for i in "${!pulled_files[@]}"; do
      f="${pulled_files[i]}"
      r="${remote_sizes[i]}"
      l="${local_sizes[i]}"
      [[ -z "$f" ]] && continue
      status="remote=${r:-?} local=${l:-?}"
      [[ -n "$r" && -n "$l" && "$r" != "$l" ]] && status+=" mismatch"
      echo "  $(basename "$f") $status"
    done
  fi
} >>"$SUMMARY"

# ---- Operator hints to STDOUT (plain) ----------------------------------------
echo "Artifacts in: $RUN_DIR"
echo "Summary: $SUMMARY"

if [[ -s "$RAW_FILE" ]]; then
  echo "---- RAW pm path (first 20) ----"
  sed -n '1,20p' "$RAW_FILE"
fi
if [[ -s "$SAN_FILE" ]]; then
  echo "---- Sanitized paths (first 20) ----"
  sed -n '1,20p' "$SAN_FILE"
  echo "---- Endings (first 20) ----"
  sed -n 'l' "$SAN_FILE" | sed -n '1,20p'
fi
