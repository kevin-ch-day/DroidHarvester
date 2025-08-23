#!/usr/bin/env bash
set -euo pipefail
cmd="${1:-}"; shift || true
if [[ "$cmd" == "-s" ]]; then
  shift
  cmd="${1:-}"; shift || true
fi
case "$cmd" in
  shell)
    case "${1:-}" in
      pm)
        if [[ "${2:-}" == "path" ]]; then
          pkg="${3:-}"
          cat "tests/fixtures/pm_path_${pkg//./_}.txt"
        elif [[ "${2:-}" == "list" && "${3:-}" == "packages" ]]; then
          if [[ "${4:-}" == "-f" && "${5:-}" == "-3" ]]; then
            cat tests/fixtures/pm_list_f_3.txt
          else
            cat tests/fixtures/pm_list_all.txt
          fi
        fi
        ;;
      dumpsys)
        pkg="${3:-}"
        cat "tests/fixtures/dumpsys_${pkg//./_}.txt"
        ;;
      test)
        [[ -f "tests/fixtures/device_fs${2:-}" ]]
        ;;
      stat)
        p="${4:-}"
        stat -c %s "tests/fixtures/device_fs${p}"
        ;;
      sha256sum|md5sum)
        p="${2:-}"
        if [[ -f "tests/fixtures/device_fs${p}" ]]; then
          if [[ "$1" == "sha256sum" && $(command -v sha256sum) ]]; then
            sha256sum "tests/fixtures/device_fs${p}"
          else
            md5sum "tests/fixtures/device_fs${p}"
          fi
        fi
        ;;
    esac
    ;;
  pull)
    src="${1:-}"; dst="${2:-}"
    cp "tests/fixtures/device_fs${src}" "$dst"
    ;;
  get-state)
    echo device
    ;;
  *)
    ;;
 esac
