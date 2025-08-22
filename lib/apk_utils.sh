#!/usr/bin/env bash
set -euo pipefail
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# lib/apk_utils.sh
# Handles APK discovery and pulling from device
# ---------------------------------------------------

# Get all APK paths for a package (base + splits)
get_apk_paths() {
    local pkg="$1"

    # "pm path" may return multiple lines (for split APKs)
    local paths
    paths=$(adb_shell pm path "$pkg" 2>/dev/null | tr -d '\r' | sed 's/package://g' || true)

    if [[ -z "$paths" ]]; then
        log ERROR "No APK paths found for package $pkg"
        return 1
    fi

    echo "$paths"
}

# Pull APK from device with retries and verification
pull_apk() {
    local pkg="$1"
    local apk_path="$2"

    # Normalize file name (strip special characters)
    local safe_name
    safe_name=$(basename "$apk_path" | sed 's/[^a-zA-Z0-9._-]/_/g')

    local outdir="$DEVICE_DIR/$pkg"
    local outfile="$outdir/$safe_name"
    mkdir -p "$outdir"

    # Confirm file exists on device
    if ! adb -s "$DEVICE" shell "[ -f \"$apk_path\" ]" >/dev/null 2>&1; then
        log WARN "File not found on device: $apk_path"
        return 1
    fi

    # Attempt pull with retries
    local attempts=0
    local max_attempts=3
    local success=0

    while (( attempts < max_attempts )); do
        attempts=$((attempts+1))
        log INFO "Pulling $apk_path (attempt $attempts of $max_attempts)..."

        if adb -s "$DEVICE" pull "$apk_path" "$outfile" >/dev/null 2>&1; then
            if [[ -s "$outfile" ]]; then
                success=1
                break
            else
                log WARN "Pulled file is empty: $outfile"
            fi
        else
            log WARN "Pull command failed for $apk_path"
            if ! adb devices | awk 'NR>1 && $2=="device" {print $1}' | grep -qx "$DEVICE"; then
                read -rp "Device disconnected. retry or reselect device? [r/s]: " ans
                case "$ans" in
                    r|R) continue ;;
                    s|S) choose_device; return 1 ;;
                    *)   log ERROR "E_NO_DEVICE: device unavailable"; return "$E_NO_DEVICE" ;;
                esac
            fi
        fi

        sleep 1
    done

    if (( success == 0 )); then
        log ERROR "E_PULL_FAIL: Failed to pull $apk_path after $max_attempts attempts"
        return 1
    fi

    # Verify file size
    local fsize
    fsize=$(stat -c%s "$outfile" 2>/dev/null || echo 0)
    log INFO "Pulled $outfile (size: $fsize bytes)"
    echo "$outfile"
}
