#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# capability_report.sh - report device capabilities
# ---------------------------------------------------

capability_report() {
    if [[ -z "${DEVICE:-}" ]]; then
        log WARN "Choose a device first."
        return
    fi

    local tags debug su_status
    tags=$(adb_shell getprop ro.build.tags 2>/dev/null || echo "?")
    debug=$(adb_shell getprop ro.debuggable 2>/dev/null || echo "?")
    if adb_shell su 0 id >/dev/null 2>&1; then
        su_status="present"
    else
        su_status="absent"
    fi

    log INFO "Build tags: ${tags}"
    log INFO "ro.debuggable: ${debug}"
    log INFO "su: ${su_status}"

    local pkgs=()
    pkgs+=("${TARGET_PACKAGES[@]}")
    if [[ -n "${CUSTOM_PACKAGES[*]:-}" ]]; then
        pkgs+=("${CUSTOM_PACKAGES[@]}")
    fi

    local pkg sample strategy
    for pkg in "${pkgs[@]}"; do
        sample="$(apk_get_paths "$pkg" 2>/dev/null | head -n1 || true)"
        if [[ -z "$sample" ]]; then
            log INFO "$pkg: not installed"
            continue
        fi
        if strategy="$(determine_pull_strategy "$pkg" "$sample" 2>/dev/null)"; then
            log INFO "$pkg: $strategy"
        else
            log INFO "$pkg: none"
        fi
    done
}
