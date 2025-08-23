#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# lib/apk_utils.sh - APK discovery and pulling
# ---------------------------------------------------

get_apk_paths() {
    local pkg="$1"
    local output rc
    output=$(
        with_timeout "$DH_SHELL_TIMEOUT" pm_path -- \
            adb_retry "$DH_RETRIES" "$DH_BACKOFF" pm_path -- \
                adb -s "$DEVICE" shell pm path "$pkg" 2>/dev/null
    )
    rc=$?
    if (( rc != 0 )); then
        LOG_CODE="$E_PM_PATH" LOG_RC="$rc" LOG_PKG="$pkg" log ERROR "pm path failed"
        return 0
    fi
    local paths
    paths=$(echo "$output" | tr -d '\r' | sed -n 's/^package://p')
    local count
    count=$(printf '%s\n' "$paths" | sed '/^$/d' | wc -l || true)
    LOG_COMP="pm_path" LOG_PKG="$pkg" LOG_DUR_MS="" log DEBUG "paths=$count"
    [[ -z "$paths" ]] && { log WARN "No APK paths found for package $pkg"; return 0; }
    echo "$paths"
}

pull_apk() {
    local pkg="$1"
    local apk_path="$2"
    local safe_name
    safe_name=$(basename "$apk_path" | sed 's/[^a-zA-Z0-9._-]/_/g')
    local outdir="$DEVICE_DIR/$pkg/${safe_name%.apk}"
    local outfile="$outdir/$safe_name"
    mkdir -p "$outdir"
    local role="base"
    [[ "$safe_name" != "base.apk" ]] && role="split"

    if ! with_trace adb_test -- adb -s "$DEVICE" shell test -f "$apk_path"; then
        local rc=$?
        LOG_CODE="$E_APK_MISSING" LOG_RC="$rc" LOG_PKG="$pkg" LOG_APK="$safe_name" log WARN "apk missing $apk_path"
        return 1
    fi

    LOG_PKG="$pkg" LOG_APK="$safe_name" log INFO "Pulling $role APK $apk_path"
    if ! with_timeout "$DH_PULL_TIMEOUT" adb_pull -- \
        adb_retry "$DH_RETRIES" "$DH_BACKOFF" adb_pull -- \
            adb -s "$DEVICE" pull "$apk_path" "$outfile"; then
        local rc=$?
        LOG_CODE="$E_PULL_FAIL" LOG_RC="$rc" LOG_PKG="$pkg" LOG_APK="$safe_name" log ERROR "pull failed"
        return 1
    fi

    if [[ ! -s "$outfile" ]]; then
        LOG_CODE="$E_APK_EMPTY" LOG_PKG="$pkg" LOG_APK="$safe_name" log ERROR "pulled file empty"
        return 1
    fi

    LOG_PKG="$pkg" LOG_APK="$safe_name" log INFO "Pulled $role APK $outfile"
    echo "$outfile"
}
