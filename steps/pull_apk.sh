#!/usr/bin/env bash
# steps/pull_apk.sh — robust single-APK transfer with smart fallbacks
# Usage:
#   steps/pull_apk.sh <package> <apk_path> [dest_file]
# Notes:
#   - Uses config/config.sh for defaults (ADB_BIN, DH_PULL_TIMEOUT, dirs).
#   - Logs with context (pkg, apk, dev), writes atomically, verifies size.
#   - Prefers adb pull for /sdcard, streams protected roots, then copy-to-sdcard.

set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR

PKG="${1:-}"
APK_PATH="${2:-}"
DST_OVERRIDE="${3:-}"

if [[ -z "$PKG" || -z "$APK_PATH" ]]; then
  echo "Usage: $0 <package> <apk_path> [dest_file]" >&2
  exit 64  # EX_USAGE
fi

# ---- repo roots & modules ----------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# config
# shellcheck source=/dev/null
source "$REPO_ROOT/config/config.sh"

# core libs
for m in core/logging core/errors core/trace core/device io/apk_utils io/report; do
  # shellcheck source=/dev/null
  source "$REPO_ROOT/lib/$m.sh"
done

# ---- device resolution -------------------------------------------------------
# DEVICE may be set by caller; otherwise pick the first attached "device"
if [[ -z "${DEVICE:-}" ]]; then
  DEVICE="$("$ADB_BIN" devices | awk '/\tdevice$/{print $1; exit}')"
fi
DEVICE="$(printf '%s' "${DEVICE:-}" | tr -d '\r' | xargs)"

if [[ -z "$DEVICE" ]]; then
  LOG_CODE="${E_DEVICE_NOT_FOUND:-11}" log ERROR "no device available"
  exit 1
fi

# Prefer helpers if available
if declare -F assert_device_ready >/dev/null; then
  assert_device_ready "$DEVICE"
fi

# Ensure ADB args are consistent
ADB_ARGS=( -s "$DEVICE" )

# ---- figure out destination path --------------------------------------------
OUTDIR=""
OUTFILE=""
ROLE="base"

if [[ -n "$DST_OVERRIDE" ]]; then
  OUTDIR="$(dirname -- "$DST_OVERRIDE")"
  OUTFILE="$DST_OVERRIDE"
else
  # compute_outfile_vars should print NUL-separated: outdir\0outfile\0role
  if declare -F compute_outfile_vars >/dev/null; then
    IFS=$'\0' read -r OUTDIR OUTFILE ROLE < <(compute_outfile_vars "$PKG" "$APK_PATH")
  else
    # Fallback layout: results/<DEV>/<pkg>/   file named by split/base
    OUTDIR="$RESULTS_DIR/$DEVICE/$PKG"
    mkdir -p "$OUTDIR"
    base="$(basename -- "$APK_PATH")"
    OUTFILE="$OUTDIR/$base"
  fi
fi

mkdir -p -- "$OUTDIR"

# Context for log lines
LOG_DEV="$DEVICE"
LOG_PKG="$PKG"
LOG_APK="$(basename -- "$OUTFILE")"

# ---- atomic write: temp file then move ---------------------------------------
tmp="$(mktemp -p "$OUTDIR" ".${PKG//./_}.XXXXXX.tmp.apk")"
cleanup() { rm -f -- "$tmp" 2>/dev/null || true; }
trap cleanup EXIT

# ---- transfer ----------------------------------------------------------------
start_ns="$(date +%s%N || true)"

log INFO "Pulling $ROLE APK from $APK_PATH -> $OUTFILE"

# Use the new smart helper; it must see ADB_BIN/ADB_ARGS/DH_PULL_TIMEOUT.
# pull_apk_smart chooses the best method and falls back as needed.
if ! pull_apk_smart "$APK_PATH" "$tmp"; then
  rc=$?
  LOG_CODE="${E_PULL_FAIL:-32}" LOG_RC="$rc" log ERROR "pull failed for $APK_PATH"
  exit 1
fi

# ---- validate & finalize -----------------------------------------------------
# Ensure non-empty file
if [[ ! -s "$tmp" ]]; then
  LOG_CODE="${E_APK_EMPTY:-33}" log ERROR "pulled file is empty: $tmp"
  exit 1
fi

# Move into place atomically
mv -f -- "$tmp" "$OUTFILE"
trap - EXIT  # success path stops tmp cleanup

# Metrics
end_ns="$(date +%s%N || true)"
bytes="$(stat -c %s "$OUTFILE" 2>/dev/null || echo 0)"
dur_ms=0
if [[ -n "${start_ns:-}" && -n "${end_ns:-}" && "$end_ns" =~ ^[0-9]+$ && "$start_ns" =~ ^[0-9]+$ ]]; then
  dur_ms="$(( (end_ns - start_ns) / 1000000 ))"
fi

# Optional hash summary (sha256 if available)
hash_str=""
if command -v sha256sum >/dev/null 2>&1; then
  hash_str="$(sha256sum "$OUTFILE" | awk '{print $1}')"
fi

# Human rate
rate=""
if [[ "$bytes" -gt 0 && "$dur_ms" -gt 0 ]]; then
  # bytes/sec → MiB/s (rounded)
  bps=$(( bytes * 1000 / dur_ms ))
  mibps=$(awk "BEGIN{printf \"%.1f\", $bps/1048576}")
  rate="$mibps MiB/s"
fi

extra="size=${bytes}B"
[[ -n "$rate" ]] && extra="$extra rate=$rate"
[[ -n "$hash_str" ]] && extra="$extra sha256=$hash_str"

log INFO "Pulled $ROLE APK to $OUTFILE ($extra)"

# Emit path for callers that capture stdout
printf '%s\n' "$OUTFILE"
