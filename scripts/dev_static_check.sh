#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND" >&2' ERR

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
LOG_DIR="$REPO_ROOT/logs"
mkdir -p "$LOG_DIR"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="$LOG_DIR/static_check_${TS}.txt"

ok=0
find . -name '*.sh' -print0 | xargs -0 bash -n >"$OUT" 2>&1 || ok=1
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck lib/**/*.sh scripts/*.sh >>"$OUT" 2>&1 || ok=1
else
  echo "shellcheck not found. On Fedora: sudo dnf install -y shellcheck" >>"$OUT"
fi
cat "$OUT"
exit $ok
