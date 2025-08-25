#!/usr/bin/env bash
# lib/core/device/pm.sh
# ADB package-manager helpers (soft-fail; multi-user aware)
set -euo pipefail
# No ERR trap here: PM probes must stay quiet even on expected misses

# --- internal: run a command with ERR trap disabled and errexit off -----------
_pm_run_quiet() {
  # Usage: _pm_run_quiet <outvar> <rcvar> -- <cmd...>
  # Captures stdout into <outvar> and exit code into <rcvar>; always returns 0.
  local __outvar=$1 __rcvar=$2; shift 2
  [[ "${1:-}" == "--" ]] && shift || { echo "[pm] missing -- in _pm_run_quiet" >&2; return 127; }

  local __old_err_trap
  __old_err_trap="$(trap -p ERR || true)"
  trap - ERR

  set +e
  local __out __rc
  __out="$("$@" 2>/dev/null)"
  __rc=$?
  set -e

  printf -v "$__outvar" '%s' "$__out"
  printf -v "$__rcvar" '%s' "$__rc"

  # Restore the previous ERR trap if any (after capturing results)
  [[ -n "$__old_err_trap" ]] && eval "$__old_err_trap" || true

  return 0
}

# --- internal: optional --user argument for multi-user aware commands ---------
_pm_user_args() {
  if [[ -n "${DH_USER_ID:-}" ]]; then
    printf -- '--user\037%s' "$DH_USER_ID" | tr '\037' ' '
  fi
}

# pm_path_raw <package>
# - Returns "package:/...apk" lines from `pm path`
# - Soft-fail: on error prints nothing and returns 0 (caller can continue)
# - Respects DH_USER_ID if set
pm_path_raw() {
  local pkg="${1:?package name required}"
  local out rc
  # Build args array safely
  local -a args=(pm path)
  if [[ -n "${DH_USER_ID:-}" ]]; then
    args+=(--user "$DH_USER_ID")
  fi
  args+=("$pkg")

  _pm_run_quiet out rc -- adb_shell "${args[@]}"
  if (( rc != 0 )); then
    return 0
  fi

  printf '%s\n' "$out" | tr -d '\r'
}

# pm_path_sanitize
# - Reads from STDIN ("package:/...") and emits absolute /...apk paths only
pm_path_sanitize() {
  tr -d '\r' \
    | sed -n 's/^package://p' \
    | sed -n '/^\/.*\.apk$/p'
}

# pm_is_installed <package>
# - Returns 0 if at least one APK path exists, 1 otherwise
# - Fully shields ERR so missing packages don’t print ERROR lines
pm_is_installed() {
  local pkg="${1:?package name required}"
  # Don’t let a failing probe trigger ERR; collect then test.
  local paths
  paths="$(pm_path_raw "$pkg" | pm_path_sanitize || true)"
  if [[ -n "$paths" ]]; then
    return 0
  else
    return 1
  fi
}

# pm_list_pkgs [pattern]
# - Lists installed package names; host-side optional filter
# - Soft-fail: on adb error prints nothing and returns 0
pm_list_pkgs() {
  local pattern="${1:-}"
  local out rc

  local -a args=(pm list packages)
  if [[ -n "${DH_USER_ID:-}" ]]; then
    args+=(--user "$DH_USER_ID")
  fi

  _pm_run_quiet out rc -- adb_shell "${args[@]}"
  if (( rc != 0 )); then
    return 0
  fi

  out="$(printf '%s\n' "$out" | tr -d '\r' | sed -n 's/^package://p')"
  if [[ -n "$pattern" ]]; then
    # Fixed-string grep so dots don’t act as regex
    printf '%s\n' "$out" | grep -F -- "$pattern" || true
  else
    printf '%s\n' "$out"
  fi
}
