#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR
# ---------------------------------------------------
# report.sh - Report initialization and finalization
# ---------------------------------------------------
# Generates analyst-ready reports in TXT (default), CSV, and JSON.
# TXT reports are structured in an IEEE-style format with plain ASCII.

init_report() {
    mkdir -p "$DEVICE_DIR"
    touch "$LOGFILE"

    # CSV header with session metadata
    {
        echo "# SessionID,$SESSION_ID"
        echo "# Host,$(hostname)"
        echo "# User,$(whoami)"
        echo "# OS,$(uname -srvmo)"
        echo "# Device,$DEVICE"
        echo "# Fingerprint,$DEVICE_FINGERPRINT"
        echo "# Log,$LOGFILE"
        echo "package,file,sha256,sha1,md5,size,perms,modified,version,versionCode,targetSdk,installer,firstInstall,lastUpdate,uid,installType,findings"
    } > "$REPORT"
    
    # JSON temp
    : > "$JSON_REPORT.tmp"

    # TXT init (IEEE-style preamble)
    TXT_REPORT="$RESULTS_DIR/apks_report_$TIMESTAMP.txt"
    {
        echo "============================================================"
        echo "                     APK HARVEST REPORT"
        echo "============================================================"
        echo "Session ID  : $SESSION_ID"
        echo "Generated   : $(date)"
        echo "Host        : $(hostname)"
        echo "User        : $(whoami)"
        echo "OS          : $(uname -srvmo)"
        echo "Device ID   : ${DEVICE:-unknown}"
        echo "Fingerprint : ${DEVICE_FINGERPRINT:-unknown}"
        echo "Log File    : $LOGFILE"
        echo "Output Path : $DEVICE_DIR"
        echo "============================================================"
        echo
        echo "Section I. Introduction"
        echo "    This report documents Android application packages (APKs)"
        echo "    harvested from the connected device. The intent is to"
        echo "    support digital forensics, malware analysis, and mobile"
        echo "    security research."
        echo
        echo "Section II. Methodology"
        echo "    APKs were identified using Android Debug Bridge (adb) and"
        echo "    extracted for offline examination. For each APK, cryptographic"
        echo "    hashes and metadata fields were computed to establish"
        echo "    integrity, provenance, and baseline characteristics."
        echo
        echo "Section III. APK Metadata"
        echo "    Each entry below corresponds to a discovered package and"
        echo "    its associated attributes."
        echo "------------------------------------------------------------"
    } > "$TXT_REPORT"
}

latest_report() {
    find "$RESULTS_DIR" -maxdepth 1 -type f -name 'apks_report_*.txt' -print0 \
        | xargs -0 stat --printf '%Y\t%n\0' 2>/dev/null \
        | sort -z -nr \
        | tr '\0' '\n' \
        | head -n1 \
        | cut -f2- || true
}

append_txt_report() {
    local pkg="$1"
    local outfile="$2"
    local sha256="$3"
    local sha1="$4"
    local md5="$5"
    local size="$6"
    local version="$7"
    local versionCode="$8"
    local targetSdk="$9"
    local installer="${10}"
    local installType="${11}"

    {
        echo "Package Name : $pkg"
        echo "APK File     : $outfile"
        echo "SHA256       : $sha256"
        echo "SHA1         : $sha1"
        echo "MD5          : $md5"
        echo "File Size    : $size bytes"
        echo "Version      : $version"
        echo "Version Code : $versionCode"
        echo "Target SDK   : $targetSdk"
        echo "Installer    : $installer"
        echo "Install Type : $installType"
        echo "Findings Summary : TBD"
        echo "------------------------------------------------------------"
    } >> "$TXT_REPORT"
}

finalize_report() {
    local mode="${1:-txt}"  # default = txt

    local pkg_count
    pkg_count=$(tail -n +2 "$REPORT" | wc -l)
    {
        echo
        echo "Section IV. Summary"
        echo "    Total APKs harvested : $pkg_count"
        echo "    Output Directory     : $DEVICE_DIR"
        echo
        echo "Section V. Conclusion"
        echo "    The metadata presented herein provides a verifiable record"
        echo "    of applications present on the device at the time of capture."
        echo "    This dataset may be used as a foundation for:"
        echo "      - Static analysis of binaries"
        echo "      - Dynamic sandboxing experiments"
        echo "      - Threat intelligence enrichment"
        echo "============================================================"
    } >> "$TXT_REPORT"

    if [[ "$mode" == *"csv"* || "$mode" == "both" || "$mode" == "all" ]]; then
        log INFO "CSV report saved: $REPORT"
    fi
    if [[ "$mode" == *"json"* || "$mode" == "both" || "$mode" == "all" ]]; then
        jq -s \
            --arg sid "$SESSION_ID" \
            --arg host "$(hostname)" \
            --arg user "$(whoami)" \
            --arg os "$(uname -srvmo)" \
            --arg device "$DEVICE" \
            --arg fp "$DEVICE_FINGERPRINT" \
            --arg log "$LOGFILE" \
            '{session:{id:$sid,host:$host,user:$user,os:$os,device:$device,fingerprint:$fp,log:$log},apps:.}' \
            "$JSON_REPORT.tmp" > "$JSON_REPORT"
        log INFO "JSON report saved: $JSON_REPORT"
    fi
    if [[ "$mode" == *"txt"* || "$mode" == "all" ]]; then
        log INFO "TXT report saved: $TXT_REPORT"
    fi
    cleanup_reports
}

cleanup_reports() {
    [[ -n "${JSON_REPORT:-}" ]] && rm -f "$JSON_REPORT.tmp"
}
