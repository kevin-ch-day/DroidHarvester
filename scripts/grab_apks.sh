#!/usr/bin/env bash
# scripts/grab_apks.sh — No-args APK puller (base + splits)
set -euo pipefail
set -E
trap 'echo "[ERR] ${BASH_SOURCE[0]}:$LINENO" >&2' ERR

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -P "${SCRIPT_DIR}/.." && pwd)"

# Load config (repo-style)
if [[ -r "${REPO_ROOT}/config/config.sh" ]]; then
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/config/config.sh"
else
  echo "[FATAL] config/config.sh not found" >&2
  exit 64
fi

TS="$(date +%Y%m%d_%H%M%S)"

# shellcheck disable=SC1090
source "$REPO_ROOT/lib/logging/logging_engine.sh"
# shellcheck disable=SC1090
source "$REPO_ROOT/lib/io/pull_file.sh"
log_file_init "$(_log_path apk_grab)"

# adb + device
ADB_BIN="${ADB_BIN:-$(command -v adb || true)}"
[[ -x "${ADB_BIN:-}" ]] || { log ERROR "adb not found"; exit 2; }
SERIAL="$("$ADB_BIN" get-serialno 2>/dev/null || true)"
[[ -n "$SERIAL" && "$SERIAL" != "unknown" ]] || { log ERROR "no device"; exit 3; }
ADB_S=(-s "$SERIAL")

to_safe() { echo "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '_'; }

DEVICE_VENDOR="$("$ADB_BIN" "${ADB_S[@]}" shell getprop ro.product.manufacturer | tr -d '\r')"
DEVICE_MODEL="$("$ADB_BIN" "${ADB_S[@]}" shell getprop ro.product.model | tr -d '\r')"
DEVICE_ANDROID_VERSION="$("$ADB_BIN" "${ADB_S[@]}" shell getprop ro.build.version.release | tr -d '\r')"
DEVICE_BUILD_ID="$("$ADB_BIN" "${ADB_S[@]}" shell getprop ro.build.id | tr -d '\r')"
safe_vendor="$(to_safe "$DEVICE_VENDOR")"
safe_model="$(to_safe "$DEVICE_MODEL")"
DEVICE_DIR_NAME="${safe_vendor}_${safe_model}_${SERIAL}"
DEVICE_DIR="${RESULTS_DIR}/${DEVICE_DIR_NAME}"
OUT_ROOT="${DEVICE_DIR}/quick_pull_${TS}"
mkdir -p "$OUT_ROOT"
DEVICE_LABEL="$DEVICE_VENDOR $DEVICE_MODEL [$SERIAL]"
LOG_DEV="$DEVICE_LABEL"
export LOG_DEV
{
  echo "serial=$SERIAL"
  echo "vendor=$DEVICE_VENDOR"
  echo "model=$DEVICE_MODEL"
  echo "android_version=$DEVICE_ANDROID_VERSION"
  echo "build_id=$DEVICE_BUILD_ID"
  "$ADB_BIN" "${ADB_S[@]}" shell getprop
} > "$DEVICE_DIR/device_profile.txt" 2>/dev/null || true

# Targets from config (plus any customs that config appended)
(( ${#TARGET_PACKAGES[@]} )) || { log WARN "no targets defined"; exit 0; }

log INFO "device : $DEVICE_LABEL"
log INFO "output : $OUT_ROOT"
log INFO "targets: ${TARGET_PACKAGES[*]}"

sanitize_paths() { tr -d '\r' | sed -n 's/^package://p'; }
order_base_first() {
  awk '/\/base\.apk$/{print;next}{a[NR]=$0}END{for(i=1;i<=NR;i++) if (a[i] && a[i]!~/\/base\.apk$/) print a[i]}'
}
get_pm_paths() {
  local pkg="$1" out=""
  out="$("$ADB_BIN" "${ADB_S[@]}" shell cmd package path "$pkg" 2>/dev/null || true)"
  [[ -z "$out" ]] && out="$("$ADB_BIN" "${ADB_S[@]}" shell pm  path "$pkg" 2>/dev/null || true)"
  printf "%s" "$out"
}
remote_size() {
  local p="$1"
  "$ADB_BIN" "${ADB_S[@]}" shell "toybox stat -c %s \"$p\" 2>/dev/null || stat -c %s \"$p\" 2>/dev/null || ls -l \"$p\" 2>/dev/null | awk '{print \$5}'" \
    | tr -d '\r' | head -1 || true
}
sha256_host() {
  local f="$1"
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$f" | awk '{print $1}'
  else shasum -a 256 "$f" | awk '{print $1}'; fi
}
pull_one_pkg() {
  local pkg="$1"
  local pkg_root="$OUT_ROOT/$pkg"
  local pm_dir="$pkg_root/pm"
  local meta_dir="$pkg_root/meta"
  local pulled="$pkg_root/pulled"
  mkdir -p "$pm_dir" "$meta_dir" "$pulled"

  log INFO "$pkg: discovering APKs..."
  local raw; raw="$(get_pm_paths "$pkg")"
  printf "%s\n" "$raw"                        > "$pm_dir/raw.txt"
  printf "%s\n" "$raw" | sanitize_paths       > "$pm_dir/san.txt"

  local paths; paths="$(printf "%s\n" "$raw" | sanitize_paths | order_base_first)"
  if [[ -z "$paths" ]]; then
    log WARN "$pkg: no paths (not installed?)"
    return 0
  fi

  "$ADB_BIN" "${ADB_S[@]}" shell dumpsys package "$pkg" 2>/dev/null | tr -d '\r' > "$meta_dir/dumpsys.txt" || true
  local vn vc inst
  vn="$(grep -m1 -oE 'versionName=[^ ]+' "$meta_dir/dumpsys.txt" | cut -d= -f2 || true)"
  vc="$(grep -m1 -oE 'versionCode=[^ ]+' "$meta_dir/dumpsys.txt" | cut -d= -f2 || true)"
  inst="$(grep -m1 -oE 'installerPackageName=[^ ]+' "$meta_dir/dumpsys.txt" | cut -d= -f2 || true)"
  printf "pkg,versionName,versionCode,installer\n%s,%s,%s,%s\n" "$pkg" "${vn:-}" "${vc:-}" "${inst:-}" > "$meta_dir/meta.csv"

  local csv="$pkg_root/pull_manifest.csv"
  echo "pkg,apk_role,remote_path,remote_bytes,local_bytes,sha256,status" > "$csv"

  while IFS= read -r rp; do
    [[ -n "$rp" ]] || continue
    local apk_role="split"; [[ "$rp" =~ /base\.apk$ ]] && apk_role="base"
    local rb; rb="$(remote_size "$rp" || echo 0)"; rb="${rb:-0}"
    local fn; fn="$(basename "$rp")"
    local dest="$pulled/$fn"

    log INFO "$pkg: pulling $fn ($rb bytes)..."
    if safe_pull_file "$rp" "$dest"; then
      local lb; lb="$(stat -c %s "$dest" 2>/dev/null || wc -c < "$dest" 2>/dev/null || echo 0)"
      local sh; sh="$(sha256_host "$dest" 2>/dev/null || echo NA)"
      local status="OK"; [[ "$rb" != "0" && "$lb" != "$rb" ]] && status="SIZE_MISMATCH"
      printf "%s,%s,%s,%s,%s,%s,%s\n" "$pkg" "$apk_role" "$rp" "$rb" "$lb" "$sh" "$status" >> "$csv"
    else
      printf "%s,%s,%s,%s,%s,%s,%s\n" "$pkg" "$apk_role" "$rp" "$rb" "0" "NA" "PULL_FAIL" >> "$csv"
      log WARN "$pkg: pull failed for $fn"
      rm -f "$dest" || true
    fi
  done <<< "$paths"

  if compgen -G "$pulled/*.apk" >/dev/null; then
    (
      cd "$pulled"
      if command -v sha256sum >/dev/null 2>&1; then
        sha256sum *.apk > hashes.sha256
      else
        shasum -a 256 *.apk > hashes.sha256
      fi
    ) || true
  fi

  log SUCCESS "$pkg → $pkg_root"
}

for pkg in "${TARGET_PACKAGES[@]}"; do
  pull_one_pkg "$pkg"
done

log SUCCESS "Artifacts under: $OUT_ROOT"
