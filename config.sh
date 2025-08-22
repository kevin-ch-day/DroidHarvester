#!/bin/bash
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
HASH_ALGOS=("sha256" "sha1" "md5")

# File size threshold (bytes) for hash computation (0 = no limit)
: "${HASH_SIZE_LIMIT:=0}"


# ===============================
# IV. REPORTING OPTIONS
# ===============================

# Report formats to generate (txt, csv, json, html if supported)
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
