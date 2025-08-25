#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/../.. && pwd)"
cd "$ROOT"
if bad=$(git grep -nE '(log/|config/log|scripts/log)' -- ':!README.md' ':!.gitignore' ':!tests/guards/no_legacy_log_paths.sh' 2>/dev/null); then
  if [[ -n "$bad" ]]; then
    echo "$bad"
    echo "legacy log path reference found" >&2
    exit 1
  fi
fi
