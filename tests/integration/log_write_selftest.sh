#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/../.. && pwd)"
source "$ROOT/lib/logging/logging_engine.sh"
path="$(_log_path selftest)"
log_file_init "$path"
[[ -f "$path" ]]
[[ -d "$LOG_ROOT" ]]
[[ ! -e "$ROOT/log" ]]
[[ ! -e "$ROOT/config"/log ]]
[[ ! -e "$ROOT/scripts"/log ]]
# ensure error logs are captured separately
log_error "selftest error"
[[ -f "$ERRORFILE" ]]
grep -q "selftest error" "$ERRORFILE"
rm -f "$path"
rm -f "$ERRORFILE"
echo "log_write_selftest OK"
