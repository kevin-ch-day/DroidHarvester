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
    local f_col="$YELLOW" p_col="$YELLOW"
    (( PKGS_FOUND > 0 )) && f_col="$GREEN"
    (( PKGS_PULLED > 0 )) && p_col="$GREEN"
    printf " ${WHITE}Harvested${NC}: found %s%s%s / pulled %s%s%s | Targets: ${CYAN}%s${NC} default / ${CYAN}%s${NC} custom | Latest: %s\n" \
        "$f_col" "${PKGS_FOUND:-0}" "$NC" "$p_col" "${PKGS_PULLED:-0}" "$NC" "${#TARGET_PACKAGES[@]}" "$custom_count" "${QUICK_PULL_DIR:-n/a}"
    echo
    show_menu \
        "Choose device" \
        "Scan for target apps" \
        "" \
        "Add custom package" \
        "Quick APK Harvest" \
        "Show latest quick-pull" \
        "Harvest APKs + metadata" \
        "" \
        "View last report" \
        "List ALL installed apps" \
        "Search installed apps" \
        "Device capability report" \
        "Export report bundle" \
        "Resume last session" \
        "Clean up partial run" \
        "Clear logs/results"
}
