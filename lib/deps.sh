#!/usr/bin/env bash
set -euo pipefail
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR

check_dependencies() {
    local missing=()
    for cmd in adb jq sha256sum md5sum sha1sum zip column; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    if (( ${#missing[@]} )); then
        for cmd in "${missing[@]}"; do
            echo "Missing dependency: $cmd - install via 'sudo dnf install -y $cmd'" >&2
        done
        exit 1
    fi
}
