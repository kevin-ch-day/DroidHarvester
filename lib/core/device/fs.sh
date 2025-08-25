#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]:-?}:$LINENO" >&2' ERR

dev_exists() {
  adb_shell test -e "$1"
}

dev_stat_size() {
  local out
  out="$(adb_shell stat -c %s "$1" 2>/dev/null || true)"
  printf '%s\n' "$out" | tr -d '\r'
}

dev_ls() {
  adb_shell ls -l "$1"
}

dev_free_space() {
  adb_shell df -h /data
}
