#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Shared helpers
# shellcheck disable=SC1090
source "$ROOT/lib/core/logging.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/errors.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/trace.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/device.sh"

DEVICE="${1:-}"
if [[ -z "$DEVICE" ]]; then
  if tmp_dev="$(get_normalized_serial)"; then
    set_device "$tmp_dev"
  else
    rc=$?
    case "$rc" in
      1) echo "[ERR] no devices detected." >&2 ;;
      2) echo "[ERR] multiple devices detected; specify device." >&2 ;;
      3) echo "[ERR] device unauthorized. run 'adb kill-server; adb devices; accept RSA prompt; re-run.'" >&2 ;;
      *) echo "[ERR] device detection failed (rc=$rc)." >&2 ;;
    esac
    exit 1
  fi
else
  set_device "$DEVICE" || true
fi

assert_device_ready "$DEVICE"

LOG_COMP="health"

log INFO "adb get-state"
adb_get_state >/dev/null 2>&1

log INFO "adb shell echo OK"
adb_shell echo OK >/dev/null

log INFO "device df"
adb_shell df >/dev/null

log INFO "host df"
df -h "${HOME:-/}" || df -h
