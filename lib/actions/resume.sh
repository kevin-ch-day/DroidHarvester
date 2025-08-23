#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# resume.sh - resume last session
# ---------------------------------------------------

resume_last_session() {
    local last_dev
    last_dev=$(find "$RESULTS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 \
        | xargs -0 stat --printf '%Y\t%n\0' 2>/dev/null \
        | sort -z -nr \
        | head -z -n1 \
        | cut -f2- \
        | tr -d '\0')
    if [[ -z "$last_dev" ]]; then
        log WARN "No previous session found."
        return
    fi
    DEVICE=$(basename "$last_dev")
    DEVICE_DIR="$last_dev"
    init_report
    log SUCCESS "Resumed device: $DEVICE"
}
