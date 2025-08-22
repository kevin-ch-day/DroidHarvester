#!/usr/bin/env bash
# ---------------------------------------------------
# make_executable.sh - Ensure all .sh files in this
# project (and child dirs) are executable
# ---------------------------------------------------

set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR

# Colors
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}Scanning for .sh files in: $PROJECT_DIR${NC}"

count=0
changed=0

# Use a safer loop instead of mapfile to avoid errors when no matches
while IFS= read -r -d '' file; do
    ((count++))
    if [[ ! -x "$file" ]]; then
        chmod +x "$file"
        echo -e "${GREEN}Made executable:${NC} $file"
        ((changed++))
    else
        echo -e "${BLUE}Already executable:${NC} $file"
    fi
done < <(find "$PROJECT_DIR" -type f -name "*.sh" -print0)

if [[ $count -eq 0 ]]; then
    echo -e "${YELLOW}No .sh files found in $PROJECT_DIR${NC}"
    exit 0
fi

echo -e "\n${BLUE}========= Summary =========${NC}"
echo "Total .sh files found: $count"
echo "Files updated       : $changed"
echo -e "${BLUE}===========================${NC}\n"
