#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# cleanup.sh - remove partial run artifacts
# ---------------------------------------------------

cleanup_partial_run() {
    if [[ -z "${DEVICE_DIR:-}" || ! -d "$DEVICE_DIR" ]]; then
        log WARN "No device directory to clean."
        return
    fi
    read -rp "Remove $DEVICE_DIR? [y/N]: " ans
    case "$ans" in
        [Yy]*)
            rm -rf "$DEVICE_DIR"
            local script_res="$REPO_ROOT/scripts/results/$DEVICE_DIR_NAME"
            rm -rf "$script_res" 2>/dev/null || true
            log SUCCESS "Removed $DEVICE_DIR"
            [[ -d "$script_res" ]] || log SUCCESS "Removed $script_res"
            DEVICE=""
            DEVICE_LABEL=""
            DEVICE_SERIAL=""
            ;;
        *)     log WARN "Cleanup cancelled." ;;
    esac
}

# Remove all logs and results directories
cleanup_all_artifacts() {
    read -rp "Remove all contents of $RESULTS_DIR and $LOG_DIR? [y/N]: " ans
    case "$ans" in
        [Yy]*)
            rm -rf "$RESULTS_DIR"/* "$LOG_DIR"/* 2>/dev/null || true
            log SUCCESS "Cleared $RESULTS_DIR and $LOG_DIR"
            ;;
        *)
            log WARN "Cleanup cancelled." ;;
    esac
}
