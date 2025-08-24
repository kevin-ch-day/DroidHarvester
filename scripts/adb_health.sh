#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
  if tmp_dev=$(get_normalized_serial); then
    DEVICE="$tmp_dev"
  else
    rc=$?
    case "$rc" in
      1) echo "[ERR] no devices detected." >&2 ;;
      2) echo "[ERR] multiple devices detected; specify device." >&2 ;;
      3) echo "[ERR] device unauthorized. run 'adb kill-server; adb devices; accept RSA prompt; re-run.'" >&2 ;;
    esac
    exit 1
  fi
else
  DEVICE="$(printf '%s' "$DEVICE" | tr -d '\r' | xargs)"
fi
assert_device_ready "$DEVICE"
update_adb_flags
adb_healthcheck
