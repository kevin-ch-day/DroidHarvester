#!/usr/bin/env bash
# ---------------------------------------------------
# diag_adb_health.sh - minimal ADB connectivity check
# Fedora/Linux only. Plain ASCII output.
# ---------------------------------------------------
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND" >&2' ERR

usage() {
  cat <<EOF
Usage: $0 [--device <ID>] [--pkg <PACKAGE>]

Runs a minimal connectivity test against an Android device:
  0) adb version
  1) adb get-state
  2) adb shell echo OK
  3) adb shell 'id; whoami; getprop ro.build.version.release'

If --pkg is supplied, also runs a focused package path check:
  - adb shell pm path <PACKAGE>
  - Verifies each returned path exists on-device (ls -l)
  - Shows a sanitized (package:// stripped) view and flags non-path lines

If --device is not provided, the script will use the only connected device.
If multiple devices are connected, you must pass --device.

Examples:
  $0
  $0 --device ZY22JK89DR
  $0 --device ZY22JK89DR --pkg com.zhiliaoapp.musically
EOF
}

DEVICE=""
PKG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="${2:-}"; shift 2 ;;
    --pkg)    PKG="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

if ! command -v adb >/dev/null 2>&1; then
  echo "ERROR: adb not found. On Fedora: sudo dnf -y install android-tools"
  exit 2
fi

LOG_DIR="./logs"
mkdir -p "$LOG_DIR"
TS="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${LOG_DIR}/adb_health_${TS}.txt"

pick_device() {
  if [[ -n "$DEVICE" ]]; then
    echo "$DEVICE"
    return
  fi
  mapfile -t devs < <(adb devices | awk 'NR>1 && $2=="device" {print $1}')
  if (( ${#devs[@]} == 0 )); then
    echo "ERROR: no devices detected via 'adb devices'." | tee -a "$LOG_FILE"
    exit 3
  elif (( ${#devs[@]} > 1 )); then
    echo "ERROR: multiple devices detected. Use --device <ID>." | tee -a "$LOG_FILE"
    printf 'Detected:\n' | tee -a "$LOG_FILE"
    printf '  %s\n' "${devs[@]}" | tee -a "$LOG_FILE"
    exit 4
  fi
  echo "${devs[0]}"
}

run_step() {
  local title="$1"; shift
  echo "STEP: $title"           | tee -a "$LOG_FILE"
  set +e
  "$@"                        | tee -a "$LOG_FILE"
  rc=$?
  set -e
  echo "exit=$rc"              | tee -a "$LOG_FILE"
  echo "--------------------------------------------------" | tee -a "$LOG_FILE"
  return $rc
}

DEVICE="$(pick_device)"
echo "Device    : $DEVICE"           | tee    "$LOG_FILE"
echo "Timestamp : $TS"               | tee -a "$LOG_FILE"
echo "ADB path  : $(command -v adb)" | tee -a "$LOG_FILE"
echo "--------------------------------------------------" | tee -a "$LOG_FILE"

# 0) adb version (useful to spot mismatches)
run_step "adb version" adb version || true

# 1) adb get-state
run_step "adb get-state" adb -s "$DEVICE" get-state || true

# 2) adb shell echo OK
run_step "adb shell echo OK" adb -s "$DEVICE" shell echo OK || true

# 3) id; whoami; Android release
run_step "adb shell id; whoami; getprop ro.build.version.release" \
  adb -s "$DEVICE" shell 'id; whoami; getprop ro.build.version.release' || true

# Optional: package path diagnostics
if [[ -n "$PKG" ]]; then
  echo "PACKAGE DIAG: $PKG" | tee -a "$LOG_FILE"
  OUT="$(mktemp)"; ERR="$(mktemp)"
  CLEAN="$(mktemp)"
  trap 'rm -f "$OUT" "$ERR" "$CLEAN"' EXIT

  echo "STEP: adb shell pm path $PKG" | tee -a "$LOG_FILE"
  set +e
  adb -s "$DEVICE" shell pm path "$PKG" >"$OUT" 2>"$ERR"
  rc=$?
  set -e
  echo "exit=$rc" | tee -a "$LOG_FILE"
  echo "---- RAW STDOUT ----" | tee -a "$LOG_FILE"
  sed -n '1,200p' "$OUT" | tee -a "$LOG_FILE"
  echo "---- RAW STDERR ----" | tee -a "$LOG_FILE"
  sed -n '1,200p' "$ERR" | tee -a "$LOG_FILE"

  # Sanitize: strip 'package:' prefix and CR, keep only non-empty lines
  tr -d '\r' <"$OUT" | sed 's/^package://g;/^$/d' > "$CLEAN"

  echo "---- SANITIZED PATHS (expected absolute /data/... lines) ----" | tee -a "$LOG_FILE"
  sed -n '1,200p' "$CLEAN" | tee -a "$LOG_FILE"

  echo "---- NON-PATH LINES IN STDOUT (should be empty) ----" | tee -a "$LOG_FILE"
  # Any line not starting with '/' is suspicious
  grep -vE '^/' "$CLEAN" || true | tee -a "$LOG_FILE"

  echo "---- VERIFY EACH PATH EXISTS ON-DEVICE ----" | tee -a "$LOG_FILE"
  ok=0; bad=0
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    if adb -s "$DEVICE" shell ls -l "$p" >/dev/null 2>&1; then
      echo "OK   $p" | tee -a "$LOG_FILE"
      ((ok++))
    else
      echo "FAIL $p" | tee -a "$LOG_FILE"
      ((bad++))
    fi
  done < "$CLEAN"
  echo "Summary: ok=$ok bad=$bad" | tee -a "$LOG_FILE"
  echo "--------------------------------------------------" | tee -a "$LOG_FILE"
fi

echo "Log saved to: $LOG_FILE"
