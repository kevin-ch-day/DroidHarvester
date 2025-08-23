#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# config.sh
# Global configuration for DroidHarvester
# ---------------------------------------------------
# Purpose:
#   Defines global parameters for logging, output formats,
#   hashing policies, and default package lists.
#
# Notes:
#   - This file should remain portable and ASCII-only.
#   - Analysts can override defaults via environment variables.
#   - Custom packages may be provided via external file.
# ---------------------------------------------------

# Determine repository root if caller has not set SCRIPT_DIR
: "${SCRIPT_DIR:="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"}"

# ===============================
# I. OUTPUT DIRECTORIES
# ===============================

# Base results directory (relative to script directory)
: "${RESULTS_DIR:="$SCRIPT_DIR/results"}"

# Timestamp format for log and report files
: "${TIMESTAMP_FORMAT:="+%Y%m%d_%H%M%S"}"


# ===============================
# II. TARGET PACKAGES
# ===============================

# Default package list (social media / messaging)
TARGET_PACKAGES=(
    "com.zhiliaoapp.musically"    # TikTok
    "com.facebook.katana"         # Facebook
    "com.facebook.orca"           # Messenger
    "com.snapchat.android"        # Snapchat
    "com.twitter.android"         # Twitter/X
    "com.instagram.android"       # Instagram
    "com.whatsapp"                # WhatsApp
)

# Optional custom package list file
CUSTOM_PACKAGES_FILE="$SCRIPT_DIR/custom_packages.txt"
if [[ -f "$CUSTOM_PACKAGES_FILE" ]]; then
    while read -r pkg; do
        [[ -n "$pkg" && ! "$pkg" =~ ^# ]] && TARGET_PACKAGES+=("$pkg")
    done < "$CUSTOM_PACKAGES_FILE"
fi


# ===============================
# III. HASHING CONFIGURATION
# ===============================

# Hash algorithms to compute
# Extendable: add "blake2b" or "sha512" if required
# shellcheck disable=SC2034  # referenced externally
HASH_ALGOS=("sha256" "sha1" "md5")

# File size threshold (bytes) for hash computation (0 = no limit)
: "${HASH_SIZE_LIMIT:=0}"


# ===============================
# IV. REPORTING OPTIONS
# ===============================

# Report formats to generate (txt, csv, json, html if supported)
# shellcheck disable=SC2034  # referenced externally
REPORT_FORMATS=("txt" "csv" "json")

# Log level: INFO | DEBUG | WARN | ERROR
: "${LOG_LEVEL:="INFO"}"

# Append device profile to reports (true/false)
: "${INCLUDE_DEVICE_PROFILE:=true}"

# Append environment/system metadata (true/false)
: "${INCLUDE_ENV_METADATA:=true}"


# ===============================
# V. ADB / DEVICE SETTINGS
# ===============================

# Timeout for adb wait-for-device (seconds)
: "${ADB_TIMEOUT:=30}"

# Allow multiple devices (true/false)
: "${ALLOW_MULTI_DEVICE:=false}"

# Wrapper defaults (override via environment)
: "${DH_SHELL_TIMEOUT:=15}"
: "${DH_PULL_TIMEOUT:=60}"
: "${DH_RETRIES:=3}"
: "${DH_BACKOFF:=1}"

validate_config() {
    local var val
    for var in DH_SHELL_TIMEOUT DH_PULL_TIMEOUT DH_RETRIES DH_BACKOFF; do
        val="${!var}"
        if ! [[ "$val" =~ ^[0-9]+$ ]] || (( val <= 0 )); then
            LOG_COMP="config" log WARN "$var invalid ($val); using default"
            case $var in
                DH_SHELL_TIMEOUT) val=15 ;;
                DH_PULL_TIMEOUT) val=60 ;;
                DH_RETRIES) val=3 ;;
                DH_BACKOFF) val=1 ;;
            esac
            eval "$var=$val"
        fi
        export "$var"
    done
}


# Wrapper defaults
: "${DH_SHELL_TIMEOUT:=15}"
: "${DH_PULL_TIMEOUT:=60}"
: "${DH_RETRIES:=3}"
: "${DH_BACKOFF:=1}"

validate_pos_int() { [[ "$1" =~ ^[0-9]+$ && "$1" -gt 0 ]]; }

if ! validate_pos_int "$DH_SHELL_TIMEOUT"; then
    log WARN "DH_SHELL_TIMEOUT invalid ($DH_SHELL_TIMEOUT); using default 15"
    DH_SHELL_TIMEOUT=15
fi
if ! validate_pos_int "$DH_PULL_TIMEOUT"; then
    log WARN "DH_PULL_TIMEOUT invalid ($DH_PULL_TIMEOUT); using default 60"
    DH_PULL_TIMEOUT=60
fi
if ! validate_pos_int "$DH_RETRIES"; then
    log WARN "DH_RETRIES invalid ($DH_RETRIES); using default 3"
    DH_RETRIES=3
fi
if ! validate_pos_int "$DH_BACKOFF"; then
    log WARN "DH_BACKOFF invalid ($DH_BACKOFF); using default 1"
    DH_BACKOFF=1
fi


# ===============================
# VI. ANALYST NOTES
# ===============================

# Analysts may override config.sh defaults at runtime:
#   Example: LOG_LEVEL=DEBUG ./run.sh
#   Example: REPORT_FORMATS=("csv") ./run.sh
#
# Analysts may also update custom_packages.txt to add targets
# without editing this file.
# ---------------------------------------------------
