#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND" >&2' ERR
# ---------------------------------------------------
# static_check.sh - Static analysis for shell scripts
# ---------------------------------------------------

E_DEPS=2

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

: "${LOG_ROOT:="$REPO_ROOT/logs"}"
# shellcheck disable=SC2034
LOG_DIR="$LOG_ROOT"  # Backwards compatibility
mkdir -p "$LOG_ROOT"
LOG_FILE="$LOG_ROOT/static_check_$(date +%Y%m%d_%H%M%S).txt"

echo "Static analysis log: $LOG_FILE"

ok=0

# Run bash -n quietly across the repo (excluding .git) and count failures
if find . -path './.git' -prune -o -name '*.sh' -print0 |
  xargs -0 -n1 bash -n >>"$LOG_FILE" 2>&1; then
  echo "bash -n: OK" | tee -a "$LOG_FILE"
else
  echo "bash -n: issues detected" | tee -a "$LOG_FILE"
  ok=1
fi

# Run shellcheck across the repo, ignoring noisy warnings, and summarize
SHELLCHECK_EXCLUDES=${SHELLCHECK_EXCLUDES:-SC1090,SC1091}
if command -v shellcheck >/dev/null 2>&1; then
  find . -path './.git' -prune -o -name '*.sh' -print0 |
    xargs -0 shellcheck --format=gcc -e "$SHELLCHECK_EXCLUDES" >"$LOG_FILE.shellcheck" 2>&1 || true
  issue_count=$(wc -l <"$LOG_FILE.shellcheck")
  if (( issue_count > 0 )); then
    echo "shellcheck: ${issue_count} issues" | tee -a "$LOG_FILE"
    awk -F: '{print $1}' "$LOG_FILE.shellcheck" | sort | uniq -c | sort -nr | head -n 5 |
      awk '{printf "  %s issues in %s\n", $1, $2}' | tee -a "$LOG_FILE"
    ok=1
  else
    echo "shellcheck: OK" | tee -a "$LOG_FILE"
  fi
  cat "$LOG_FILE.shellcheck" >>"$LOG_FILE"
  rm -f "$LOG_FILE.shellcheck"
else
  echo "shellcheck not found. On Fedora: sudo dnf install -y ShellCheck" | tee -a "$LOG_FILE"
  exit $E_DEPS
fi

echo "Summary written to $LOG_FILE"
exit $ok
