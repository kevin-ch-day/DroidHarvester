#!/usr/bin/env bash
# ---------------------------------------------------
# adb_apk_diag.sh - end-to-end ADB APK diagnostics
# ---------------------------------------------------
set -euo pipefail
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND" >&2' ERR

# ====== HARD-CODED SETTINGS ===================================================
DEV=""
PKG="com.zhiliaoapp.musically"
PKG_CANDIDATES=(com.zhiliaoapp.musically com.whatsapp com.instagram.android com.facebook.katana)
STAGE=""  # results/<dev>/manual_pull_<timestamp> if empty

DO_PULL_BASE=1     # pull base.apk (or first split)
DO_PULL_ALL=0      # pull all splits (limited by LIMIT)
DO_VERIFY=0        # hash-verify pulls (device+host tools permitting)

LIMIT=10           # cap checks/pulls shown
RETRIES=3          # retry attempts for pm path simulation
BACKOFF=1          # seconds between retries
DEBUG=0
# =============================================================================

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { echo "FATAL: $*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }
ts() { date +%Y%m%d_%H%M%S; }

pick_device() {
  local first
  first="$(adb devices | awk 'NR>1 && $2=="device"{print $1; exit}')"
  [[ -n "$first" ]] || die "No connected devices."
  echo "$first"
}

# Return PKG if installed & resolvable via pm path. Else try candidates.
pick_installed_pkg() {
  local cand
  if [[ -n "$PKG" ]]; then
    if adb -s "$DEV" shell pm path "$PKG" >/dev/null 2>&1; then
      echo "$PKG"; return 0
    fi
  fi
  for cand in "${PKG_CANDIDATES[@]}"; do
    if adb -s "$DEV" shell pm path "$cand" >/dev/null 2>&1; then
      echo "$cand"; return 0
    fi
  done
  return 1
}

maybe_pull_one() {
  local src="$1" dest_dir="$2"
  mkdir -p "$dest_dir"
  local out="$dest_dir/$(basename "$src")"

  # Preflight existence helps with clearer errors on scoped storage devices.
  if ! adb -s "$DEV" shell test -f "$src" >/dev/null 2>&1; then
    log "Remote not found (test -f failed): $src"
    return 1
  fi

  log "Pulling: $src -> $out"
  if adb -s "$DEV" pull "$src" "$out" >/dev/null 2>&1; then
    if [[ -s "$out" ]]; then
      log "Pulled OK: $out"
      echo "$out"
      return 0
    else
      log "Pulled file is empty: $out"
      return 1
    fi
  else
    log "adb pull failed for $src"
    return 1
  fi
}

detect_device_hash_cmd() {
  if adb -s "$DEV" shell 'command -v sha256sum >/dev/null 2>&1'; then
    echo "sha256sum"
  elif adb -s "$DEV" shell 'command -v toybox >/dev/null 2>&1'; then
    echo "toybox sha256sum"
  elif adb -s "$DEV" shell 'command -v md5sum >/dev/null 2>&1'; then
    echo "md5sum"
  else
    echo ""
  fi
}

verify_hash() {
  local dev_path="$1" local_file="$2"
  local device_hash_cmd dev_hash local_hash algo
  device_hash_cmd="$(detect_device_hash_cmd)"
  if [[ -z "$device_hash_cmd" ]]; then
    log "No hash tool on device; skipping device-side verification."
    return 0
  fi

  if [[ "$device_hash_cmd" == *sha256sum* ]]; then
    algo="sha256"
    dev_hash="$(adb -s "$DEV" shell $device_hash_cmd "$dev_path" | awk '{print $1}')"
    if command -v sha256sum >/dev/null 2>&1; then
      local_hash="$(sha256sum "$local_file" | awk '{print $1}')"
    else
      log "No host sha256sum; skipping verification."
      return 0
    fi
  else
    algo="md5"
    dev_hash="$(adb -s "$DEV" shell md5sum "$dev_path" | awk '{print $1}')"
    if command -v md5sum >/dev/null 2>&1; then
      local_hash="$(md5sum "$local_file" | awk '{print $1}')"
    else
      log "No host md5sum; skipping verification."
      return 0
    fi
  fi

  log "Device $algo: $dev_hash"
  log "Local  $algo: $local_hash"
  if [[ "$dev_hash" == "$local_hash" ]]; then
    log "HASH MATCH ($algo)"
  else
    log "HASH MISMATCH ($algo)"
    return 2
  fi
}

# ====== RUN ===================================================================

(( DEBUG )) && set -x
require_cmd adb

# Device
[[ -n "$DEV" ]] || DEV="$(pick_device)"
adb -s "$DEV" wait-for-device
log "Using device: $DEV"

# Health
log "Health: adb get-state";               adb -s "$DEV" get-state
log "Health: adb shell echo OK";           adb -s "$DEV" shell echo OK
log "Health: identity & version";          adb -s "$DEV" shell 'id; whoami; getprop ro.build.version.release' || true

# Package selection
if ! PKG="$(pick_installed_pkg)"; then
  die "None of the target packages are resolvable via 'pm path': $PKG ${PKG_CANDIDATES[*]}"
fi
log "Target package: $PKG (installed)"

# pm path raw (preview)
log "pm path (raw, first 20 lines)"
adb -s "$DEV" shell pm path "$PKG" | sed -n '1,20p' || true

# pm path sanitized (absolute file paths only)
SANITIZED_PATHS="$(adb -s "$DEV" shell pm path "$PKG" | tr -d '\r' | sed -n 's/^package://p')"
if [[ -z "$SANITIZED_PATHS" ]]; then
  die "pm path returned no paths (sanitized empty)."
fi
log "pm path (sanitized, first 20)"
printf '%s\n' "$SANITIZED_PATHS" | sed -n '1,20p'

# Verify existence on device
log "Verifying each path exists on device"
OK=0; FAIL=0; CHECKED=0
while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  if adb -s "$DEV" shell ls -l "$p" >/dev/null 2>&1; then
    printf 'OK   %s\n' "$p"
    (( ++OK ))
  else
    printf 'FAIL %s\n' "$p"
    (( ++FAIL ))
  fi
  (( ++CHECKED ))
  (( CHECKED >= LIMIT )) && break
done <<< "$SANITIZED_PATHS"
log "Existence summary: checked=$CHECKED ok=$OK fail=$FAIL"

# Stage dir
if [[ -z "$STAGE" ]]; then
  STAGE="results/$DEV/manual_pull_$(ts)"
fi
mkdir -p "$STAGE"

# Pull base (optional)
if (( DO_PULL_BASE == 1 )); then
  BASE="$(printf '%s\n' "$SANITIZED_PATHS" | grep -m1 '/base\.apk$' || printf '%s\n' "$SANITIZED_PATHS" | head -n1)"
  log "Selected base path: $BASE"
  if LOCAL="$(maybe_pull_one "$BASE" "$STAGE")"; then
    if (( DO_VERIFY == 1 )); then
      verify_hash "$BASE" "$LOCAL" || true
    fi
  fi
fi

# Pull all splits (optional)
if (( DO_PULL_ALL == 1 )); then
  log "Pulling ALL APK paths (limited to $LIMIT)"
  mkdir -p "$STAGE/all"
  POK=0; PFAIL=0; PCHECK=0
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    if LOCAL="$(maybe_pull_one "$p" "$STAGE/all")"; then
      (( ++POK ))
      if (( DO_VERIFY == 1 )); then
        verify_hash "$p" "$LOCAL" || true
      fi
    else
      (( ++PFAIL ))
    fi
    (( ++PCHECK ))
    (( PCHECK >= LIMIT )) && break
  done <<< "$SANITIZED_PATHS"
  log "Pull summary: checked=$PCHECK ok=$POK fail=$PFAIL (dest=$STAGE/all)"
fi

# Retry simulation (simple)
log "Retry simulation: pm path (retries=$RETRIES backoff=${BACKOFF}s)"
attempt=0; rc=1
while (( attempt < RETRIES )); do
  if adb -s "$DEV" shell pm path "$PKG" >/dev/null 2>&1; then
    log "pm path succeeded on attempt $((attempt+1))"
    rc=0; break
  fi
  (( ++attempt ))
  sleep "$BACKOFF"
done
(( rc != 0 )) && log "pm path failed after $RETRIES attempts" || true

# Third-party preview: split on the *last* '=' to avoid mangling paths with '=='
log "Third-party packages (-f -3), preview:"
adb -s "$DEV" shell pm list packages -f -3 \
  | tr -d '\r' \
  | sed 's/^package://; s/=\([^=]*\)$/,\1/' \
  | sed -n '1,20p' || true

log "DONE."
