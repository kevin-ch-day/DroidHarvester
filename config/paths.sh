#!/usr/bin/env bash
: "${RESULTS_DIR:="$REPO_ROOT/results"}"
: "${LOG_DIR:="${LOG_ROOT:-$REPO_ROOT/logs}"}"
: "${TIMESTAMP_FORMAT:="+%Y%m%d_%H%M%S"}"
mkdir -p "$RESULTS_DIR" "$LOG_DIR"

# Backwards compatibility for callers still using LOG_ROOT
LOG_ROOT="$LOG_DIR"

