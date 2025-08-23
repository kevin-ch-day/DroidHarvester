#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# header.sh - Menu header/footer helpers
# ---------------------------------------------------

draw_menu_header() {
    local title="$1"
    local device_arg="${2-__unset__}"
    local report_arg="${3-__unset__}"
    echo
    echo "============================================================"
    printf " %-58s\n" "DROIDHARVESTER // ANALYST CONTROL INTERFACE"
    echo "------------------------------------------------------------"
    printf " %-58s\n" "SESSION : $(date '+%Y-%m-%d %H:%M:%S')"
    printf " %-58s\n" "MODULE  : $title"
    if [[ "$device_arg" != "__unset__" ]]; then
        printf " %-58s\n" "DEVICE  : ${device_arg:-Not selected}"
    fi
    if [[ "$report_arg" != "__unset__" ]]; then
        printf " %-58s\n" "REPORT  : ${report_arg:-None}"
    fi
    echo "============================================================"
}

draw_menu_footer() {
    local status="${1:-Awaiting analyst command...}"
    echo "------------------------------------------------------------"
    printf " %-58s\n" "STATUS : $status"
    echo "============================================================"
}
