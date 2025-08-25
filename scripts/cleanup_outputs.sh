#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for f in "$ROOT"/config/*.sh; do
  # shellcheck disable=SC1090
  [[ -r "$f" ]] && source "$f"
done
# shellcheck disable=SC1090
source "$ROOT/lib/core/logging.sh"
# shellcheck disable=SC1090
source "$ROOT/lib/actions/cleanup.sh"
cleanup_all_artifacts
