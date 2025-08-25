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
if rg -n 'pull.+\| tee' -g '!tests/run.sh' -g '!scripts/archive/*' > /tmp/tee.txt 2>&1; then
  cat /tmp/tee.txt
  echo "tee found in pull path" >&2
  exit 1
fi

"$ROOT/tests/guards/no_root_config_imports.sh"
"$ROOT/tests/guards/no_legacy_log_paths.sh"
"$ROOT/tests/integration/log_write_selftest.sh"
"$ROOT/tests/integration/finalize_quickpull_test.sh"
"$ROOT/tests/unit/twitter_no_slash_test.sh"

# Load helpers
# shellcheck disable=SC1090
. "$ROOT/lib/logging/logging_engine.sh"
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
# Grep positive case
out=$(FAKE_ADB_SCENARIO=good adb -s ZY22JK89DR shell pm list packages | grep -Ei 'tiktok|aweme|trill|musically|bytedance')
printf '%s\n' "$out" | grep -q 'musically'

# Grep negative case
if FAKE_ADB_SCENARIO=good adb -s ZY22JK89DR shell pm list packages | grep -Ei 'notarealpackage' >/tmp/grep_empty.txt; then
  echo "expected empty grep" >&2
  exit 1
fi
[ ! -s /tmp/grep_empty.txt ]



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
  source "$ROOT/lib/logging/logging_engine.sh"
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
  source "$ROOT/lib/logging/logging_engine.sh"
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
  source "$ROOT/lib/logging/logging_engine.sh"
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
  source "$ROOT/lib/logging/logging_engine.sh"
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
  source "$ROOT/lib/logging/logging_engine.sh"
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
  source "$ROOT/lib/logging/logging_engine.sh"
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
grep -q 'direct pull failed' /tmp/pull_fail.log

# APK path resolution success
out=$(FAKE_ADB_SCENARIO=good ROOT="$ROOT" bash -c '
  set -euo pipefail
  PATH="$ROOT/tests/fakes:$PATH"
  source "$ROOT/lib/logging/logging_engine.sh"; LOGFILE=/dev/null
  source "$ROOT/lib/core/trace.sh"
  source "$ROOT/lib/core/device.sh"
  source "$ROOT/lib/io/apk_utils.sh"
  set_device ZY22JK89DR
  apk_get_paths com.zhiliaoapp.musically
')
printf '%s\n' "$out" | grep -q '/data/app/com.zhiliaoapp.musically-1/base.apk'
printf '%s\n' "$out" | grep -q '/data/app/com.zhiliaoapp.musically-1/split_config.en.apk'

# APK path resolution failure
out=$(FAKE_ADB_SCENARIO=good ROOT="$ROOT" bash -c '
  set -euo pipefail
  PATH="$ROOT/tests/fakes:$PATH"
  source "$ROOT/lib/logging/logging_engine.sh"; LOGFILE=/dev/null
  source "$ROOT/lib/core/trace.sh"
  source "$ROOT/lib/core/device.sh"
  source "$ROOT/lib/io/apk_utils.sh"
  set_device ZY22JK89DR
  apk_get_paths com.whatsapp
')
printf '%s\n' "$out" | grep -q '/data/app/.*base.apk'

# apk_paths_verify covers OK and MISSING
verify=$(FAKE_ADB_SCENARIO=good ROOT="$ROOT" bash -c '
  set -euo pipefail
  PATH="$ROOT/tests/fakes:$PATH"
  source "$ROOT/lib/logging/logging_engine.sh"; LOGFILE=/dev/null
  source "$ROOT/lib/core/trace.sh"
  source "$ROOT/lib/core/device.sh"
  source "$ROOT/lib/io/apk_utils.sh"
  set_device ZY22JK89DR
  printf "/data/app/com.zhiliaoapp.musically-1/base.apk\n/data/app/doesnotexist.apk\n" | apk_paths_verify
')
printf '%s\n' "$verify" | grep -q $'/data/app/com.zhiliaoapp.musically-1/base.apk\tOK'
printf '%s\n' "$verify" | grep -q $'/data/app/doesnotexist.apk\tMISSING'

# Third-party package listing
out=$(FAKE_ADB_SCENARIO=good ROOT="$ROOT" bash -c '
  set -euo pipefail
  PATH="$ROOT/tests/fakes:$PATH"
  source "$ROOT/lib/logging/logging_engine.sh"; LOGFILE=/dev/null
  source "$ROOT/lib/core/trace.sh"
  source "$ROOT/lib/core/device.sh"
  source "$ROOT/lib/io/apk_utils.sh"
  set_device ZY22JK89DR
  apk_list_third_party
')
printf '%s\n' "$out" | grep -q '^com.zhiliaoapp.musically$'
printf '%s\n' "$out" | grep -q '^com.example.app$'

# device-side hashing
hash=$(FAKE_ADB_SCENARIO=good ROOT="$ROOT" bash -c '
  set -euo pipefail
  PATH="$ROOT/tests/fakes:$PATH"
  source "$ROOT/lib/logging/logging_engine.sh"; LOGFILE=/dev/null
  source "$ROOT/lib/core/trace.sh"
  source "$ROOT/lib/core/device.sh"
  source "$ROOT/lib/io/apk_utils.sh"
  set_device ZY22JK89DR
  device_sha256 /data/app/com.zhiliaoapp.musically-1/base.apk
')
[ "$hash" = "161e286b4118f3d163973f551caf1de560888fa9196f767023c6ae40fe792e50" ]

# device-side hashing absent should yield empty
hash=$(FAKE_ADB_SCENARIO=nosha ROOT="$ROOT" bash -c '
  set -euo pipefail
  PATH="$ROOT/tests/fakes:$PATH"
  source "$ROOT/lib/logging/logging_engine.sh"; LOGFILE=/dev/null
  source "$ROOT/lib/core/trace.sh"
  source "$ROOT/lib/core/device.sh"
  source "$ROOT/lib/io/apk_utils.sh"
  set_device ZY22JK89DR
  device_sha256 /data/app/com.zhiliaoapp.musically-1/base.apk || true
')
hash=$(printf '%s' "$hash")
[ -z "$hash" ]

# Pull without sha256sum should still succeed
rm -rf /tmp/pull_nosha
FAKE_ADB_SCENARIO=nosha ROOT="$ROOT" bash -c '
  set -euo pipefail
  PATH="$ROOT/tests/fakes:$PATH"
  source "$ROOT/lib/logging/logging_engine.sh"; LOGFILE=/dev/null
  source "$ROOT/lib/core/trace.sh"
  source "$ROOT/lib/core/device.sh"
  source "$ROOT/lib/io/apk_utils.sh"
  set_device ZY22JK89DR
  run_adb_pull_with_fallbacks /data/app/com.zhiliaoapp.musically-1/base.apk /tmp/pull_nosha/base.apk
' >/tmp/pull_nosha.log 2>&1
[ -s /tmp/pull_nosha/base.apk ]

# Capability: retail denial
if FAKE_ADB_SCENARIO=cap_retail ROOT="$ROOT" bash -c '
  set -euo pipefail
  PATH="$ROOT/tests/fakes:$PATH"
  source "$ROOT/lib/logging/logging_engine.sh"; LOGFILE=/dev/null
  source "$ROOT/lib/core/trace.sh"
  source "$ROOT/lib/core/device.sh"
  source "$ROOT/lib/io/apk_utils.sh"
  set_device ZY22JK89DR
  apk_pull_all_for_package com.whatsapp
' >/tmp/retail.log 2>&1; then
  echo "expected retail failure" >&2
  exit 1
fi
grep -q 'APKs not readable' /tmp/retail.log

# Capability: direct pull
rm -rf /tmp/direct_ok
FAKE_ADB_SCENARIO=cap_direct ROOT="$ROOT" bash -c '
  set -euo pipefail
  PATH="$ROOT/tests/fakes:$PATH"
  source "$ROOT/lib/logging/logging_engine.sh"; LOGFILE=/dev/null
  source "$ROOT/lib/core/trace.sh"
  source "$ROOT/lib/core/device.sh"
  source "$ROOT/lib/io/apk_utils.sh"
  set_device ZY22JK89DR
  DEVICE_DIR=/tmp/direct_ok
  apk_pull_all_for_package com.zhiliaoapp.musically
' >/tmp/direct.log 2>&1
[ -s /tmp/direct_ok/com.zhiliaoapp.musically/base/base.apk ]
[ -s /tmp/direct_ok/com.zhiliaoapp.musically/split_config.en/split_config.en.apk ]

# Capability: run-as pull
rm -rf /tmp/run_as_ok
FAKE_ADB_SCENARIO=cap_run_as ROOT="$ROOT" bash -c '
  set -euo pipefail
  PATH="$ROOT/tests/fakes:$PATH"
  source "$ROOT/lib/logging/logging_engine.sh"; LOGFILE=/dev/null
  source "$ROOT/lib/core/trace.sh"
  source "$ROOT/lib/core/device.sh"
  source "$ROOT/lib/io/apk_utils.sh"
  set_device ZY22JK89DR
  DEVICE_DIR=/tmp/run_as_ok
  apk_pull_all_for_package com.zhiliaoapp.musically
' >/tmp/runas.log 2>&1
[ -s /tmp/run_as_ok/com.zhiliaoapp.musically/base/base.apk ]
[ -s /tmp/run_as_ok/com.zhiliaoapp.musically/split_config.en/split_config.en.apk ]

# Strategy detection helper
out=$(FAKE_ADB_SCENARIO=cap_direct ROOT="$ROOT" bash -c '
  set -euo pipefail
  PATH="$ROOT/tests/fakes:$PATH"
  source "$ROOT/lib/logging/logging_engine.sh"; LOGFILE=/dev/null
  source "$ROOT/lib/core/trace.sh"
  source "$ROOT/lib/core/device.sh"
  source "$ROOT/lib/io/apk_utils.sh"
  set_device ZY22JK89DR
  determine_pull_strategy com.zhiliaoapp.musically /data/app/com.zhiliaoapp.musically-1/base.apk
')
[ "$out" = "direct" ]

out=$(FAKE_ADB_SCENARIO=cap_run_as ROOT="$ROOT" bash -c '
  set -euo pipefail
  PATH="$ROOT/tests/fakes:$PATH"
  source "$ROOT/lib/logging/logging_engine.sh"; LOGFILE=/dev/null
  source "$ROOT/lib/core/trace.sh"
  source "$ROOT/lib/core/device.sh"
  source "$ROOT/lib/io/apk_utils.sh"
  set_device ZY22JK89DR
  determine_pull_strategy com.zhiliaoapp.musically /data/app/com.zhiliaoapp.musically-1/base.apk
')
[ "$out" = "run-as" ]

if FAKE_ADB_SCENARIO=cap_retail ROOT="$ROOT" bash -c '
  set -euo pipefail
  PATH="$ROOT/tests/fakes:$PATH"
  source "$ROOT/lib/logging/logging_engine.sh"; LOGFILE=/dev/null
  source "$ROOT/lib/core/trace.sh"
  source "$ROOT/lib/core/device.sh"
  source "$ROOT/lib/io/apk_utils.sh"
  set_device ZY22JK89DR
  determine_pull_strategy com.whatsapp /data/app/~~1s1a872NnDIeEuSxr6EfUw==/com.whatsapp-ZacC6_YVQdU9snankbRX5A==/base.apk
' >/tmp/strat_none.log 2>&1; then
  echo "expected strategy failure" >&2
  exit 1
fi

# Capability report: retail device
out=$(FAKE_ADB_SCENARIO=cap_retail ROOT="$ROOT" bash -c '
  set -euo pipefail
  PATH="$ROOT/tests/fakes:$PATH"
  source "$ROOT/lib/logging/logging_engine.sh"; LOGFILE=/dev/null
  source "$ROOT/lib/core/trace.sh"
  source "$ROOT/lib/core/device.sh"
  source "$ROOT/lib/io/apk_utils.sh"
  source "$ROOT/lib/actions/capability_report.sh"
  TARGET_PACKAGES=(com.whatsapp)
  set_device ZY22JK89DR
  capability_report
' 2>&1)
printf '%s\n' "$out" | grep -q 'Build tags: release-keys'
printf '%s\n' "$out" | grep -q 'ro.debuggable: 0'
printf '%s\n' "$out" | grep -q 'su: absent'
printf '%s\n' "$out" | grep -q 'com.whatsapp: none'

# Capability report: direct pull scenario
out=$(FAKE_ADB_SCENARIO=cap_direct ROOT="$ROOT" bash -c '
  set -euo pipefail
  PATH="$ROOT/tests/fakes:$PATH"
  source "$ROOT/lib/logging/logging_engine.sh"; LOGFILE=/dev/null
  source "$ROOT/lib/core/trace.sh"
  source "$ROOT/lib/core/device.sh"
  source "$ROOT/lib/io/apk_utils.sh"
  source "$ROOT/lib/actions/capability_report.sh"
  TARGET_PACKAGES=(com.zhiliaoapp.musically)
  set_device ZY22JK89DR
  capability_report
' 2>&1)
printf '%s\n' "$out" | grep -q 'Build tags: test-keys'
printf '%s\n' "$out" | grep -q 'ro.debuggable: 1'
printf '%s\n' "$out" | grep -q 'su: present'
printf '%s\n' "$out" | grep -q 'com.zhiliaoapp.musically: direct'

echo "OK: tests passed"
