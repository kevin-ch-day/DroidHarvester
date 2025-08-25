#!/usr/bin/env bash
HASH_ALGOS=("sha256" "sha1" "md5")
: "${HASH_SIZE_LIMIT:=0}"

REPORT_FORMATS=("txt" "csv" "json")
: "${LOG_LEVEL:="INFO"}"
: "${INCLUDE_DEVICE_PROFILE:=true}"
: "${INCLUDE_ENV_METADATA:=true}"

