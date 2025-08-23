#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND" >&2' ERR

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
SCRIPT_DIR="$REPO_ROOT"

LOG_DIR="$REPO_ROOT/logs"
mkdir -p "$LOG_DIR"

# shellcheck disable=SC1090
source "$REPO_ROOT/config.sh"
for m in core/logging core/errors core/deps core/device io/apk_utils; do
  # shellcheck disable=SC1090
  source "$REPO_ROOT/lib/$m.sh"
done

DEVICE=""
PKG=""
LIMIT=5
usage() {
  cat <<USAGE
Usage: $0 --pkg PACKAGE [--limit N] [--device ID] [--debug]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="${2:-}"; shift 2;;
    --pkg) PKG="${2:-}"; shift 2;;
    --limit) LIMIT="${2:-}"; shift 2;;
    --debug) LOG_LEVEL=DEBUG; shift;;
    -h|--help) usage; exit 0;;
    *) die "$E_USAGE" "Unknown option: $1";;
  esac
done

[[ -z "$PKG" ]] && die "$E_USAGE" "--pkg required"

require_all adb awk sed grep nl tee

DEVICE="$(device_pick_or_fail "$DEVICE")"

TS=$(date +%Y%m%d_%H%M%S)
BASE="paths_diag_${TS}"
STDOUT_FILE="$LOG_DIR/${BASE}.out"
STDERR_FILE="$LOG_DIR/${BASE}.err"
SUMMARY_FILE="$LOG_DIR/${BASE}.summary.txt"
log_file_init "$SUMMARY_FILE"
log INFO "stdout=$STDOUT_FILE"
log INFO "stderr=$STDERR_FILE"

# run get_apk_paths and capture streams
tmp_LOGFILE="$LOGFILE"
LOGFILE=""
set +e
get_apk_paths "$PKG" >"$STDOUT_FILE" 2>"$STDERR_FILE"
rc=$?
set -e
LOGFILE="$tmp_LOGFILE"

(( rc != 0 )) && die "$E_ADB" "get_apk_paths failed rc=$rc"
[[ ! -s "$STDOUT_FILE" ]] && die "$E_ADB" "get_apk_paths returned no paths"

log INFO "Device: $DEVICE"
log INFO "Package: $PKG"

log INFO "==== STDOUT (apk paths) ===="
nl -ba "$STDOUT_FILE" | sed -n '1,40p' | tee -a "$SUMMARY_FILE"

log INFO "==== STDERR (logs) ===="
sed -n '1,80p' "$STDERR_FILE" | tee -a "$SUMMARY_FILE"

log INFO "==== NON-PATH contamination ===="
if grep -vE '^/' "$STDOUT_FILE" >/dev/null; then
  grep -vE '^/' "$STDOUT_FILE" | tee -a "$SUMMARY_FILE"
else
  log INFO "(none)"
fi

log INFO "==== Line endings check ===="
sed -n 'l' "$STDOUT_FILE" | sed -n '1,40p' | tee -a "$SUMMARY_FILE"

log INFO "==== VERIFY PATHS EXIST (sample up to $LIMIT) ===="
count=0
ok=0
fail=0
while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  ((count++))
  try adbq "$DEVICE" shell ls -l "$p" >/dev/null
  rc=$?
  if (( rc == 0 )); then
    log INFO "ok   $p"
    ((ok++))
  else
    log WARN "fail $p"
    ((fail++))
  fi
  (( count >= LIMIT )) && break

done < "$STDOUT_FILE"

log INFO "summary: ok=$ok fail=$fail sampled=$count"

exit 0
