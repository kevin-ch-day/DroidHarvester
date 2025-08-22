#!/bin/bash
# ---------------------------------------------------
# report.sh - Report initialization and finalization
# ---------------------------------------------------
# Generates analyst-ready reports in TXT (default), CSV, and JSON.
# TXT reports are structured in an IEEE-style format with plain ASCII.

init_report() {
    mkdir -p "$DEVICE_DIR"
    touch "$LOGFILE"

    # CSV header
    echo "package,file,sha256,sha1,md5,size,version,versionCode,targetSdk,installer,installType" > "$REPORT"
    
    # JSON temp
    : > "$JSON_REPORT.tmp"

    # TXT init (IEEE-style preamble)
    TXT_REPORT="$RESULTS_DIR/apks_report_$TIMESTAMP.txt"
    {
        echo "============================================================"
        echo "                     APK HARVEST REPORT"
        echo "============================================================"
        echo "Generated   : $(date)"
        echo "Device ID   : ${DEVICE:-unknown}"
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
        echo "------------------------------------------------------------"
    } >> "$TXT_REPORT"
}

finalize_report() {
    local mode="${1:-txt}"  # default = txt

    local pkg_count=$(tail -n +2 "$REPORT" | wc -l)
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
        log "CSV report saved: $REPORT"
    fi
    if [[ "$mode" == *"json"* || "$mode" == "both" || "$mode" == "all" ]]; then
        jq -s '.' "$JSON_REPORT.tmp" > "$JSON_REPORT"
        rm -f "$JSON_REPORT.tmp"
        log "JSON report saved: $JSON_REPORT"
    fi
    if [[ "$mode" == *"txt"* || "$mode" == "all" ]]; then
        log "TXT report saved: $TXT_REPORT"
    fi
}
