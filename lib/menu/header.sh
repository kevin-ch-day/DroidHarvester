#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# header.sh - Menu header/footer helpers
# ---------------------------------------------------

# shellcheck disable=SC1090
source "$REPO_ROOT/lib/ui/colors.sh"

draw_menu_header() {
    local title="$1"
    local device_arg="${2-__unset__}"
    local report_arg="${3-__unset__}"
    echo
    echo "${CYAN}============================================================${NC}"
    printf " ${CYAN}%-58s${NC}\n" "DROIDHARVESTER // ANALYST CONTROL INTERFACE"
    echo "${CYAN}------------------------------------------------------------${NC}"
    printf " ${CYAN}%-58s${NC}\n" "SESSION : $(date '+%Y-%m-%d %H:%M:%S')"
    printf " ${CYAN}%-58s${NC}\n" "MODULE  : $title"
    if [[ "$device_arg" != "__unset__" ]]; then
        printf " ${CYAN}%-58s${NC}\n" "DEVICE  : ${device_arg:-Not selected}"
    fi
    if [[ "$report_arg" != "__unset__" ]]; then
        printf " ${CYAN}%-58s${NC}\n" "REPORT  : ${report_arg:-None}"
    fi
    echo "${CYAN}============================================================${NC}"
}

draw_menu_footer() {
    local status="${1:-Awaiting analyst command...}"
    echo "${CYAN}------------------------------------------------------------${NC}"
    printf " ${CYAN}%-58s${NC}\n" "STATUS : $status"
    echo "${CYAN}============================================================${NC}"
}
