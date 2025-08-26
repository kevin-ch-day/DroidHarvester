#!/usr/bin/env bash
set -euo pipefail

: "${REPO_ROOT:="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"}"

# load core logging functions and categorized log helpers
source "$REPO_ROOT/lib/logging/logging_core.sh"

# initialize logging once
if [[ -z "${DROIDHARVESTER_LOGGING_INITIALIZED:-}" ]]; then
    logging_init
    DROIDHARVESTER_LOGGING_INITIALIZED=1
fi

