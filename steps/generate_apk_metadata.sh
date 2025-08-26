#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "ERROR: ${BASH_SOURCE[0]}:$LINENO" >&2' ERR

# steps/generate_apk_metadata.sh - extract metadata for a pulled APK

pkg="${1:-}"
outfile="${2:-}"
device_path="${3:-}"
if [[ -z "$pkg" || -z "$outfile" ]]; then
  echo "Usage: $0 <package> <local_apk> [device_path]" >&2
  exit 64
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090,SC1091
source "$REPO_ROOT/config/config.sh"
# shellcheck disable=SC1090
for m in logging/logging_engine core/errors core/trace core/device io/report; do
  source "$REPO_ROOT/lib/$m.sh"
done

DEVICE="$(printf '%s' "${DEVICE:-}" | tr -d '\r' | xargs)"
assert_device_ready "$DEVICE"
update_adb_flags

csv_escape() {
    local q='"'
    local str=${1//$q/$q$q}
    printf '"%s"' "$str"
}

if [[ -f "$outfile" ]]; then
    sha256=$(sha256sum "$outfile" | awk '{print $1}')
    sha1=$(sha1sum "$outfile" | awk '{print $1}')
    md5=$(md5sum "$outfile" | awk '{print $1}')
    size=$(stat -c%s "$outfile")
    perms=$(stat -c%A "$outfile")
    mtime=$(stat -c%y "$outfile")

    version="unknown"
    versionCode="unknown"
    targetSdk="unknown"
    installer="unknown"
    firstInstall="unknown"
    lastUpdate="unknown"
    uid="unknown"
    grantedPerms=""

    if [[ "$(basename "$outfile")" == "base.apk" ]]; then
        info=$(adb_shell dumpsys package "$pkg" 2>/dev/null || true)
        if [[ -n "$info" ]]; then
            version=$(awk -F= '/versionName/{print $2;exit}' <<<"$info" | xargs || true)
            versionCode=$(awk -F'[= ]' '/versionCode/{print $2;exit}' <<<"$info" | xargs || true)
            targetSdk=$(awk -F= '/targetSdk/{print $2;exit}' <<<"$info" | xargs || true)
            installer=$(awk -F= '/installerPackageName/{print $2;exit}' <<<"$info" | tr -d ' ' | xargs || true)
            firstInstall=$(awk -F= '/firstInstallTime/{print $2;exit}' <<<"$info" | xargs || true)
            lastUpdate=$(awk -F= '/lastUpdateTime/{print $2;exit}' <<<"$info" | xargs || true)
            uid=$(awk -F= '/userId=/{print $2;exit}' <<<"$info" | xargs || true)
            grantedPerms=$(awk '/grantedPermissions:/{flag=1;next} /^[^ ]/{flag=0} flag{gsub(/^ +/,"",$0);print}' <<<"$info" | paste -sd',' -)
        else
            log WARN "dumpsys package $pkg returned empty"
        fi
    fi

    installType="user"
    if [[ "$device_path" == /system/* || "$device_path" == /product/* || "$device_path" == /vendor/* || "$device_path" == /apex/* ]]; then
        installType="system"
    fi
    role="base"
    [[ "$(basename "$outfile")" != "base.apk" ]] && role="split"

    perm_count=$( [ -n "$grantedPerms" ] && printf '%s' "$grantedPerms" | tr ',' '\n' | wc -l | tr -d ' ' || echo 0 )

    LOG_PKG="$pkg" LOG_APK="$(basename "$outfile")" log INFO "Metadata for $pkg"
    log INFO "  File       : $(basename "$outfile") ($role, ${size} bytes)"
    [[ "$version" != "unknown" ]] && log INFO "  Version    : $version (code: $versionCode, targetSdk: $targetSdk)"
    [[ "$installer" != "unknown" ]] && log INFO "  Installer  : $installer"
    log INFO "  Permissions: ${grantedPerms:-none} (${perm_count})"

    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$(csv_escape "$pkg")" \
        "$(csv_escape "$outfile")" \
        "$(csv_escape "$role")" \
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

    append_txt_report "$pkg" "$outfile" "$role" "$sha256" "$sha1" "$md5" "$size" "$version" "$versionCode" "$targetSdk" "$installer" "$installType"

    jq -n \
      --arg pkg "$pkg" \
      --arg file "$outfile" \
      --arg role "$role" \
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
      '{package:$pkg,file:$file,role:$role,sha256:$sha256,sha1:$sha1,md5:$md5,size:$size,perms:$perms,modified:$mtime,version:$version,versionCode:$versionCode,targetSdk:$targetSdk,installer:$installer,firstInstall:$firstInstall,lastUpdate:$lastUpdate,uid:$uid,installType:$installType,findings:$findings}' \
      >> "$JSON_REPORT.tmp"

    pulled_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    base_noext="${outfile%.apk}"
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
