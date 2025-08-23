#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR

# steps/generate_apk_list.sh - list APK paths for a package

pkg="${1:-}"
if [[ -z "$pkg" ]]; then
  echo "Usage: $0 <package>" >&2
  exit 64
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$REPO_ROOT/config.sh"
# shellcheck disable=SC1090
for m in core/logging core/errors core/trace core/device io/apk_utils; do
  source "$REPO_ROOT/lib/$m.sh"
done

ensure_timeouts_defaults

# shield ERR while running fallbacks
raw=""
rc=0
__old_err_trap="$(trap -p ERR || true)"
trap - ERR
set +e
raw="$(run_pm_path_with_fallbacks "$pkg")"
rc=$?
set -e
[[ -n "$__old_err_trap" ]] && eval "$__old_err_trap" || true

if (( rc != 0 )); then
  LOG_CODE="${E_PM_PATH:-21}" LOG_RC="$rc" LOG_PKG="$pkg" LOG_COMP="pm_path" \
    log ERROR "pm path failed (attempts rc: ${PM_PATH_TRIES_RC:-unknown})"
  exit 0
fi

paths="$(printf '%s' "$raw" | sanitize_pm_output)"
count=$(printf '%s\n' "$paths" | sed '/^$/d' | wc -l || true)
LOG_COMP="pm_path" LOG_PKG="$pkg" log DEBUG "paths=$count"

[[ -z "$paths" ]] && { log WARN "No APK paths found for package $pkg"; exit 0; }

printf '%s\n' "$paths"
