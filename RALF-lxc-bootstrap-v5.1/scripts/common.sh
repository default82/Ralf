#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_CONFIG="${PROJECT_ROOT}/config/defaults.json"
CONFIG_PATH="${RALF_CONFIG:-/root/ralf/config.json}"

load_config_file(){
  if [[ -f "$CONFIG_PATH" ]]; then
    echo "$CONFIG_PATH"
  else
    echo "$DEFAULT_CONFIG"
  fi
}

CONFIG_FILE="$(load_config_file)"

config_get(){
  local query="$1"
  jq -r "$query" "$CONFIG_FILE"
}

config_get_path(){
  local query="$1"
  local value
  value="$(config_get "$query")"
  if [[ "$value" == /* ]]; then
    echo "$value"
  else
    echo "${PROJECT_ROOT}/${value}"
  fi
}
