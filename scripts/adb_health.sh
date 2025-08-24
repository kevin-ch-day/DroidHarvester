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
    DEVICE="$tmp_dev"
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
  DEVICE="$(printf '%s' "$DEVICE" | tr -d '\r' | xargs)"
fi

assert_device_ready "$DEVICE"

# Prefer centralized ADB flags if available
if type update_adb_flags >/dev/null 2>&1; then
  update_adb_flags
else
  export ADB_FLAGS="-s $DEVICE"
fi

LOG_COMP="health"

log INFO "adb get-state"
adb ${ADB_FLAGS:-} get-state

log INFO "adb -s $DEVICE shell echo OK"
adb ${ADB_FLAGS:-} shell echo OK

log INFO "device df"
adb ${ADB_FLAGS:-} shell df

log INFO "host df"
df -h "${HOME:-/}" || df -h

# Optional: show normalized serial bytes when debugging
if [[ "${DEBUG:-0}" == "1" ]]; then
  printf '[DEBUG] DEVICE="%s"\n' "$DEVICE"
  printf '[DEBUG] DEVICE bytes: '
  printf '%s' "$DEVICE" | hexdump -C | sed -n '1p'
fi
