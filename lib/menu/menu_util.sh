#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# menu_util.sh - Shared Menu Utilities for DroidHarvester
# ---------------------------------------------------
# Provides reusable functions for structured, analyst-grade menus,
# validated input, and confirmation prompts. Designed for clarity
# in SOC-style environments where precision matters.
# ---------------------------------------------------

# shellcheck disable=SC1090
source "$REPO_ROOT/lib/ui/colors.sh"

# ---------------------------------------------------
# Show Menu Options (Numbered, Structured)
# Usage: show_menu "Option 1" "Option 2" ...
# ---------------------------------------------------
show_menu() {
    local i=1
    echo
    for option in "$@"; do
        printf "  ${BLUE}[%2d]${NC} %s\n" "$i" "$option"
        ((i++))
    done
    echo "${CYAN}------------------------------------------------------------${NC}"
}

# ---------------------------------------------------
# Read Choice with Validation
# Usage: choice=$(read_choice <num_options>)
#        choice=$(read_choice_range <min> <max>)
# ---------------------------------------------------
read_choice_range() {
    local min="$1" max="$2" choice
    while true; do
        read -rp "Enter selection [$min-$max]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= min && choice <= max )); then
            echo "$choice"
            return
        fi
        if command -v log >/dev/null 2>&1; then
            log WARN "Invalid input. Enter a number between $min and $max." || true
        else
            echo "[WARN] Invalid input. Enter a number between $min and $max." >&2
        fi
    done
}

read_choice() {
    local max="$1"
    read_choice_range 1 "$max"
}

# ---------------------------------------------------
# Pause until analyst acknowledges
# ---------------------------------------------------
pause() {
    echo
    read -rp "Press ENTER to continue..." _
}

# ---------------------------------------------------
# Confirmation Prompt (Y/n)
# Usage: if confirm "Proceed with action?"; then ...
# ---------------------------------------------------
confirm() {
    local prompt="$1"
    echo
    read -rp "WARNING: $prompt [y/N]: " ans
    case "$ans" in
        [Yy]*) return 0 ;;
        *)     return 1 ;;
    esac
}

