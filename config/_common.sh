#!/usr/bin/env bash
_config_warn() { printf '[WARN][config] %s\n' "$*" >&2; }
_is_posint()      { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 > 0 )); }
_is_nonnegint()   { [[ "$1" =~ ^[0-9]+$ ]]; }
_is_timeout_val() { [[ "$1" == "0" || "$1" =~ ^[0-9]+([smhd])?$ ]]; }

