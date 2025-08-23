#!/usr/bin/env bash
# ---------------------------------------------------
# adb_apk_diag.sh - end-to-end ADB APK diagnostics
# ---------------------------------------------------
set -euo pipefail
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND" >&2' ERR

# ====== HARD-CODED SETTINGS ===================================================
DEV=""   # first connected device if empty

# Primary target; falls back to candidates if not resolvable via "pm path"
PKG="com.zhiliaoapp.musically"
PKG_CANDIDATES=(
  com.zhiliaoapp.musically
  com.ss.android.ugc.aweme          # TikTok global
  com.ss.android.ugc.trill          # TikTok JP
  com.ss.android.ugc.aweme.lite     # TikTok Lite
  com.whatsapp
  com.instagram.android
  com.facebook.katana
)

# Scans
DO_TIKTOK_SCAN=1            # scan ByteDance/TikTok-family pkgs
DO_TIKTOK_RELATED=1         # name-based search (tiktok/aweme/trill/musically/bytedance)
DO_TIKTOK_SPLIT_LIST=1      # list split APKs whose filenames look TikTok-ish

# Pulling / verification
DO_PULL_BASE=1              # pull base.apk (or first split)
DO_PULL_ALL=0               # pull all splits (limited by LIMIT)
DO_VERIFY=0                 # device+host hash verify when pulling

# Limits / retries
LIMIT=10
RETRIES=3
BACKOFF=1

# Housekeeping
CLEAN_PREVIOUS=1            # remove previous manual_diag_* for this device each run

DEBUG=0
# =============================================================================

# ---- small helpers -----------------------------------------------------------
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

# ---- pm path helpers ---------------------------------------------------------
pm_path_raw_to_file() {
  local pkg="$1" out="$2"
  adb -s "$DEV" shell pm path "$pkg" | tr -d '\r' > "$out"
}

sanitize_pm_path_file() {
  # pm path lines look like: "package:/absolute/path.apk"
  # Do NOT strip at '='; '=' belongs to `pm list -f`, not `pm path`.
  local raw="$1" sanitized="$2"
  sed -n 's/^package://p' "$raw" > "$sanitized"
}

pick_installed_pkg() {
  if [[ -n "$PKG" ]] && adb -s "$DEV" shell pm path "$PKG" >/dev/null 2>&1; then
    echo "$PKG"; return 0
  fi
  local cand
  for cand in "${PKG_CANDIDATES[@]}"; do
    if adb -s "$DEV" shell pm path "$cand" >/dev/null 2>&1; then
      echo "$cand"; return 0
    fi
  done
  return 1
}

# ---- device file helpers -----------------------------------------------------
dev_file_size() {
  local path="$1"
  adb -s "$DEV" shell "toybox stat -c %s '$path' 2>/dev/null || stat -c %s '$path' 2>/dev/null" \
    | tr -d '\r' | awk 'NF{print; exit}'
}

maybe_pull_one() {
  local src="$1" dest_dir="$2"
  mkdir -p "$dest_dir"
  local out="$dest_dir/$(basename "$src")"

  if ! adb -s "$DEV" shell test -f "$src" >/dev/null 2>&1; then
    log "Remote not found (test -f failed): $src"
    return 1
  fi
  log "Pulling: $src -> $out"
  if adb -s "$DEV" pull "$src" "$out" >/dev/null 2>&1; then
    if [[ -s "$out" ]]; then
      log "Pulled OK: $out"
      printf '%s\n' "$out"
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
  elif adb -s "$DEV" shell 'toybox sha256sum --help >/dev/null 2>&1'; then
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
  [[ "$dev_hash" == "$local_hash" ]] && { log "HASH MATCH ($algo)"; return 0; }
  log "HASH MISMATCH ($algo)"; return 2
}

# ---- verification / pulls ----------------------------------------------------
verify_paths_exist() {
  # Reads sanitized paths from file, writes CSV, prints OK/FAIL lines, honors LIMIT.
  local sanitized="$1" csv_out="$2"
  echo "path,exists,size_bytes" > "$csv_out"
  local OK=0 FAIL=0 CHECKED=0 p sz
  # IMPORTANT: read via redirection, not a pipe, to avoid subshell counters.
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    if adb -s "$DEV" shell ls -l "$p" >/dev/null 2>&1; then
      sz="$(dev_file_size "$p" || true)"
      echo "$p,1,${sz:-}" >> "$csv_out"
      printf 'OK   %s\n' "$p"
      ((OK++))
    else
      echo "$p,0," >> "$csv_out"
      printf 'FAIL %s\n' "$p"
      ((FAIL++))
    fi
    ((CHECKED++))
    (( CHECKED >= LIMIT )) && break
  done < "$sanitized"
  log "Existence summary: checked=$CHECKED ok=$OK fail=$FAIL (csv: $csv_out)"
}

pick_base_path() {
  local sanitized="$1" base
  base="$(grep -m1 '/base\.apk$' "$sanitized" || true)"
  [[ -z "$base" ]] && base="$(head -n1 "$sanitized" || true)"
  [[ -z "$base" ]] && { log "No base or first split found."; return 1; }
  printf '%s' "$base"
}

pull_base_and_or_all() {
  local sanitized="$1" stage="$2"
  if (( DO_PULL_BASE == 1 )); then
    local BASE LOCAL
    if BASE="$(pick_base_path "$sanitized")"; then
      log "Selected base path: $BASE"
      if LOCAL="$(maybe_pull_one "$BASE" "$stage")"; then
        (( DO_VERIFY == 1 )) && verify_hash "$BASE" "$LOCAL" || true
      fi
    fi
  fi
  if (( DO_PULL_ALL == 1 )); then
    log "Pulling ALL APK paths (limited to $LIMIT)"
    mkdir -p "$stage/all"
    local POK=0 PFAIL=0 PCHECK=0 p LOCAL
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      if LOCAL="$(maybe_pull_one "$p" "$stage/all")"; then
        ((POK++))
        (( DO_VERIFY == 1 )) && verify_hash "$p" "$LOCAL" || true
      else
        ((PFAIL++))
      fi
      ((PCHECK++))
      (( PCHECK >= LIMIT )) && break
    done < "$sanitized"
    log "Pull summary: checked=$PCHECK ok=$POK fail=$PFAIL (dest=$stage/all)"
  fi
}

# ---- misc ----------------------------------------------------
retry_simulation() {
  local pkg="$1" attempt=0 rc=1
  log "Retry simulation: pm path (retries=$RETRIES backoff=${BACKOFF}s)"
  while (( attempt < RETRIES )); do
    if adb -s "$DEV" shell pm path "$pkg" >/dev/null 2>&1; then
      log "pm path succeeded on attempt $((attempt+1))"; rc=0; break
    fi
    ((attempt++)); sleep "$BACKOFF"
  done
  (( rc != 0 )) && log "pm path failed after $RETRIES attempts" || true
}

third_party_preview() {
  local out_csv="$1"
  log "Third-party packages (-f -3), preview:"
  echo "apk_path,package" > "$out_csv"
  adb -s "$DEV" shell pm list packages -f -3 \
    | tr -d '\r' \
    | sed 's/^package://; s/=\([^=]*\)$/,\1/' \
    | tee >(sed -n '1,20p' >&2) \
    >> "$out_csv" || true
}

# ---- TikTok & related scans --------------------------------------------------
scan_tiktok_family() {
  (( DO_TIKTOK_SCAN == 1 )) || return 0
  log "Scanning for TikTok-family packages…"
  local listing="$RUN_DIR/packages_all.txt"
  adb -s "$DEV" shell pm list packages \
    | tr -d '\r' | sed 's/^package://g' > "$listing"

  local family_csv="$RUN_DIR/tiktok_family.csv"
  echo "package,apk_path" > "$family_csv"

  local patterns=(
    '^com\.ss\.android\.ugc\.aweme($|[^a-zA-Z])'
    '^com\.ss\.android\.ugc\.trill($|[^a-zA-Z])'
    '^com\.zhiliaoapp\.musically($|[^a-zA-Z])'
    '^com\.ss\.android\.ugc\.'
    '^com\.bytedance\.'
  )
  local pat_join; pat_join="$(IFS='|'; echo "${patterns[*]}")"

  grep -E "$pat_join" "$listing" | sort -u | while read -r fam_pkg; do
    local raw="$RUN_DIR/pm_path_${fam_pkg//./_}.txt"
    local san="$RUN_DIR/pm_path_${fam_pkg//./_}_san.txt"
    pm_path_raw_to_file "$fam_pkg" "$raw" || true
    sanitize_pm_path_file "$raw" "$san"
    local first_path; first_path="$(head -n1 "$san" || true)"
    if [[ -n "$first_path" ]]; then
      echo "$fam_pkg,$first_path" >> "$family_csv"
      log "TikTok-family: $fam_pkg → $first_path"
    else
      echo "$fam_pkg," >> "$family_csv"
      log "TikTok-family: $fam_pkg (no path)"
    fi
  done
  log "TikTok-family results → $family_csv"
}

scan_tiktok_related() {
  (( DO_TIKTOK_RELATED == 1 )) || return 0
  log "Scanning for TikTok-related names…"
  local listing="$RUN_DIR/packages_all.txt"
  [[ -f "$listing" ]] || adb -s "$DEV" shell pm list packages | tr -d '\r' | sed 's/^package://g' > "$listing"

  local out="$RUN_DIR/tiktok_related.csv"
  echo "package,first_apk_path,versionName,versionCode,installer" > "$out"

  local name_pat='(tiktok|aweme|trill|musically|bytedance)'
  grep -E -i "$name_pat" "$listing" | sort -u | while read -r pkg; do
    local raw="$RUN_DIR/pm_path_${pkg//./_}_rel_raw.txt"
    local san="$RUN_DIR/pm_path_${pkg//./_}_rel_san.txt"
    pm_path_raw_to_file "$pkg" "$raw" || true
    sanitize_pm_path_file "$raw" "$san"
    local first_path; first_path="$(head -n1 "$san" || true)"
    local vn vc inst
    vn="$(adb -s "$DEV" shell dumpsys package "$pkg" 2>/dev/null | awk -F= '/versionName=/{print $2; exit}')"
    vc="$(adb -s "$DEV" shell dumpsys package "$pkg" 2>/dev/null | awk -F= '/versionCode=/{print $2; exit}' | awk '{print $1}')"
    inst="$(adb -s "$DEV" shell dumpsys package "$pkg" 2>/dev/null | awk -F= '/installerPackageName=/{print $2; exit}')"
    echo "$pkg,${first_path:-},${vn:-},${vc:-},${inst:-}" >> "$out"
    log "Related: $pkg (vn=${vn:-?} vc=${vc:-?})"
  done
  log "TikTok-related results → $out"
}

list_tiktok_splits() {
  (( DO_TIKTOK_SPLIT_LIST == 1 )) || return 0
  local sanitized="$1"
  local out="$RUN_DIR/tiktok_splits.txt"
  log "Searching for TikTok-related split filenames…"
  awk -v IGNORECASE=1 '
    /\/[^\/]+\.apk$/ {
      file=$0
      name=gensub(/^.*\//, "", 1, file)
      if (name ~ /(tiktok|aweme|trill|bytedance)/) print file
    }' "$sanitized" | sort -u > "$out" || true
  sed -n '1,20p' "$out" || true
  log "TikTok-related split list → $out"
}

# ---- cleanup ----------------------------------------------------
safe_clean_previous_runs() {
  (( CLEAN_PREVIOUS == 1 )) || return 0
  local base="scripts/results/$DEV"
  # Safety rails: only delete inside scripts/results/<DEVICE>
  [[ -d "$base" ]] || return 0
  log "Cleaning previous runs in $base (manual_diag_*)"
  # Remove only directories named manual_diag_*
  find "$base" -maxdepth 1 -type d -name 'manual_diag_*' -exec rm -rf {} + || true
}

# ====== MAIN ==================================================================
main() {
  (( DEBUG )) && set -x
  require_cmd adb

  [[ -n "$DEV" ]] || DEV="$(pick_device)"
  adb -s "$DEV" wait-for-device
  log "Using device: $DEV"

  # Cleanup any prior runs for this device
  safe_clean_previous_runs

  RUN_DIR="scripts/results/$DEV/manual_diag_$(ts)"
  STAGE="$RUN_DIR/stage"
  mkdir -p "$RUN_DIR" "$STAGE"

  # Health
  log "Health: adb get-state";               adb -s "$DEV" get-state
  log "Health: adb shell echo OK";           adb -s "$DEV" shell echo OK
  log "Health: identity & version";          adb -s "$DEV" shell 'id; whoami; getprop ro.build.version.release' || true

  # Package selection
  if ! PKG="$(pick_installed_pkg)"; then
    die "None of the target packages are resolvable via 'pm path': ${PKG_CANDIDATES[*]}"
  fi
  log "Target package: $PKG (installed)"

  # pm path raw + sanitized
  local RAW="$RUN_DIR/pm_path_raw.txt"
  local SAN="$RUN_DIR/pm_path_sanitized.txt"
  log "pm path (raw, first 20 lines)"
  pm_path_raw_to_file "$PKG" "$RAW"
  sed -n '1,20p' "$RAW"
  sanitize_pm_path_file "$RAW" "$SAN"
  if ! grep -qE '\.apk($|[^/])' "$SAN"; then
    log "WARN: sanitized list has no .apk-looking entries; check raw input & sanitizer."
  fi
  local TOTAL; TOTAL=$(sed '/^$/d' "$SAN" | wc -l || true)
  log "pm path (sanitized, first 20) — total=$TOTAL"
  sed -n '1,20p' "$SAN"

  # Existence check
  verify_paths_exist "$SAN" "$RUN_DIR/existence.csv"

  # Optional: list TikTok-ish split filenames
  list_tiktok_splits "$SAN"

  # Pulls
  pull_base_and_or_all "$SAN" "$STAGE"

  # Retry simulation + third-party preview
  retry_simulation "$PKG"
  third_party_preview "$RUN_DIR/third_party_preview.csv"

  # TikTok scans
  scan_tiktok_family
  scan_tiktok_related

  log "Artifacts in: $RUN_DIR"
  log "DONE."
}

main "$@"
