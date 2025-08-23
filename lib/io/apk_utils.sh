#!/usr/bin/env bash
# ---------------------------------------------------
# lib/io/apk_utils.sh - helpers for APK operations
# ---------------------------------------------------
# Scope: keep this a *helper* library. No CSV writing or heavy orchestration.
#        Consumers: diag.sh, steps/*, higher-level actions.
#
# Requires (provided elsewhere in repo):
#   - log (core/logging), with_trace/with_timeout (core/trace), adb_retry (core/device)
#   - env: DEVICE (selected device id), DEVICE_DIR (optional staging dir per device)
#
# Conventions:
#   - Functions print *data* on stdout; logs go through `log`.
#   - For adb_retry: pass *only* adb subcommands (e.g., `shell pm path ...`, `pull SRC DST`).
#     The wrapper prepends `adb -s "$DEVICE"` itself.
# ---------------------------------------------------

set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR

# --- Defaults / knobs ---------------------------------------------------------

ensure_timeouts_defaults() {
  : "${DH_SHELL_TIMEOUT:=15}"   # seconds for shell ops (pm path/list)
  : "${DH_PULL_TIMEOUT:=120}"   # seconds for pulls (larger for big splits)
  : "${DH_RETRIES:=3}"          # retry count for adb_retry
  : "${DH_BACKOFF:=1}"          # seconds between retries

  # Behavior toggles the caller can override
  : "${DH_INCLUDE_SPLITS:=1}"   # 1 = include split APKs when pulling
  : "${DH_SKIP_EXISTING:=1}"    # 1 = skip pull if local file exists and non-empty
  : "${DH_VERIFY_PULL:=1}"      # 1 = verify pulled file via SHA256 (device vs local)
  : "${DH_HASH_ON_DEVICE_FIRST:=1}" # 1 = prefer device sha256sum; 0 = pull then hash
  : "${DH_DRY_RUN:=0}"          # 1 = print planned actions but do not modify files
}
ensure_timeouts_defaults

# --- Small utils --------------------------------------------------------------

# Strip CRs and leading 'package:' prefix from pm path output
sanitize_pm_output() {
  tr -d '\r' | sed -n 's/^package://p'
}

# Return a safe filename from a path (/x/y/base.apk -> base.apk, sanitized)
safe_apk_name() {
  basename -- "$1" | sed 's/[^a-zA-Z0-9._-]/_/g'
}

# Classify install partition from an absolute APK path
# -> echoes: data|system|system_ext|product|vendor|apex|other
apk_install_partition() {
  case "$1" in
    /data/app* )    echo data ;;
    /system/* )     echo system ;;
    /system_ext/* ) echo system_ext ;;
    /product/* )    echo product ;;
    /vendor/* )     echo vendor ;;
    /apex/* )       echo apex ;;
    * )             echo other ;;
  esac
}

# Classify split/base role from filename (best-effort)
# -> echoes: base|split|split_config|unknown
apk_split_role() {
  local name; name="$(safe_apk_name "$1")"
  case "$name" in
    base.apk) echo base ;;
    split_config.*.apk) echo split_config ;;
    split_*.apk) echo split ;;
    *) echo unknown ;;
  esac
}

# Compute output dir/file and role for a given pkg + source path
# Returns NUL-separated triplet: outdir\0outfile\0role
compute_outfile_vars() {
  local pkg="$1" apk_path="$2" safe; safe="$(safe_apk_name "$apk_path")"
  local root="${3:-${DEVICE_DIR:-.}}"
  local outdir="$root/$pkg/${safe%.apk}"
  local outfile="$outdir/$safe"
  local role; role="$(apk_split_role "$apk_path")"
  printf '%s\0%s\0%s' "$outdir" "$outfile" "$role"
}

# --- pm list / pm path helpers ------------------------------------------------

# Variant runner: prints RAW `pm path` output to stdout; returns rc.
# A) retry w/ label   B) retry w/o label   C) direct (no retry)
_pm_path_run() {
  local variant="$1" pkg="$2"
  case "$variant" in
    A)
      with_timeout "$DH_SHELL_TIMEOUT" pm_path -- \
        adb_retry "$DH_RETRIES" "$DH_BACKOFF" pm_path -- \
          shell pm path "$pkg" 2>/dev/null
      ;;
    B)
      with_timeout "$DH_SHELL_TIMEOUT" pm_path -- \
        adb_retry "$DH_RETRIES" "$DH_BACKOFF" -- \
          shell pm path "$pkg" 2>/dev/null
      ;;
    C)
      with_timeout "$DH_SHELL_TIMEOUT" pm_path -- \
        adb -s "$DEVICE" shell pm path "$pkg" 2>/dev/null
      ;;
    *) return 127 ;;
  esac
}

# Global breadcrumb for diagnostics (e.g., "A:127 B:0 C:...")
PM_PATH_TRIES_RC=""

# Tries A→B→C; echoes RAW output; returns final rc.
run_pm_path_with_fallbacks() {
  local pkg="$1" out rc tries=""
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

# Public: return resolved APK paths for a package (one per line, absolute)
# Usage: apk_get_paths com.example.app
apk_get_paths() {
  local pkg="$1"
  local raw
  if ! raw="$(run_pm_path_with_fallbacks "$pkg")"; then
    LOG_PKG="$pkg" LOG_NOTE="$PM_PATH_TRIES_RC" log WARN "pm path failed"
    return 1
  fi
  printf '%s\n' "$raw" | sanitize_pm_output | sed '/^$/d' | sort -u
}

# Public: list third-party packages (like `pm list packages -f -3`, but only names)
# Usage: apk_list_third_party
apk_list_third_party() {
  local output rc
  output=$(
    with_timeout "$DH_SHELL_TIMEOUT" pm_list -- \
      adb_retry "$DH_RETRIES" "$DH_BACKOFF" pm_list -- \
        shell pm list packages -3 2>/dev/null
  )
  rc=$?
  if (( rc != 0 )); then
    LOG_RC="$rc" log WARN "pm list packages -3 failed"
    return "$rc"
  fi
  # Strip "package:" prefix
  printf '%s\n' "$output" | tr -d '\r' | sed -n 's/^package://p' | sort -u
}

# Verify each path exists on device; prints "<path>\tOK|MISSING"
# Returns 0 (verification ran), non-zero only for transport errors
apk_paths_verify() {
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if adb -s "$DEVICE" shell test -f "$line" 2>/dev/null; then
      printf '%s\tOK\n' "$line"
    else
      printf '%s\tMISSING\n' "$line"
    fi
  done
}

# --- hashing helpers ----------------------------------------------------------

# Try to compute SHA256 on device for a given ABS path; echoes hash or nothing
device_sha256() {
  local path="$1" out rc
  # Try common variants (toybox, busybox, coreutils)
  out=$(
    with_timeout "$DH_SHELL_TIMEOUT" sha_dev -- \
      adb_retry "$DH_RETRIES" "$DH_BACKOFF" sha_dev -- \
        shell 'command -v sha256sum >/dev/null 2>&1 && sha256sum "$0" || (command -v toybox >/dev/null 2>&1 && toybox sha256sum "$0")' "$path" 2>/dev/null
  ); rc=$?
  if (( rc != 0 )) || [[ -z "${out:-}" ]]; then
    # Fallback: some builds output just hash or "hash  filename"
    out=$(
      with_timeout "$DH_SHELL_TIMEOUT" sha_dev -- \
        adb_retry "$DH_RETRIES" "$DH_BACKOFF" sha_dev -- \
          shell sha256sum "$path" 2>/dev/null
    ) || true
  fi
  # Normalize to first field
  printf '%s\n' "$out" | awk '{print $1}' | head -n1
}

# Local SHA256 for a file; echoes hash or nothing
file_sha256() {
  local file="$1"
  command -v sha256sum >/dev/null 2>&1 || { log WARN "sha256sum not found locally"; return 1; }
  sha256sum -- "$file" 2>/dev/null | awk '{print $1}'
}

# --- pull helpers -------------------------------------------------------------

# Variant runner: try pull using (A) retry w/ label, (B) retry w/o label, (C) direct
_adb_pull_run() {
  local variant="$1" src="$2" dst="$3"
  case "$variant" in
    A)
      with_timeout "$DH_PULL_TIMEOUT" adb_pull -- \
        adb_retry "$DH_RETRIES" "$DH_BACKOFF" adb_pull -- \
          pull "$src" "$dst"
      ;;
    B)
      with_timeout "$DH_PULL_TIMEOUT" adb_pull -- \
        adb_retry "$DH_RETRIES" "$DH_BACKOFF" -- \
          pull "$src" "$dst"
      ;;
    C)
      with_timeout "$DH_PULL_TIMEOUT" adb_pull -- \
        adb -s "$DEVICE" pull "$src" "$dst"
      ;;
    *) return 127 ;;
  esac
}

# Tries A→B→C; returns final rc (no stdout)
run_adb_pull_with_fallbacks() {
  local src="$1" dst="$2" rc
  local __old_err_trap; __old_err_trap="$(trap -p ERR || true)"
  trap - ERR
  set +e

  _adb_pull_run A "$src" "$dst"; rc=$?
  if (( rc != 0 )); then _adb_pull_run B "$src" "$dst"; rc=$?; fi
  if (( rc != 0 )); then _adb_pull_run C "$src" "$dst"; rc=$?; fi

  set -e
  [[ -n "$__old_err_trap" ]] && eval "$__old_err_trap" || true
  return "$rc"
}

# Pull a single APK path for a package into DEST (default DEVICE_DIR)
# honors DH_SKIP_EXISTING, DH_VERIFY_PULL, DH_DRY_RUN
# Prints destination file path on success.
apk_pull_one() {
  local pkg="$1" src_path="$2" dest_root="${3:-${DEVICE_DIR:-.}}"
  IFS=$'\0' read -r outdir outfile role < <(compute_outfile_vars "$pkg" "$src_path" "$dest_root")
  [[ "$DH_DRY_RUN" == "1" ]] && { printf '%s\n' "$outfile"; return 0; }
  mkdir -p -- "$outdir"

  if [[ "$DH_SKIP_EXISTING" == "1" && -s "$outfile" ]]; then
    LOG_PKG="$pkg" LOG_APK="$(basename "$outfile")" log INFO "Skip existing"
    printf '%s\n' "$outfile"
    return 0
  fi

  # (Optional) pre-check on device
  if ! adb -s "$DEVICE" shell test -f "$src_path" 2>/dev/null; then
    LOG_PKG="$pkg" LOG_APK="$src_path" log WARN "Source APK missing on device"
    return 1
  fi

  # Optional: compute device hash first to avoid re-pulling identical files
  local dev_hash=""
  if [[ "$DH_VERIFY_PULL" == "1" && "$DH_HASH_ON_DEVICE_FIRST" == "1" ]]; then
    dev_hash="$(device_sha256 "$src_path" || true)"
  fi

  LOG_PKG="$pkg" LOG_APK="$(basename "$outfile")" log INFO "Pulling ($(apk_install_partition "$src_path") / $(apk_split_role "$src_path"))"
  if ! run_adb_pull_with_fallbacks "$src_path" "$outfile"; then
    LOG_PKG="$pkg" LOG_APK="$(basename "$outfile")" log ERROR "Pull failed"
    return 1
  fi
  if [[ ! -s "$outfile" ]]; then
    LOG_PKG="$pkg" LOG_APK="$(basename "$outfile")" log ERROR "Pulled file empty"
    return 1
  fi

  # Verify via SHA256 (if requested and toolchain available)
  if [[ "$DH_VERIFY_PULL" == "1" ]]; then
    local local_hash; local_hash="$(file_sha256 "$outfile" || true)"
    if [[ -z "$local_hash" ]]; then
      LOG_PKG="$pkg" LOG_APK="$(basename "$outfile")" log WARN "Local sha256 unavailable; skipping verify"
    else
      # If we didn't compute device hash earlier, try now (best-effort)
      [[ -z "$dev_hash" ]] && dev_hash="$(device_sha256 "$src_path" || true)"
      if [[ -n "$dev_hash" && -n "$local_hash" && "$dev_hash" != "$local_hash" ]]; then
        LOG_PKG="$pkg" LOG_APK="$(basename "$outfile")" log ERROR "SHA256 mismatch (device vs local)"
        return 1
      fi
    fi
  fi

  printf '%s\n' "$outfile"
}

# Pull all APK paths for a package. Options via env:
#   DH_INCLUDE_SPLITS, DH_SKIP_EXISTING, DH_VERIFY_PULL, DH_DRY_RUN
# Prints all destination file paths on success, one per line.
apk_pull_all_for_package() {
  local pkg="$1" dest_root="${2:-${DEVICE_DIR:-.}}"
  local pulled=0
  local paths
  if ! paths="$(apk_get_paths "$pkg")"; then
    LOG_PKG="$pkg" log WARN "No paths resolved; nothing to pull"
    return 1
  fi

  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    local role; role="$(apk_split_role "$p")"
    if [[ "$DH_INCLUDE_SPLITS" != "1" && "$role" != "base" ]]; then
      LOG_PKG="$pkg" LOG_APK="$p" log DEBUG "Skipping split due to DH_INCLUDE_SPLITS=0"
      continue
    fi
    if fpath="$(apk_pull_one "$pkg" "$p" "$dest_root")"; then
      printf '%s\n' "$fpath"
      ((pulled++))
    else
      LOG_PKG="$pkg" LOG_APK="$p" log WARN "pull failed (continuing)"
    fi
  done <<< "$paths"

  (( pulled > 0 ))
}

# Convenience: echo "<path>\trole\tpartition" for given package
apk_paths_describe() {
  local pkg="$1"
  local p
  if ! apk_get_paths "$pkg" >/dev/null; then
    LOG_PKG="$pkg" log WARN "pm path failed for package"
    return 1
  fi
  apk_get_paths "$pkg" | while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    printf '%s\t%s\t%s\n' "$p" "$(apk_split_role "$p")" "$(apk_install_partition "$p")"
  done
}
