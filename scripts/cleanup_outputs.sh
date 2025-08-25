#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load config and logging for consistent paths
# shellcheck disable=SC1090
source "$ROOT/config/config.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/core/logging.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/actions/cleanup.sh"

log_file_init "$(_log_path cleanup)"
cleanup_all_artifacts
