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
    MAGENTA=$(tput setaf 5)
    CYAN=$(tput setaf 6)
    WHITE=$(tput setaf 7)
    GRAY=$(tput setaf 8)

    BOLD=$(tput bold)
    UNDERLINE=$(tput smul)
    RESET_UNDERLINE=$(tput rmul)
    NC=$(tput sgr0)  # reset
else
    # Fallback ANSI escape sequences
    RED="\033[0;31m"
    GREEN="\033[0;32m"
    YELLOW="\033[1;33m"
    BLUE="\033[0;34m"
    MAGENTA="\033[0;35m"
    CYAN="\033[0;36m"
    WHITE="\033[1;37m"
    GRAY="\033[0;90m"

    BOLD="\033[1m"
    UNDERLINE="\033[4m"
    RESET_UNDERLINE="\033[24m"
    NC="\033[0m"
fi
