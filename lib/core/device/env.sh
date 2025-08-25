#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]:-?}:$LINENO" >&2' ERR

update_adb_flags() {
  ADB_ARGS=(-s "$DEVICE")
  export ADB_ARGS
}

normalize_serial() {
  printf '%s' "$1" | tr -d '\r' | xargs
}

set_device() {
  local serial
  serial="$(normalize_serial "$1")"
  [[ -n "$serial" ]] || return 1
  DEVICE="$serial"
  update_adb_flags
  export DEVICE
  if [[ "${DEBUG:-0}" == "1" ]]; then
    printf '[DEBUG] DEV="%s"\n' "$DEVICE" >&2
    printf '[DEBUG] DEV bytes: ' >&2
    printf '%s' "$DEVICE" | hexdump -C | sed -n '1p' >&2
  fi
}
