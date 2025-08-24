#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]:-?}:$LINENO" >&2' ERR
# ---------------------------------------------------
# scan_apps.sh - scan for target packages
# ---------------------------------------------------

scan_apps() {
    [[ -z "$DEVICE" ]] && { log WARN "Choose a device first."; return; }
    log INFO "Scanning for target apps..."
    local pkg_list rc
    pkg_list=$(adb_retry "$DH_SHELL_TIMEOUT" "$DH_RETRIES" "$DH_BACKOFF" pm_list -- \
            shell pm list packages 2>&1) || rc=$?
    if [[ -n "${rc:-}" ]]; then
        LOG_CODE="$E_PM_LIST" LOG_RC="$rc" log ERROR "failed to list packages"
        adb_get_state >/dev/null 2>&1 || true
        if [[ "${DH_DEBUG:-0}" == "1" ]]; then
            printf '[CMD] adb %s shell pm list packages\n' "$ADB_FLAGS" >&2
            printf '%s\n' "$pkg_list" >&2
        fi
        return 1
    fi
    for pkg in "${TARGET_PACKAGES[@]}"; do
        if grep -Fq -- "$pkg" <<< "$pkg_list"; then
            LOG_PKG="$pkg" log SUCCESS "Found: $pkg"
        else
            LOG_PKG="$pkg" log WARN "Not installed: $pkg"
        fi
    done
}
