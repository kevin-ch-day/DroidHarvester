#!/usr/bin/env bash
# ---------------------------------------------------
# lib/io/pull_file.sh - robust file pull helper with fallbacks
# ---------------------------------------------------
# Uses adb to copy a remote file to the host, attempting multiple
# strategies before giving up:
#   1) direct `adb pull`
#   2) `adb exec-out` streaming
#   3) copy to /data/local/tmp then pull
# The helper expects ADB_BIN to be set and will honor ADB_ARGS, ADB_S,
# or DEVICE for device selection. Optional logging via `log` if defined.

set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR

safe_pull_file() {
  local remote="$1" dest="$2" device_tmp bn timeout
  timeout="${DH_PULL_TIMEOUT:-120}"
  bn="$(basename -- "$dest")"

  # Determine adb arguments for device targeting
  local -a adb_flags=()
  if [[ ${ADB_ARGS+set} ]]; then
    adb_flags=("${ADB_ARGS[@]}")
  elif [[ ${ADB_S+set} ]]; then
    adb_flags=("${ADB_S[@]}")
  elif [[ -n ${DEVICE:-} ]]; then
    adb_flags=(-s "$DEVICE")
  fi

  mkdir -p "$(dirname -- "$dest")"

  if timeout --preserve-status -- "$timeout" \
       "$ADB_BIN" "${adb_flags[@]}" pull "$remote" "$dest" >/dev/null 2>&1; then
    return 0
  fi

  if declare -F log >/dev/null; then
    LOG_APK="$bn" log WARN "direct pull failed; trying exec-out"
  fi

  if timeout --preserve-status -- "$timeout" \
       "$ADB_BIN" "${adb_flags[@]}" exec-out "cat \"$remote\"" \
       > "${dest}.part" 2>/dev/null; then
    mv -f "${dest}.part" "$dest"
    return 0
  fi
  rm -f "${dest}.part" >/dev/null 2>&1 || true

  if declare -F log >/dev/null; then
    LOG_APK="$bn" log WARN "exec-out fallback failed; trying tmp copy"
  fi

  device_tmp="/data/local/tmp/$bn"
  if "$ADB_BIN" "${adb_flags[@]}" shell "cp \"$remote\" \"$device_tmp\"" >/dev/null 2>&1 && \
     timeout --preserve-status -- "$timeout" \
       "$ADB_BIN" "${adb_flags[@]}" pull "$device_tmp" "$dest" >/dev/null 2>&1; then
    "$ADB_BIN" "${adb_flags[@]}" shell "rm -f \"$device_tmp\"" >/dev/null 2>&1 || true
    [[ -s "$dest" ]] && return 0
  fi

  "$ADB_BIN" "${adb_flags[@]}" shell "rm -f \"$device_tmp\"" >/dev/null 2>&1 || true
  return 1
}

