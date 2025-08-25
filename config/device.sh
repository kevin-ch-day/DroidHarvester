#!/usr/bin/env bash
ADB_BIN_DEFAULT="$(command -v adb 2>/dev/null || true)"
if [[ -z "$ADB_BIN_DEFAULT" && -n "${ANDROID_HOME:-}" && -x "${ANDROID_HOME}/platform-tools/adb" ]]; then
  ADB_BIN_DEFAULT="${ANDROID_HOME}/platform-tools/adb"
fi
: "${ADB_BIN:="$ADB_BIN_DEFAULT"}"
: "${ADB_TIMEOUT:=30}"
: "${ALLOW_MULTI_DEVICE:=false}"
: "${DH_USER_ID:=}"
: "${DH_SHELL_TIMEOUT:=15}"
: "${DH_PULL_TIMEOUT:=300}"
: "${DH_RETRIES:=3}"
: "${DH_BACKOFF:=1}"

