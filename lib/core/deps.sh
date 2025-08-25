#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND" >&2' ERR

# require <bin> -> die if missing with Fedora hint
require() {
    local bin="$1"
    local pkg="$bin"
    case "$bin" in
        adb) pkg="android-tools";;
    esac
    if ! command -v "$bin" >/dev/null 2>&1; then
        die "$E_DEPS" "Missing dependency: $bin (Fedora: sudo dnf install -y $pkg)"
    fi
}

# require_all <bins...>
require_all() {
    local b
    for b in "$@"; do
        require "$b"
    done
}

# Backwards compatibility
check_dependencies() {
    require_all adb jq sha256sum md5sum sha1sum zip column
}
