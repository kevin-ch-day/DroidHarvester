#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND" >&2' ERR

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
SCRIPT_DIR="$REPO_ROOT"

LOG_DIR="$REPO_ROOT/log"
mkdir -p "$LOG_DIR"

# shellcheck disable=SC1090
source "$REPO_ROOT/config.sh"
for m in core/logging core/errors; do
  # shellcheck disable=SC1090
  source "$REPO_ROOT/lib/$m.sh"
done

usage() {
  cat <<USAGE
Usage: $0 [--debug] [-h|--help] [files...]
USAGE
}

DEVICE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="${2:-}"; shift 2;;
    --debug) LOG_LEVEL=DEBUG; shift;;
    -h|--help) usage; exit 0;;
    *) break;;
  esac
done

FILES=("$@")

LOG_FILE="$LOG_DIR/make_executable_$(date +%Y%m%d_%H%M%S).txt"
log_file_init "$LOG_FILE"

if (( ${#FILES[@]} == 0 )); then
  log WARN "no files specified"
  exit 0
fi

for f in "${FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    die "$E_IO" "File not found: $f"
  fi
  rel=$(realpath --relative-to="$REPO_ROOT" "$f")
  if chmod +x "$f"; then
    log SUCCESS "$rel"
  else
    die "$E_IO" "chmod failed for $f"
  fi
done
