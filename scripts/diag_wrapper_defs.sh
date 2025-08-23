#!/usr/bin/env bash
# ---------------------------------------------------
# diag_wrapper_defs.sh - verify wrapper functions are loaded
# Fedora/Linux. Plain ASCII. Run from scripts/: ./diag_wrapper_defs.sh
# ---------------------------------------------------
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND" >&2' ERR

usage() {
  cat <<'EOF'
Usage: ./diag_wrapper_defs.sh [-h|--help]

Checks whether key wrapper functions are present in the current shell
(before and after sourcing shared libs), and shows where they are defined
in the codebase.

Functions checked:
  with_timeout, adb_retry, pm_path, with_trace, adb_test, adb_pull
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage; exit 0
fi

# Resolve repo root from scripts/
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

LOG_DIR="$REPO_ROOT/logs"
mkdir -p "$LOG_DIR"
TS="$(date +%Y%m%d_%H%M%S)"
TRANSCRIPT="$LOG_DIR/wrappers_diag_${TS}.txt"

echo "Transcript: $TRANSCRIPT"
echo "Repo root : $REPO_ROOT"
echo "--------------------------------------------------" | tee -a "$TRANSCRIPT"

# List of wrapper functions we expect to exist after sourcing
FUNCS=(with_timeout adb_retry pm_path with_trace adb_test adb_pull)

print_set() {
  local label="$1"
  echo "== $label ==" | tee -a "$TRANSCRIPT"
  local missing=0
  for f in "${FUNCS[@]}"; do
    if type -t "$f" >/dev/null 2>&1; then
      printf "present : %s\n" "$f" | tee -a "$TRANSCRIPT"
    else
      printf "MISSING : %s\n" "$f" | tee -a "$TRANSCRIPT"
      ((missing++))
    fi
  done
  echo "missing  : $missing" | tee -a "$TRANSCRIPT"
  echo "--------------------------------------------------" | tee -a "$TRANSCRIPT"
  return "$missing"
}

# A) BEFORE sourcing libs
print_set "Before sourcing libs" || true

# B) Source config and likely providers of these wrappers
# shellcheck disable=SC1090
source "$REPO_ROOT/config.sh" || true

# shellcheck disable=SC1090
source "$REPO_ROOT/lib/core/logging.sh"  || true
# shellcheck disable=SC1090
source "$REPO_ROOT/lib/core/errors.sh"   || true
# shellcheck disable=SC1090
source "$REPO_ROOT/lib/core/deps.sh"     || true

# Wrappers & adb helpers are typically here:
# shellcheck disable=SC1090
source "$REPO_ROOT/lib/core/trace.sh"    || true
# shellcheck disable=SC1090
source "$REPO_ROOT/lib/core/device.sh"   || true

# apk_utils may reference those wrappers
# shellcheck disable=SC1090
source "$REPO_ROOT/lib/io/apk_utils.sh"  || true

# C) AFTER sourcing libs
if print_set "After sourcing libs"; then
  MISSING_AFTER=$?
else
  MISSING_AFTER=$?
fi

# D) Where are they defined?
echo "== Definition locations (grep) ==" | tee -a "$TRANSCRIPT"
grep -R --line-number -E '^(with_timeout|adb_retry|pm_path|with_trace|adb_test|adb_pull)\s*\(\)' lib \
  | tee -a "$TRANSCRIPT" || true
echo "--------------------------------------------------" | tee -a "$TRANSCRIPT"

if (( MISSING_AFTER > 0 )); then
  echo "Some functions are still missing after sourcing libs (count=$MISSING_AFTER)." | tee -a "$TRANSCRIPT"
  echo "Check that the defining file(s) above are being sourced before users like lib/io/apk_utils.sh." | tee -a "$TRANSCRIPT"
fi

# Exit with the number of missing functions after sourcing (0 = all good)
exit "$MISSING_AFTER"
