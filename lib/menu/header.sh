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
    local device_arg="${2-}"
    local report_arg="${3-}"
    local line
    line=$(ui_line "$UI_H2")
    echo
    echo "${CYAN}${line}${NC}"
    printf " ${WHITE}%s${NC}\n" "DROIDHARVESTER // ANALYST CONTROL INTERFACE"
    echo "${CYAN}${line}${NC}"
    printf " ${CYAN}SESSION${NC} : ${WHITE}%s${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')"
    printf " ${CYAN}MODULE ${NC} : ${WHITE}%s${NC}\n" "$title"
    if [[ -n "$device_arg" ]]; then
        printf " ${CYAN}DEVICE ${NC} : ${WHITE}%s${NC}\n" "${device_arg:-Not selected}"
    fi
    if [[ -n "$report_arg" ]]; then
        printf " ${CYAN}REPORT ${NC} : ${WHITE}%s${NC}\n" "${report_arg:-None}"
    fi
    echo "${CYAN}${line}${NC}"
}

draw_menu_footer() {
    local status="${1:-Awaiting analyst command...}"
    local line
    line=$(ui_line "$UI_H1")
    echo "${CYAN}${line}${NC}"
    printf " ${CYAN}STATUS${NC} : ${WHITE}%s${NC}\n" "$status"
    echo "${CYAN}$(ui_line "$UI_H2")${NC}"
}
