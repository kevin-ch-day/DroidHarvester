#!/usr/bin/env bash
# ---------------------------------------------------
# test_get_apk_paths.sh - targeted diagnostic for get_apk_paths()
# Usage: ./scripts/test_get_apk_paths.sh [--debug] [--device SERIAL] [--package PKG]
# Plain ASCII. Fedora/Linux. No menu, no side effects.
# ---------------------------------------------------
set -euo pipefail
# No ERR trap; rely on explicit error messages

# ---- Exit codes ----
E_USAGE=64; E_DEPS=2; E_NO_DEVICE=10; E_MULTI_DEVICE=11; E_NOT_FOUND=12

# ---- Argument parsing ----
usage() {
  echo "Usage: $0 [--debug] [--device SERIAL] [--package PKG]" >&2
}

DEVICE_OVERRIDE=""
PACKAGES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)   LOG_LEVEL="DEBUG"; shift ;;
    --device)  DEVICE_OVERRIDE="$2"; shift 2 ;;
    --package) PACKAGES+=("$2"); shift 2 ;;
    -h|--help) usage; exit $E_USAGE ;;
    *)         usage; exit $E_USAGE ;;
  esac
done

SAMPLE_LIMIT=5

# Repo root (script lives in scripts/)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

LOG_DIR="$REPO_ROOT/logs"
mkdir -p "$LOG_DIR"
TS="$(date +%Y%m%d_%H%M%S)"

# --- Minimal local requires (avoid relying on non-existent helpers) ---
require() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: $1 not found." >&2; exit $E_DEPS; }; }
require adb; require awk; require sed; require grep; require nl; require tee; require wc; require tr; require sort; require comm

# --- Load project config/libs (for get_apk_paths & logging) ---
# shellcheck disable=SC1090
source "$REPO_ROOT/config.sh"
trap - ERR
# shellcheck disable=SC1090
source "$REPO_ROOT/lib/core/logging.sh"   || true
trap - ERR
# shellcheck disable=SC1090
source "$REPO_ROOT/lib/io/apk_utils.sh"   || true
trap - ERR

: "${LOG_LEVEL:=INFO}"
export LOG_LEVEL

# Default package list: first TARGET_PACKAGES entry if none supplied
if (( ${#PACKAGES[@]} == 0 )); then
  PACKAGES=("${TARGET_PACKAGES[0]}")
fi

# --- Helper: pick the device (auto-pick single or use override) ---
pick_device_or_fail() {
  local id="$DEVICE_OVERRIDE"
  if [[ -n "$id" ]]; then
    if adb devices | awk 'NR>1 && $2=="device"{print $1}' | grep -qx "$id"; then
      echo "$id"
      return 0
    else
      echo "ERROR: device $id not detected via 'adb devices'." >&2
      return $E_NOT_FOUND
    fi
  fi
  mapfile -t devs < <(adb devices | awk 'NR>1 && $2=="device"{print $1}')
  if (( ${#devs[@]} == 0 )); then
    echo "ERROR: no devices detected via 'adb devices'." >&2
    return $E_NO_DEVICE
  elif (( ${#devs[@]} > 1 )); then
    echo "ERROR: multiple devices detected. Specify --device." >&2
    printf 'Detected:\n' >&2
    printf '  %s\n' "${devs[@]}" >&2
    return $E_MULTI_DEVICE
  fi
  echo "${devs[0]}"
}
set +e
DEVICE="$(pick_device_or_fail)"
rc=$?
set -e
if (( rc != 0 )); then
  exit $rc
fi

# --- Banner ---
echo "Device   : $DEVICE"
echo "Packages : ${#PACKAGES[@]} (${PACKAGES[*]})"
echo "Limit    : $SAMPLE_LIMIT"
echo "Logs dir : $LOG_DIR"
echo "--------------------------------------------------"
adb version | sed -n '1,3p'
echo "--------------------------------------------------"
echo "Android release:"
adb -s "$DEVICE" shell getprop ro.build.version.release || true
echo "--------------------------------------------------"

overall_fail=0

# --- Per-package test loop ---
for PKG in "${PACKAGES[@]}"; do
  BASE="paths_diag_${TS}_$(echo "$PKG" | tr '.' '_' )"
  STDOUT_FILE="$LOG_DIR/${BASE}.out"
  STDERR_FILE="$LOG_DIR/${BASE}.err"
  SUMMARY_FILE="$LOG_DIR/${BASE}.summary.txt"
  GT_FILE="$LOG_DIR/${BASE}.groundtruth.txt"

  echo
  echo "==== TEST: $PKG ===="
  echo "stdout : $STDOUT_FILE"
  echo "stderr : $STDERR_FILE"
  echo "summary: $SUMMARY_FILE"
  echo "--------------------------------------------------"
  echo "RAW pm path (first 20 lines):"
  adb -s "$DEVICE" shell pm path "$PKG" | sed -n '1,20p' || true
  echo "--------------------------------------------------"

  # Ground truth: strip 'package:' and CR, drop blanks
  adb -s "$DEVICE" shell pm path "$PKG" \
    | tr -d '\r' \
    | sed 's/^package://g' \
    | sed '/^$/d' >"$GT_FILE" || true

  # Run function and capture streams (don’t die on non-zero immediately)
  set +e
  get_apk_paths "$PKG" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  rc_get=$?
  set -e

  {
    echo "==== STDOUT (should be ONLY /absolute/apk/paths) ===="
    nl -ba "$STDOUT_FILE" | sed -n '1,60p'
    echo "==== STDERR (should be ONLY logs) ===="
    sed -n '1,120p' "$STDERR_FILE"
    echo "==== NON-PATH lines leaked into STDOUT (should be empty) ===="
    if grep -vE '^/.*\.apk$' "$STDOUT_FILE" >/dev/null 2>&1; then
      grep -vE '^/.*\.apk$' "$STDOUT_FILE" | sed -n '1,80p'
      echo "RESULT: FAIL (stdout contains non-path lines)"
    else
      echo "(none)"
    fi
    echo "==== STDOUT with visible line endings (helps spot CRs) ===="
    sed -n 'l' "$STDOUT_FILE" | sed -n '1,60p'
  } | tee "$SUMMARY_FILE"

  n_stdout="$(grep -c '.*' "$STDOUT_FILE" || true)"
  n_gt="$(grep -c '.*' "$GT_FILE" || true)"
  n_badlines="$(grep -vE '^/.*\.apk$' "$STDOUT_FILE" | wc -l || true)"

  echo "==== COUNTS ===="           | tee -a "$SUMMARY_FILE"
  echo "stdout_lines = $n_stdout"   | tee -a "$SUMMARY_FILE"
  echo "groundtruth  = $n_gt"       | tee -a "$SUMMARY_FILE"
  echo "bad_lines    = $n_badlines" | tee -a "$SUMMARY_FILE"

  echo "==== GROUND TRUTH not in get_apk_paths (should be empty) ====" | tee -a "$SUMMARY_FILE"
  comm -23 <(sort -u "$GT_FILE") <(sort -u "$STDOUT_FILE") | sed -n '1,60p' | tee -a "$SUMMARY_FILE" || true

  echo "==== get_apk_paths extra (not in ground truth) (may be empty) ====" | tee -a "$SUMMARY_FILE"
  comm -13 <(sort -u "$GT_FILE") <(sort -u "$STDOUT_FILE") | sed -n '1,60p' | tee -a "$SUMMARY_FILE" || true

  echo "==== VERIFY PATHS EXIST ON DEVICE (sample up to $SAMPLE_LIMIT) ====" | tee -a "$SUMMARY_FILE"
  checked=0; ok=0; fail=0
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    (( checked++ ))
    if adb -s "$DEVICE" shell ls -l "$p" >/dev/null 2>&1; then
      (( ok++ )); printf "ok   : %s\n" "$p" | tee -a "$SUMMARY_FILE"
    else
      (( fail++ )); printf "fail : %s\n" "$p" | tee -a "$SUMMARY_FILE"
    fi
    (( checked >= SAMPLE_LIMIT )) && break || true
  done < "$STDOUT_FILE"

  echo "--------------------------------------------------" | tee -a "$SUMMARY_FILE"
  echo "Totals: stdout=$n_stdout gt=$n_gt checked=$checked ok=$ok fail=$fail rc_get_apk_paths=$rc_get" | tee -a "$SUMMARY_FILE"

  # Result policy per package
  if (( rc_get != 0 )) || (( n_stdout == 0 )) || (( n_badlines > 0 )); then
    echo "RESULT: FAIL for $PKG (see $SUMMARY_FILE)" | tee -a "$SUMMARY_FILE"
    overall_fail=1
  else
    echo "RESULT: PASS for $PKG" | tee -a "$SUMMARY_FILE"
  fi
done

echo
if (( overall_fail == 0 )); then
  echo "ALL TESTS PASSED ✔"
  exit 0
else
  echo "ONE OR MORE TESTS FAILED ✖ (see summaries under logs/)"
  exit 1
fi
