#!/usr/bin/env bash
: "${RESULTS_DIR:="$REPO_ROOT/results"}"
: "${LOG_ROOT:="$REPO_ROOT/logs"}"
: "${TIMESTAMP_FORMAT:="+%Y%m%d_%H%M%S"}"
mkdir -p "$RESULTS_DIR" "$LOG_ROOT"

# Backwards compatibility for callers still using LOG_DIR
LOG_DIR="$LOG_ROOT"

