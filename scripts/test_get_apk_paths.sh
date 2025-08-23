#!/usr/bin/env bash
# ---------------------------------------------------
# test_get_apk_paths.sh - isolate & verify get_apk_paths()
# Plain ASCII. Fedora/Linux. No menu, no side effects.
# ---------------------------------------------------
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND" >&2' ERR

usage() {
  cat <<'EOF'
Usage: ./test_get_apk_paths.sh [--device ID] [--pkg PACKAGE] [--limit N]

Runs get_apk_paths() outside the menu and verifies:
  - STDOUT contains only absolute APK paths (one per line)
  - STDERR contains only logs
  - Each reported path exists on the device (sampled)

Options:
  --device ID   ADB device id (defaults to the only connected device)
  --pkg NAME    Package to test (defaults to first entry in TARGET_PACKAGES)
  --limit N     Max paths to probe on-device (default: 5)
  -h, --help    Show this help

Examples:
  ./test_get_apk_paths.sh --pkg com.zhiliaoapp.musically
  ./test_get_apk_paths.sh --device ZY22JK89DR --pkg com.twitter.android
EOF
}

# -------------------------
# Args
# -------------------------
DEVICE=""
PKG=""
LIMIT=5

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="${2:-}"; shift 2 ;;
    --pkg)    PKG="${2:-}";    shift 2 ;;
    --limit)  LIMIT="${2:-}";  shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# -------------------------
# Resolve repo root (script is at repo root)
# -------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

# -------------------------
# Logging files
# -------------------------
LOG_DIR="$REPO_ROOT/logs"
mkdir -p "$LOG_DIR"
TS="$(date +%Y%m%d_%H%M%S)"
BASE="paths_diag_${TS}"

STDOUT_FILE="$LOG_DIR/${BASE}.out"
STDERR_FILE="$LOG_DIR/${BASE}.err"
SUMMARY_FILE="$LOG_DIR/${BASE}.summary.txt"

# -------------------------
# Sanity: dependencies
# -------------------------
require() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: $1 not found."; exit 2; }; }
require adb
require awk
require sed
require grep
require nl
require tee

# -------------------------
# Pick device
# -------------------------
pick_device() {
  if [[ -n "$DEVICE" ]]; then
    echo "$DEVICE"
    return
  fi
  mapfile -t devs < <(adb devices | awk 'NR>1 && $2=="device"{print $1}')
  if (( ${#devs[@]} == 0 )); then
    echo "ERROR: no devices detected via 'adb devices'." >&2
    exit 3
  elif (( ${#devs[@]} > 1 )); then
    echo "ERROR: multiple devices detected. Use --device <ID>." >&2
    printf 'Detected:\n' >&2
    printf '  %s\n' "${devs[@]}" >&2
    exit 4
  fi
  echo "${devs[0]}"
}

DEVICE="$(pick_device)"

# -------------------------
# Load app environment (no menu)
# -------------------------
# shellcheck disable=SC1090
source "$REPO_ROOT/config.sh"
# shellcheck disable=SC1090
source "$REPO_ROOT/lib/core/logging.sh"
# shellcheck disable=SC1090
source "$REPO_ROOT/lib/core/device.sh"
# shellcheck disable=SC1090
source "$REPO_ROOT/lib/io/apk_utils.sh"
# shellcheck disable=SC1090
source "$REPO_ROOT/lib/analysis/metadata.sh"
# shellcheck disable=SC1090
source "$REPO_ROOT/lib/io/report.sh"

# Force verbose logs for this test
export LOG_LEVEL="${LOG_LEVEL:-DEBUG}"
export DEVICE

# -------------------------
# Choose package
# -------------------------
if [[ -z "$PKG" ]]; then
  if (( ${#TARGET_PACKAGES[@]} == 0 )); then
    echo "ERROR: TARGET_PACKAGES is empty in config.sh and --pkg not provided." >&2
    exit 5
  fi
  PKG="${TARGET_PACKAGES[0]}"
fi

# -------------------------
# ADB banner for quick context
# -------------------------
echo "Device   : $DEVICE"
echo "Package  : $PKG"
echo "Limit    : $LIMIT"
echo "Stdout   : $STDOUT_FILE"
echo "Stderr   : $STDERR_FILE"
echo "Summary  : $SUMMARY_FILE"
echo "--------------------------------------------------"
adb version | sed -n '1,3p'
echo "--------------------------------------------------"
echo "adb -s \"$DEVICE\" shell getprop ro.build.version.release:"
adb -s "$DEVICE" shell getprop ro.build.version.release || true
echo "--------------------------------------------------"

# -------------------------
# Raw pm path (ground truth)
# -------------------------
echo "RAW: adb -s \"$DEVICE\" shell pm path \"$PKG\" (first 20 lines):"
adb -s "$DEVICE" shell pm path "$PKG" | sed -n '1,20p'
echo "--------------------------------------------------"

# -------------------------
# Run get_apk_paths and capture streams
# -------------------------
set +e
get_apk_paths "$PKG" >"$STDOUT_FILE" 2>"$STDERR_FILE"
rc=$?
set -e

# -------------------------
# Summarize
# -------------------------
echo "==== STDOUT (should be ONLY /absolute/apk/paths) ====" | tee "$SUMMARY_FILE"
nl -ba "$STDOUT_FILE" | sed -n '1,40p' | tee -a "$SUMMARY_FILE"

echo "==== STDERR (should be ONLY logs) ====" | tee -a "$SUMMARY_FILE"
sed -n '1,80p' "$STDERR_FILE" | tee -a "$SUMMARY_FILE"

echo "==== NON-PATH lines leaked into STDOUT (should be empty) ====" | tee -a "$SUMMARY_FILE"
NONPATH="$(grep -vE '^/' "$STDOUT_FILE" || true)"
if [[ -n "$NONPATH" ]]; then
  echo "$NONPATH" | sed -n '1,80p' | tee -a "$SUMMARY_FILE"
  echo "RESULT: FAIL (stdout contains non-path lines)" | tee -a "$SUMMARY_FILE"
else
  echo "(none)" | tee -a "$SUMMARY_FILE"
fi

echo "==== STDOUT with visible line endings (helps spot CRs) ====" | tee -a "$SUMMARY_FILE"
sed -n 'l' "$STDOUT_FILE" | sed -n '1,40p' | tee -a "$SUMMARY_FILE"

# -------------------------
# Probe existence of first N paths
# -------------------------
echo "==== VERIFY PATHS EXIST ON DEVICE (sample up to LIMIT) ====" | tee -a "$SUMMARY_FILE"
total=$(grep -c '.' "$STDOUT_FILE" || true)
ok=0; fail=0; checked=0

# Use while-read to preserve whitespace; paths are absolute so safe.
while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  (( checked++ ))
  if adb -s "$DEVICE" shell ls -l "$p" >/dev/null 2>&1; then
    (( ok++ ))
    printf "ok   : %s\n" "$p" | tee -a "$SUMMARY_FILE"
  else
    (( fail++ ))
    printf "fail : %s\n" "$p" | tee -a "$SUMMARY_FILE"
  fi
  (( checked >= LIMIT )) && break || true
done < "$STDOUT_FILE"

echo "--------------------------------------------------" | tee -a "$SUMMARY_FILE"
echo "Totals: total_lines=$total checked=$checked ok=$ok fail=$fail rc_get_apk_paths=$rc" | tee -a "$SUMMARY_FILE"
echo "Done. See full logs in:" | tee -a "$SUMMARY_FILE"
echo "  $STDOUT_FILE" | tee -a "$SUMMARY_FILE"
echo "  $STDERR_FILE" | tee -a "$SUMMARY_FILE"
echo "  $SUMMARY_FILE" | tee -a "$SUMMARY_FILE"
