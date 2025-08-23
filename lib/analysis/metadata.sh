#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR

csv_escape() {
    local q='"'
    local str=${1//$q/$q$q}
    printf '"%s"' "$str"
}

apk_metadata() {
    local pkg="$1"
    local outfile="$2"

    if [[ -f "$outfile" ]]; then
        # Hashes & file info
        local sha256 sha1 md5 size perms mtime
        sha256=$(sha256sum "$outfile" | awk '{print $1}')
        sha1=$(sha1sum "$outfile" | awk '{print $1}')
        md5=$(md5sum "$outfile" | awk '{print $1}')
        size=$(stat -c%s "$outfile")
        perms=$(stat -c%A "$outfile")
        mtime=$(stat -c%y "$outfile")

        # Defaults
        local version="unknown"
        local versionCode="unknown"
        local targetSdk="unknown"
        local installer="unknown"
        local firstInstall="unknown"
        local lastUpdate="unknown"
        local uid="unknown"

        # Only parse detailed info for base.apk to avoid duplicates
        if [[ "$(basename "$outfile")" == "base.apk" ]]; then
            local info
            info=$(adb_shell dumpsys package "$pkg" 2>/dev/null || true)

            version=$(echo "$info" | grep versionName | head -n1 | awk -F= '{print $2}' | xargs)
            versionCode=$(echo "$info" | grep versionCode | head -n1 | grep -o '[0-9]\+' | xargs)
            targetSdk=$(echo "$info" | grep targetSdk | head -n1 | awk -F= '{print $2}' | xargs)
            installer=$(echo "$info" | grep "installerPackageName" | awk -F= '{print $2}' | tr -d ' ' | xargs)
            firstInstall=$(echo "$info" | grep firstInstallTime | awk -F= '{print $2}' | xargs)
            lastUpdate=$(echo "$info" | grep lastUpdateTime | awk -F= '{print $2}' | xargs)
            uid=$(echo "$info" | grep userId= | head -n1 | awk -F= '{print $2}' | xargs)
        fi

        # Guess install type by path
        local installType="user"
        if [[ "$outfile" == *"/system/"* || "$outfile" == *"/product/"* || "$outfile" == *"/vendor/"* || "$outfile" == *"/apex/"* ]]; then
            installType="system"
        fi
        local role="base"
        [[ "$(basename "$outfile")" != "base.apk" ]] && role="split"

        # -----------------------------
        # Logging
        # -----------------------------
        log INFO "✅ Metadata for $pkg → $(basename "$outfile")"
        log INFO "      File        : $outfile"
        log INFO "      Role        : $role"
        log INFO "      SHA256      : $sha256"
        log INFO "      SHA1        : $sha1"
        log INFO "      MD5         : $md5"
        log INFO "      Size        : $size bytes"
        log INFO "      Perms       : $perms"
        log INFO "      Modified    : $mtime"
        [[ "$version" != "unknown" ]] && log INFO "      Version     : $version (code: $versionCode, targetSdk: $targetSdk)"
        [[ "$installer" != "unknown" ]] && log INFO "      Installer   : $installer"
        [[ "$firstInstall" != "unknown" ]] && log INFO "      FirstInstall: $firstInstall"
        [[ "$lastUpdate" != "unknown" ]] && log INFO "      LastUpdate  : $lastUpdate"
        [[ "$uid" != "unknown" ]] && log INFO "      UID         : $uid"
        log INFO "      InstallType : $installType"

        # -----------------------------
        # CSV Report
        # -----------------------------
        printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
            "$(csv_escape "$pkg")" \
            "$(csv_escape "$outfile")" \
            "$(csv_escape "$sha256")" \
            "$(csv_escape "$sha1")" \
            "$(csv_escape "$md5")" \
            "$(csv_escape "$size")" \
            "$(csv_escape "$perms")" \
            "$(csv_escape "$mtime")" \
            "$(csv_escape "$version")" \
            "$(csv_escape "$versionCode")" \
            "$(csv_escape "$targetSdk")" \
            "$(csv_escape "$installer")" \
            "$(csv_escape "$firstInstall")" \
            "$(csv_escape "$lastUpdate")" \
            "$(csv_escape "$uid")" \
            "$(csv_escape "$installType")" \
            "$(csv_escape "TBD")" >> "$REPORT"

        append_txt_report "$pkg" "$outfile" "$sha256" "$sha1" "$md5" "$size" "$version" "$versionCode" "$targetSdk" "$installer" "$installType"

        # -----------------------------
        # JSON Report
        # -----------------------------
        jq -n \
          --arg pkg "$pkg" \
          --arg file "$outfile" \
          --arg sha256 "$sha256" \
          --arg sha1 "$sha1" \
          --arg md5 "$md5" \
          --arg size "$size" \
          --arg perms "$perms" \
          --arg mtime "$mtime" \
          --arg version "$version" \
          --arg versionCode "$versionCode" \
          --arg targetSdk "$targetSdk" \
          --arg installer "$installer" \
          --arg firstInstall "$firstInstall" \
          --arg lastUpdate "$lastUpdate" \
          --arg uid "$uid" \
          --arg installType "$installType" \
          --arg findings "TBD" \
          '{package:$pkg,file:$file,sha256:$sha256,sha1:$sha1,md5:$md5,size:$size,perms:$perms,modified:$mtime,version:$version,versionCode:$versionCode,targetSdk:$targetSdk,installer:$installer,firstInstall:$firstInstall,lastUpdate:$lastUpdate,uid:$uid,installType:$installType,findings:$findings}' \
          >> "$JSON_REPORT.tmp"

        # -----------------------------
        # Per-APK sidecar reports
        # -----------------------------
        local pulled_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        local base_noext="${outfile%.apk}"
        {
            echo "Package: $pkg"
            echo "APK: $(basename "$outfile")"
            echo "Role: $role"
            echo "SHA256: $sha256"
            echo "SHA1: $sha1"
            echo "MD5: $md5"
            echo "Size: $size"
            echo "Pulled: $pulled_at"
        } > "${base_noext}.txt"

        {
            echo "package,apk,role,sha256,sha1,md5,size,pulled_at,install_type"
            printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
                "$(csv_escape "$pkg")" \
                "$(csv_escape "$(basename "$outfile")")" \
                "$(csv_escape "$role")" \
                "$(csv_escape "$sha256")" \
                "$(csv_escape "$sha1")" \
                "$(csv_escape "$md5")" \
                "$(csv_escape "$size")" \
                "$(csv_escape "$pulled_at")" \
                "$(csv_escape "$installType")"
        } > "${base_noext}.csv"

        jq -n \
          --arg pkg "$pkg" \
          --arg apk "$(basename "$outfile")" \
          --arg role "$role" \
          --arg sha256 "$sha256" \
          --arg sha1 "$sha1" \
          --arg md5 "$md5" \
          --arg size "$size" \
          --arg pulled "$pulled_at" \
          --arg installType "$installType" \
          '{package:$pkg,apk:$apk,role:$role,sha256:$sha256,sha1:$sha1,md5:$md5,size:$size,pulled_at:$pulled,install_type:$installType}' \
          > "${base_noext}.json"
    fi
}
