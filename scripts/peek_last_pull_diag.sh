#!/usr/bin/env bash
# ---------------------------------------------------
# peek_last_pull_diag.sh - inspect latest diag_pull logs
# Fedora/Linux. Plain ASCII. Run from scripts/: ./peek_last_pull_diag.sh
# ---------------------------------------------------
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND" >&2' ERR

usage() {
  cat <<'EOF'
Usage: ./peek_last_pull_diag.sh [--pkg PACKAGE] [-h|--help]

Shows the latest diag_pull traces for PACKAGE (default: com.zhiliaoapp.musically),
verifies OUT/ERR line counts, and displays possible path lines and line endings.

Examples:
  ./peek_last_pull_diag.sh
  ./peek_last_pull_diag.sh --pkg com.twitter.android
EOF
}

# -------------------------
# Args
# -------------------------
PKG="com.zhiliaoapp.musically"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pkg) PKG="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# -------------------------
# Repo root + logs dir
# -------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$REPO_ROOT/logs"
PKG_ESC="${PKG//./_}"

die() { echo "ERROR: $2" >&2; exit "${1:-1}"; }

# Return newest file by mtime for a given suffix
# Uses newline-delimited ls -1t (OK for our file patterns).
latest_match() {
  local ext="$1"
  local pattern="$LOG_DIR/pull_diag_*_${PKG_ESC}${ext}"
  # No matches? return empty
  if ! compgen -G "$pattern" >/dev/null; then
    printf ''
    return
  fi
  # Newest by mtime
  ls -1t -- $pattern 2>/dev/null | head -n 1
}

OUT="$(latest_match '.out')"
ERR="$(latest_match '.err')"
SUM="$(latest_match '.summary.txt')"

if [[ -z "${OUT:-}" && -z "${ERR:-}" && -z "${SUM:-}" ]]; then
  die 2 "No matching diag_pull logs found in $LOG_DIR for package $PKG (pattern: pull_diag_*_${PKG_ESC}.*)"
fi

echo "Package = $PKG"
echo "OUT     = ${OUT:-<none>}"
echo "ERR     = ${ERR:-<none>}"
echo "SUMMARY = ${SUM:-<none>}"
echo "--------------------------------------------------"

# 1) Counts (if present)
if [[ -n "${OUT:-}" && -n "${ERR:-}" ]]; then
  wc -l "$OUT" "$ERR"
elif [[ -n "${OUT:-}" ]]; then
  wc -l "$OUT"
elif [[ -n "${ERR:-}" ]]; then
  wc -l "$ERR"
else
  echo "No OUT/ERR files found; only SUMMARY present."
fi

# 2) Quick ERR preview (first 40 lines)
if [[ -n "${ERR:-}" && -s "$ERR" ]]; then
  echo "--- ERR (first 40) ---"
  sed -n '1,40p' "$ERR"
else
  echo "--- no ERR file or it is empty ---"
fi

# 3) Are there absolute APK paths hiding in ERR?
if [[ -n "${ERR:-}" && -s "$ERR" ]]; then
  echo "--- lines that look like paths in ERR ---"
  grep -E '(^/data/|^/system/).+\.apk$' "$ERR" | sed -n '1,20p' || true
fi

# 4) OUT preview (first 40), and with visible line endings
if [[ -n "${OUT:-}" && -s "$OUT" ]]; then
  echo "--- OUT (first 40) ---"
  sed -n '1,40p' "$OUT"
  echo "--- OUT endings (first 40) ---"
  # 'sed -n l' shows CR as \r$, etc.
  sed -n 'l' "$OUT" | sed -n '1,40p'
else
  echo "--- no OUT file or it is empty ---"
fi

# 5) SUMMARY preview (optional)
if [[ -n "${SUM:-}" && -s "$SUM" ]]; then
  echo "--- SUMMARY (first 40) ---"
  sed -n '1,40p' "$SUM"
fi
