#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# resume.sh - resume last session
# ---------------------------------------------------

resume_last_session() {
    local last_dev
    last_dev=$(ls -1dt "$RESULTS_DIR"/*/ 2>/dev/null | head -n1 || true)
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
