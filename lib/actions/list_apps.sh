#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# list_apps.sh - list installed packages
# ---------------------------------------------------

list_installed_apps() {
    [[ -z "$DEVICE" ]] && { log WARN "Choose a device first."; return; }
    log INFO "Listing installed apps..."
    adb_shell pm list packages | sed 's/package://g' | sort
}
