#!/usr/bin/env bash
# Quick APK pull vs. stream diagnostic
# Usage: scripts/tests/pull_apk_stream_test.sh [PACKAGE] [SERIAL]
#   PACKAGE defaults to com.whatsapp
#   SERIAL  defaults to $DEV or auto-picks the first "device" from `adb devices -l`

set -u -o pipefail

# -----------------------------
# Config / Environment
# -----------------------------
PKG="${1:-com.whatsapp}"
DEV="${2:-${DEV:-}}"
ADB_BIN="${ADB_BIN:-$(command -v adb)}"
DH_PULL_TIMEOUT="${DH_PULL_TIMEOUT:-}"   # seconds; if set and non-zero we use `timeout`
OUTDIR="${OUTDIR:-/tmp/dh_pull_test}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/lib/core/logging.sh"
mkdir -p "$OUTDIR"

LOGFILE="${LOGFILE:-$(_log_path pull_stream_${PKG//./_})}"

# -----------------------------
# Helpers
# -----------------------------
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$LOGFILE" ; }

pick_device() {
  if [[ -n "${DEV}" ]]; then
    return 0
  fi
  mapfile -t devs < <("$ADB_BIN" devices -l | awk '/device usb|device product|device transport_id/ {print $1}')
  if (( ${#devs[@]} == 0 )); then
    log "ERR: no devices connected"
    exit 1
  fi
  DEV="${devs[0]}"
}

adbq() { "$ADB_BIN" -s "$DEV" "$@" ; }

maybe_timeout() {
  # Usage: maybe_timeout <label> <cmd...>
  local label="$1"; shift
  if [[ -n "$DH_PULL_TIMEOUT" && "$DH_PULL_TIMEOUT" != "0" ]]; then
    timeout --preserve-status -- "$DH_PULL_TIMEOUT" "$@" ; return $?
  else
    "$@" ; return $?
  fi
}

# -----------------------------
# Preamble
# -----------------------------
log "=== APK Pull vs Stream Test ==="
log "PKG=$PKG"
log "OUTDIR=$OUTDIR"
log "LOGFILE=$LOGFILE"

pick_device
log "Using device: $DEV"
log "ADB_BIN: $ADB_BIN"
"$ADB_BIN" version 2>&1 | tee -a "$LOGFILE"
"$ADB_BIN" host-features 2>&1 | tee -a "$LOGFILE"

adbq get-state 1>/dev/null || { log "ERR: adb cannot talk to $DEV"; exit 1; }

# -----------------------------
# Resolve APK path
# -----------------------------
APK="$(adbq shell pm path "$PKG" | sed -n 's/^package://p' | head -n1)"
if [[ -z "$APK" ]]; then
  log "ERR: could not resolve APK path for $PKG (is it installed?)"
  exit 2
fi
log "APK=$APK"

# -----------------------------
# Show perms / SELinux
# -----------------------------
log "--- Permissions & SELinux ---"
adbq shell ls -l "$APK"      2>&1 | tee -a "$LOGFILE" || true
adbq shell ls -lZ "$APK"     2>/dev/null | tee -a "$LOGFILE" || true

# -----------------------------
# Attempt classic pull
# -----------------------------
USB_DST="$OUTDIR/${PKG//./_}.usb.apk"
STREAM_DST="$OUTDIR/${PKG//./_}.stream.apk"

log "--- Classic pull (sync) ---"
if [[ -n "$DH_PULL_TIMEOUT" && "$DH_PULL_TIMEOUT" != "0" ]]; then
  log "Using pull timeout: $DH_PULL_TIMEOUT"
fi

if maybe_timeout "pull" "$ADB_BIN" -s "$DEV" pull "$APK" "$USB_DST" 2>&1 \
  | tee -a "$LOGFILE" ; then
  PULL_RC=0
  log "pull rc=0"
else
  PULL_RC=$?
  log "pull rc=$PULL_RC"
fi

# -----------------------------
# Stream via shell
# -----------------------------
log "--- Stream via exec-out ---"
if adbq exec-out "cat '$APK'" > "$STREAM_DST" 2>>"$LOGFILE" ; then
  STREAM_RC=0
  log "stream rc=0"
else
  STREAM_RC=$?
  log "stream rc=$STREAM_RC"
fi

# -----------------------------
# Integrity (size/hash)
# -----------------------------
log "--- Integrity (size/hash) ---"
ls -lh "$USB_DST" "$STREAM_DST" 2>&1 | tee -a "$LOGFILE" || true
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$USB_DST" "$STREAM_DST" 2>/dev/null | tee -a "$LOGFILE" || true
else
  log "sha256sum not found; skipping hash"
fi

# Quick compare if both exist
if [[ -s "$USB_DST" && -s "$STREAM_DST" ]]; then
  if command -v sha256sum >/dev/null 2>&1; then
    USB_HASH="$(sha256sum "$USB_DST"    | awk '{print $1}')"
    STR_HASH="$(sha256sum "$STREAM_DST" | awk '{print $1}')"
    if [[ "$USB_HASH" == "$STR_HASH" ]]; then
      MATCH="YES"
    else
      MATCH="NO"
    fi
  else
    # fallback: size compare
    USB_SIZE="$(stat -c %s "$USB_DST" 2>/dev/null || echo 0)"
    STR_SIZE="$(stat -c %s "$STREAM_DST" 2>/dev/null || echo 0)"
    MATCH=$([[ "$USB_SIZE" == "$STR_SIZE" ]] && echo YES || echo NO)
  fi
else
  MATCH="N/A"
fi

# -----------------------------
# Summary
# -----------------------------
log "=== Summary ==="
log "Device        : $DEV"
log "Package       : $PKG"
log "APK path      : $APK"
log "pull rc       : ${PULL_RC:-NA}"
log "stream rc     : ${STREAM_RC:-NA}"
log "hash/size match: $MATCH"
log "USB file      : $USB_DST"
log "STREAM file   : $STREAM_DST"
log "Log file      : $LOGFILE"

# Exit code logic:
#  - success if streaming succeeded (gives you a viable path forward)
#  - nonzero if both methods failed
if [[ "${STREAM_RC:-1}" -eq 0 ]]; then
  exit 0
elif [[ "${PULL_RC:-1}" -eq 0 ]]; then
  exit 0
else
  exit 3
fi
