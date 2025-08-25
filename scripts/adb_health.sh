#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load config so logging and device helpers see overrides
# shellcheck disable=SC1090
source "$ROOT/config/config.sh"

# Shared helpers
# shellcheck disable=SC1090
source "$ROOT/lib/core/logging.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/errors.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/trace.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/device/env.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/device/select.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/device/wrappers.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/device/health.sh"

log_file_init "$(_log_path adb_health)"

SERIAL="$(device_pick_or_fail "${1:-}")"
set_device "$SERIAL"
assert_device_ready "$DEVICE"

LOG_COMP="health"
adb_healthcheck
