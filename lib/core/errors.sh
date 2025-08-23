#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# errors.sh - central error codes
# ---------------------------------------------------

export E_NO_DEVICE=1
export E_ADB_DOWN=2
export E_PM_LIST=3
export E_PM_PATH=4
export E_PULL_FAIL=5
export E_APK_MISSING=6
export E_APK_EMPTY=7
export E_HASH_FAIL=8
export E_DUMPSYS_FAIL=9
export E_REPORT_FAIL=10
export E_EXPORT_SKIP=11
export E_TIMEOUT=12

err_desc() {
    case "$1" in
        "$E_NO_DEVICE") echo "no_device" ;;
        "$E_ADB_DOWN") echo "adb_down" ;;
        "$E_PM_LIST") echo "pm_list_fail" ;;
        "$E_PM_PATH") echo "pm_path_fail" ;;
        "$E_PULL_FAIL") echo "pull_fail" ;;
        "$E_APK_MISSING") echo "apk_missing" ;;
        "$E_APK_EMPTY") echo "apk_empty" ;;
        "$E_HASH_FAIL") echo "hash_fail" ;;
        "$E_DUMPSYS_FAIL") echo "dumpsys_fail" ;;
        "$E_REPORT_FAIL") echo "report_fail" ;;
        "$E_EXPORT_SKIP") echo "export_skip" ;;
        "$E_TIMEOUT") echo "timeout" ;;
        *) echo "-" ;;
    esac
}
