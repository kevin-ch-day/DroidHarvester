#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]:-?}:$LINENO" >&2' ERR

device_list_connected() {
  adb devices | awk 'NR>1 && $2=="device" {print $1}' | tr -d '\r'
}

device_pick_or_fail() {
  local specified="${1:-}" adb_out unauthorized
  specified="$(normalize_serial "$specified")"
  adb_out="$(adb devices 2>/dev/null)"
  unauthorized=$(printf '%s\n' "$adb_out" | awk '/unauthorized/ {print $1}')
  if [[ -n "$unauthorized" ]]; then
    die "$E_UNAUTHORIZED" "device '$unauthorized' unauthorized"
  fi
  mapfile -t devs < <(printf '%s\n' "$adb_out" | awk 'NR>1 && $2=="device" {print $1}' | tr -d '\r')
  if [[ -n "$specified" ]]; then
    if printf '%s\n' "${devs[@]}" | grep -Fxq "$specified"; then
      echo "$specified"
      return 0
    fi
    die "$E_NO_DEVICE" "Device '$specified' not found"
  fi
  if (( ${#devs[@]} == 0 )); then
    die "$E_NO_DEVICE" "No devices detected"
  elif (( ${#devs[@]} > 1 )); then
    die "$E_MULTI_DEVICE" "multiple devices detected; use --device"
  fi
  echo "${devs[0]}"
}

get_normalized_serial() {
  local line serial state
  local -a devs
  while read -r line; do
    serial="${line%%[[:space:]]*}"
    state="${line##*$serial}"
    state="${state##*[[:space:]]}"
    case "$state" in
      device)
        devs+=("$(normalize_serial "$serial")")
        ;;
      unauthorized)
        printf '[ERR] device %q unauthorized\n' "$serial" >&2
        return 3
        ;;
    esac
  done < <(adb devices | tail -n +2)
  if (( ${#devs[@]} == 0 )); then
    return 1
  elif (( ${#devs[@]} > 1 )); then
    return 2
  fi
  printf '%s\n' "${devs[0]}"
}

assert_device_ready() {
  local s="$1"
  adb -s "$s" get-state >/dev/null 2>&1 || {
    echo "[ERR] device '$s' not ready (need state=device)." >&2
    return 1
  }
}
