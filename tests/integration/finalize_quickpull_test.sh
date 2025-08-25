#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/../.. && pwd)"
export REPO_ROOT="$ROOT"
export RESULTS_DIR="$ROOT/results_test"
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"
source "$ROOT/config/config.sh" >/dev/null 2>&1
source "$ROOT/config/packages.sh" >/dev/null 2>&1
VENDOR="acme"
MODEL="phone_x"
DEV_SERIAL="FAKE123"
DEV_DIR="${VENDOR}_${MODEL}_${DEV_SERIAL}"
RUN_DIR="$RESULTS_DIR/$DEV_DIR/quick_pull_20240101_000000"
mkdir -p "$RESULTS_DIR/$DEV_DIR"
cat >"$RESULTS_DIR/$DEV_DIR/device_profile.txt" <<EOF
serial=$DEV_SERIAL
vendor=$VENDOR
model=$MODEL
android_version=14
build_id=TESTBUILD
EOF
for pkg in "${!FRIENDLY_DIR_MAP[@]}"; do
  mkdir -p "$RUN_DIR/$pkg/pulled"
  echo "$pkg" > "$RUN_DIR/$pkg/pulled/base.apk"
done
# add a split apk for one package to verify manifest handles splits
mkdir -p "$RUN_DIR/com.facebook.katana/pulled"
echo split > "$RUN_DIR/com.facebook.katana/pulled/split_config.en.apk"

"$ROOT/steps/finalize_quickpull.sh" >/tmp/finalize.log

MANIFEST="$RESULTS_DIR/$DEV_DIR/quick_pull_results/manifest.csv"
[ -f "$MANIFEST" ]
grep -q '^app_dir,app_file,package,versionName,versionCode,apk_role,' "$MANIFEST"
grep -q 'split_config.en.apk' "$MANIFEST"

for pkg in "${!FRIENDLY_DIR_MAP[@]}"; do
  dir="${FRIENDLY_DIR_MAP[$pkg]}"
  file="${FRIENDLY_FILE_MAP[$pkg]}.apk"
  [ -f "$RESULTS_DIR/$DEV_DIR/quick_pull_results/$dir/$file" ]
done

rm -rf "$RESULTS_DIR"
echo "finalize_quickpull_test OK"
