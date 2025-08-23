#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# find_latest.sh - find-based helper to locate latest report
# ---------------------------------------------------

latest_report() {
    find "$RESULTS_DIR" -maxdepth 1 -type f -name 'apks_report_*.txt' -print0 \
        | xargs -0 stat --printf '%Y\t%n\0' 2>/dev/null \
        | sort -z -nr \
        | tr '\0' '\n' \
        | head -n1 \
        | cut -f2- || true
}
