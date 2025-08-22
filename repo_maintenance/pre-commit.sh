#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "pre-commit: error at line $LINENO" >&2' ERR

fail=0
while IFS= read -r file; do
    if [[ "$file" == *.apk ]]; then
        echo "pre-commit: APK files are not allowed ($file)" >&2
        fail=1
    fi
    if [[ -f "$file" ]]; then
        size=$(stat -c%s "$file")
        if (( size > 52428800 )); then
            echo "pre-commit: $file exceeds 50MB" >&2
            fail=1
        fi
    fi
done < <(git diff --cached --name-only --diff-filter=AM)

exit $fail
