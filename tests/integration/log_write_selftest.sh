#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/../.. && pwd)"
mkdir -p "$ROOT/log"
source "$ROOT/lib/core/logging.sh"
path="$(_log_path selftest)"
log_file_init "$path"
[[ -f "$path" ]]
[[ ! -e "$ROOT/logs" ]]
[[ ! -e "$ROOT/config"/logs ]]
[[ ! -e "$ROOT/scripts"/logs ]]
rm -f "$path"
echo "log_write_selftest OK"
