#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]:-?}:$LINENO" >&2' ERR

pm_path_raw() {
  local pkg="$1" out rc
  out="$(adb_shell pm path "$pkg" 2>/dev/null)"; rc=$?
  printf '%s\n' "$out" | tr -d '\r'
  return "$rc"
}

pm_path_sanitize() {
  tr -d '\r' | sed -n 's/^package://p' | sed '/^$/d'
}

pm_is_installed() {
  pm_path_raw "$1" >/dev/null
}

pm_list_pkgs() {
  local pattern="${1:-}"
  local out
  out="$(adb_shell pm list packages 2>/dev/null)" || return $?
  out="$(printf '%s\n' "$out" | tr -d '\r' | sed -n 's/^package://p')"
  if [[ -n "$pattern" ]]; then
    printf '%s\n' "$out" | grep -- "$pattern"
  else
    printf '%s\n' "$out"
  fi
}
