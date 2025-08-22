#!/usr/bin/env bash
# shellcheck disable=SC2034
set -euo pipefail
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# lib/colors.sh
# Centralized color/format definitions
# ---------------------------------------------------

if tput setaf 1 >/dev/null 2>&1; then
    # Use tput for portability
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    CYAN=$(tput setaf 6)
    NC=$(tput sgr0)  # reset
else
    # Fallback ANSI escape sequences
    RED="\033[0;31m"
    GREEN="\033[0;32m"
    YELLOW="\033[1;33m"
    BLUE="\033[0;34m"
    CYAN="\033[0;36m"
    NC="\033[0m"
fi
