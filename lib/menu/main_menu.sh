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
    printf " ${WHITE}Harvested${NC}: found ${YELLOW}%s${NC} / pulled ${YELLOW}%s${NC} | Targets: ${YELLOW}%s${NC} default / ${YELLOW}%s${NC} custom | Latest: %s\n" \
        "${PKGS_FOUND:-0}" "${PKGS_PULLED:-0}" "${#TARGET_PACKAGES[@]}" "$custom_count" "${QUICK_PULL_DIR:-n/a}"
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
