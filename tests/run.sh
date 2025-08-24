#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/.. && pwd)"
export PATH="$ROOT/tests/fakes:$PATH"

# Case 1: good device with trailing space in adb output
out=$(FAKE_ADB_SCENARIO=good DEBUG=1 DH_DRY_RUN=1 "$ROOT/scripts/adb_apk_diag.sh" 2>&1)
hex_line=$(printf '%s\n' "$out" | grep '\[DEBUG\] DEV bytes:')
printf '%s\n' "$hex_line" | grep -q '5a 59 32 32 4a 4b 38 39[[:space:]]*44 52'
printf '%s\n' "$hex_line" | grep -q '|ZY22JK89DR|'
printf '%s\n' "$hex_line" | grep -qv '0d'
printf '%s\n' "$out" | grep -q 'Artifacts in:'

# Case 2: DEV env var with trailing space should be trimmed
out=$(FAKE_ADB_SCENARIO=good DEV='ZY22JK89DR ' DEBUG=1 DH_DRY_RUN=1 "$ROOT/scripts/adb_apk_diag.sh" 2>&1)
printf '%s\n' "$out" | grep -q 'Artifacts in:'

# Case 3: multiple devices triggers error
if FAKE_ADB_SCENARIO=multi "$ROOT/scripts/adb_apk_diag.sh" >/tmp/multi.log 2>&1; then
  echo "expected failure on multiple devices" >&2
  exit 1
fi
grep -q 'multiple devices detected' /tmp/multi.log

# Case 4: unauthorized device triggers error
if FAKE_ADB_SCENARIO=unauthorized "$ROOT/scripts/adb_apk_diag.sh" >/tmp/unauth.log 2>&1; then
  echo "expected failure on unauthorized" >&2
  exit 1
fi
grep -q 'unauthorized' /tmp/unauth.log

# Ensure health script uses normalized serial
FAKE_ADB_SCENARIO=good DH_DRY_RUN=1 "$ROOT/scripts/adb_health.sh" >/dev/null

# Scan success
out=$(FAKE_ADB_SCENARIO=good adb -s ZY22JK89DR shell pm list packages)
printf '%s\n' "$out" | grep -q 'package:com.zhiliaoapp.musically'

# Scan failure
if FAKE_ADB_SCENARIO=list_fail adb -s ZY22JK89DR shell pm list packages >/tmp/scan_fail.log 2>&1; then
  echo "expected scan failure" >&2
  exit 1
fi
grep -q 'cmd: failure' /tmp/scan_fail.log

# Pull success
# Pull success
rm -rf /tmp/pull_good
FAKE_ADB_SCENARIO=good adb -s ZY22JK89DR pull /data/app/com.zhiliaoapp.musically-1/base.apk /tmp/pull_good/base.apk >/tmp/pull_good.log
[ -s /tmp/pull_good/base.apk ]

# Pull permission fallback success
rm -rf /tmp/pull_perm
if FAKE_ADB_SCENARIO=pull_perm adb -s ZY22JK89DR pull /data/app/com.zhiliaoapp.musically-1/base.apk /tmp/pull_perm/base.apk >/tmp/pull_perm.log 2>&1; then
  echo "expected direct pull failure" >&2; exit 1; fi
FAKE_ADB_SCENARIO=pull_perm adb -s ZY22JK89DR shell cp /data/app/com.zhiliaoapp.musically-1/base.apk /data/local/tmp/tmp.apk
FAKE_ADB_SCENARIO=pull_perm adb -s ZY22JK89DR pull /data/local/tmp/tmp.apk /tmp/pull_perm/base.apk
[ -s /tmp/pull_perm/base.apk ]

# Pull failure after fallback
rm -rf /tmp/pull_fail
if FAKE_ADB_SCENARIO=pull_fail adb -s ZY22JK89DR pull /data/app/com.zhiliaoapp.musically-1/base.apk /tmp/pull_fail/base.apk >/tmp/pull_fail.log 2>&1; then
  echo "expected pull failure" >&2; exit 1; fi
FAKE_ADB_SCENARIO=pull_fail adb -s ZY22JK89DR shell cp /data/app/com.zhiliaoapp.musically-1/base.apk /data/local/tmp/tmp.apk >/tmp/pull_fail.log 2>&1 || true
if FAKE_ADB_SCENARIO=pull_fail adb -s ZY22JK89DR pull /data/local/tmp/tmp.apk /tmp/pull_fail/base.apk >/tmp/pull_fail.log 2>&1; then
  echo "expected pull failure" >&2; exit 1; fi
grep -q 'Permission denied' /tmp/pull_fail.log

echo "OK: tests passed"
