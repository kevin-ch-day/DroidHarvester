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
        [Yy]*) rm -rf "$DEVICE_DIR"; log SUCCESS "Removed $DEVICE_DIR"; DEVICE="" ;;
        *)     log WARN "Cleanup cancelled." ;;
    esac
}
