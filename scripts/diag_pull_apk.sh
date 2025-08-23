#!/usr/bin/env bash
# ---------------------------------------------------
# diag_pull_apk.sh - exercise get_apk_paths() and pull a few APKs
# Fedora/Linux only. Plain ASCII. Logs go to repo-root logs/.
# ---------------------------------------------------
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND" >&2' ERR

# --- repo root & logs dir ---
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
LOG_DIR="$REPO_ROOT/logs"
mkdir -p "$LOG_DIR"

# --- shared config + libs (no menu) ---
# shellcheck disable=SC1090
source "$REPO_ROOT/config.sh"
for m in core/logging core/errors core/deps core/device io/apk_utils; do
  # shellcheck disable=SC1090
  source "$REPO_ROOT/lib/$m.sh"
done

# --- defaults (no args required) ---
DEVICE=""
PKG="${PKG:-com.zhiliaoapp.musically}"
LIMIT="${LIMIT:-3}"
LOG_LEVEL="${LOG_LEVEL:-DEBUG}"   # be chatty for diagnostics

# Optional overrides
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="${2:-}"; shift 2 ;;
    --pkg)    PKG="${2:-}";    shift 2 ;;
    --limit)  LIMIT="${2:-}";  shift 2 ;;
    --debug)  LOG_LEVEL=DEBUG; shift ;;
    -h|--help)
      cat <<EOF
Usage: ./diag_pull_apk.sh [--device ID] [--pkg PACKAGE] [--limit N] [--debug]
Defaults: PACKAGE=$PKG  LIMIT=$LIMIT
EOF
      exit 0
      ;;
    *) die "$E_USAGE" "Unknown option: $1" ;;
  esac
done
export LOG_LEVEL

# --- deps ---
require_all adb awk sed grep stat sha256sum du df

# --- device pick & announce ---
DEVICE="$(device_pick_or_fail "$DEVICE")"
export DEVICE
TS="$(date +%Y%m%d_%H%M%S)"

base_id="pull_diag_${TS}_$(echo "$PKG" | tr '.' '_' )"
SUMMARY_FILE="$LOG_DIR/${base_id}.summary.txt"
STDOUT_FILE="$LOG_DIR/${base_id}.out"
STDERR_FILE="$LOG_DIR/${base_id}.err"

log_file_init "$SUMMARY_FILE"
log INFO "Device   : $DEVICE"
log INFO "Package  : $PKG"
log INFO "Limit    : $LIMIT"
log INFO "Summary  : $SUMMARY_FILE"
log INFO "stdout   : $STDOUT_FILE"
log INFO "stderr   : $STDERR_FILE"
echo "--------------------------------------------------" | tee -a "$SUMMARY_FILE"

# --- quick context ---
adb version | sed -n '1,3p' | tee -a "$SUMMARY_FILE"
echo "--------------------------------------------------" | tee -a "$SUMMARY_FILE"
echo "Android release:" | tee -a "$SUMMARY_FILE"
adb -s "$DEVICE" shell getprop ro.build.version.release | tee -a "$SUMMARY_FILE"
echo "--------------------------------------------------" | tee -a "$SUMMARY_FILE"

# --- discover paths (reuse the same seam as harvester) ---
set +e
get_apk_paths "$PKG" >"$STDOUT_FILE" 2>"$STDERR_FILE"
rc_paths=$?
set -e

echo "RAW pm path (first 20):" | tee -a "$SUMMARY_FILE"
adb -s "$DEVICE" shell pm path "$PKG" | sed -n '1,20p' | tee -a "$SUMMARY_FILE"
echo "--------------------------------------------------" | tee -a "$SUMMARY_FILE"

if (( rc_paths != 0 )); then
  log WARN "get_apk_paths returned rc=$rc_paths (continuing for analysis)"
fi

# Check for contamination
if grep -vE '^/' "$STDOUT_FILE" >/dev/null 2>&1; then
  log WARN "Non-path lines leaked into STDOUT:"
  grep -vE '^/' "$STDOUT_FILE" | sed -n '1,40p' | tee -a "$SUMMARY_FILE"
fi

# --- prepare local staging ---
STAGE_DIR="$REPO_ROOT/results/$DEVICE/debug_pull_${TS}"
mkdir -p "$STAGE_DIR"
log INFO "Staging dir: $STAGE_DIR"

# --- disk headroom (host) ---
host_df=$(df -h "$REPO_ROOT" | sed -n '2p')
echo "Host df: $host_df" | tee -a "$SUMMARY_FILE"

# --- iterate a few paths, verify existence, then pull ---
checked=0; ok=0; fail=0
echo "---- Begin per-path checks (max $LIMIT) ----" | tee -a "$SUMMARY_FILE"

while IFS= read -r ap; do
  [[ -z "$ap" ]] && continue
  ((checked++))
  echo "Path #$checked: $ap" | tee -a "$SUMMARY_FILE"

  # exists?
  if adb -s "$DEVICE" shell ls -l "$ap" >/dev/null 2>&1; then
    echo "  remote: exists" | tee -a "$SUMMARY_FILE"
  else
    echo "  remote: MISSING (ls failed)" | tee -a "$SUMMARY_FILE"
    ((fail++))
    (( checked >= LIMIT )) && break || continue
  fi

  # remote size (best-effort)
  rsize="$(adb -s "$DEVICE" shell 'toybox stat -c %s '"$ap"' 2>/dev/null || stat -c %s '"$ap"' 2>/dev/null || wc -c < '"$ap"' 2>/dev/null' || true)"
  [[ -n "${rsize//[[:space:]]/}" ]] && echo "  remote_size: $rsize bytes" | tee -a "$SUMMARY_FILE"

  # attempt pull
  bname="$(basename "$ap")"
  out="$STAGE_DIR/$bname"
  # capture stderr to inspect for Permission denied, etc.
  pull_err="$LOG_DIR/${base_id}_pull_${checked}.err"
  set +e
  adb -s "$DEVICE" pull -p "$ap" "$out" 1>>"$SUMMARY_FILE" 2>"$pull_err"
  rc_pull=$?
  set -e

  if (( rc_pull == 0 )) && [[ -s "$out" ]]; then
    lsize="$(stat -c %s "$out" 2>/dev/null || echo 0)"
    sha="$(sha256sum "$out" | awk '{print $1}')"
    echo "  local: $out" | tee -a "$SUMMARY_FILE"
    echo "  local_size: $lsize bytes" | tee -a "$SUMMARY_FILE"
    echo "  sha256: $sha" | tee -a "$SUMMARY_FILE"
    [[ -n "${rsize//[[:space:]]/}" && "$lsize" != "$rsize" ]] && echo "  WARN: size mismatch (remote $rsize, local $lsize)" | tee -a "$SUMMARY_FILE"
    ((ok++))
  else
    echo "  PULL FAILED (rc=$rc_pull). stderr in: $pull_err" | tee -a "$SUMMARY_FILE"
    if grep -Ei 'denied|permission|not permitted|read-only|no such file' "$pull_err" -n | sed -n '1,3p' | tee -a "$SUMMARY_FILE" ; then true; fi
    ((fail++))
  fi

  echo "--------------------------------------------------" | tee -a "$SUMMARY_FILE"
  (( checked >= LIMIT )) && break || true
done < "$STDOUT_FILE"

echo "Result: checked=$checked ok=$ok fail=$fail" | tee -a "$SUMMARY_FILE"
echo "Pulled files (if any) in: $STAGE_DIR" | tee -a "$SUMMARY_FILE"
echo "Done. See also:" | tee -a "$SUMMARY_FILE"
echo "  $STDOUT_FILE (paths)" | tee -a "$SUMMARY_FILE"
echo "  $STDERR_FILE (logs)"  | tee -a "$SUMMARY_FILE"
exit 0
