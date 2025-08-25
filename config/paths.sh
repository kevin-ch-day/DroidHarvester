#!/usr/bin/env bash
: "${RESULTS_DIR:="$REPO_ROOT/results"}"
: "${LOG_ROOT:="$REPO_ROOT/log"}"
: "${LOG_DIR:="$LOG_ROOT"}"
: "${TIMESTAMP_FORMAT:="+%Y%m%d_%H%M%S"}"
mkdir -p "$RESULTS_DIR" "$LOG_ROOT"

