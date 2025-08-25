#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]:-?}:$LINENO" >&2' ERR

ensure_wrapper_defaults() {
  : "${DH_RETRIES:=3}"
  : "${DH_BACKOFF:=1}"
  : "${DH_PULL_TIMEOUT:=60}"
  : "${DH_SHELL_TIMEOUT:=15}"
  [[ "$DH_RETRIES" =~ ^[0-9]+$ ]] || die "$E_USAGE" "DH_RETRIES must be integer"
  [[ "$DH_BACKOFF" =~ ^[0-9]+$ ]] || die "$E_USAGE" "DH_BACKOFF must be integer"
  [[ "$DH_PULL_TIMEOUT" =~ ^[0-9]+$ ]] || die "$E_USAGE" "DH_PULL_TIMEOUT must be integer"
  [[ "$DH_SHELL_TIMEOUT" =~ ^[0-9]+$ ]] || die "$E_USAGE" "DH_SHELL_TIMEOUT must be integer"
}
ensure_wrapper_defaults

adb_retry() {
  local timeout="${1:-$DH_SHELL_TIMEOUT}"; shift
  local max="${1:-$DH_RETRIES}"; shift
  local backoff="${1:-$DH_BACKOFF}"; shift
  local label=""; local -a cmd
  if ! parse_wrapper_args label cmd "$@"; then
    return 127
  fi
  local attempt=0 rc=0 start end dur
  start=$(date +%s%3N)
  while (( attempt < max )); do
    with_trace "$label" -- timeout --preserve-status -- "$timeout" adb "${ADB_ARGS[@]}" "${cmd[@]}" && { rc=0; break; }
    rc=$?
    attempt=$((attempt+1))
    (( attempt < max )) && sleep "$backoff"
  done
  end=$(date +%s%3N)
  dur=$((end-start))
  LOG_COMP="$label" LOG_RC="$rc" LOG_DUR_MS="$dur" LOG_ATTEMPTS="$attempt" log DEBUG "adb_retry"
  return "$rc"
}

adb_shell() {
  adb_retry "$DH_SHELL_TIMEOUT" "$DH_RETRIES" "$DH_BACKOFF" adb_shell -- shell "$@"
}

adb_pull() {
  adb_retry "$DH_PULL_TIMEOUT" "$DH_RETRIES" "$DH_BACKOFF" adb_pull -- pull "$@"
}

adbq() {
  local dev="$1"; shift
  adb -s "$dev" "$@" || {
    local rc=$?
    LOG_RC="$rc" log WARN "adb $* failed"
    return "$rc"
  }
}

with_device() {
  local serial="$1"; shift
  [[ "$1" == "--" ]] || return 127
  shift
  local old_dev="${DEVICE:-}"; local -a old_args=("${ADB_ARGS[@]-}")
  set_device "$serial" || return 1
  "$@"
  local rc=$?
  if [[ -n "${old_dev:-}" ]]; then
    DEVICE="$old_dev"
    ADB_ARGS=("${old_args[@]}")
    export DEVICE ADB_ARGS
  else
    unset DEVICE ADB_ARGS
  fi
  return "$rc"
}
