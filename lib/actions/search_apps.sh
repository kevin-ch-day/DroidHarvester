#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# search_apps.sh - search installed packages
# ---------------------------------------------------

search_installed_apps() {
    [[ -z "$DEVICE" ]] && { log WARN "Choose a device first."; return; }
    read -rp "Enter search keyword: " keyword
    if [[ -z "$keyword" ]]; then
        log WARN "No keyword entered."
        return
    fi
    log INFO "Searching for '$keyword'..."
    local results
    results=$(adb_shell pm list packages | grep -Fi -- "$keyword" | sed 's/package://g' || true)
    if [[ -n "$results" ]]; then
        echo "$results"
    else
        log WARN "No packages match '$keyword'"
    fi
}
