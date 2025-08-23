#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND" >&2' ERR

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
LOG_DIR="$REPO_ROOT/logs"
mkdir -p "$LOG_DIR"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="$LOG_DIR/wrappers_selftest_${TS}.txt"
LOG_LEVEL=DEBUG
export LOG_LEVEL

for m in core/logging core/errors core/trace core/device; do
  # shellcheck disable=SC1090
  source "$REPO_ROOT/lib/$m.sh"
done
log_file_init "$OUT.log"
trap - ERR

err=0

# with_trace missing --
set +e
with_trace label echo hi >/dev/null 2>&1
rc=$?
set -e
[[ $rc -eq 127 ]] || { echo "with_trace missing -- rc=$rc" >>"$OUT"; err=1; }

# with_trace valid
set +e
with_trace ok -- true >/dev/null 2>&1
rc=$?
set -e
[[ $rc -eq 0 ]] || { echo "with_trace rc=$rc" >>"$OUT"; err=1; }

# with_timeout missing --
set +e
with_timeout 1 label echo hi >/dev/null 2>&1
rc=$?
set -e
[[ $rc -eq 127 ]] || { echo "with_timeout missing -- rc=$rc" >>"$OUT"; err=1; }

# with_timeout timeout
set +e
with_timeout 1 tmo -- sleep 2 >/dev/null 2>&1
rc=$?
set -e
[[ $rc -eq 124 || $rc -eq 137 || $rc -eq 143 ]] || { echo "with_timeout timeout rc=$rc" >>"$OUT"; err=1; }

# adb_retry missing --
set +e
adb_retry 1 0 label echo hi >/dev/null 2>&1
rc=$?
set -e
[[ $rc -eq 127 ]] || { echo "adb_retry missing -- rc=$rc" >>"$OUT"; err=1; }

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
PATH="$TMPDIR:$PATH"
DEVICE="test"
set +e
adb_retry 5 0 retrytest -- get-state >/dev/null 2>>"$OUT.log"
rc=$?
set -e
[[ $rc -eq 0 ]] || { echo "adb_retry did not succeed rc=$rc" >>"$OUT"; err=1; }
if ! grep -q 'attempts=3' "$OUT.log"; then
  echo "adb_retry attempts not logged" >>"$OUT"
  err=1
fi

if (( err )); then
  echo "SELFTEST FAIL" >>"$OUT"
  exit 1
else
  echo "SELFTEST PASS" >>"$OUT"
fi
