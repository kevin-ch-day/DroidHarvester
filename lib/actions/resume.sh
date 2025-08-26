#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# resume.sh - resume last session
# ---------------------------------------------------

resume_last_session() {
    local last_dev
    # Use find instead of ls for robustness
    last_dev=$(find "$RESULTS_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null \
        | sort -nr | head -n1 | cut -d' ' -f2- || true)
    if [[ -z "$last_dev" ]]; then
        log WARN "No previous session found."
        return
    fi
    last_dev="${last_dev%/}"
    DEVICE_DIR="$last_dev"
    DEVICE_SERIAL="$(basename "$last_dev" | awk -F'_' '{print $NF}')"
    DEVICE="$DEVICE_SERIAL"
    gather_device_profile "$DEVICE_SERIAL"
    init_report
    log SUCCESS "Resumed device: $DEVICE_LABEL"
}
