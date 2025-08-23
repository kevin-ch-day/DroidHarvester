#!/usr/bin/env bash
# ---------------------------------------------------
# test_get_apk_paths.sh - zero-arg, hardcoded test
# Plain ASCII. Fedora/Linux. No menu, no side effects.
# ---------------------------------------------------
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND" >&2' ERR

# ======= HARD-CODED SETTINGS (edit as needed) =================
HARD_DEVICE_ID="ZY22JK89DR"
HARD_PACKAGES=(
  "com.zhiliaoapp.musically"
  # "com.twitter.android"
  # "com.instagram.android"
)
SAMPLE_LIMIT=5
# =============================================================

# Repo root (script lives in scripts/)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

LOG_DIR="$REPO_ROOT/logs"
mkdir -p "$LOG_DIR"
TS="$(date +%Y%m%d_%H%M%S)"

# --- Minimal local requires (avoid relying on non-existent helpers) ---
require() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: $1 not found."; exit 2; }; }
require adb; require awk; require sed; require grep; require nl; require tee; require wc; require tr; require sort; require comm

# --- Load project config/libs (for get_apk_paths & logging) ---
# shellcheck disable=SC1090
source "$REPO_ROOT/config.sh"
# shellcheck disable=SC1090
source "$REPO_ROOT/lib/core/logging.sh"   || true
# shellcheck disable=SC1090
source "$REPO_ROOT/lib/io/apk_utils.sh"   || true

: "${LOG_LEVEL:=INFO}"
export LOG_LEVEL

# --- Helper: pick the device (use hardcoded, else auto-pick single) ---
pick_device_or_fail() {
  local id="$HARD_DEVICE_ID"
  if [[ -n "$id" ]]; then
    echo "$id"
    return 0
  fi
  # Fallback: single attached device
  mapfile -t devs < <(adb devices | awk 'NR>1 && $2=="device"{print $1}')
  if (( ${#devs[@]} == 0 )); then
    echo "ERROR: no devices detected via 'adb devices'." >&2
    exit 10
  elif (( ${#devs[@]} > 1 )); then
    echo "ERROR: multiple devices detected. Set HARD_DEVICE_ID in this script." >&2
    printf 'Detected:\n' >&2
    printf '  %s\n' "${devs[@]}" >&2
    exit 11
  fi
  echo "${devs[0]}"
}

DEVICE="$(pick_device_or_fail)"

# --- Banner ---
echo "Device   : $DEVICE"
echo "Packages : ${#HARD_PACKAGES[@]} (edit HARD_PACKAGES[] in this script)"
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
for PKG in "${HARD_PACKAGES[@]}"; do
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
