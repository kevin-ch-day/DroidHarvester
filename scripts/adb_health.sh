#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/lib/core/logging.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/errors.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/trace.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/device.sh"

DEVICE="${1:-$(device_pick_or_fail)}"
adb_healthcheck
