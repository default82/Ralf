#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME [options]

Options (can also be provided via environment variables):
  --vmid <id>          Container VMID (env: RALF_LXC_VMID, default: 10060)
  --hostname <name>    Container hostname (env: RALF_LXC_HOSTNAME, default: lisa-llm)
  --bridge <name>      Proxmox bridge (env: RALF_LXC_BRIDGE, default: vmbr0)
  --ip <cidr|dhcp>     IPv4 assignment (env: RALF_LXC_IP, default: dhcp)
  --gw <address>       IPv4 gateway (env: RALF_LXC_GW)
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

container_exists() {
  local vmid=$1
  if [[ $DRY_RUN -eq 1 ]]; then
    return 1
  fi
  pct status "$vmid" >/dev/null 2>&1
}

container_running() {
  local vmid=$1
  if [[ $DRY_RUN -eq 1 ]]; then
    return 1
  fi
  local status
  if ! status=$(pct status "$vmid" 2>/dev/null); then
    return 1
  fi
  [[ $status =~ running ]]
}

ensure_template() {
  local storage=$1
  local template=$2
  local template_path="$storage:vztmpl/$template"

  if [[ $DRY_RUN -eq 1 ]]; then
    log INFO "Dry run: ensuring template $template_path"
    run_cmd pveam download "$storage" "$template"
    return
  fi

  if pveam list "$storage" | awk '{print $2}' | grep -Fxq "vztmpl/$template"; then
    log INFO "Template $template already available on $storage"
    return
  fi

  log INFO "Downloading template $template to $storage"
  run_cmd pveam download "$storage" "$template"
}

set_base_resources() {
  local vmid=$1
  run_cmd pct set "$vmid" \
    --hostname "$HOSTNAME" \
    --cores "$CORES" \
    --memory "$MEMORY" \
    --features "nesting=1,keyctl=1,fuse=1" \
    --onboot 1 \
    --net0 "$NET0_CONFIG"
}

resize_rootfs_if_needed() {
  local vmid=$1
  local desired=$2
  if [[ -z $desired ]]; then
    return
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    run_cmd pct resize "$vmid" rootfs "$desired"
    return
  fi

  local current
  if ! current=$(pct config "$vmid" | awk -F'[=, ]' '/^rootfs:/ {for (i=1;i<=NF;i++) if ($i=="size") {print $(i+1); exit}}'); then
    return
  fi

  local to_bytes
  to_bytes() {
    local value=$1
    if command -v numfmt >/dev/null 2>&1; then
      numfmt --from=iec "$value" 2>/dev/null || numfmt --from=si "$value"
    else
      printf '%s' "$value"
    fi
  }

  local desired_bytes current_bytes
  desired_bytes=$(to_bytes "$desired")
  current_bytes=$(to_bytes "$current")
  if [[ -z $desired_bytes || -z $current_bytes ]]; then
    return
  fi

  if (( desired_bytes > current_bytes )); then
    log INFO "Expanding rootfs from $current to $desired"
    run_cmd pct resize "$vmid" rootfs "$desired"
  fi
}

wait_for_network() {
  local vmid=$1
  local iface=$2
  if [[ $DRY_RUN -eq 1 ]]; then
    log INFO "Dry run: skipping network wait for $iface"
    return
  fi
  for ((attempt=1; attempt<=30; attempt++)); do
    if pct exec "$vmid" -- ip -o -4 addr show dev "$iface" | grep -q 'inet '; then
      return
    fi
    sleep 2
  done
  log WARN "Timed out waiting for network on $iface"
}

pct_exec() {
  local vmid=$1; shift
  run_cmd pct exec "$vmid" -- "$@"
}

provision_packages() {
  local vmid=$1
  local packages=(ca-certificates curl git jq yq python3-pip)
  local script='set -Eeuo pipefail
shift
missing=()
for pkg in "$@"; do
  if ! dpkg-query -W -f="\${Status}" "$pkg" 2>/dev/null | grep -q "install ok installed"; then
    missing+=("$pkg")
  fi
done
if (( ${#missing[@]} )); then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y "${missing[@]}"
fi'
  pct_exec "$vmid" bash -lc "$script" _ "${packages[@]}"
}

provision_ollama() {
  local vmid=$1
  local script='set -Eeuo pipefail
if ! command -v ollama >/dev/null 2>&1; then
  curl -fsSL https://ollama.ai/install.sh | sh
fi
if systemctl is-enabled --quiet ollama 2>/dev/null; then
  systemctl restart ollama
else
  systemctl enable --now ollama
fi'
  pct_exec "$vmid" bash -lc "$script"
}

provision_aider() {
  local vmid=$1
  local script='set -Eeuo pipefail
pip3 install --upgrade --no-cache-dir aider-chat'
  pct_exec "$vmid" bash -lc "$script"
}

provision_directories() {
  local vmid=$1
  local script='set -Eeuo pipefail
mkdir -p \
  /srv/ralf/automation/lxc \
  /srv/ralf/automation/net \
  /srv/ralf/automation/pve \
  /srv/ralf/automation/ralf \
  /srv/ralf/inventory \
  /srv/ralf/zfs \
  /srv/ralf/docs \
  /srv/ralf/tests \
  /srv/ralf/ci'
  pct_exec "$vmid" bash -lc "$script"
}

provision_wrapper() {
  local vmid=$1
  local wrapper_path="$REPO_ROOT/files/ralf-ai"
  if [[ ! -f $wrapper_path ]]; then
    log ERROR "Wrapper script not found at $wrapper_path"
    exit 1
  fi
  run_cmd pct push "$vmid" "$wrapper_path" /usr/local/bin/ralf-ai
  pct_exec "$vmid" chmod 0755 /usr/local/bin/ralf-ai
  pct_exec "$vmid" /usr/local/bin/ralf-ai --help
}

# Defaults from environment overrides
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

if [[ $DRY_RUN != 0 ]]; then
  DRY_RUN=1
fi

while [[ $# -gt 0 ]]; do
  case $1 in
    --vmid)
      VMID=$2; shift 2 ;;
    --hostname)
      HOSTNAME=$2; shift 2 ;;
    --bridge)
      BRIDGE=$2; shift 2 ;;
    --ip)
      IP_ASSIGNMENT=$2; shift 2 ;;
    --gw)
      GATEWAY=$2; shift 2 ;;
    --cores)
      CORES=$2; shift 2 ;;
    --memory)
      MEMORY=$2; shift 2 ;;
    --disk)
      DISK_SIZE=$2; shift 2 ;;
    --storage)
      STORAGE=$2; shift 2 ;;
    --mp0-host)
      MP0_HOST=$2; shift 2 ;;
    --mp1-host)
      MP1_HOST=$2; shift 2 ;;
    --dry-run)
      DRY_RUN=1; shift ;;
    --help|-h)
      usage
      exit 0 ;;
    *)
      log ERROR "Unknown option: $1"
      usage
      exit 2 ;;
  esac
done

if [[ -z $VMID || -z $STORAGE || -z $HOSTNAME ]]; then
  log ERROR "--vmid, --hostname, and --storage must be provided"
  usage
  exit 2
fi

ensure_command pct
ensure_command pveam

echo "==> Local AI LXC build plan"
if [[ $DRY_RUN -eq 1 ]]; then
  echo "[dry-run] Running in dry-run mode"
fi

TEMPLATE_NAME="ubuntu-24.04-standard_24.04-1_amd64.tar.zst"
TEMPLATE_PATH="${STORAGE}:vztmpl/${TEMPLATE_NAME}"
ensure_template "$STORAGE" "$TEMPLATE_NAME"

NET0_CONFIG="name=eth0,bridge=$BRIDGE"
if [[ $IP_ASSIGNMENT == dhcp ]]; then
  NET0_CONFIG="$NET0_CONFIG,ip=dhcp"
else
  NET0_CONFIG="$NET0_CONFIG,ip=$IP_ASSIGNMENT"
  if [[ -n $GATEWAY ]]; then
    NET0_CONFIG="$NET0_CONFIG,gw=$GATEWAY"
  fi
fi

if [[ -n $MP0_HOST ]]; then
  run_cmd mkdir -p "$MP0_HOST"
fi
if [[ -n $MP1_HOST ]]; then
  run_cmd mkdir -p "$MP1_HOST"
fi

if ! container_exists "$VMID"; then
  log INFO "Creating container $VMID"
  run_cmd pct create "$VMID" "$TEMPLATE_PATH" \
    --hostname "$HOSTNAME" \
    --cores "$CORES" \
    --memory "$MEMORY" \
    --features "nesting=1,keyctl=1,fuse=1" \
    --onboot 1 \
    --rootfs "${STORAGE}:${DISK_SIZE}" \
    --unprivileged 1 \
    --net0 "$NET0_CONFIG"
else
  log INFO "Container $VMID already exists; reconciling configuration"
  set_base_resources "$VMID"
  resize_rootfs_if_needed "$VMID" "$DISK_SIZE"
fi

if [[ -n $MP0_HOST ]]; then
  run_cmd pct set "$VMID" -mp0 "$MP0_HOST,mp=/srv/ralf"
fi
if [[ -n $MP1_HOST ]]; then
  run_cmd pct set "$VMID" -mp1 "$MP1_HOST,mp=/srv/ralf/models"
fi

if ! container_running "$VMID"; then
  log INFO "Starting container $VMID"
  run_cmd pct start "$VMID"
fi

wait_for_network "$VMID" eth0

provision_packages "$VMID"
provision_ollama "$VMID"
provision_aider "$VMID"
provision_directories "$VMID"
provision_wrapper "$VMID"

log INFO "Provisioning complete"

if [[ $DRY_RUN -eq 1 ]]; then
  echo "==> Dry run complete"
fi
