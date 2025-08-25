#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND" >&2' ERR
# ---------------------------------------------------
# static_check.sh - Static analysis for shell scripts
# ---------------------------------------------------

E_DEPS=2

REPO_ROOT="$(cd "
$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

LOG_DIR="$REPO_ROOT/log"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/static_check_$(date +%Y%m%d_%H%M%S).txt"

echo "Static analysis log: $LOG_FILE"

ok=0

echo "== bash -n ==" | tee "$LOG_FILE"
# Syntax check all .sh files
if ! find . -name '*.sh' -print0 | xargs -0 -n1 bash -n | tee -a "$LOG_FILE"; then
  ok=1
fi

echo "== shellcheck ==" | tee -a "$LOG_FILE"
if command -v shellcheck >/dev/null 2>&1; then
  if ! find lib scripts -name '*.sh' -print0 | xargs -0 shellcheck | tee -a "$LOG_FILE"; then
    ok=1
  fi
else
  echo "shellcheck not found. On Fedora: sudo dnf install -y ShellCheck" | tee -a "$LOG_FILE"
  exit $E_DEPS
fi

exit $ok
