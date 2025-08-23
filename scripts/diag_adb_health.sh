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
for m in core/logging core/errors core/deps core/device; do
  # shellcheck disable=SC1090
  source "$REPO_ROOT/lib/$m.sh"
done

DEVICE=""
usage() {
  cat <<USAGE
Usage: $0 [--device ID] [--debug] [-h|--help]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="${2:-}"; shift 2;;
    --debug) LOG_LEVEL=DEBUG; shift;;
    -h|--help) usage; exit 0;;
    *) die "$E_USAGE" "Unknown option: $1";;
  esac
done

require_all adb awk sed

LOG_FILE="$LOG_DIR/adb_health_$(date +%Y%m%d_%H%M%S).txt"
log_file_init "$LOG_FILE"

DEVICE="$(device_pick_or_fail "$DEVICE")"
log INFO "device=$DEVICE"

run_step() {
  local title="$1"; shift
  log INFO "$title"
  set +e
  try "$@" 2>&1 | tee -a "$LOG_FILE"
  local rc=${PIPESTATUS[0]}
  set -e
  log INFO "exit=$rc"
  echo "--------------------------------------------------" | tee -a "$LOG_FILE"
}

run_step "adb version" bash -c 'adb version | head -n 3'
run_step "adb get-state" adbq "$DEVICE" get-state
run_step "adb shell echo OK" adbq "$DEVICE" shell echo OK
run_step "adb shell id; whoami; getprop" adbq "$DEVICE" shell 'id; whoami; getprop ro.build.version.release'

exit 0
