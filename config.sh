#!/usr/bin/env bash
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$REPO_ROOT/config/config.sh"
[[ -r "$TARGET" ]] || { echo "[FATAL] Missing $TARGET" >&2; exit 78; }
# shellcheck disable=SC1090
source "$TARGET"

