#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# add_custom_package.sh - add package to custom list
# ---------------------------------------------------

add_custom_package() {
    read -rp "Enter package name (e.g., com.example.app): " pkg
    if [[ -n "$pkg" ]]; then
        CUSTOM_PACKAGES+=("$pkg")
        echo "$pkg" >> "$CUSTOM_PACKAGES_FILE"
        log SUCCESS "Added custom package: $pkg"
    else
        log WARN "No package entered."
    fi
}
