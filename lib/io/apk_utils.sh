#!/usr/bin/env bash
# ---------------------------------------------------
# lib/io/apk_utils.sh - helpers for APK operations
# ---------------------------------------------------
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR

# --- Small guards -------------------------------------------------------------

ensure_timeouts_defaults() {
  : "${DH_SHELL_TIMEOUT:=15}"
  : "${DH_PULL_TIMEOUT:=60}"
  : "${DH_RETRIES:=3}"
  : "${DH_BACKOFF:=1}"
}

# --- pm path helpers ----------------------------------------------------------

# Variant runner: prints RAW pm path output to stdout; returns rc.
# A) retry w/ label   B) retry w/o label   C) direct (no retry)
_pm_path_run() {
  local variant="$1" pkg="$2"
  case "$variant" in
    A)
      with_timeout "$DH_SHELL_TIMEOUT" pm_path -- \
        adb_retry "$DH_RETRIES" "$DH_BACKOFF" pm_path -- \
          adb -s "$DEVICE" shell pm path "$pkg" 2>/dev/null
      ;;
    B)
      with_timeout "$DH_SHELL_TIMEOUT" pm_path -- \
        adb_retry "$DH_RETRIES" "$DH_BACKOFF" -- \
          adb -s "$DEVICE" shell pm path "$pkg" 2>/dev/null
      ;;
    C)
      with_timeout "$DH_SHELL_TIMEOUT" pm_path -- \
        adb -s "$DEVICE" shell pm path "$pkg" 2>/dev/null
      ;;
    *)
      return 127
      ;;
  esac
}

# Global breadcrumb for diagnostics (e.g., "A:127 B:0 C:...")
PM_PATH_TRIES_RC=""

# Tries A→B→C; echoes RAW output; returns final rc.
run_pm_path_with_fallbacks() {
  local pkg="$1" out rc tries=""
  # Temporarily silence the ERR trap while probing fallbacks.
  local __old_err_trap; __old_err_trap="$(trap -p ERR || true)"
  trap - ERR
  set +e

  out="$(_pm_path_run A "$pkg")"; rc=$?; tries+="A:$rc "
  if (( rc != 0 )); then
    out="$(_pm_path_run B "$pkg")"; rc=$?; tries+="B:$rc "
  fi
  if (( rc != 0 )); then
    out="$(_pm_path_run C "$pkg")"; rc=$?; tries+="C:$rc "
  fi

  set -e
  [[ -n "$__old_err_trap" ]] && eval "$__old_err_trap" || true

  PM_PATH_TRIES_RC="$tries"
  printf '%s' "$out"
  return "$rc"
}

sanitize_pm_output() {
  # Reads RAW pm path output on stdin, prints ABSOLUTE paths one per line.
  tr -d '\r' | sed -n 's/^package://p'
}

# --- pull helpers -------------------------------------------------------------

safe_apk_name() {
  # $1 = /path/to.apk → prints sanitized file name
  basename -- "$1" | sed 's/[^a-zA-Z0-9._-]/_/g'
}

# Sets OUT: outdir outfile role
compute_outfile_vars() {
  local pkg="$1" apk_path="$2" safe; safe="$(safe_apk_name "$apk_path")"
  local outdir="$DEVICE_DIR/$pkg/${safe%.apk}"
  local outfile="$outdir/$safe"
  local role="base"; [[ "$safe" != "base.apk" ]] && role="split"
  printf '%s\0%s\0%s' "$outdir" "$outfile" "$role"
}

# Variant runner: try pull using (A) retry w/ label, (B) retry w/o label, (C) direct
_adb_pull_run() {
  local variant="$1" src="$2" dst="$3"
  case "$variant" in
    A)
      with_timeout "$DH_PULL_TIMEOUT" adb_pull -- \
        adb_retry "$DH_RETRIES" "$DH_BACKOFF" adb_pull -- \
          adb -s "$DEVICE" pull "$src" "$dst"
      ;;
    B)
      with_timeout "$DH_PULL_TIMEOUT" adb_pull -- \
        adb_retry "$DH_RETRIES" "$DH_BACKOFF" -- \
          adb -s "$DEVICE" pull "$src" "$dst"
      ;;
    C)
      with_timeout "$DH_PULL_TIMEOUT" adb_pull -- \
        adb -s "$DEVICE" pull "$src" "$dst"
      ;;
    *)
      return 127
      ;;
  esac
}

# Tries A→B→C; returns final rc (no stdout)
run_adb_pull_with_fallbacks() {
  local src="$1" dst="$2" rc
  local __old_err_trap; __old_err_trap="$(trap -p ERR || true)"
  trap - ERR
  set +e

  _adb_pull_run A "$src" "$dst"; rc=$?
  (( rc != 0 )) && _adb_pull_run B "$src" "$dst"; rc=$?
  (( rc != 0 )) && _adb_pull_run C "$src" "$dst"; rc=$?

  set -e
  [[ -n "$__old_err_trap" ]] && eval "$__old_err_trap" || true
  return "$rc"
}


