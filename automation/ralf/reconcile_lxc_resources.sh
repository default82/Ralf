#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME=$(basename "$0")
CONFIG_FILE=${RALF_LXC_CONFIG_FILE:-/etc/ralf-lxc.d/override.conf}
DRY_RUN=${RALF_LXC_DRY_RUN:-0}
if [[ $DRY_RUN != 0 ]]; then
  DRY_RUN=1
fi

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME [options]

Options:
  --config <path>   Path to override configuration (default: $CONFIG_FILE)
  --vmid <id>       Target container VMID (default: from config)
  --help            Show this help
USAGE
}

log() {
  local level=$1; shift
  printf '[%s] %s\n' "$level" "$*" >&2
}

run_cmd() {
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '[dry-run] Would execute:'
    local arg
    for arg in "$@"; do
      printf ' %q' "$arg"
    done
    printf '\n'
    return 0
  fi
  "$@"
}

ensure_command() {
  local cmd=$1
  if [[ $DRY_RUN -eq 1 ]]; then
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log WARN "Command '$cmd' not found; skipping availability check due to dry-run"
    fi
    return
  fi
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log ERROR "Required command '$cmd' not found"
    exit 1
  fi
}

declare -A CONFIG_OVERRIDES=()
declare -A CURRENT_CONFIG=()

load_config() {
  if [[ ! -f $CONFIG_FILE ]]; then
    log ERROR "Configuration file $CONFIG_FILE not found"
    exit 1
  fi
  while IFS='=' read -r key value; do
    key=${key//[[:space:]]/}
    [[ -z $key || $key == \#* ]] && continue
    CONFIG_OVERRIDES[$key]=$value
  done <"$CONFIG_FILE"
}

parse_current_config() {
  while IFS= read -r line; do
    [[ -z $line ]] && continue
    if [[ $line == *:* ]]; then
      local key=${line%%:*}
      local value=${line#*: }
      CURRENT_CONFIG[$key]=$value
    fi
  done < <(pct config "$VMID")
}

current_value() {
  local key=$1
  printf '%s' "${CURRENT_CONFIG[$key]:-}"
}

normalize_csv() {
  local value=${1:-}
  value=${value//[[:space:]]/}
  IFS=',' read -r -a parts <<<"$value"
  if (( ${#parts[@]} == 0 )); then
    return
  fi
  printf '%s\n' "${parts[@]}" | sort | paste -sd',' -
}

to_bytes() {
  local value=$1
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --from=iec "$value" 2>/dev/null || numfmt --from=si "$value"
  else
    printf '%s' "$value"
  fi
}

maybe_add_arg() {
  local flag=$1
  local desired=$2
  local current=$3
  [[ -z $desired ]] && return
  if [[ $DRY_RUN -eq 1 ]]; then
    SET_ARGS+=("$flag" "$desired")
    return
  fi
  if [[ $current != "$desired" ]]; then
    SET_ARGS+=("$flag" "$desired")
  fi
}

ensure_mount() {
  local mp_key=$1
  local host_path=$2
  local container_path=$3
  [[ -z $host_path ]] && return
  run_cmd mkdir -p "$host_path"
  local desired="${host_path},mp=${container_path}"
  if [[ $DRY_RUN -eq 1 ]]; then
    SET_ARGS+=("-${mp_key}" "$desired")
    return
  fi
  local current=$(current_value "$mp_key")
  if [[ $current != "$desired" ]]; then
    SET_ARGS+=("-${mp_key}" "$desired")
  fi
}

VMID=${RALF_LXC_VMID:-}

while [[ $# -gt 0 ]]; do
  case $1 in
    --config)
      CONFIG_FILE=$2; shift 2 ;;
    --vmid)
      VMID=$2; shift 2 ;;
    --help|-h)
      usage
      exit 0 ;;
    *)
      log ERROR "Unknown option: $1"
      usage
      exit 2 ;;
  esac
done

load_config

if [[ -z $VMID ]]; then
  VMID=${CONFIG_OVERRIDES[VMID]:-}
fi

if [[ -z $VMID ]]; then
  log ERROR "VMID not provided"
  exit 2
fi

ensure_command pct

if [[ $DRY_RUN -eq 0 ]]; then
  if ! pct status "$VMID" >/dev/null 2>&1; then
    log WARN "Container $VMID does not exist; skipping reconciliation"
    exit 0
  fi
  parse_current_config
else
  log INFO "Dry run: skipping container existence check"
fi

declare -a SET_ARGS=()

DESIRED_HOSTNAME=${CONFIG_OVERRIDES[HOSTNAME]:-}
DESIRED_CORES=${CONFIG_OVERRIDES[CORES]:-}
DESIRED_MEMORY=${CONFIG_OVERRIDES[MEMORY]:-}
DESIRED_DISK=${CONFIG_OVERRIDES[DISK_SIZE]:-}
DESIRED_BRIDGE=${CONFIG_OVERRIDES[BRIDGE]:-}
DESIRED_IP=${CONFIG_OVERRIDES[IP_ASSIGNMENT]:-}
DESIRED_GW=${CONFIG_OVERRIDES[GATEWAY]:-}
DESIRED_MP0=${CONFIG_OVERRIDES[MP0_HOST]:-}
DESIRED_MP1=${CONFIG_OVERRIDES[MP1_HOST]:-}

if [[ -n $DESIRED_BRIDGE ]]; then
  NET0_CONFIG="name=eth0,bridge=$DESIRED_BRIDGE"
  if [[ -n $DESIRED_IP ]]; then
    if [[ $DESIRED_IP == dhcp ]]; then
      NET0_CONFIG+=",ip=dhcp"
    else
      NET0_CONFIG+=",ip=$DESIRED_IP"
    fi
  fi
  if [[ -n $DESIRED_GW ]]; then
    NET0_CONFIG+=",gw=$DESIRED_GW"
  fi
fi

current_hostname=$(current_value hostname)
maybe_add_arg --hostname "$DESIRED_HOSTNAME" "$current_hostname"
current_cores=$(current_value cores)
maybe_add_arg --cores "$DESIRED_CORES" "$current_cores"
current_memory=$(current_value memory)
maybe_add_arg --memory "$DESIRED_MEMORY" "$current_memory"

DESIRED_FEATURES=nesting=1,keyctl=1,fuse=1
if [[ $DRY_RUN -eq 1 ]]; then
  SET_ARGS+=(--features "$DESIRED_FEATURES")
else
  current_features=$(current_value features)
  if [[ $(normalize_csv "$current_features") != $(normalize_csv "$DESIRED_FEATURES") ]]; then
    SET_ARGS+=(--features "$DESIRED_FEATURES")
  fi
fi

maybe_add_arg --onboot 1 "$(current_value onboot)"

if [[ -n ${NET0_CONFIG:-} ]]; then
  maybe_add_arg --net0 "$NET0_CONFIG" "$(current_value net0)"
fi

ensure_mount mp0 "$DESIRED_MP0" /srv/ralf
ensure_mount mp1 "$DESIRED_MP1" /srv/ralf/models

if (( ${#SET_ARGS[@]} > 0 )); then
  run_cmd pct set "$VMID" "${SET_ARGS[@]}"
else
  log INFO "pct configuration already matches desired state"
fi

if [[ -n $DESIRED_DISK ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    run_cmd pct resize "$VMID" rootfs "$DESIRED_DISK"
  else
    current_rootfs=$(current_value rootfs)
    if [[ $current_rootfs =~ size=([^,]+) ]]; then
      current_size=${BASH_REMATCH[1]}
      desired_bytes=$(to_bytes "$DESIRED_DISK")
      current_bytes=$(to_bytes "$current_size")
      if [[ -n $desired_bytes && -n $current_bytes ]] && (( desired_bytes > current_bytes )); then
        log INFO "Expanding rootfs from $current_size to $DESIRED_DISK"
        run_cmd pct resize "$VMID" rootfs "$DESIRED_DISK"
      else
        log INFO "Rootfs already at $current_size; no resize needed"
      fi
    else
      log WARN "Unable to determine current rootfs size; skipping resize"
    fi
  fi
fi

log INFO "Reconciliation complete"
