#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# export_bundle.sh - export reports into a zip
# ---------------------------------------------------

export_report() {
    local zipfile="$RESULTS_DIR/apk_harvest_${TIMESTAMP}.zip"
    local files=()
    for f in "$REPORT" "$JSON_REPORT" "$TXT_REPORT" "$LOGFILE"; do
        [[ -f "$f" ]] && files+=("$f")
    done
    if [[ ${#files[@]} -eq 0 ]]; then
        log WARN "No reports to export. Run a harvest first."
        return
    fi
    zip -j "$zipfile" "${files[@]}" >/dev/null
    log SUCCESS "Exported report bundle: $zipfile"
}
