#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# view_report.sh - view latest report
# ---------------------------------------------------

view_report() {
    local latest
    latest=$(latest_report)
    if [[ -z "$latest" ]]; then
        log WARN "No reports found."
    else
        LAST_TXT_REPORT="$latest"
        echo
        echo "--------------------------------------------------"
        echo " Last Report (Preview)"
        echo "--------------------------------------------------"
        head -n 40 "$latest"
        echo "--------------------------------------------------"
        log INFO "Full report: $latest"
    fi
}
