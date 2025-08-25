#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/log"
mkdir -p "$DEST"
moved=0
for src in "$ROOT/logs" "$ROOT/config"/logs "$ROOT/scripts"/logs; do
  if [[ -d "$src" ]]; then
    while IFS= read -r -d '' f; do
      mv "$f" "$DEST/"
      ((moved++))
    done < <(find "$src" -maxdepth 1 -type f -print0) || true
  fi
done
echo "moved $moved file(s) into $DEST"
