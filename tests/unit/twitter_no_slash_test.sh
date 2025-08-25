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
cat >"$RESULTS_DIR/$DEV_DIR/device_profile.txt" <<EOP
serial=$DEV_SERIAL
vendor=$VENDOR
model=$MODEL
android_version=14
build_id=TESTBUILD
EOP
mkdir -p "$RUN_DIR/com.twitter.android/pulled"
echo com.twitter.android > "$RUN_DIR/com.twitter.android/pulled/base.apk"
"$ROOT/steps/finalize_quickpull.sh" >/tmp/finalize_twitter.log
MANIFEST="$RESULTS_DIR/$DEV_DIR/quick_pull_results/manifest.csv"
line=$(grep ',com.twitter.android,' "$MANIFEST")
app_dir=$(echo "$line" | cut -d, -f1)
app_file=$(echo "$line" | cut -d, -f2)
[[ "$app_dir" != *'/'* ]]
[[ "$app_file" != *'/'* ]]
[ -f "$RESULTS_DIR/$DEV_DIR/quick_pull_results/$app_dir/$app_file" ]
rm -rf "$RESULTS_DIR"
echo "twitter_no_slash_test OK"
