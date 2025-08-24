#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/.. && pwd)"
export PATH="$ROOT/tests/fakes:$PATH"

# Repo guards
if rg -n 'get-transport-id' -g '!tests/run.sh' -g '!scripts/archive/*' > /tmp/gtid.txt 2>&1; then
  cat /tmp/gtid.txt
  echo "get-transport-id found" >&2
  exit 1
fi
if rg -n '\\btimeout\\b.*adb_retry' -g '!tests/run.sh' -g '!scripts/archive/*' > /tmp/tmo.txt 2>&1; then
  cat /tmp/tmo.txt
  echo "timeout adb_retry pattern found" >&2
  exit 1
fi

# Load helpers
# shellcheck disable=SC1090
. "$ROOT/lib/core/logging.sh"
export LOGFILE=/dev/null
# shellcheck disable=SC1090
. "$ROOT/lib/core/trace.sh"
# shellcheck disable=SC1090
. "$ROOT/lib/core/device.sh"
# shellcheck disable=SC1090
. "$ROOT/lib/io/apk_utils.sh"

# Debug print from set_device should hex-dump the serial
out=$(DEBUG=1 set_device 'ZY22JK89DR ' 2>&1)
printf '%s\n' "$out" | grep -q '\[DEBUG\] DEV bytes:'
printf '%s\n' "$out" | grep -q '5a 59 32 32 4a 4b 38 39'
printf '%s\n' "$out" | grep -qv '0d'

# Case 1: good device with trailing space
out=$(FAKE_ADB_SCENARIO=good DEBUG=1 DH_DRY_RUN=1 "$ROOT/scripts/adb_apk_diag.sh" 2>&1)
hex_line=$(printf '%s\n' "$out" | grep '\[DEBUG\] DEV bytes:')
printf '%s\n' "$hex_line" | grep -q '5a 59 32 32 4a 4b 38 39[[:space:]]*44 52'
printf '%s\n' "$hex_line" | grep -q '|ZY22JK89DR|'
printf '%s\n' "$hex_line" | grep -qv '0d'
printf '%s\n' "$out" | grep -q 'Artifacts in:'

# Case 1b: CR in serial trimmed
out=$(FAKE_ADB_SCENARIO=crlf DEBUG=1 DH_DRY_RUN=1 "$ROOT/scripts/adb_apk_diag.sh" 2>&1)
hex_line=$(printf '%s\n' "$out" | grep '\[DEBUG\] DEV bytes:')
printf '%s\n' "$hex_line" | grep -q '|ZY22JK89DR|'
printf '%s\n' "$hex_line" | grep -qv '0d'

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

# Scan success (plain pm list)
out=$(FAKE_ADB_SCENARIO=good adb -s ZY22JK89DR shell pm list packages)
printf '%s\n' "$out" | grep -q 'package:com.zhiliaoapp.musically'

# Scan success via wrapper (mirrors menu path)
set_device ZY22JK89DR
out=$(FAKE_ADB_SCENARIO=good adb_retry "$DH_SHELL_TIMEOUT" "$DH_RETRIES" "$DH_BACKOFF" pm_list -- shell pm list packages 2>&1)
printf '%s\n' "$out" | grep -q 'package:com.zhiliaoapp.musically'

# Scan failure via wrapper
if out=$(FAKE_ADB_SCENARIO=list_fail adb_retry "$DH_SHELL_TIMEOUT" "$DH_RETRIES" "$DH_BACKOFF" pm_list -- shell pm list packages 2>&1); then
  echo "expected wrapper list failure" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -q 'cmd: failure'

# Noise guard: scan_apps output should not leak 'device'
tmp=$(mktemp)
FAKE_ADB_SCENARIO=good ROOT="$ROOT" bash -c '
  set -euo pipefail
  source "$ROOT/lib/core/errors.sh"
  source "$ROOT/lib/core/logging.sh"
  LOGFILE=/dev/null
  source "$ROOT/lib/core/trace.sh"
  source "$ROOT/lib/core/device.sh"
  source "$ROOT/lib/actions/scan_apps.sh"
  TARGET_PACKAGES=("com.zhiliaoapp.musically")
  set_device ZY22JK89DR
  scan_apps
' >"$tmp" 2>&1
grep -q 'Found: com.zhiliaoapp.musically' "$tmp"
if grep -q '^device$' "$tmp"; then
  echo "unexpected device noise" >&2
  exit 1
fi

# Scan failure without debug should not print CMD
tmp_fail=$(mktemp)
if FAKE_ADB_SCENARIO=list_fail ROOT="$ROOT" bash -c '
  set -euo pipefail
  source "$ROOT/lib/core/errors.sh"
  source "$ROOT/lib/core/logging.sh"
  LOGFILE=/dev/null
  source "$ROOT/lib/core/trace.sh"
  source "$ROOT/lib/core/device.sh"
  source "$ROOT/lib/actions/scan_apps.sh"
  TARGET_PACKAGES=("com.zhiliaoapp.musically")
  set_device ZY22JK89DR
  scan_apps
' >"$tmp_fail" 2>&1; then
  echo "expected scan failure" >&2
  exit 1
fi
grep -q 'failed to list packages' "$tmp_fail"
if grep -q '\[CMD\]' "$tmp_fail"; then
  echo "CMD leaked" >&2
  exit 1
fi

# Scan failure with debug should print CMD
tmp_fail_dbg=$(mktemp)
if FAKE_ADB_SCENARIO=list_fail DH_DEBUG=1 ROOT="$ROOT" bash -c '
  set -euo pipefail
  source "$ROOT/lib/core/errors.sh"
  source "$ROOT/lib/core/logging.sh"
  LOGFILE=/dev/null
  source "$ROOT/lib/core/trace.sh"
  source "$ROOT/lib/core/device.sh"
  source "$ROOT/lib/actions/scan_apps.sh"
  TARGET_PACKAGES=("com.zhiliaoapp.musically")
  set_device ZY22JK89DR
  scan_apps
' >"$tmp_fail_dbg" 2>&1; then
  echo "expected scan failure" >&2
  exit 1
fi
grep -q '\[CMD\]' "$tmp_fail_dbg"

# Pull success via helper
rm -rf /tmp/pull_good
FAKE_ADB_SCENARIO=good ROOT="$ROOT" bash -c '
  set -euo pipefail
  source "$ROOT/lib/core/logging.sh"
  LOGFILE=/dev/null
  source "$ROOT/lib/core/trace.sh"
  source "$ROOT/lib/core/device.sh"
  source "$ROOT/lib/io/apk_utils.sh"
  set_device ZY22JK89DR
  run_adb_pull_with_fallbacks /data/app/com.zhiliaoapp.musically-1/base.apk /tmp/pull_good/base.apk
' >/tmp/pull_good.log 2>&1
[ -s /tmp/pull_good/base.apk ]

# Pull permission fallback success
rm -rf /tmp/pull_perm
FAKE_ADB_SCENARIO=pull_perm ROOT="$ROOT" bash -c '
  set -euo pipefail
  source "$ROOT/lib/core/logging.sh"
  LOGFILE=/dev/null
  source "$ROOT/lib/core/trace.sh"
  source "$ROOT/lib/core/device.sh"
  source "$ROOT/lib/io/apk_utils.sh"
  set_device ZY22JK89DR
  run_adb_pull_with_fallbacks /data/app/com.zhiliaoapp.musically-1/base.apk /tmp/pull_perm/base.apk
' >/tmp/pull_perm.log 2>&1
[ -s /tmp/pull_perm/base.apk ]

# Pull failure after fallback
rm -rf /tmp/pull_fail
if FAKE_ADB_SCENARIO=pull_fail ROOT="$ROOT" bash -c '
  set -euo pipefail
  source "$ROOT/lib/core/logging.sh"
  LOGFILE=/dev/null
  source "$ROOT/lib/core/trace.sh"
  source "$ROOT/lib/core/device.sh"
  source "$ROOT/lib/io/apk_utils.sh"
  set_device ZY22JK89DR
  run_adb_pull_with_fallbacks /data/app/com.zhiliaoapp.musically-1/base.apk /tmp/pull_fail/base.apk
' >/tmp/pull_fail.log 2>&1; then
  echo "expected pull failure" >&2
  exit 1
fi
grep -q 'Permission denied' /tmp/pull_fail.log

echo "OK: tests passed"
