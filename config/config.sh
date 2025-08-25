#!/usr/bin/env bash
# ---------------------------------------------------
# config.sh
# Global configuration for DroidHarvester
# ---------------------------------------------------
# Purpose:
#   Defines global parameters for logging, outputs,
#   hashing policies, ADB/tooling, and default packages.
#
# Notes:
#   - Keep portable & ASCII-only.
#   - Any value here can be overridden via environment.
#   - Custom packages may be provided via external file.
# ---------------------------------------------------

# Only enable strict mode when executed directly, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  set -E
  trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
fi

# Determine config dir and repo root
: "${SCRIPT_DIR:="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"}"
: "${REPO_ROOT:="$(cd "${SCRIPT_DIR}/.." && pwd)"}"

# ===============================
# I. OUTPUT DIRECTORIES
# ===============================

# Results & logs live at repo root by default
: "${RESULTS_DIR:="${REPO_ROOT}/results"}"
: "${LOG_DIR:="${REPO_ROOT}/logs"}"

# Timestamp format for log and report files (passed directly to `date`)
: "${TIMESTAMP_FORMAT:="+%Y%m%d_%H%M%S"}"

# Ensure base dirs exist (harmless if already present)
mkdir -p "${RESULTS_DIR}" "${LOG_DIR}"

# Automatically purge logs after run.sh exits (true/false)
: "${CLEAR_LOGS:=false}"

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

# Optional custom package list file at repo root (same level as results/)
: "${CUSTOM_PACKAGES_FILE:="${REPO_ROOT}/custom_packages.txt"}"
if [[ -f "$CUSTOM_PACKAGES_FILE" ]]; then
  while IFS= read -r pkg; do
    [[ -n "$pkg" && ! "$pkg" =~ ^[[:space:]]*# ]] && TARGET_PACKAGES+=("$pkg")
  done < "$CUSTOM_PACKAGES_FILE"
fi

# ===============================
# III. HASHING CONFIGURATION
# ===============================

# Hash algorithms to compute (extendable)
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

# Preferred adb binary; override to point at Platform-Tools:
#   ADB_BIN="$HOME/Android/platform-tools/adb" ./run.sh
# Resolve preferred adb binary without failing when missing
ADB_BIN="${ADB_BIN:-$(command -v adb 2>/dev/null || true)}"

# Timeout for `adb wait-for-device` (seconds)
: "${ADB_TIMEOUT:=30}"

# Allow multiple devices (true/false)
: "${ALLOW_MULTI_DEVICE:=false}"

# Wrapper defaults (override via environment)
: "${DH_SHELL_TIMEOUT:=15}"   # seconds, integer > 0
: "${DH_PULL_TIMEOUT:=300}"   # accepts 0 (disable) or e.g. 300 / 300s
: "${DH_RETRIES:=3}"          # integer > 0
: "${DH_BACKOFF:=1}"          # integer > 0 (seconds)

# -------------------------------
# Validation helpers & export
# -------------------------------
_config_warn() {
  # Use repo logger if loaded; otherwise stderr
  if declare -F log >/dev/null 2>&1; then
    LOG_COMP="config" log WARN "$*"
  else
    printf '[WARN][config] %s\n' "$*" >&2
  fi
}

_is_posint() { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 > 0 )); }
_is_nonnegint() { [[ "$1" =~ ^[0-9]+$ ]]; }
_is_timeout_val() {
  # 0 OR integer seconds OR integer with s/m/h/d suffix
  [[ "$1" == "0" || "$1" =~ ^[0-9]+([smhd])?$ ]]
}

validate_config() {
  local v
  # DH_SHELL_TIMEOUT must be > 0 integer
  v="${DH_SHELL_TIMEOUT}"
  if ! _is_posint "$v"; then
    _config_warn "DH_SHELL_TIMEOUT invalid ($v); defaulting to 15"
    DH_SHELL_TIMEOUT=15
  fi

  # DH_PULL_TIMEOUT: allow 0 or suffixed values
  v="${DH_PULL_TIMEOUT}"
  if ! _is_timeout_val "$v"; then
    _config_warn "DH_PULL_TIMEOUT invalid ($v); defaulting to 300"
    DH_PULL_TIMEOUT=300
  fi

  # DH_RETRIES, DH_BACKOFF must be > 0 integer
  v="${DH_RETRIES}"
  if ! _is_posint "$v"; then
    _config_warn "DH_RETRIES invalid ($v); defaulting to 3"
    DH_RETRIES=3
  fi
  v="${DH_BACKOFF}"
  if ! _is_posint "$v"; then
    _config_warn "DH_BACKOFF invalid ($v); defaulting to 1"
    DH_BACKOFF=1
  fi

  export ADB_BIN ADB_TIMEOUT ALLOW_MULTI_DEVICE
  export DH_SHELL_TIMEOUT DH_PULL_TIMEOUT DH_RETRIES DH_BACKOFF
  export RESULTS_DIR LOG_DIR REPO_ROOT SCRIPT_DIR TIMESTAMP_FORMAT
  export LOG_LEVEL INCLUDE_DEVICE_PROFILE INCLUDE_ENV_METADATA
}

validate_config

# ===============================
# VI. ANALYST NOTES
# ===============================
# Override examples:
#   LOG_LEVEL=DEBUG ./run.sh
#   REPORT_FORMATS=("csv") ./run.sh
#   ADB_BIN="$HOME/Android/platform-tools/adb" ./run.sh
#   DH_PULL_TIMEOUT=0 ./run.sh               # disable transfer timeout
#   DH_PULL_TIMEOUT=600s ./run.sh            # 10 minutes
#   CUSTOM_PACKAGES_FILE=/path/to/extra.txt ./run.sh
# ---------------------------------------------------
