#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]:-?}:$LINENO" >&2' ERR

dev_prop_get() {
  local prop="$1" out rc
  out="$(adb_shell getprop "$prop" 2>/dev/null)"; rc=$?
  printf '%s\n' "$out" | tr -d '\r'
  return "$rc"
}

dev_release() {
  dev_prop_get ro.build.version.release
}

dev_abis() {
  local out
  out="$(dev_prop_get ro.product.cpu.abilist)"
  [[ -n "$out" ]] || out="$(dev_prop_get ro.product.cpu.abi)"
  printf '%s\n' "$out"
}

dev_build_fingerprint() {
  dev_prop_get ro.build.fingerprint
}
