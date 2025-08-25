#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/lib/core/device/env.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/device/select.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/device/wrappers.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/device/health.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/device/props.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/device/fs.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/device/pm.sh"
