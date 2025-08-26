#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# harvest.sh - harvest APKs and metadata
# ---------------------------------------------------
# Public entrypoint: harvest
# Helpers:
#   _harvest_prepare
#   _harvest_one_pkg <pkg>
#   _pull_one_path <pkg> <path>
# ---------------------------------------------------

# Prepare run; ensure device and targets exist; reset counters.
_harvest_prepare() {
    if [[ -z "${DEVICE:-}" ]]; then
        log WARN "Choose a device first."
        return 1
    fi
    # Build the working target list
    ALL_PKGS=( "${TARGET_PACKAGES[@]}" )
    if [[ -n "${CUSTOM_PACKAGES[*]:-}" ]]; then
        ALL_PKGS+=( "${CUSTOM_PACKAGES[@]}" )
    fi
    if [[ ${#ALL_PKGS[@]} -eq 0 ]]; then
        log WARN "No packages selected."
        return 1
    fi

    # Reset session counters
    PKGS_FOUND=0
    PKGS_PULLED=0
    return 0
}

# Process one package: enumerate paths, pull, and record metadata.
_harvest_one_pkg() {
    local pkg="$1"
    LOG_PKG="$pkg" log INFO "Checking ${pkg}..."

    # Query APK paths (base + splits). Do not abort on empty.
    local apk_paths
    apk_paths="$(DEVICE="$DEVICE" LOGFILE="$LOGFILE" bash "$REPO_ROOT/steps/generate_apk_list.sh" "$pkg" || true)"
    if [[ -z "$apk_paths" ]]; then
        LOG_PKG="$pkg" log WARN "Not installed or no paths"
        return 0
    fi

    # Split into an array safely.
    local -a paths_array=()
    mapfile -t paths_array <<<"$apk_paths"

    local splits="${#paths_array[@]}"
    LOG_PKG="$pkg" log DEBUG "splits=${splits}"

    # Avoid set -e trap on post-increment. Use pre-increment.
    (( ++PKGS_FOUND ))

    local pulled_any=0
    local path
    for path in "${paths_array[@]}"; do
        [[ -z "$path" ]] && continue
        LOG_PKG="$pkg" log INFO "Found APK: ${path}"
        if _pull_one_path "$pkg" "$path"; then
            pulled_any=1
        fi
    done

    if (( pulled_any )); then
        (( ++PKGS_PULLED ))
    fi
    LOG_PKG="$pkg" log DEBUG "package_complete pulled=${pulled_any} splits=${splits}"
    return 0
}

# Pull a single APK path and append metadata.
# Returns 0 if the pull+metadata succeeded for this path, 1 otherwise.
_pull_one_path() {
    local pkg="$1"
    local path="$2"

    # Pull to local filesystem
    local outfile
    outfile="$(DEVICE="$DEVICE" DEVICE_DIR="$DEVICE_DIR" LOGFILE="$LOGFILE" bash "$REPO_ROOT/steps/pull_apk.sh" "$pkg" "$path")"
    local rc=$?
    if (( rc != 0 )); then
        LOG_PKG="$pkg" log WARN "pull_failed rc=${rc} path=${path}"
        return 1
    fi
    if [[ -z "$outfile" ]]; then
        LOG_PKG="$pkg" log WARN "pull_returned_empty path=${path}"
        return 1
    fi

    # Record metadata for this artifact via step script
    if ! DEVICE="$DEVICE" LOGFILE="$LOGFILE" REPORT="$REPORT" JSON_REPORT="$JSON_REPORT" \
        TXT_REPORT="$TXT_REPORT" bash "$REPO_ROOT/steps/generate_apk_metadata.sh" "$pkg" "$outfile" "$path"; then
        LOG_PKG="$pkg" log WARN "metadata_failed file=${outfile}"
        return 1
    fi
    return 0
}

# Public entrypoint. Orchestrates the run.
harvest() {
    # Prepare targets and counters
    if ! _harvest_prepare; then
        return 0   # keep interactive flow; message already logged
    fi

    # Iterate packages with simple progress indicator
    local pkg idx=0 total=${#ALL_PKGS[@]}
    for pkg in "${ALL_PKGS[@]}"; do
        ((idx++))
        log INFO "Analyzing [$idx/$total] $pkg"
        _harvest_one_pkg "$pkg"
    done

    # Finalize and advertise output locations
    finalize_report "all"
    # shellcheck disable=SC2034
    LAST_TXT_REPORT="$TXT_REPORT"
    log SUCCESS "Harvest complete. Reports written to $RESULTS_DIR"
    logging_rotate
}
