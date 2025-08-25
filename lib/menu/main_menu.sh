#!/usr/bin/env bash
set -euo pipefail
# ---------------------------------------------------
# main_menu.sh - Render the primary DroidHarvester menu
# ---------------------------------------------------

# shellcheck disable=SC1090
source "$REPO_ROOT/lib/ui/colors.sh"

render_main_menu() {
    local title="$1" device="$2" last_report="$3"

    local custom_count=0
    if declare -p CUSTOM_PACKAGES >/dev/null 2>&1; then
        set +u
        custom_count=${#CUSTOM_PACKAGES[@]}
        set -u
    fi

    draw_menu_header "$title" "$device" "$last_report"
    echo " Harvested   : found ${PKGS_FOUND:-0} pulled ${PKGS_PULLED:-0}"
    echo " Targets     : ${#TARGET_PACKAGES[@]} default / ${custom_count} custom"

    echo
    local options=(
        "Choose device"
        "Scan for target apps"
        "Add custom package"
        "Quick APK Harvest"
        "Harvest APKs + metadata"
        "View last report"
        "List ALL installed apps"
        "Search installed apps"
        "Device capability report"
        "Export report bundle"
        "Resume last session"
        "Clean up partial run"
        "Clear logs/results"
    )
    local i=1
    for opt in "${options[@]}"; do
        printf "  ${BLUE}[%2d]${NC} %s\n" "$i" "$opt"
        ((i++))
    done
    printf "  ${BLUE}[ 0]${NC} Exit\n"
    echo "${CYAN}------------------------------------------------------------${NC}"
}
