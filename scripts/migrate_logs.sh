#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$ROOT"
# shellcheck disable=SC1090
source "$ROOT/config/paths.sh"

legacy="$ROOT/log"
if [[ -d "$legacy" && "$legacy" != "$LOG_ROOT" ]]; then
  echo "Migrating legacy log directory to $LOG_ROOT" >&2
  mkdir -p "$LOG_ROOT"
  shopt -s dotglob nullglob
  for f in "$legacy"/*; do
    base="$(basename "$f")"
    dest="$LOG_ROOT/$base"
    if [[ -e "$dest" ]]; then
      i=1
      while [[ -e "$dest.$i" ]]; do ((i++)); done
      echo "Renaming $base to ${base}.$i to avoid overwrite" >&2
      dest="$dest.$i"
    fi
    mv "$f" "$dest"
  done
  shopt -u dotglob nullglob
  rmdir "$legacy" 2>/dev/null || true
fi
