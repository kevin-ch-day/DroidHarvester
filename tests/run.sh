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

echo "OK: tests passed"
