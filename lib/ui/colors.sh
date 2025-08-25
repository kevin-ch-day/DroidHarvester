#!/usr/bin/env bash
# shellcheck disable=SC2034
# ---------------------------------------------------
# lib/ui/colors.sh - High contrast palette & helpers
# ---------------------------------------------------
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR

: "${DH_THEME:=dark-hi}"

# Disable colors for NO_COLOR=1 or DH_THEME=mono
if [[ "${NO_COLOR-}" == "1" || "$DH_THEME" == "mono" ]]; then
    RED=""; GREEN=""; YELLOW=""; CYAN=""; WHITE=""; GRAY=""; BLUE=""; NC=""
else
    if tput setaf 1 >/dev/null 2>&1; then
        RED=$(tput setaf 9)
        GREEN=$(tput setaf 10)
        YELLOW=$(tput setaf 11)
        CYAN=$(tput setaf 14)
        WHITE=$(tput setaf 15)
        GRAY=$(tput setaf 8)
        BLUE="$CYAN"
        NC=$(tput sgr0)
    else
        RED="\033[1;31m"
        GREEN="\033[1;32m"
        YELLOW="\033[1;33m"
        CYAN="\033[1;36m"
        WHITE="\033[1;37m"
        GRAY="\033[0;90m"
        BLUE="$CYAN"
        NC="\033[0m"
    fi
fi

# Line characters (unicode default with ASCII fallback)
if [[ "${DH_NO_UNICODE:-0}" == "1" ]]; then
    UI_H1="-"
    UI_H2="="
else
    UI_H1="─"
    UI_H2="═"
fi

# Draw a horizontal line of given char and width (default 70)
ui_line() {
    local char="${1:-$UI_H1}" width="${2:-70}"
    local out=""
    for ((i=0; i<width; i++)); do
        out+="$char"
    done
    printf '%s' "$out"
}
