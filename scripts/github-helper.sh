#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND" >&2' ERR

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
SCRIPT_DIR="$REPO_ROOT"

LOG_DIR="$REPO_ROOT/logs"
mkdir -p "$LOG_DIR"

# shellcheck disable=SC1090
source "$REPO_ROOT/config.sh"
for m in core/logging core/errors core/deps; do
  # shellcheck disable=SC1090
  source "$REPO_ROOT/lib/$m.sh"
done

usage() {
  cat <<USAGE
Usage: $0 [--debug] [-h|--help]
USAGE
}

DEVICE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="${2:-}"; shift 2;;
    --debug) LOG_LEVEL=DEBUG; shift;;
    -h|--help) usage; exit 0;;
    *) die "$E_USAGE" "Unknown option: $1";;
  esac
done

require git

LOG_FILE="$LOG_DIR/github_helper_$(date +%Y%m%d_%H%M%S).txt"
log_file_init "$LOG_FILE"

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "(unknown)")
upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "(none)")
log INFO "branch=$branch upstream=$upstream"

log INFO "git status"
git -c color.ui=false status --short | tee -a "$LOG_FILE"

log INFO "largest tracked files"
git ls-files -z | xargs -0 du -b 2>/dev/null | sort -nr | head -n 5 | tee -a "$LOG_FILE"

log INFO "recent commits"
git log --oneline --no-color -n 5 | tee -a "$LOG_FILE"
