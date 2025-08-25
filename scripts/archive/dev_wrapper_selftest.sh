#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND" >&2' ERR
# ---------------------------------------------------
# wrappers_selftest.sh - Validate retry/trace wrappers
# ---------------------------------------------------

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

LOG_DIR="$REPO_ROOT/log"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/wrappers_selftest_$(date +%Y%m%d_%H%M%S).txt"

LOG_LEVEL=DEBUG
export LOG_LEVEL

# shellcheck disable=SC1090
for m in core/logging core/errors core/trace core/device; do
  source "$REPO_ROOT/lib/$m.sh"
done
log_file_init "$LOG_FILE.log"
trap - ERR

pass=0; fail=0
report() {
    local rc=$1 expected=$2 label=$3
    if [[ $rc -eq $expected ]]; then
        echo "PASS $label"
        ((pass++))
    else
        echo "FAIL $label (rc=$rc expected=$expected)"
        ((fail++))
    fi
}

{
  echo "Wrapper selftest starting..."
  echo "----------------------------------------"

  # with_trace missing "--"
  set +e
  with_trace badlabel echo hi >/dev/null 2>&1; rc=$?
  set -e
  report $rc 127 "with_trace missing --"

  # with_trace valid
  set +e
  with_trace ok -- true >/dev/null 2>&1; rc=$?
  set -e
  report $rc 0 "with_trace rc"

  # with_timeout missing "--"
  set +e
  with_timeout 1 label echo hi >/dev/null 2>&1; rc=$?
  set -e
  report $rc 127 "with_timeout missing --"

  # with_timeout timeout
  set +e
  with_timeout 1 tmo -- sleep 2 >/dev/null 2>&1; rc=$?
  set -e
  if [[ $rc -eq 124 || $rc -eq 137 || $rc -eq 143 ]]; then
      echo "PASS with_timeout timeout"
      ((pass++))
  else
      echo "FAIL with_timeout timeout (rc=$rc)"
      ((fail++))
  fi

  # adb_retry missing "--"
  set +e
  adb_retry 1 1 0 label echo hi >/dev/null 2>&1; rc=$?
  set -e
  report $rc 127 "adb_retry missing --"

  # adb_retry attempts with fake adb
  TMPDIR="$(mktemp -d)"
  rm -f /tmp/adb_retry_count
  cat > "$TMPDIR/adb" <<'SH'
#!/usr/bin/env bash
f=/tmp/adb_retry_count
c=$(cat "$f" 2>/dev/null || echo 0)
c=$((c+1))
printf %s "$c" >"$f"
[[ $c -lt 3 ]] && exit 1 || exit 0
SH
  chmod +x "$TMPDIR/adb"
  PATH="$TMPDIR:$PATH:$PATH"
  DEVICE="test"
  set +e
  adb_retry 1 5 0 retrytest -- get-state >/dev/null 2>>"$LOG_FILE.log"; rc=$?
  set -e
  report $rc 0 "adb_retry succeeds after retries"
  if ! grep -q 'attempts=3' "$LOG_FILE.log"; then
      echo "FAIL adb_retry attempts not logged"
      ((fail++))
  else
      echo "PASS adb_retry attempts logged"
      ((pass++))
  fi

  echo "----------------------------------------"
  echo "pass=$pass fail=$fail"
  if ((fail > 0)); then
    echo "SELFTEST FAIL"
    exit 1
  else
    echo "SELFTEST PASS"
    exit 0
  fi
} | tee "$LOG_FILE"
