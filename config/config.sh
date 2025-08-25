#!/usr/bin/env bash
[[ -n "${DROIDHARVESTER_CONFIG_LOADED:-}" ]] && return 0 2>/dev/null || true
DROIDHARVESTER_CONFIG_LOADED=1

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  set -E
  trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
fi

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -P "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"
source "$SCRIPT_DIR/paths.sh"
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/packages.sh"
source "$SCRIPT_DIR/reporting.sh"
source "$SCRIPT_DIR/device.sh"
source "$SCRIPT_DIR/validate.sh"

# Optional local overrides
[[ -r "$SCRIPT_DIR/local.sh" ]] && source "$SCRIPT_DIR/local.sh"

validate_config

