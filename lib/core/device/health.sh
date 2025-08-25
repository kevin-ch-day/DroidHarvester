#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]:-?}:$LINENO" >&2' ERR

adb_healthcheck() {
  log INFO "adb version"
  adb version >/dev/null 2>&1 || true
  log INFO "adb get-state"
  adbq "$DEVICE" get-state >/dev/null 2>&1 || true
  log INFO "adb shell echo OK"
  adb_shell echo OK >/dev/null 2>&1 || true
  log INFO "device df"
  adb_shell df -h /data >/dev/null 2>&1 || true
  log INFO "host df"
  df -h . || true
}
