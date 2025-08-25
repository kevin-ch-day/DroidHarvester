#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if git grep -n 'source "$REPO_ROOT/config.sh"' -- 'lib/**' 'steps/**' 'scripts/**' 'run.sh' >/tmp/root_config.txt; then
  cat /tmp/root_config.txt
  echo "Disallowed import of root config.sh detected" >&2
  exit 1
fi

