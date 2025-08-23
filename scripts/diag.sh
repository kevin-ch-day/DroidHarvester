#!/usr/bin/env bash
# ---------------------------------------------------
# diag.sh - unified diagnostics entry point
# ---------------------------------------------------
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND" >&2' ERR

usage() {
  cat <<USAGE
Usage: $0 <subcmd> [--device ID] [--pkg NAME] [--limit N] [--pull] [--debug]
Subcommands:
  health   # ADB/device sanity
  paths    # get_apk_paths isolation
  pull     # staged pull check
  peek     # inspect latest pull diag
  all      # health -> paths -> pull -> peek
USAGE
}

[[ $# -lt 1 ]] && { usage; exit 64; }
SUBCMD="$1"; shift
DEVICE=""
PKG="com.zhiliaoapp.musically"
LIMIT=5
PULL=0
LOG_LEVEL="${LOG_LEVEL:-INFO}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="${2:-}"; shift 2;;
    --pkg)    PKG="${2:-}"; shift 2;;
    --limit)  LIMIT="${2:-}"; shift 2;;
    --pull)   PULL=1; shift;;
    --debug)  LOG_LEVEL=DEBUG; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage; exit 64;;
  esac
done
export LOG_LEVEL

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
LOG_DIR="$REPO_ROOT/logs"; mkdir -p "$LOG_DIR"

# shellcheck disable=SC1090
source "$REPO_ROOT/config.sh"
# shellcheck disable=SC1090
for m in core/logging core/errors core/deps core/device core/trace io/report; do
  source "$REPO_ROOT/lib/$m.sh"
done
validate_config

DEVICE="$(device_pick_or_fail "$DEVICE")"

cmd_health() {
  local log="$LOG_DIR/adb_health_$(date +%Y%m%d_%H%M%S).txt"
  log_file_init "$log"
  run_step() {
    local title="$1"; shift
    log INFO "$title"
    set +e
    "$@" 2>&1 | tee -a "$log"
    local rc=${PIPESTATUS[0]}
    set -e
    log INFO "exit=$rc"
    echo "--------------------------------------------------" | tee -a "$log"
  }
  run_step "adb version" bash -c 'adb version | head -n 3'
  run_step "adb get-state" adbq "$DEVICE" get-state
  run_step "adb shell echo OK" adbq "$DEVICE" shell echo OK
  run_step "adb shell id; whoami; getprop" adbq "$DEVICE" shell 'id; whoami; getprop ro.build.version.release'
}

cmd_paths() {
  local ts
  ts=$(date +%Y%m%d_%H%M%S)
  local base="paths_diag_${ts}_$(echo "$PKG" | tr '.' '_')"
  local out="$LOG_DIR/${base}.out"
  local err="$LOG_DIR/${base}.err"
  local sum="$LOG_DIR/${base}.summary.txt"
  set +e
  DEVICE="$DEVICE" LOGFILE="$LOGFILE" bash "$REPO_ROOT/steps/generate_apk_list.sh" "$PKG" >"$out" 2>"$err"
  local rc=$?
  set -e
  {
    echo "RAW pm path (first 20):"
    adb -s "$DEVICE" shell pm path "$PKG" | sed -n '1,20p' || true
    echo "==== OUT (first 40) ===="
    nl -ba "$out" | sed -n '1,40p'
    echo "==== ERR (first 40) ===="
    sed -n '1,40p' "$err"
    echo "==== NON-PATH lines ===="
    if grep -vE '^/.+\.apk$' "$out" >/dev/null 2>&1; then
      grep -vE '^/.+\.apk$' "$out" | sed -n '1,40p'
    else
      echo "(none)"
    fi
    echo "==== OUT endings ===="
    sed -n 'l' "$out" | sed -n '1,40p'
    echo "==== VERIFY PATHS (limit $LIMIT) ===="
    local checked=0 ok=0 fail=0
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      ((checked++))
      if adbq "$DEVICE" shell ls -l "$p" >/dev/null 2>&1; then
        ((ok++)); echo "ok   : $p"
      else
        ((fail++)); echo "fail : $p"
      fi
      (( checked >= LIMIT )) && break
    done < "$out"
    echo "Totals: rc_get_apk_paths=$rc checked=$checked ok=$ok fail=$fail"
  } | tee "$sum"
}

cmd_pull() {
  local ts
  ts=$(date +%Y%m%d_%H%M%S)
  local base="pull_diag_${ts}_$(echo "$PKG" | tr '.' '_')"
  local out="$LOG_DIR/${base}.out"
  local err="$LOG_DIR/${base}.err"
  local sum="$LOG_DIR/${base}.summary.txt"
  set +e
  DEVICE="$DEVICE" LOGFILE="$LOGFILE" bash "$REPO_ROOT/steps/generate_apk_list.sh" "$PKG" >"$out" 2>"$err"
  set -e
  local stage="$REPO_ROOT/results/$DEVICE/debug_pull_${ts}"
  mkdir -p "$stage"
  local checked=0 ok=0 fail=0
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    ((checked++))
    if adbq "$DEVICE" shell ls -l "$p" >/dev/null 2>&1; then
      ((ok++))
      if (( PULL == 1 )); then
        adb -s "$DEVICE" pull "$p" "$stage/" >/dev/null 2>&1 || ((fail++))
      fi
    else
      ((fail++))
    fi
    (( checked >= LIMIT )) && break
  done < "$out"
  {
    echo "stage=$stage"
    echo "checked=$checked ok=$ok fail=$fail"
  } | tee "$sum"
}

cmd_peek() {
  local pkg_esc="${PKG//./_}"
  local sum
  sum=$(ls -1t "$LOG_DIR"/pull_diag_*_${pkg_esc}.summary.txt 2>/dev/null | head -n1 || true)
  if [[ -z "$sum" ]]; then
    echo "No pull diag found for $PKG"; return 0
  fi
  local prefix="${sum%.summary.txt}"
  echo "OUT=${prefix}.out"
  echo "ERR=${prefix}.err"
  echo "SUMMARY=$sum"
  [[ -f ${prefix}.err ]] && { echo "--- ERR (first 40) ---"; sed -n '1,40p' "${prefix}.err"; }
  [[ -f ${prefix}.out ]] && { echo "--- OUT (first 40) ---"; sed -n '1,40p' "${prefix}.out"; echo "--- OUT endings ---"; sed -n 'l' "${prefix}.out" | sed -n '1,40p'; }
  [[ -f $sum ]] && { echo "--- SUMMARY (first 40) ---"; sed -n '1,40p' "$sum"; }
}

cmd_all() {
  cmd_health
  cmd_paths
  cmd_pull
  cmd_peek
  echo "All diagnostics complete"
}

case "$SUBCMD" in
  health) cmd_health ;;
  paths)  cmd_paths ;;
  pull)   cmd_pull ;;
  peek)   cmd_peek ;;
  all)    cmd_all ;;
  *) usage; exit 64 ;;
esac
