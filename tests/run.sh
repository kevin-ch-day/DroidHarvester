#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/.. && pwd)"
# Prepend the fake-ADB shim to PATH so library calls invoke it
export PATH="$ROOT/tests:$PATH"
export DEV="FAKE_SERIAL"
source "$ROOT/lib/io/apk_utils.sh"

# 0) run.sh rejects CLI args
if "$ROOT/run.sh" --help >/dev/null 2>&1; then
  echo "run.sh accepted arguments" >&2
  exit 1
fi

# 1) pm path sanitize: only strip 'package:'
diff -u <(au_pm_path_raw com.zhiliaoapp.musically | au_pm_path_sanitize) \
         <(sed -n 's/^package://p' "$ROOT/tests/fixtures/pm_path_com_zhiliaoapp_musically.txt") >/dev/null

# 2) list + pick base
SAN=$(mktemp)
au_apk_paths_for_pkg com.zhiliaoapp.musically > "$SAN"
BASE="$(au_pick_base_apk "$SAN")"
[[ "$BASE" == */base.apk ]]

# 3) pull + size + hash (best effort)
LCL=$(au_pull_one "$BASE" "$(mktemp -d)")
[[ -s "$LCL" ]]
au_dev_file_size "$BASE" >/dev/null
au_verify_hash "$BASE" "$LCL" || true

# 4) metadata CSV
au_pkg_meta_csv_line com.zhiliaoapp.musically | grep -q "^com\.zhiliaoapp\.musically,"

# 5) TikTok scans
au_scan_tiktok_family | grep -Eq 'com\.ss\.android\.ugc\.aweme|com\.zhiliaoapp\.musically'
au_scan_tiktok_related | grep -iq tiktok

# 6) diagnostic script runs
DEV="FAKE_SERIAL" "$ROOT/scripts/adb_apk_diag.sh" >/dev/null

echo "OK: tests passed"
