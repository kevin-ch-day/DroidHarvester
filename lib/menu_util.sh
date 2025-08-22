#!/bin/bash
# ---------------------------------------------------
# menu_util.sh - Shared Menu Utilities for DroidHarvester
# ---------------------------------------------------
# Provides reusable functions for structured, analyst-grade menus,
# validated input, and confirmation prompts. Designed for clarity
# in SOC-style environments where precision matters.
# ---------------------------------------------------

source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/logging.sh"

# ---------------------------------------------------
# Draw Menu Header
# ---------------------------------------------------
draw_menu_header() {
    local title="$1"
    echo
    echo "============================================================"
    printf " %-58s\n" "DROIDHARVESTER // ANALYST CONTROL INTERFACE"
    echo "------------------------------------------------------------"
    printf " %-58s\n" "SESSION : $(date '+%Y-%m-%d %H:%M:%S')"
    printf " %-58s\n" "MODULE  : $title"
    echo "============================================================"
}

# ---------------------------------------------------
# Show Menu Options (Numbered, Structured)
# Usage: show_menu "Option 1" "Option 2" ...
# ---------------------------------------------------
show_menu() {
    local i=1
    echo
    for option in "$@"; do
        printf "   [%2d] %-50s\n" "$i" "$option"
        ((i++))
    done
    echo "------------------------------------------------------------"
}

# ---------------------------------------------------
# Read Choice with Validation
# Usage: choice=$(read_choice <num_options>)
# ---------------------------------------------------
read_choice() {
    local max="$1"
    local choice

    while true; do
        read -rp "➤  Enter selection [1-$max]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=max )); then
            echo "$choice"
            return
        else
            log WARN "Invalid input. Enter a number between 1 and $max."
        fi
    done
}

# ---------------------------------------------------
# Pause until analyst acknowledges
# ---------------------------------------------------
pause() {
    echo
    read -rp "⏸  Press ENTER to continue..." _
}

# ---------------------------------------------------
# Confirmation Prompt (Y/n)
# Usage: if confirm "Proceed with action?"; then ...
# ---------------------------------------------------
confirm() {
    local prompt="$1"
    echo
    read -rp "⚠️  $prompt [y/N]: " ans
    case "$ans" in
        [Yy]*) return 0 ;;
        *)     return 1 ;;
    esac
}

# ---------------------------------------------------
# Menu Footer (Optional Status Line)
# Accepts optional STATUS string, otherwise defaults.
# ---------------------------------------------------
draw_menu_footer() {
    local status="${1:-Awaiting analyst command...}"
    echo "------------------------------------------------------------"
    printf " %-58s\n" "STATUS : $status"
    echo "============================================================"
}
