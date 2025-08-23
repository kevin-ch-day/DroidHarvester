#!/usr/bin/env bash
set -euo pipefail
set -E

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGFILE="$SCRIPT_DIR/logs/pre-commit_$(date +%Y%m%d_%H%M%S).log"
# shellcheck disable=SC1090
source "$SCRIPT_DIR/lib/logging.sh"

trap 'log ERROR "pre-commit: error at line $LINENO"' ERR

fail=0

# Ensure there are no unresolved merge conflicts
if [[ -n $(git ls-files -u) ]]; then
    log ERROR "Unmerged files detected. Resolve conflicts before committing."
    git ls-files -u >&2
    exit 1
fi

mapfile -t files < <(git diff --cached --name-only --diff-filter=AM)
if [[ ${#files[@]} -eq 0 ]]; then
    log INFO "No staged files to check."
    exit 0
fi

log INFO "Checking ${#files[@]} staged files..."

for file in "${files[@]}"; do
    log INFO "Scanning $file"
    if [[ "$file" == *.apk ]]; then
        log ERROR "APK files are not allowed ($file)"
        fail=1
    fi
    if [[ -f "$file" ]]; then
        size=$(stat -c%s "$file")
        if (( size > 52428800 )); then
            log ERROR "$file exceeds 50MB"
            fail=1
        fi

        # Only run text-based checks on non-binary files
        if grep -Iq . "$file"; then
            if grep -q $'\r' "$file"; then
                log ERROR "CRLF line endings found in $file"
                fail=1
            fi
            if grep -n -E '[ \t]+$' "$file" >/dev/null; then
                log ERROR "Trailing whitespace in $file"
                fail=1
            fi
            if grep -n -E '^(<<<<<<<|=======|>>>>>>>|\|\|\|\|\|\|)' "$file" >/dev/null; then
                log ERROR "Merge conflict markers detected in $file"
                fail=1
            fi
        fi
    fi
done

if (( fail )); then
    log ERROR "Pre-commit checks failed."
    exit $fail
fi

log SUCCESS "Pre-commit checks passed."
exit 0
