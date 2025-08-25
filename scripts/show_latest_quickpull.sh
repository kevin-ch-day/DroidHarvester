#!/usr/bin/env bash
# ---------------------------------------------------
# scripts/show_latest_quickpull.sh
# List APKs (with sizes) from the most recent quick pull,
# plus a consolidated status and per-package summary.
# Works whether logs live in ./log or ./logs.
# ---------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -P "${SCRIPT_DIR}/.." && pwd)"

# --- Config sourcing (tolerate split or monolithic) ---
try_source() { [[ -r "$1" ]] && source "$1" >/dev/null 2>&1 || true; } # shellcheck disable=SC1091
try_source "$REPO_ROOT/config/config.sh"
try_source "$REPO_ROOT/config/paths.sh"

# --- Candidate log dirs (prefer configured LOG_ROOT if present) ---
CAND_LOG_DIRS=()
[[ -n "${LOG_ROOT:-}" ]] && CAND_LOG_DIRS+=("$LOG_ROOT")
CAND_LOG_DIRS+=("$REPO_ROOT/log" "$REPO_ROOT/logs")

pick_newest_log() {
  local d
  for d in "${CAND_LOG_DIRS[@]}"; do
    [[ -d "$d" ]] || continue
    compgen -G "$d/apk_grab_*.txt" >/dev/null || continue
    ls -1t "$d"/apk_grab_*.txt | head -1
    return 0
  done
  return 1
}

# --- Determine OUT (quick_pull folder) ---
LOGFILE="$(pick_newest_log || true)"
OUT=""
if [[ -n "${LOGFILE:-}" && -f "$LOGFILE" ]]; then
  # Support both "[INFO] output :" and "output :" variants
  OUT="$(awk -F'output : ' '/^\[INFO\][[:space:]]+output[[:space:]]:|^output[[:space:]]:/{print $2; exit}' "$LOGFILE" | tr -d '\r' || true)"
fi
if [[ -z "$OUT" || ! -d "$OUT" ]]; then
  OUT="$(ls -1dt "$REPO_ROOT"/results/*/quick_pull_* 2>/dev/null | head -1 || true)"
fi

if [[ -z "$OUT" || ! -d "$OUT" ]]; then
  echo "No quick-pull folder found yet."
  echo "Run: ./scripts/grab_apks.sh"
  exit 1
fi

echo "Latest OUT: $OUT"
echo

# --- APK inventory (sorted) ---
echo "APK files:"
find "$OUT" -type f -name '*.apk' -printf '%p %s bytes\n' | sort || true

# --- Gather manifests ---
mapfile -t MANIFESTS < <(find "$OUT" -type f -name 'pull_manifest.csv' | sort || true)

if (( ${#MANIFESTS[@]} == 0 )); then
  echo
  echo "(no pull_manifest.csv files found)"
  exit 0
fi

# --- Aggregate all manifests ---
echo
echo "Pull status summary (ALL packages):"
awk -F, '
  NR==1 { next }                                    # skip header if someone passed a header into xargs (we guard below)
' < /dev/null >/dev/null 2>&1 || true

# Use xargs defensively to handle many files; AWK does the real work
# Columns (as written by grab_apks.sh): pkg,apk_type,remote_path,remote_bytes,local_bytes,sha256,status
xargs_awk() {
  awk -F, '
    FNR==1 && NR>1 { next }                          # skip header rows except first file
    NR>1 {                                           # data rows
      pkg=$1; kind=$2; status=$7;
      gsub(/\r/,"",status)
      tot[status]++
      pkgs[pkg]=1

      if (kind=="base") { bTot[pkg]++; if (status=="OK") bOK[pkg]++ }
      else               { sTot[pkg]++; if (status=="OK") sOK[pkg]++ }

      if (status!="OK") {
        # capture first 3 problem lines per package for a short preview
        if (probCnt[pkg] < 3) {
          prob[pkg,probCnt[pkg]] = sprintf("%s [%s] %s", kind, status, $3) # remote_path
          probCnt[pkg]++
        }
      }
    }
    END {
      # overall status tallies
      for (k in tot) printf("  %s: %d\n", k, tot[k])

      print "\nPer-package:"
      for (p in pkgs) {
        bT=(p in bTot)?bTot[p]:0; bO=(p in bOK)?bOK[p]:0;
        sT=(p in sTot)?sTot[p]:0; sO=(p in sOK)?sOK[p]:0;
        printf("  %-35s base %d/%d OK, splits %d/%d OK\n", p, bO, bT, sO, sT)
      }

      print "\nProblems (first few per package):"
      none=1
      for (p in pkgs) {
        n=(p in probCnt)?probCnt[p]:0
        if (n>0) {
          none=0
          print "  " p ":"
          for (i=0;i<n;i++) print "    - " prob[p,i]
        }
      }
      if (none) print "  (none)"
    }
  '
}

echo "${MANIFESTS[@]}" | xargs -n 1000 -r bash -lc 'awk -F, "FNR==1 && NR>1 {next} {print}" "$@"' _ "${MANIFESTS[@]}" | xargs_awk

# --- Version info (meta/meta.csv) ---
echo
echo "Versions:"
# meta.csv header: pkg,versionName,versionCode,installer
# Print a neat aligned table if present
found_meta=0
while IFS= read -r -d '' meta; do
  ((found_meta=1))
  awk -F, 'NR==2 {
    pkg=$1; vn=$2; vc=$3; inst=$4;
    printf("  %-35s vName=%-16s vCode=%-10s installer=%s\n", pkg, vn, vc, inst)
  }' "$meta" || true
done < <(find "$OUT" -type f -path "*/meta/meta.csv" -print0 2>/dev/null)

[[ $found_meta -eq 1 ]] || echo "  (no meta.csv found)"

# --- Hint to bundle everything for sharing ---
echo
echo "Tip: bundle for analysis"
echo "  zip -r \"${OUT}.zip\" \"$OUT\""
