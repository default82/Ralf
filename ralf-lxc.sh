#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME=$(basename "$0")

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME [options]

Required options (can also be provided via environment variables):
  --vmid <id>                 Container VMID (env: RALF_VMID)
  --template-storage <name>   Storage where the Ubuntu template is stored (env: RALF_TEMPLATE_STORAGE)
  --vm-storage <name>         Storage for the container root disk (env: RALF_VM_STORAGE)

Optional arguments:
  --hostname <name>           Container hostname (default: ralf-ai / env: RALF_HOSTNAME)
  --cores <count>             vCPU cores (default: 4 / env: RALF_CORES)
  --memory <mb>               Memory in MiB (default: 8192 / env: RALF_MEMORY)
  --swap <mb>                 Swap in MiB (default: 512 / env: RALF_SWAP)
  --disk-size <size>          Root disk size (default: 64G / env: RALF_DISK_SIZE)
  --bridge <name>             Bridge name (default: vmbr0 / env: RALF_BRIDGE)
  --net <config>              Override full net0 definition (env: RALF_NET0)
  --ip <cidr|dhcp>            IPv4 address configuration (default: dhcp / env: RALF_IP)
  --gateway <ip>              IPv4 gateway (env: RALF_GATEWAY)
  --packages <list>           Comma-separated list of extra packages to install
  --mount <src:dest[:opts]>   Bind mount to configure (can be repeated)
  --repo-root <path>          Repository root inside container (default: /opt/ralf/repos)
  --wrapper <path>            Path to local wrapper script to copy (default: ./files/ralf-ai)
  --net-iface <name>          Network interface name inside the container (default: eth0 / env: RALF_NET_IFACE)
  --dry-run                   Show actions without executing
  --help                      Show this message and exit

Environment overrides use the same validation as CLI flags.
USAGE
}

log() {
  local level=$1; shift
  printf '[%s] %s\n' "$level" "$*"
}

require_command() {
  local cmd=$1
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log ERROR "Required command '$cmd' is not available"
    exit 1
  fi
}

run_cmd() {
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '[dry-run]'
    for arg in "$@"; do
      printf ' %q' "$arg"
    done
    printf '\n'
    return 0
  fi
  "$@"
}

parse_size() {
  local size=$1
  if [[ -z $size ]]; then
    echo 0
    return
  fi
  if command -v numfmt >/dev/null 2>&1; then
    if ! numfmt --from=iec "$size" 2>/dev/null; then
      numfmt --from=si "$size"
    fi
    return
  fi
  # Fallback: accept pure numbers (already bytes)
  if [[ $size =~ ^[0-9]+$ ]]; then
    echo "$size"
  else
    echo 0
  fi
}

ensure_template() {
  local storage=$1
  local template=$2
  local template_path="$storage:vztmpl/$template"

  if pveam list "$storage" | awk '{print $2}' | grep -Fxq "vztmpl/$template"; then
    log INFO "Template $template already present on $storage"
    echo "$template_path"
    return
  fi

  log INFO "Downloading Ubuntu template $template to $storage"
  run_cmd pveam download "$storage" "$template"
  echo "$template_path"
}

container_exists() {
  local vmid=$1
  if pct status "$vmid" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

container_running() {
  local vmid=$1
  local status
  if ! status=$(pct status "$vmid" 2>/dev/null); then
    return 1
  fi
  [[ $status =~ running ]]
}

set_resources() {
  local vmid=$1
  shift
  local set_args=("$@")
  if [[ ${#set_args[@]} -eq 0 ]]; then
    return
  fi
  run_cmd pct set "$vmid" "${set_args[@]}"
}

configure_mounts() {
  local vmid=$1
  shift
  local mounts=("$@")
  local index=0
  local mount

  for mount in "${mounts[@]}"; do
    local src dest opts
    src=${mount%%:*}
    local remainder=${mount#*:}
    if [[ $remainder == "$mount" ]]; then
      log ERROR "Invalid mount definition '$mount'"
      exit 1
    fi
    if [[ $remainder == *:* ]]; then
      dest=${remainder%%:*}
      opts=${remainder#*:}
    else
      dest=$remainder
      opts=""
    fi
    local config="$src,mp=$dest"
    if [[ -n $opts ]]; then
      config="$config,$opts"
    fi
    run_cmd pct set "$vmid" -mp${index} "$config"
    ((index++))
  done
}

resize_rootfs_if_needed() {
  local vmid=$1
  local desired_size=$2
  if [[ -z $desired_size ]]; then
    return
  fi
  local desired_bytes
  desired_bytes=$(parse_size "$desired_size")
  if [[ $desired_bytes -le 0 ]]; then
    log WARN "Unable to parse desired disk size '$desired_size'"
    return
  fi
  local current
  if ! current=$(pct config "$vmid" | awk -F'[:,=]' '/^rootfs: / {for (i=1;i<=NF;i++) if ($i ~ /^size$/) {print $(i+1); exit}}'); then
    return
  fi
  local current_bytes
  current_bytes=$(parse_size "$current")
  if [[ $current_bytes -eq 0 ]]; then
    log INFO "Current disk size unknown; skipping resize"
    return
  fi
  if (( desired_bytes > current_bytes )); then
    log INFO "Expanding rootfs from $current to $desired_size"
    run_cmd pct resize "$vmid" rootfs "$desired_size"
  fi
}

ensure_started() {
  local vmid=$1
  if container_running "$vmid"; then
    return
  fi
  log INFO "Starting container $vmid"
  run_cmd pct start "$vmid"
}

wait_for_network() {
  local vmid=$1
  local iface=$2
  local attempts=30
  local delay=5
  local i
  for ((i=1; i<=attempts; i++)); do
    if [[ $DRY_RUN -eq 1 ]]; then
      log INFO "[dry-run] Skipping network wait"
      return
    fi
    if pct exec "$vmid" -- ip -o -4 addr show dev "$iface" | grep -q "inet "; then
      log INFO "Network ready on $iface"
      return
    fi
    log INFO "Waiting for network on $iface ($i/$attempts)"
    sleep "$delay"
  done
  log WARN "Timed out waiting for network on $iface"
}

provision_container() {
  local vmid=$1
  local repo_root=$2
  local wrapper=$3
  local packages_csv=$4

  local install_pkgs=(curl git ca-certificates software-properties-common pipx python3-venv)
  if [[ -n $packages_csv ]]; then
    IFS=',' read -r -a extra_pkgs <<<"$packages_csv"
    install_pkgs+=("${extra_pkgs[@]}")
  fi
  local install_pkg_list
  printf -v install_pkg_list '%s ' "${install_pkgs[@]}"
  install_pkg_list=${install_pkg_list% }

  local shell=(bash -lc)

  run_cmd pct exec "$vmid" -- "${shell[@]}" "set -Eeuo pipefail
PKGS=\"$install_pkg_list\"
if ! dpkg-query -W -f='\${Status}' \$PKGS 2>/dev/null | grep -q 'install ok installed'; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \$PKGS
fi"

  run_cmd pct exec "$vmid" -- "${shell[@]}" "set -Eeuo pipefail
if ! command -v ollama >/dev/null 2>&1; then
  curl -fsSL https://ollama.ai/install.sh | sh
fi
systemctl enable --now ollama"

  run_cmd pct exec "$vmid" -- "${shell[@]}" "set -Eeuo pipefail
if ! command -v pipx >/dev/null 2>&1; then
  apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y pipx
fi
pipx ensurepath >/dev/null 2>&1 || true
if ! pipx list | grep -q '^package aider-chat '; then
  pipx install aider-chat
else
  pipx upgrade aider-chat || true
fi"

  if [[ -n $wrapper ]]; then
    if [[ ! -f $wrapper ]]; then
      log ERROR "Wrapper script '$wrapper' not found"
      exit 1
    fi
    run_cmd pct push "$vmid" "$wrapper" /usr/local/bin/ralf-ai
    run_cmd pct exec "$vmid" -- chmod +x /usr/local/bin/ralf-ai
  fi

  run_cmd pct exec "$vmid" -- mkdir -p "$repo_root" "$repo_root/sessions" "$repo_root/backups"
}

# Defaults
VMID=${RALF_VMID:-}
TEMPLATE_STORAGE=${RALF_TEMPLATE_STORAGE:-}
VM_STORAGE=${RALF_VM_STORAGE:-}
HOSTNAME=${RALF_HOSTNAME:-ralf-ai}
CORES=${RALF_CORES:-4}
MEMORY=${RALF_MEMORY:-8192}
SWAP=${RALF_SWAP:-512}
DISK_SIZE=${RALF_DISK_SIZE:-64G}
BRIDGE=${RALF_BRIDGE:-vmbr0}
NET0_OVERRIDE=${RALF_NET0:-}
IP_CONFIG=${RALF_IP:-dhcp}
GATEWAY=${RALF_GATEWAY:-}
PACKAGES=${RALF_PACKAGES:-}
REPO_ROOT=${RALF_REPO_ROOT:-/opt/ralf/repos}
WRAPPER_PATH=${RALF_WRAPPER_PATH:-./files/ralf-ai}
DRY_RUN=0
MOUNTS=()
NET_IFACE=${RALF_NET_IFACE:-eth0}

while [[ $# -gt 0 ]]; do
  case $1 in
    --vmid)
      VMID=$2; shift 2;;
    --template-storage)
      TEMPLATE_STORAGE=$2; shift 2;;
    --vm-storage)
      VM_STORAGE=$2; shift 2;;
    --hostname)
      HOSTNAME=$2; shift 2;;
    --cores)
      CORES=$2; shift 2;;
    --memory)
      MEMORY=$2; shift 2;;
    --swap)
      SWAP=$2; shift 2;;
    --disk-size)
      DISK_SIZE=$2; shift 2;;
    --bridge)
      BRIDGE=$2; shift 2;;
    --net)
      NET0_OVERRIDE=$2; shift 2;;
    --ip)
      IP_CONFIG=$2; shift 2;;
    --gateway)
      GATEWAY=$2; shift 2;;
    --packages)
      PACKAGES=$2; shift 2;;
    --mount)
      MOUNTS+=("$2"); shift 2;;
    --repo-root)
      REPO_ROOT=$2; shift 2;;
    --wrapper)
      WRAPPER_PATH=$2; shift 2;;
    --dry-run)
      DRY_RUN=1; shift;;
    --help|-h)
      usage
      exit 0;;
    --net-iface)
      NET_IFACE=$2; shift 2;;
    *)
      log ERROR "Unknown argument: $1"
      usage
      exit 1;;
  esac
done

if [[ -z $VMID || -z $TEMPLATE_STORAGE || -z $VM_STORAGE ]]; then
  log ERROR "--vmid, --template-storage, and --vm-storage are required"
  usage
  exit 1
fi

require_command pct
require_command pveam

TEMPLATE_NAME="ubuntu-24.04-standard_24.04-1_amd64.tar.zst"
TEMPLATE_PATH=$(ensure_template "$TEMPLATE_STORAGE" "$TEMPLATE_NAME")

NET0_CONFIG=$NET0_OVERRIDE
if [[ -z $NET0_CONFIG ]]; then
  NET0_CONFIG="name=$NET_IFACE,bridge=$BRIDGE"
  if [[ $IP_CONFIG == dhcp ]]; then
    NET0_CONFIG="$NET0_CONFIG,ip=dhcp"
  else
    NET0_CONFIG="$NET0_CONFIG,ip=$IP_CONFIG"
    if [[ -n $GATEWAY ]]; then
      NET0_CONFIG="$NET0_CONFIG,gw=$GATEWAY"
    fi
  fi
fi

FEATURES="nesting=1,keyctl=1,fuse=1"
ROOTFS_ARG="${VM_STORAGE}:${DISK_SIZE}"

if ! container_exists "$VMID"; then
  log INFO "Creating container $VMID"
  run_cmd pct create "$VMID" "$TEMPLATE_PATH" \
    --hostname "$HOSTNAME" \
    --cores "$CORES" \
    --memory "$MEMORY" \
    --swap "$SWAP" \
    --rootfs "$ROOTFS_ARG" \
    --ostype ubuntu \
    --onboot 1 \
    --unprivileged 1 \
    --features "$FEATURES" \
    --net0 "$NET0_CONFIG"
else
  log INFO "Container $VMID already exists; reconciling configuration"
  set_resources "$VMID" --hostname "$HOSTNAME" --cores "$CORES" --memory "$MEMORY" --swap "$SWAP" --onboot 1 --features "$FEATURES" --net0 "$NET0_CONFIG"
  resize_rootfs_if_needed "$VMID" "$DISK_SIZE"
fi

if [[ ${#MOUNTS[@]} -gt 0 ]]; then
  configure_mounts "$VMID" "${MOUNTS[@]}"
fi

ensure_started "$VMID"
wait_for_network "$VMID" "$NET_IFACE"
provision_container "$VMID" "$REPO_ROOT" "$WRAPPER_PATH" "$PACKAGES"

log INFO "Container $VMID provisioned successfully"
