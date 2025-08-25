#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/../.. && pwd)"
export REPO_ROOT="$ROOT"
export RESULTS_DIR="$ROOT/results_test"
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"
source "$ROOT/config/config.sh" >/dev/null 2>&1
source "$ROOT/config/packages.sh" >/dev/null 2>&1
DEV="FAKE123"
RUN_DIR="$RESULTS_DIR/$DEV/quick_pull_20240101_000000"
for pkg in "${!FRIENDLY_DIR_MAP[@]}"; do
  mkdir -p "$RUN_DIR/$pkg/pulled"
  echo "$pkg" > "$RUN_DIR/$pkg/pulled/base.apk"
done
# add a split apk for one package to verify manifest handles splits
mkdir -p "$RUN_DIR/com.facebook.katana/pulled"
echo split > "$RUN_DIR/com.facebook.katana/pulled/split_config.en.apk"

"$ROOT/steps/finalize_quickpull.sh" >/tmp/finalize.log

MANIFEST="$RESULTS_DIR/$DEV/quick_pull_results/manifest.csv"
[ -f "$MANIFEST" ]
grep -q 'split_config.en.apk' "$MANIFEST"

for pkg in "${!FRIENDLY_DIR_MAP[@]}"; do
  dir="${FRIENDLY_DIR_MAP[$pkg]}"
  file="${FRIENDLY_FILE_MAP[$pkg]}.apk"
  [ -f "$RESULTS_DIR/$DEV/quick_pull_results/$dir/$file" ]
done

rm -rf "$RESULTS_DIR"
echo "finalize_quickpull_test OK"
