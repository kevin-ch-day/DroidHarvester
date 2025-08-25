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

# Transcript to /log
TS="$(date +%Y%m%d_%H%M%S)"
LOGFILE="${LOG_ROOT}/apk_grab_${TS}.txt"
exec > >(tee -a "$LOGFILE") 2>&1
echo "[INFO] transcript: $LOGFILE"

# adb + device
ADB_BIN="${ADB_BIN:-$(command -v adb || true)}"
[[ -x "${ADB_BIN:-}" ]] || { echo "[FATAL] adb not found"; exit 2; }
SERIAL="$("$ADB_BIN" get-serialno 2>/dev/null || true)"
[[ -n "$SERIAL" && "$SERIAL" != "unknown" ]] || { echo "[FATAL] no device"; exit 3; }
ADB_S=(-s "$SERIAL")

OUT_ROOT="${RESULTS_DIR}/${SERIAL}/quick_pull_${TS}"
mkdir -p "$OUT_ROOT"

# Targets from config (plus any customs that config appended)
(( ${#TARGET_PACKAGES[@]} )) || { echo "[WARN] no targets defined"; exit 0; }

echo "[INFO] device : $SERIAL"
echo "[INFO] output : $OUT_ROOT"
echo "[INFO] targets: ${TARGET_PACKAGES[*]}"

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
safe_pull_file() {
  # 1) try adb pull; 2) fallback to adb exec-out cat stream
  local remote="$1" dest="$2"
  if "$ADB_BIN" "${ADB_S[@]}" pull "$remote" "$dest" >/dev/null 2>&1; then
    return 0
  fi
  # fallback stream
  if "$ADB_BIN" "${ADB_S[@]}" exec-out "cat \"$remote\"" > "${dest}.part" 2>/dev/null; then
    mv -f "${dest}.part" "$dest"
    return 0
  fi
  rm -f "${dest}.part" >/dev/null 2>&1 || true
  return 1
}

pull_one_pkg() {
  local pkg="$1"
  local pkg_root="$OUT_ROOT/$pkg"
  local pm_dir="$pkg_root/pm"
  local meta_dir="$pkg_root/meta"
  local pulled="$pkg_root/pulled"
  mkdir -p "$pm_dir" "$meta_dir" "$pulled"

  echo "[INFO] $pkg: discovering APKs..."
  local raw; raw="$(get_pm_paths "$pkg")"
  printf "%s\n" "$raw"                        > "$pm_dir/raw.txt"
  printf "%s\n" "$raw" | sanitize_paths       > "$pm_dir/san.txt"

  local paths; paths="$(printf "%s\n" "$raw" | sanitize_paths | order_base_first)"
  if [[ -z "$paths" ]]; then
    echo "[WARN] $pkg: no paths (not installed?)"
    return 0
  fi

  "$ADB_BIN" "${ADB_S[@]}" shell dumpsys package "$pkg" 2>/dev/null | tr -d '\r' > "$meta_dir/dumpsys.txt" || true
  local vn vc inst
  vn="$(grep -m1 -oE 'versionName=[^ ]+' "$meta_dir/dumpsys.txt" | cut -d= -f2 || true)"
  vc="$(grep -m1 -oE 'versionCode=[^ ]+' "$meta_dir/dumpsys.txt" | cut -d= -f2 || true)"
  inst="$(grep -m1 -oE 'installerPackageName=[^ ]+' "$meta_dir/dumpsys.txt" | cut -d= -f2 || true)"
  printf "pkg,versionName,versionCode,installer\n%s,%s,%s,%s\n" "$pkg" "${vn:-}" "${vc:-}" "${inst:-}" > "$meta_dir/meta.csv"

  local csv="$pkg_root/pull_manifest.csv"
  echo "pkg,apk_type,remote_path,remote_bytes,local_bytes,sha256,status" > "$csv"

  while IFS= read -r rp; do
    [[ -n "$rp" ]] || continue
    local kind="split"; [[ "$rp" =~ /base\.apk$ ]] && kind="base"
    local rb; rb="$(remote_size "$rp" || echo 0)"; rb="${rb:-0}"
    local fn; fn="$(basename "$rp")"
    local dest="$pulled/$fn"

    echo "[INFO] $pkg: pulling $fn ($rb bytes)..."
    if safe_pull_file "$rp" "$dest"; then
      local lb; lb="$(stat -c %s "$dest" 2>/dev/null || wc -c < "$dest" 2>/dev/null || echo 0)"
      local sh; sh="$(sha256_host "$dest" 2>/dev/null || echo NA)"
      local status="OK"; [[ "$rb" != "0" && "$lb" != "$rb" ]] && status="SIZE_MISMATCH"
      printf "%s,%s,%s,%s,%s,%s,%s\n" "$pkg" "$kind" "$rp" "$rb" "$lb" "$sh" "$status" >> "$csv"
    else
      printf "%s,%s,%s,%s,%s,%s,%s\n" "$pkg" "$kind" "$rp" "$rb" "0" "NA" "PULL_FAIL" >> "$csv"
      echo "[WARN] $pkg: pull failed for $fn"
      rm -f "$dest" || true
    fi
  done <<< "$paths"

  if compgen -G "$pulled/*.apk" >/dev/null; then
    ( cd "$pulled"
      if command -v sha256sum >/devnull 2>&1; then sha256sum *.apk > hashes.sha256; else shasum -a 256 *.apk > hashes.sha256; fi
    ) || true
  fi

  echo "[OK]  $pkg → $pkg_root"
}

for pkg in "${TARGET_PACKAGES[@]}"; do
  pull_one_pkg "$pkg"
done

echo "[DONE] Artifacts under: $OUT_ROOT"
