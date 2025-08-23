#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# harvest.sh - harvest APKs and metadata
# ---------------------------------------------------

harvest() {
    [[ -z "$DEVICE" ]] && { log WARN "Choose a device first."; return; }
    local all_pkgs=("${TARGET_PACKAGES[@]}" "${CUSTOM_PACKAGES[@]}")
    if [[ ${#all_pkgs[@]} -eq 0 ]]; then
        log WARN "No packages selected."
        return
    fi

    PKGS_FOUND=0
    PKGS_PULLED=0

    local pkg apk_paths path outfile pulled
    for pkg in "${all_pkgs[@]}"; do
        LOG_PKG="$pkg" log INFO "Checking $pkg..."
        apk_paths="$(get_apk_paths "$pkg" || true)"
        if [[ -z "$apk_paths" ]]; then
            LOG_PKG="$pkg" log WARN "Not installed or no paths"
            continue
        fi
        local splits
        splits=$(printf '%s\n' "$apk_paths" | sed '/^$/d' | wc -l)
        LOG_PKG="$pkg" log DEBUG "splits=$splits"
        ((PKGS_FOUND++))
        pulled=0
        while IFS= read -r path; do
            outfile=$(pull_apk "$pkg" "$path")
            rc=$?
            if (( rc != 0 )); then
                continue
            fi
            if [[ -n "$outfile" ]]; then
                pulled=1
                apk_metadata "$pkg" "$outfile"
            fi
        done <<< "$apk_paths"
        ((pulled)) && ((PKGS_PULLED++))
        LOG_PKG="$pkg" log DEBUG "package_complete pulled=$pulled splits=$splits"
    done

    finalize_report "all"
    LAST_TXT_REPORT="$TXT_REPORT"
    log SUCCESS "Harvest complete. Reports written to $RESULTS_DIR"
}
