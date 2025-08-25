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
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck disable=SC1090
source "$ROOT/lib/core/device/wrappers.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/device/pm.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/device/fs.sh"

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
  local pkg="$1" apk_path="$2"
  local root="${3:-${DEVICE_DIR:-.}}"
  local base="$(basename -- "$apk_path")"
  base="$(safe_apk_name "$base")"
  local split_name="${base%.apk}"
  local outdir="$root/$pkg/$split_name"
  local outfile="$outdir/$base"
  local role; role="$(apk_split_role "$apk_path")"
  printf '%s\0%s\0%s\0' "$outdir" "$outfile" "$role"
}

# Decide how to access APK paths for a package.
# Echoes one of: direct|run-as|su; returns 1 if none viable.
determine_pull_strategy() {
  local pkg="$1" sample="$2"
  if adb_shell dd if="$sample" of=/dev/null bs=1 count=1 >/dev/null 2>&1; then
    LOG_PKG="$pkg" log DEBUG "strategy=direct"
    echo direct
    return 0
  fi
  if adb_shell run-as "$pkg" id >/dev/null 2>&1; then
    LOG_PKG="$pkg" log DEBUG "strategy=run-as"
    echo run-as
    return 0
  fi
  if adb_shell su 0 id >/dev/null 2>&1; then
    LOG_PKG="$pkg" log DEBUG "strategy=su"
    echo su
    return 0
  fi
  LOG_PKG="$pkg" log DEBUG "strategy=none"
  return 1
}

pull_with_strategy() {
  local strategy="$1" pkg="$2" src="$3" dest="$4"
  case "$strategy" in
    direct)
      run_adb_pull_with_fallbacks "$src" "$dest"
      ;;
    run-as)
      local tmp="/data/local/tmp/$(basename "$dest")"
      if adb_shell run-as "$pkg" cp "$src" "$tmp" >/dev/null 2>&1; then
        run_adb_pull_with_fallbacks "$tmp" "$dest"
        adb_shell run-as "$pkg" rm -f "$tmp" >/dev/null 2>&1 || true
      else
        return 1
      fi
      ;;
    su)
      local tmp="/data/local/tmp/$(basename "$dest")"
      if adb_shell su 0 cp "$src" "$tmp" >/dev/null 2>&1; then
        run_adb_pull_with_fallbacks "$tmp" "$dest"
        adb_shell su 0 rm -f "$tmp" >/dev/null 2>&1 || true
      else
        return 1
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

# --- pm list / pm path helpers ------------------------------------------------

# Variant runner: prints RAW `pm path` output to stdout; returns rc.
# A) retry w/ label   B) retry w/o label   C) direct (no retry)
_pm_path_run() {
  local variant="$1" pkg="$2"
  case "$variant" in
    A)
      adb_retry "$DH_SHELL_TIMEOUT" "$DH_RETRIES" "$DH_BACKOFF" pm_path -- \
        shell pm path "$pkg" 2>/dev/null
      ;;
    B)
      adb_retry "$DH_SHELL_TIMEOUT" "$DH_RETRIES" "$DH_BACKOFF" '' -- \
        shell pm path "$pkg" 2>/dev/null
      ;;
    C)
      with_timeout "$DH_SHELL_TIMEOUT" pm_path -- \
      adb "${ADB_ARGS[@]}" shell pm path "$pkg" 2>/dev/null
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

  out="$(_pm_path_run A "$pkg")"; rc=$?; tries+="A:"$rc" "
  if (( rc != 0 )); then
    out="$(_pm_path_run B "$pkg")"; rc=$?; tries+="B:"$rc" "
  fi
  if (( rc != 0 )); then
    out="$(_pm_path_run C "$pkg")"; rc=$?; tries+="C:"$rc" "
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
  local pkg="$1" out rc
  out="$(run_pm_path_with_fallbacks "$pkg")"
  rc=$?
  (( rc == 0 )) || {
    LOG_PKG="$pkg" LOG_NOTE="$PM_PATH_TRIES_RC" LOG_RC="$rc" \
      log ERROR "pm path failed"
    return 0
  }
  printf '%s\n' "$out" | sanitize_pm_output | sed '/^$/d' | sort -u
}

# Public: list third-party packages (like `pm list packages -f -3`, but only names)
# Usage: apk_list_third_party
apk_list_third_party() {
  local output rc
  output=$( 
    adb_retry "$DH_SHELL_TIMEOUT" "$DH_RETRIES" "$DH_BACKOFF" pm_list -- \
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
    if adb "${ADB_ARGS[@]}" shell test -f "$line" 2>/dev/null; then
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
  out=$(
    adb_retry "$DH_SHELL_TIMEOUT" "$DH_RETRIES" "$DH_BACKOFF" sha_dev -- \
      shell 'command -v sha256sum >/dev/null 2>&1 && sha256sum "$1" || (command -v toybox >/dev/null 2>&1 && toybox sha256sum "$1")' _ "$path" 2>/dev/null
  ); rc=$?
  if (( rc != 0 )) || [[ -z "${out:-}" ]]; then
    out=$(
      adb_retry "$DH_SHELL_TIMEOUT" "$DH_RETRIES" "$DH_BACKOFF" sha_dev -- \
        shell sha256sum "$path" 2>/dev/null
    ) || true
  fi
  printf '%s\n' "$out" | awk '{print $1}' | head -n1
}

# Local SHA256 for a file; echoes hash or nothing
file_sha256() {
  local file="$1"
  command -v sha256sum >/dev/null 2>&1 || { log WARN "sha256sum not found locally"; return 1; }
  sha256sum -- "$file" 2>/dev/null | awk '{print $1}'
}

# --- pull helpers -------------------------------------------------------------

# Pull with retry, falling back to device-side copy on permission errors
run_adb_pull_with_fallbacks() {
    local src="$1" dst="$2" rc tmp
    local __old_err_trap; __old_err_trap="$(trap -p ERR || true)"
    trap - ERR
    set +e

    mkdir -p "$(dirname "$dst")"

    log DEBUG "cmd: adb ${ADB_ARGS[*]} pull $src $dst"
    timeout --preserve-status -- "$DH_PULL_TIMEOUT" adb "${ADB_ARGS[@]}" pull "$src" "$dst" >>"$LOGFILE" 2>&1
    rc=$?
    if (( rc != 0 )); then
      LOG_APK="$(basename "$dst")" log WARN "direct pull failed; trying exec-out fallback"
      timeout --preserve-status -- "$DH_PULL_TIMEOUT" adb "${ADB_ARGS[@]}" exec-out cat "$src" >"$dst" 2>>"$LOGFILE"
      rc=$?
      if (( rc != 0 )) || [[ ! -s "$dst" ]]; then
        LOG_APK="$(basename "$dst")" log WARN "exec-out fallback failed; trying copy fallback"
        tmp="/data/local/tmp/$(basename "$dst")"
        if adb_shell cp "$src" "$tmp" >/dev/null 2>&1; then
          log DEBUG "cmd: adb ${ADB_ARGS[*]} pull $tmp $dst"
          timeout --preserve-status -- "$DH_PULL_TIMEOUT" adb "${ADB_ARGS[@]}" pull "$tmp" "$dst" >>"$LOGFILE" 2>&1
          rc=$?
          [[ -s "$dst" ]] || rc=1
          adb_shell rm -f "$tmp" >/dev/null 2>&1 || true
        else
          LOG_APK="$(basename "$dst")" log WARN "device-side copy failed"
        fi
      fi
    fi

  set -e
  [[ -n "$__old_err_trap" ]] && eval "$__old_err_trap" || true
  return "$rc"
}

# Pull a single APK path for a package into DEST (default DEVICE_DIR)
# honors DH_SKIP_EXISTING, DH_VERIFY_PULL, DH_DRY_RUN
# Prints destination file path on success.
apk_pull_one() {
  local pkg="$1" src_path="$2" dest_root="${3:-${DEVICE_DIR:-.}}"
  local parts
  readarray -d '' -t parts < <(compute_outfile_vars "$pkg" "$src_path" "$dest_root")
  local outdir="${parts[0]}" outfile="${parts[1]}" role="${parts[2]}"
  [[ "$DH_DRY_RUN" == "1" ]] && { printf '%s\n' "$outfile"; return 0; }
  mkdir -p -- "$outdir"

  if [[ "$DH_SKIP_EXISTING" == "1" && -s "$outfile" ]]; then
    LOG_PKG="$pkg" LOG_APK="$(basename "$outfile")" log INFO "Skip existing"
    printf '%s\n' "$outfile"
    return 0
  fi

  # Optional: compute device hash first to avoid re-pulling identical files
  local dev_hash=""
  if [[ "$DH_VERIFY_PULL" == "1" && "$DH_HASH_ON_DEVICE_FIRST" == "1" ]]; then
    dev_hash="$(device_sha256 "$src_path" || true)"
  fi

  LOG_PKG="$pkg" LOG_APK="$(basename "$outfile")" log INFO "Pulling ($(apk_install_partition "$src_path") / $(apk_split_role "$src_path"))"
  if ! pull_with_strategy "${APK_PULL_STRATEGY:-direct}" "$pkg" "$src_path" "$outfile"; then
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

  local sample
  sample="$(printf '%s\n' "$paths" | head -n1)"
  if ! APK_PULL_STRATEGY="$(determine_pull_strategy "$pkg" "$sample" 2>/dev/null)"; then
    LOG_PKG="$pkg" log ERROR "APKs not readable on device (no direct read, no run-as, no root)"
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
      pulled=$((pulled+1))
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

# -----------------------------------------------------------------------------
# Simplified, centralized helpers
# -----------------------------------------------------------------------------

# Raw pm path output for a package
au_pm_path_raw() {
  local pkg="$1"
  pm_path_raw "$pkg"
}

# Sanitize pm path output (strip leading 'package:')
au_pm_path_sanitize() {
  pm_path_sanitize
}

# Convenience: list sanitized APK paths for a package
au_apk_paths_for_pkg() {
  au_pm_path_raw "$1" | au_pm_path_sanitize
}

# Pick base.apk if present, else first path from file
au_pick_base_apk() {
  local file="$1"
  local base
  base=$(grep '/base\.apk$' "$file" | head -n1)
  [[ -n "$base" ]] && { echo "$base"; return 0; }
  head -n1 "$file"
}

# Get device file size in bytes
au_dev_file_size() {
  local path="$1"
  dev_stat_size "$path"
}

# Pull one file, echo local path
au_pull_one() {
  local src="$1" dest_dir="$2"
  mkdir -p "$dest_dir"
  local dest="$dest_dir/$(basename "$src")"
  adb_pull "$src" "$dest" >/dev/null
  echo "$dest"
}

# Detect hash command on device
au_detect_device_hash_cmd() {
  if adb_shell command -v sha256sum >/dev/null 2>&1; then
    echo sha256sum
  elif adb_shell command -v md5sum >/dev/null 2>&1; then
    echo md5sum
  else
    echo ""
  fi
}

# Verify device vs local hash (best effort)
au_verify_hash() {
  local dev_path="$1" local_path="$2"
  local cmd
  cmd=$(au_detect_device_hash_cmd) || true
  [[ -z "$cmd" ]] && return 0
  local dev_hash
  dev_hash=$(adb_shell "$cmd" "$dev_path" | awk '{print $1}')
  command -v "$cmd" >/dev/null 2>&1 || return 0
  local local_hash
  local_hash=$($cmd "$local_path" | awk '{print $1}')
  [[ "$dev_hash" == "$local_hash" ]]
}

# Metadata helpers
au_pkg_meta() {
  local pkg="$1"
  adb_shell dumpsys package "$pkg"
}

au_pkg_meta_csv_line() {
  local pkg="$1" meta vn vc inst
  meta="$(au_pkg_meta "$pkg")"
  vn=$(printf '%s' "$meta" | awk -F= '/versionName=/{print $2; exit}' | tr -d '\r')
  vc=$(printf '%s' "$meta" | awk -F= '/versionCode=/{print $2; exit}' | awk '{print $1}')
  inst=$(printf '%s' "$meta" | awk -F= '/installerPackageName=/{print $2; exit}' | tr -d '\r')
  printf '%s,%s,%s,%s\n' "$pkg" "$vn" "$vc" "$inst"
}

# Package discovery
au_packages_all() {
  pm_list_pkgs
}

au_scan_tiktok_family() {
  au_packages_all | grep -E '^(com\.zhiliaoapp\.musically|com\.ss\.android\.ugc\.aweme(\.lite)?|com\.ss\.android\.ugc\.trill|com\.bytedance\.)'
}

au_scan_tiktok_related() {
  au_packages_all | grep -iE 'tiktok|aweme|trill|musically|bytedance'
}

au_pm_list_third_party_csv() {
  adb_shell pm list packages -f -3 | tr -d '\r' | sed -n 's/^package://p' |
    while IFS='=' read -r path pkg; do
      printf '%s,%s\n' "$path" "$pkg"
    done
}
