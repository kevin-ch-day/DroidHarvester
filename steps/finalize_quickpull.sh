#!/usr/bin/env bash
# ---------------------------------------------------
# steps/finalize_quickpull.sh
# Normalize the latest quick pull into friendly names
# and a stable output folder with a manifest.
# ---------------------------------------------------
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND" >&2' ERR

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -P "${SCRIPT_DIR}/.." && pwd)"

# Configs (tolerate split)
try_source(){ [[ -r "$1" ]] && source "$1" >/dev/null 2>&1 || true; }  # shellcheck disable=SC1091
try_source "$REPO_ROOT/config/config.sh"
try_source "$REPO_ROOT/config/paths.sh"
try_source "$REPO_ROOT/config/packages.sh"   # optional: user-defined friendly maps

RESULTS_DIR="${RESULTS_DIR:-$REPO_ROOT/results}"

# Find newest quick pull directory, preferring raw pulls over finalized copies
pick_latest_quickpull() {
  local raw stable
  raw="$(ls -1dt "$RESULTS_DIR"/*/quick_pull_* 2>/dev/null | head -1 || true)"
  stable="$(ls -1dt "$RESULTS_DIR"/*/quick_pull_results 2>/dev/null | head -1 || true)"

  if [[ -n "$raw" ]]; then
    echo "$raw"
  elif [[ -n "$stable" ]]; then
    echo "$stable"
  fi
}

SRC_ROOT="$(pick_latest_quickpull || true)"
[[ -n "${SRC_ROOT:-}" && -d "$SRC_ROOT" ]] || { echo "[FATAL] No quick pull folder found."; exit 1; }

SERIAL="$(basename "$(dirname "$SRC_ROOT")")"
DST_ROOT="$RESULTS_DIR/$SERIAL/quick_pull_results"
mkdir -p "$DST_ROOT"

echo "[INFO] Source : $SRC_ROOT"
echo "[INFO] Output : $DST_ROOT"

# ---- Friendly names ----
# Preferred: allow repo config to define FRIENDLY_DIR_MAP and FRIENDLY_FILE_MAP
#   declare -A FRIENDLY_DIR_MAP=( [com.facebook.katana]=facebook_app ... )
#   declare -A FRIENDLY_FILE_MAP=( [com.facebook.katana]=facebook_app ... )
declare -A _DEFAULT_DIR_MAP=(
  [com.zhiliaoapp.musically]=tiktok
  [com.facebook.katana]=facebook_app
  [com.facebook.orca]=messenger
  [com.snapchat.android]=snapchat
  [com.twitter.android]=twitter
  [com.instagram.android]=instagram
  [com.whatsapp]=whatsapp
)
declare -A _DEFAULT_FILE_MAP=(
  [com.zhiliaoapp.musically]=tiktok_app
  [com.facebook.katana]=facebook_app
  [com.facebook.orca]=messenger_app
  [com.snapchat.android]=snapchat_app
  [com.twitter.android]=twitter_app
  [com.instagram.android]=instagram_app
  [com.whatsapp]=whatsapp_app
)

to_safe() { echo "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_.' '_' ; }

# Pick value from user map if defined, else default, else safe(pkg)
friendly_dir_for() {
  local pkg="$1"
  if declare -p FRIENDLY_DIR_MAP >/dev/null 2>&1 && [[ -n "${FRIENDLY_DIR_MAP[$pkg]+x}" ]]; then
    echo "${FRIENDLY_DIR_MAP[$pkg]}"
  elif [[ -n "${_DEFAULT_DIR_MAP[$pkg]+x}" ]]; then
    echo "${_DEFAULT_DIR_MAP[$pkg]}"
  else
    to_safe "$pkg"
  fi
}
friendly_file_for() {
  local pkg="$1"
  if declare -p FRIENDLY_FILE_MAP >/dev/null 2>&1 && [[ -n "${FRIENDLY_FILE_MAP[$pkg]+x}" ]]; then
    echo "${FRIENDLY_FILE_MAP[$pkg]}"
  elif [[ -n "${_DEFAULT_FILE_MAP[$pkg]+x}" ]]; then
    echo "${_DEFAULT_FILE_MAP[$pkg]}"
  else
    to_safe "$pkg"
  fi
}

unique_dest() {
  local dest="$1"
  [[ ! -e "$dest" ]] && { printf '%s' "$dest"; return; }
  local base="${dest%.*}" ext="${dest##*.}" i=1
  while [[ -e "${base}.${i}.${ext}" ]]; do ((i++)); done
  printf '%s' "${base}.${i}.${ext}"
}

sha256_host() {
  local f="$1"
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$f" | awk '{print $1}'
  else shasum -a 256 "$f" | awk '{print $1}'; fi
}

MAN_CSV="$DST_ROOT/manifest.csv"
if [[ ! -s "$MAN_CSV" ]]; then
  echo "app_dir,app_file,package,versionName,versionCode,kind,bytes,sha256,src,dst" > "$MAN_CSV"
fi

shopt -s nullglob
changed=0
for pkg_dir in "$SRC_ROOT"/*; do
  [[ -d "$pkg_dir" ]] || continue
  pkg="$(basename "$pkg_dir")"

  # Locate pulled dir
  pulled="$pkg_dir/pulled"
  [[ -d "$pulled" ]] || pulled="$(find "$pkg_dir" -maxdepth 2 -type d -name 'pulled' | head -1 || true)"
  [[ -d "$pulled" ]] || continue

  app_dir="$(friendly_dir_for "$pkg")"
  file_base="$(friendly_file_for "$pkg")"
  dst_app_dir="$DST_ROOT/$app_dir"
  mkdir -p "$dst_app_dir"

  vname="" vcode=""
  if [[ -f "$pkg_dir/meta/meta.csv" ]]; then
    read -r _line < <(tail -n +2 "$pkg_dir/meta/meta.csv" 2>/dev/null || true)
    IFS=',' read -r _pkg vname vcode _installer <<< "${_line:-,,}"
  fi

  for src_apk in "$pulled"/*.apk; do
    [[ -f "$src_apk" ]] || continue
    bn="$(basename "$src_apk")"
    kind="split"
    out_name="$file_base"

    if [[ "$bn" == "base.apk" ]]; then
      kind="base"
      [[ -n "$vname" || -n "$vcode" ]] && out_name="${out_name}_v${vname:-NA}_${vcode:-NA}"
      out_file="${out_name}.apk"
    elif [[ "$bn" == split_*.apk ]]; then
      suffix="${bn#split_}"
      out_file="${out_name}_$suffix"
    else
      out_file="${out_name}_${bn}"
    fi

    dst="$dst_app_dir/$out_file"
    dst="$(unique_dest "$dst")"
    cp -f "$src_apk" "$dst"
    ((changed++))

    bytes="$(stat -c %s "$dst" 2>/dev/null || wc -c < "$dst")"
    hash="$(sha256_host "$dst")"
    echo "$app_dir,$out_file,$pkg,${vname:-},${vcode:-},$kind,$bytes,$hash,$src_apk,$dst" >> "$MAN_CSV"

    echo "[COPY] $pkg: $bn -> $app_dir/$out_file"
  done
done

echo
echo "[OK] Friendly copies under: $DST_ROOT"
echo "     manifest: $MAN_CSV"
[[ $changed -gt 0 ]] || echo "[WARN] No new APKs were copied (nothing to do)."

