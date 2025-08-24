#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR

# steps/pull_apk.sh - pull an APK from device

pkg="${1:-}"
apk_path="${2:-}"
if [[ -z "$pkg" || -z "$apk_path" ]]; then
  echo "Usage: $0 <package> <apk_path>" >&2
  exit 64
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$REPO_ROOT/config.sh"
# shellcheck disable=SC1090
for m in core/logging core/errors core/trace core/device io/apk_utils; do
  source "$REPO_ROOT/lib/$m.sh"
done

DEVICE="$(printf '%s' "${DEVICE:-}" | tr -d '\r' | xargs)"
assert_device_ready "$DEVICE"
update_adb_flags

ensure_timeouts_defaults

IFS=$'\0' read -r outdir outfile role < <(compute_outfile_vars "$pkg" "$apk_path") || true
mkdir -p -- "$outdir"

LOG_PKG="$pkg" LOG_APK="$(basename "$outfile")" log INFO "Pulling $role APK $apk_path"

if ! run_adb_pull_with_fallbacks "$apk_path" "$outfile"; then
  rc=$?
  LOG_CODE="${E_PULL_FAIL:-32}" LOG_RC="$rc" LOG_PKG="$pkg" LOG_APK="$(basename "$outfile")" \
    log ERROR "pull failed"
  exit 1
fi

if [[ ! -s "$outfile" ]]; then
  LOG_CODE="${E_APK_EMPTY:-33}" LOG_PKG="$pkg" LOG_APK="$(basename "$outfile")" \
    log ERROR "pulled file empty"
  exit 1
fi

LOG_PKG="$pkg" LOG_APK="$(basename "$outfile")" log INFO "Pulled $role APK $outfile"
printf '%s\n' "$outfile"
