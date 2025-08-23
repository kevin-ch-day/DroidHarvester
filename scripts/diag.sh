#!/usr/bin/env bash
# ---------------------------------------------------
# diag.sh - unified diagnostics entry point
# ---------------------------------------------------
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND" >&2' ERR

usage() {
  cat <<USAGE
Usage: $0 {health|paths|pull|peek|all} [--device ID] [--pkg PKG] [--limit N] [--debug]
USAGE
}

subcmd="${1:-}"; shift || true
if [[ -z "$subcmd" ]]; then
  usage; exit 64
fi

device=""
pkg=""
limit=""
debug=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) device="${2:-}"; shift 2;;
    --pkg)    pkg="${2:-}"; shift 2;;
    --limit)  limit="${2:-}"; shift 2;;
    --debug)  LOG_LEVEL=DEBUG; debug=1; shift;;
    -h|--help) usage; exit 0;;
    *) break;;
  esac
done
export LOG_LEVEL
dbg() { ((debug)) && echo --debug; return 0; }

case "$subcmd" in
  health)
    # shellcheck disable=SC2046
    scripts/diag_adb_health.sh ${device:+--device "$device"} $(dbg)
    ;;
  paths)
    # shellcheck disable=SC2046
    scripts/test_get_apk_paths.sh ${device:+--device "$device"} ${pkg:+--package "$pkg"} $(dbg)
    ;;
  pull)
    # shellcheck disable=SC2046
    scripts/diag_pull_apk.sh ${device:+--device "$device"} ${pkg:+--pkg "$pkg"} ${limit:+--limit "$limit"} $(dbg)
    ;;
  peek)
    scripts/peek_last_pull_diag.sh
    ;;
  all)
    # shellcheck disable=SC2046
    "$0" health ${device:+--device "$device"} $(dbg)
    # shellcheck disable=SC2046
    "$0" paths ${device:+--device "$device"} ${pkg:+--pkg "$pkg"} $(dbg)
    # shellcheck disable=SC2046
    "$0" pull ${device:+--device "$device"} ${pkg:+--pkg "$pkg"} ${limit:+--limit "$limit"} $(dbg)
    "$0" peek
    ;;
  *)
    echo "Unknown subcommand: $subcmd" >&2
    exit 64
    ;;
esac
