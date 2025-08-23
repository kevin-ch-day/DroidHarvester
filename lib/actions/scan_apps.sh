#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# scan_apps.sh - scan for target packages
# ---------------------------------------------------

scan_apps() {
    [[ -z "$DEVICE" ]] && { log WARN "Choose a device first."; return; }
    log INFO "Scanning for target apps..."
    local pkg_list
    if ! pkg_list="$(with_timeout "$DH_SHELL_TIMEOUT" pm_list -- \
        adb_retry "$DH_RETRIES" "$DH_BACKOFF" pm_list -- \
            adb -s "$DEVICE" shell pm list packages)"; then
        LOG_CODE="$E_PM_LIST" log ERROR "failed to list packages"
        return
    fi
    for pkg in "${TARGET_PACKAGES[@]}"; do
        if grep -Fq -- "$pkg" <<< "$pkg_list"; then
            LOG_PKG="$pkg" log SUCCESS "Found: $pkg"
        else
            LOG_PKG="$pkg" log WARN "Not installed: $pkg"
        fi
    done
}
