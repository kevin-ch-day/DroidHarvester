#!/usr/bin/env bash
# ---------------------------------------------------
# lib/io/apk_utils.sh - APK discovery and pulling
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

# --- Public: get_apk_paths ----------------------------------------------------

get_apk_paths() {
  ensure_timeouts_defaults
  local pkg="$1"

  # --- Shield ERR + -e while we call the fallbacks runner ---
  local raw rc __old_err_trap
  __old_err_trap="$(trap -p ERR || true)"
  trap - ERR
  set +e
  raw="$(run_pm_path_with_fallbacks "$pkg")"
  rc=$?
  set -e
  # Restore ERR trap (if any)
  [[ -n "$__old_err_trap" ]] && eval "$__old_err_trap" || true

  if (( rc != 0 )); then
    # PM_PATH_TRIES_RC is set by run_pm_path_with_fallbacks (A:rc B:rc C:rc)
    LOG_CODE="${E_PM_PATH:-21}" LOG_RC="$rc" LOG_PKG="$pkg" LOG_COMP="pm_path" \
      log ERROR "pm path failed (attempts rc: ${PM_PATH_TRIES_RC:-unknown})"
    return 0  # non-fatal for callers
  fi

  # Sanitize → stdout (absolute paths only)
  local paths count
  paths="$(printf '%s' "$raw" | sanitize_pm_output)"
  count=$(printf '%s\n' "$paths" | sed '/^$/d' | wc -l || true)
  LOG_COMP="pm_path" LOG_PKG="$pkg" log DEBUG "paths=$count"

  [[ -z "$paths" ]] && { log WARN "No APK paths found for package $pkg"; return 0; }
  printf '%s\n' "$paths"
}


# --- Public: pull_apk ---------------------------------------------------------

pull_apk() {
  ensure_timeouts_defaults

  local pkg="$1" apk_path="$2"

  # Calculate output locations
  local outdir outfile role
  IFS=$'\0' read -r outdir outfile role < <(compute_outfile_vars "$pkg" "$apk_path")
  mkdir -p -- "$outdir"

  # Existence probe
  if ! with_trace adb_test -- adb -s "$DEVICE" shell test -f "$apk_path"; then
    local rc=$?
    LOG_CODE="${E_APK_MISSING:-31}" LOG_RC="$rc" LOG_PKG="$pkg" LOG_APK="$(basename "$outfile")" \
      log WARN "apk missing $apk_path"
    return 1
  fi

  LOG_PKG="$pkg" LOG_APK="$(basename "$outfile")" log INFO "Pulling $role APK $apk_path"

  # Pull with wrapper fallbacks
  if ! run_adb_pull_with_fallbacks "$apk_path" "$outfile"; then
    local rc=$?
    LOG_CODE="${E_PULL_FAIL:-32}" LOG_RC="$rc" LOG_PKG="$pkg" LOG_APK="$(basename "$outfile")" \
      log ERROR "pull failed"
    return 1
  fi

  if [[ ! -s "$outfile" ]]; then
    LOG_CODE="${E_APK_EMPTY:-33}" LOG_PKG="$pkg" LOG_APK="$(basename "$outfile")" \
      log ERROR "pulled file empty"
    return 1
  fi

  LOG_PKG="$pkg" LOG_APK="$(basename "$outfile")" log INFO "Pulled $role APK $outfile"
  printf '%s\n' "$outfile"
}
