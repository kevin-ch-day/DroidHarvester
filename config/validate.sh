#!/usr/bin/env bash
validate_config() {
  local v

  v="${DH_SHELL_TIMEOUT}"
  if ! _is_posint "$v"; then
    _config_warn "DH_SHELL_TIMEOUT invalid ($v); defaulting to 15"
    DH_SHELL_TIMEOUT=15
  fi

  v="${DH_PULL_TIMEOUT}"
  if ! _is_timeout_val "$v"; then
    _config_warn "DH_PULL_TIMEOUT invalid ($v); defaulting to 300"
    DH_PULL_TIMEOUT=300
  fi

  v="${DH_RETRIES}"
  if ! _is_posint "$v"; then
    _config_warn "DH_RETRIES invalid ($v); defaulting to 3"
    DH_RETRIES=3
  fi

  v="${DH_BACKOFF}"
  if ! _is_posint "$v"; then
    _config_warn "DH_BACKOFF invalid ($v); defaulting to 1"
    DH_BACKOFF=1
  fi

  if [[ -z "${ADB_BIN:-}" || ! -x "$ADB_BIN" ]]; then
    _config_warn "ADB_BIN not set or not executable ($ADB_BIN)"
  fi

  export REPO_ROOT SCRIPT_DIR RESULTS_DIR LOG_DIR TIMESTAMP_FORMAT
  export LOG_KEEP_N CLEAR_LOGS
  export ADB_BIN ADB_TIMEOUT ALLOW_MULTI_DEVICE DH_USER_ID
  export DH_SHELL_TIMEOUT DH_PULL_TIMEOUT DH_RETRIES DH_BACKOFF
  export LOG_LEVEL INCLUDE_DEVICE_PROFILE INCLUDE_ENV_METADATA
}

