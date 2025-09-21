#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)
WRAPPER_SOURCE="${SCRIPT_DIR}/rlwrap/ralf-ai.sh"

DEFAULT_TEMPLATE="ubuntu-24.04-standard_24.04-1_amd64.tar.zst"

log() {
  printf '%s\n' "$*"
}

usage() {
  cat <<USAGE
Usage: ${SCRIPT_NAME} [options]

Options (can also be provided via environment variables):
  --vmid <id>          Container VMID (env: RALF_LXC_VMID, default: 10060)
  --hostname <name>    Container hostname (env: RALF_LXC_HOSTNAME, default: lisa-llm)
  --bridge <name>      Proxmox bridge (env: RALF_LXC_BRIDGE, default: vmbr0)
  --ip <cidr|dhcp>     IPv4 assignment (env: RALF_LXC_IP, default: dhcp)
  --gw <address>       IPv4 gateway (env: RALF_LXC_GW, optional)
  --cores <count>      vCPU cores (env: RALF_LXC_CORES, default: 2)
  --memory <mb>        Memory in MiB (env: RALF_LXC_MEMORY, default: 4096)
  --disk <size>        Root disk size (env: RALF_LXC_DISK, default: 24G)
  --storage <name>     Storage target (env: RALF_LXC_STORAGE, default: local-lvm)
  --mp0-host <path>    Host path for /srv/ralf (env: RALF_LXC_MP0_HOST, default: /srv/ralf)
  --mp1-host <path>    Optional host path for /srv/ralf/models (env: RALF_LXC_MP1_HOST)
  --dry-run            Preview actions without executing (env: RALF_LXC_DRY_RUN)
  --help               Show this help message
USAGE
}

run_cmd() {
  if (( DRY_RUN )); then
    local rendered='[dry-run]'
    local arg
    for arg in "$@"; do
      rendered+=" $(printf '%q' "${arg}")"
    done
    log "${rendered}"
    return 0
  fi
  "$@"
}

command_available() {
  command -v "$1" >/dev/null 2>&1
}

require_command() {
  local binary=$1
  if (( DRY_RUN )); then
    if ! command_available "$binary"; then
      log "[warn] ${binary} not found; continuing because of dry-run"
    fi
    return
  fi
  if ! command_available "$binary"; then
    log "[error] Required command '${binary}' is not available"
    exit 1
  fi
}

parse_args() {
  VMID=${RALF_LXC_VMID:-10060}
  HOSTNAME=${RALF_LXC_HOSTNAME:-lisa-llm}
  BRIDGE=${RALF_LXC_BRIDGE:-vmbr0}
  IP_ASSIGNMENT=${RALF_LXC_IP:-dhcp}
  GATEWAY=${RALF_LXC_GW:-}
  CORES=${RALF_LXC_CORES:-2}
  MEMORY=${RALF_LXC_MEMORY:-4096}
  DISK_SIZE=${RALF_LXC_DISK:-24G}
  STORAGE=${RALF_LXC_STORAGE:-local-lvm}
  MP0_HOST=${RALF_LXC_MP0_HOST:-/srv/ralf}
  MP1_HOST=${RALF_LXC_MP1_HOST:-}
  DRY_RUN=${RALF_LXC_DRY_RUN:-0}

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --vmid)
        VMID=$2; shift 2 ;;
      --vmid=*)
        VMID=${1#*=}; shift ;;
      --hostname)
        HOSTNAME=$2; shift 2 ;;
      --hostname=*)
        HOSTNAME=${1#*=}; shift ;;
      --bridge)
        BRIDGE=$2; shift 2 ;;
      --bridge=*)
        BRIDGE=${1#*=}; shift ;;
      --ip)
        IP_ASSIGNMENT=$2; shift 2 ;;
      --ip=*)
        IP_ASSIGNMENT=${1#*=}; shift ;;
      --gw)
        GATEWAY=$2; shift 2 ;;
      --gw=*)
        GATEWAY=${1#*=}; shift ;;
      --cores)
        CORES=$2; shift 2 ;;
      --cores=*)
        CORES=${1#*=}; shift ;;
      --memory)
        MEMORY=$2; shift 2 ;;
      --memory=*)
        MEMORY=${1#*=}; shift ;;
      --disk)
        DISK_SIZE=$2; shift 2 ;;
      --disk=*)
        DISK_SIZE=${1#*=}; shift ;;
      --storage)
        STORAGE=$2; shift 2 ;;
      --storage=*)
        STORAGE=${1#*=}; shift ;;
      --mp0-host)
        MP0_HOST=$2; shift 2 ;;
      --mp0-host=*)
        MP0_HOST=${1#*=}; shift ;;
      --mp1-host)
        MP1_HOST=$2; shift 2 ;;
      --mp1-host=*)
        MP1_HOST=${1#*=}; shift ;;
      --dry-run)
        DRY_RUN=1; shift ;;
      --help|-h)
        usage
        exit 0 ;;
      *)
        log "Unknown option: $1"
        usage
        exit 1 ;;
    esac
  done

  if [[ ! -f "${WRAPPER_SOURCE}" ]]; then
    log "[error] Wrapper source ${WRAPPER_SOURCE} not found"
    exit 1
  fi
}

net_config() {
  local config="name=eth0,bridge=${BRIDGE},firewall=1"
  if [[ ${IP_ASSIGNMENT,,} == dhcp ]]; then
    config+=",ip=dhcp"
  else
    config+="\,ip=${IP_ASSIGNMENT}"
    if [[ -n ${GATEWAY} ]]; then
      config+="\,gw=${GATEWAY}"
    fi
  fi
  printf '%s' "${config}"
}

ensure_template() {
  local template_path="${STORAGE}:vztmpl/${DEFAULT_TEMPLATE}"
  if command_available pveam; then
    local found=0
    local column1 column2 rest
    while read -r column1 column2 rest; do
      [[ -z ${column1:-} ]] && continue
      [[ ${column1,,} == name ]] && continue
      if [[ ${column1} == "${template_path}" ]]; then
        found=1
        break
      fi
      if [[ ${column1} == "${STORAGE}:vztmpl" && ${column2:-} == "${DEFAULT_TEMPLATE}" ]]; then
        found=1
        break
      fi
    done < <(pveam list "${STORAGE}" 2>/dev/null || true)
    if (( found )); then
      log "Template ${template_path} already present"
      return
    fi
  elif (( ! DRY_RUN )); then
    log "[error] pveam command not available"
    exit 1
  fi
  run_cmd pveam download "${STORAGE}" "${DEFAULT_TEMPLATE}"
}

container_exists() {
  if (( DRY_RUN )) && ! command_available pct; then
    return 1
  fi
  if ! command_available pct; then
    log "[error] pct command not available"
    exit 1
  fi
  pct status "${VMID}" >/dev/null 2>&1
}

ensure_host_paths() {
  run_cmd install -d -m 0755 "${MP0_HOST}"
  if [[ -n ${MP1_HOST} ]]; then
    run_cmd install -d -m 0755 "${MP1_HOST}"
  fi
}

create_container() {
  local net0
  net0=$(net_config)
  local rootfs="${STORAGE}:${DISK_SIZE}"
  local mp0="${MP0_HOST},mp=/srv/ralf"
  log "Creating container ${VMID} (${HOSTNAME})"
  run_cmd pct create "${VMID}" "${STORAGE}:vztmpl/${DEFAULT_TEMPLATE}" \
    --hostname "${HOSTNAME}" \
    --cores "${CORES}" \
    --memory "${MEMORY}" \
    --rootfs "${rootfs}" \
    --features nesting=1,keyctl=1 \
    --onboot 1 \
    --net0 "${net0}" \
    --mp0 "${mp0}"
}

update_container() {
  local net0
  net0=$(net_config)
  run_cmd pct set "${VMID}" --hostname "${HOSTNAME}" --cores "${CORES}" --memory "${MEMORY}" --features nesting=1,keyctl=1 --onboot 1 --net0 "${net0}" --mp0 "${MP0_HOST},mp=/srv/ralf"
  if [[ -n ${MP1_HOST} ]]; then
    run_cmd pct set "${VMID}" --mp1 "${MP1_HOST},mp=/srv/ralf/models"
  fi
}

ensure_disk_size() {
  if (( DRY_RUN )); then
    run_cmd pct resize "${VMID}" rootfs "${DISK_SIZE}"
    return
  fi
  local current_size
  current_size=$(pct config "${VMID}" | awk -F'[=, ]+' '/^rootfs:/ {for (i=1; i<=NF; i++) if ($i ~ /^size=/) {split($i,a,"="); print a[2]; exit}}')
  if [[ "${current_size}" != "${DISK_SIZE}" ]]; then
    log "Adjusting disk from ${current_size:-unknown} to ${DISK_SIZE}"
    run_cmd pct resize "${VMID}" rootfs "${DISK_SIZE}"
  fi
}

ensure_started() {
  if (( DRY_RUN )); then
    run_cmd pct start "${VMID}"
    return
  fi
  local status
  status=$(pct status "${VMID}" | awk '{print $2}')
  if [[ ${status} != "running" ]]; then
    run_cmd pct start "${VMID}"
  fi
}

wait_for_network() {
  if (( DRY_RUN )); then
    log "Skipping network wait in dry-run"
    return
  fi
  for _ in {1..30}; do
    if pct exec "${VMID}" -- ip -o -4 addr show dev eth0 >/dev/null 2>&1; then
      return
    fi
    sleep 2
  done
  log "[warn] Timed out waiting for network"
}

provision_packages() {
  run_cmd pct exec "${VMID}" -- bash -c "set -Eeuo pipefail; apt-get update"
  run_cmd pct exec "${VMID}" -- bash -c "set -Eeuo pipefail; DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl git jq yq python3-pip"
}

install_ollama() {
  run_cmd pct exec "${VMID}" -- bash -c "set -Eeuo pipefail; if ! command -v ollama >/dev/null 2>&1; then curl -fsSL https://ollama.ai/install.sh | sh; fi"
  run_cmd pct exec "${VMID}" -- systemctl enable --now ollama
}

install_aider() {
  run_cmd pct exec "${VMID}" -- bash -c "set -Eeuo pipefail; python3 -m pip install --upgrade pip"
  run_cmd pct exec "${VMID}" -- bash -c "set -Eeuo pipefail; python3 -m pip install --upgrade aider-chat"
}

create_directories() {
  local -a dirs=(
    /srv/ralf
    /srv/ralf/automation
    /srv/ralf/automation/lxc
    /srv/ralf/automation/net
    /srv/ralf/automation/pve
    /srv/ralf/automation/ralf
    /srv/ralf/inventory
    /srv/ralf/zfs
    /srv/ralf/docs
    /srv/ralf/tests
    /srv/ralf/ci
  )
  local dir
  for dir in "${dirs[@]}"; do
    run_cmd pct exec "${VMID}" -- mkdir -p "${dir}"
  done
}

install_wrapper() {
  run_cmd pct push "${VMID}" "${WRAPPER_SOURCE}" /usr/local/bin/ralf-ai
  run_cmd pct exec "${VMID}" -- chmod 0755 /usr/local/bin/ralf-ai
  run_cmd pct exec "${VMID}" -- ralf-ai --help
}

main() {
  parse_args "$@"

  if (( DRY_RUN )); then
    log "==> lisa-llm build plan (dry-run)"
  else
    log "==> lisa-llm build"
  fi

  require_command pct
  require_command pveam

  ensure_host_paths
  ensure_template

  local exists=1
  if container_exists; then
    log "Container ${VMID} already exists"
  else
    exists=0
    create_container
  fi

  update_container
  ensure_disk_size
  ensure_started
  wait_for_network

  provision_packages
  install_ollama
  install_aider
  create_directories
  install_wrapper

  if (( DRY_RUN )); then
    log "==> Dry run complete"
  else
    log "==> Build complete"
  fi
}

main "$@"
