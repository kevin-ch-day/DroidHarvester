#!/usr/bin/env bash
set -eo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
LOG_DIR="$REPO_ROOT/logs"; mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/wrappers_selftest_$(date +%Y%m%d_%H%M%S).txt"

# shellcheck disable=SC1090
source "$REPO_ROOT/config.sh"
# shellcheck disable=SC1090
for m in core/logging core/errors core/deps core/device core/trace; do
  source "$REPO_ROOT/lib/$m.sh"
done
validate_config
trap - ERR

pass=0; fail=0
report() { if [[ $1 -eq $2 ]]; then echo "PASS $3"; ((pass++)); else echo "FAIL $3 (rc=$1 expected=$2)"; ((fail++)); fi }

{
  echo "Static wrapper selftest";
  echo "----------------------------------------";

  set +e
  with_timeout 1 wt_label -- bash -c 'exit 42'; rc=$?; report $rc 42 "with_timeout rc"
  with_trace wt_label -- bash -c 'exit 7'; rc=$?; report $rc 7 "with_trace rc"
  adb_retry 1 0 ar_label -- bash -c 'exit 9'; rc=$?; report $rc 9 "adb_retry rc"

  with_timeout 1 to_label -- bash -c 'sleep 2'; rc=$?; report $rc 124 "with_timeout timeout"
  out=$(with_trace "echo SHOULD_NOT" -- true 2>&1); report $(grep -q SHOULD_NOT <<<"$out"; echo $?) 1 "label not executed"
  set -e

  echo "----------------------------------------";
  echo "pass=$pass fail=$fail";
  exit $fail
} | tee "$LOG_FILE"
