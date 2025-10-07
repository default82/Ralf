#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_CONFIG="${PROJECT_ROOT}/config/defaults.json"
CONFIG_PATH="${RALF_CONFIG:-/root/ralf/config.json}"

refresh_config(){
  if [[ -f "$CONFIG_PATH" ]]; then
    CONFIG_FILE="$CONFIG_PATH"
  else
    CONFIG_FILE="$DEFAULT_CONFIG"
  fi
}

refresh_config

config_get(){
  local query="$1"
  refresh_config
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
