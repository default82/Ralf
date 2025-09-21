#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)
CONFIG_DIR=${RALF_LXC_CONFIG_DIR:-/etc/ralf-lxc.d}
CONFIG_FILE_TARGET=${RALF_LXC_CONFIG_FILE:-${CONFIG_DIR}/override.conf}
CONFIG_FILE=$CONFIG_FILE_TARGET
CONFIG_HEADER="# Managed by ${SCRIPT_NAME} -- manual edits may be overwritten"

declare -A EXISTING_CONFIG=()
declare -A FINAL_CONFIG=()

IS_INTERACTIVE=0
if [[ -t 0 && -t 1 ]]; then
  IS_INTERACTIVE=1
fi
if [[ ${RALF_LXC_NON_INTERACTIVE:-0} -eq 1 || ${RALF_LXC_AUTO_CONFIRM:-0} -eq 1 ]]; then
  IS_INTERACTIVE=0
fi

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME [options]

Options (can also be provided via environment variables):
  --vmid <id>          Container VMID (env: RALF_LXC_VMID, default: 10060)
  --hostname <name>    Container hostname (env: RALF_LXC_HOSTNAME, default: lisa-llm)
  --bridge <name>      Proxmox bridge (env: RALF_LXC_BRIDGE, default: vmbr0)
  --ip <cidr|dhcp>     IPv4 assignment (env: RALF_LXC_IP, default: dhcp)
  --gw <address>       IPv4 gateway (env: RALF_LXC_GW)
  --cores <count>      vCPU cores (env: RALF_LXC_CORES, default: dynamic)
  --memory <mb>        Memory in MiB (env: RALF_LXC_MEMORY, default: dynamic)
  --disk <size>        Root disk size (env: RALF_LXC_DISK, default: dynamic)
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

write_file() {
  local path=$1
  local mode=${2:-0644}
  local content=$3
  local display_path=${4:-$path}

  if [[ $DRY_RUN -eq 1 ]]; then
    log INFO "[dry-run] Would write ${display_path}"
    printf '%s\n' "$content"
    install -D -m "$mode" /dev/null "$path"
    printf '%s\n' "$content" >"$path"
    return
  fi

  install -D -m "$mode" /dev/null "$path"
  printf '%s\n' "$content" >"$path"
}

load_existing_config() {
  if [[ ! -f $CONFIG_FILE ]]; then
    return
  fi
  while IFS='=' read -r key value; do
    key=${key//[[:space:]]/}
    [[ -z $key || $key == \#* ]] && continue
    EXISTING_CONFIG[$key]=$value
  done <"$CONFIG_FILE"
}

save_final_config() {
  local keys=(
    VMID
    HOSTNAME
    STORAGE
    BRIDGE
    IP_ASSIGNMENT
    GATEWAY
    CORES
    MEMORY
    DISK_SIZE
    MP0_HOST
    MP1_HOST
  )

  local buffer="$CONFIG_HEADER"
  buffer+=$'\n'
  for key in "${keys[@]}"; do
    local value=${FINAL_CONFIG[$key]:-}
    [[ -z $value ]] && continue
    buffer+="${key}=${value}"$'\n'
  done

  write_file "$CONFIG_FILE" 0644 "$buffer" "$CONFIG_FILE_TARGET"
}

gather_host_resources() {
  ensure_command lscpu
  ensure_command free
  ensure_command lsblk

  HOST_TOTAL_CORES=0
  if command -v lscpu >/dev/null 2>&1; then
    HOST_TOTAL_CORES=$(lscpu | awk -F': +"?' '/^CPU\(s\):/ {print $2; exit}')
  fi
  if [[ -z $HOST_TOTAL_CORES ]]; then
    HOST_TOTAL_CORES=0
  fi

  HOST_TOTAL_MEM_MB=0
  if command -v free >/dev/null 2>&1; then
    HOST_TOTAL_MEM_MB=$(free -m | awk '/^Mem:/ {print $2; exit}')
  fi
  if [[ -z $HOST_TOTAL_MEM_MB ]]; then
    HOST_TOTAL_MEM_MB=0
  fi

  HOST_ROOT_BYTES=0
  if command -v lsblk >/dev/null 2>&1; then
    while IFS=' ' read -r entry; do
      eval "$entry"
      if [[ ${MOUNTPOINT:-} == '/' ]]; then
        HOST_ROOT_BYTES=${SIZE:-0}
        break
      fi
    done < <(lsblk -b -P -o NAME,MOUNTPOINT,SIZE 2>/dev/null)
  fi
  if [[ -z $HOST_ROOT_BYTES ]]; then
    HOST_ROOT_BYTES=0
  fi

  log INFO "Detected host cores: ${HOST_TOTAL_CORES:-unknown}"
  log INFO "Detected host memory (MiB): ${HOST_TOTAL_MEM_MB:-unknown}"
  if [[ $HOST_ROOT_BYTES -gt 0 ]]; then
    log INFO "Detected root disk (bytes): $HOST_ROOT_BYTES"
  else
    log WARN "Unable to determine root disk size"
  fi
}

calculate_dynamic_defaults() {
  gather_host_resources

  DEFAULT_CORES=2
  if [[ ${HOST_TOTAL_CORES:-0} -gt 0 ]]; then
    local half=$((HOST_TOTAL_CORES / 2))
    if (( half < 1 )); then
      half=$HOST_TOTAL_CORES
    fi
    if (( half < 2 && HOST_TOTAL_CORES >= 2 )); then
      half=2
    fi
    DEFAULT_CORES=$half
  fi

  DEFAULT_MEMORY=4096
  if [[ ${HOST_TOTAL_MEM_MB:-0} -gt 0 ]]; then
    local half=$((HOST_TOTAL_MEM_MB / 2))
    local reserve=$((HOST_TOTAL_MEM_MB - 512))
    if (( reserve <= 0 )); then
      reserve=$HOST_TOTAL_MEM_MB
    fi
    if (( half > reserve )); then
      half=$reserve
    fi
    if (( half < 2048 && HOST_TOTAL_MEM_MB >= 2048 )); then
      half=2048
    fi
    if (( half < 1024 )); then
      half=HOST_TOTAL_MEM_MB
    fi
    DEFAULT_MEMORY=$half
  fi

  DEFAULT_DISK_SIZE=24G
  if [[ ${HOST_ROOT_BYTES:-0} -gt 0 ]]; then
    local root_mib=$((HOST_ROOT_BYTES / 1024 / 1024))
    if (( root_mib > 0 )); then
      local proposed=$((root_mib / 3))
      local min_mib=$((24 * 1024))
      local reserve=$((root_mib - 10240))
      if (( proposed < min_mib )); then
        proposed=$min_mib
      fi
      if (( reserve > 0 && proposed > reserve )); then
        proposed=$reserve
      fi
      if (( proposed < min_mib )); then
        proposed=min_mib
      fi
      if (( proposed < 1024 )); then
        proposed=1024
      fi
      local gib=$(( (proposed + 1023) / 1024 ))
      if (( gib < 1 )); then
        gib=24
      fi
      DEFAULT_DISK_SIZE="${gib}G"
    fi
  fi
}

prompt_for_setting() {
  local key=$1
  local description=$2
  local default_value=$3

  if [[ -n ${!key:-} ]]; then
    FINAL_CONFIG[$key]=${!key}
    return
  fi

  local candidate=${EXISTING_CONFIG[$key]:-$default_value}

  if [[ $IS_INTERACTIVE -eq 1 ]]; then
    local input
    read -r -p "${description} [${candidate}]: " input || true
    if [[ -n $input ]]; then
      candidate=$input
    fi
  else
    log INFO "Auto-confirming ${description}: ${candidate}"
  fi

  printf -v "$key" '%s' "$candidate"
  FINAL_CONFIG[$key]=$candidate
}

run_reconcile_script() {
  local vmid=$1
  local reconcile_script="$REPO_ROOT/automation/ralf/reconcile_lxc_resources.sh"
  if [[ ! -f $reconcile_script ]]; then
    log ERROR "Reconcile helper not found at $reconcile_script"
    exit 1
  fi

  log INFO "Reconciling pct configuration for VMID $vmid"
  if [[ $DRY_RUN -eq 1 ]]; then
    env RALF_LXC_CONFIG_FILE="$CONFIG_FILE" RALF_LXC_DRY_RUN=1 "$reconcile_script" --vmid "$vmid"
  else
    env RALF_LXC_CONFIG_FILE="$CONFIG_FILE" "$reconcile_script" --vmid "$vmid"
  fi
}

install_reconcile_hook() {
  local reconcile_source="$REPO_ROOT/automation/ralf/reconcile_lxc_resources.sh"
  local reconcile_target=/usr/local/sbin/ralf-lxc-reconcile
  local service_path=/etc/systemd/system/ralf-lxc-reconcile.service
  local timer_path=/etc/systemd/system/ralf-lxc-reconcile.timer

  if [[ ! -f $reconcile_source ]]; then
    log ERROR "Reconcile helper not found at $reconcile_source"
    exit 1
  fi

  run_cmd install -D -m 0755 "$reconcile_source" "$reconcile_target"

  local service_content
  service_content=$(cat <<EOF
[Unit]
Description=Reconcile Ralf LXC resources
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment=RALF_LXC_CONFIG_FILE=$CONFIG_FILE_TARGET
ExecStart=$reconcile_target --vmid $VMID
EOF
)

  local service_write_path=$service_path
  local timer_write_path=$timer_path
  if [[ $DRY_RUN -eq 1 ]]; then
    service_write_path=$(mktemp -t ralf-lxc-service.XXXXXX)
    timer_write_path=$(mktemp -t ralf-lxc-timer.XXXXXX)
  fi

  write_file "$service_write_path" 0644 "$service_content" "$service_path"

  local timer_content
  timer_content=$(cat <<EOF
[Unit]
Description=Periodic Ralf LXC resource reconciliation timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF
)

  write_file "$timer_write_path" 0644 "$timer_content" "$timer_path"

  ensure_command systemctl

  if [[ $DRY_RUN -eq 1 ]]; then
    log INFO "Dry run: skipping systemd enablement for ralf-lxc-reconcile.timer"
    return
  fi

  run_cmd systemctl daemon-reload
  run_cmd systemctl enable --now ralf-lxc-reconcile.timer
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

  local template_entry="$template_path"
  if pveam list "$storage" | awk -v target="$template_entry" '
      NR == 1 && $1 == "NAME" { next }
      $1 == target { found=1 }
      END { exit found ? 0 : 1 }
    ';
  then
    log INFO "Template $template already available on $storage"
    return
  fi

  log INFO "Downloading template $template to $storage"
  run_cmd pveam download "$storage" "$template"
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
  local wrapper_source="$REPO_ROOT/automation/ralf/rlwrap/ralf-ai.sh"
  if [[ ! -f $wrapper_source ]]; then
    log ERROR "Wrapper script not found at $wrapper_source"
    exit 1
  fi

  local tmp_dir
  tmp_dir=$(mktemp -d)

  local wrapper_path="${tmp_dir}/ralf-ai"
  cp "$wrapper_source" "$wrapper_path"

  run_cmd pct push "$vmid" "$wrapper_path" /usr/local/bin/ralf-ai
  pct_exec "$vmid" chmod 0755 /usr/local/bin/ralf-ai
  pct_exec "$vmid" /usr/local/bin/ralf-ai --help

  rm -rf "$tmp_dir"
}

# Defaults from environment overrides and persisted configuration
DRY_RUN=${RALF_LXC_DRY_RUN:-0}

load_existing_config

VMID=${RALF_LXC_VMID:-${EXISTING_CONFIG[VMID]:-10060}}
HOSTNAME=${RALF_LXC_HOSTNAME:-${EXISTING_CONFIG[HOSTNAME]:-lisa-llm}}
BRIDGE=${RALF_LXC_BRIDGE:-${EXISTING_CONFIG[BRIDGE]:-vmbr0}}
IP_ASSIGNMENT=${RALF_LXC_IP:-${EXISTING_CONFIG[IP_ASSIGNMENT]:-dhcp}}
GATEWAY=${RALF_LXC_GW:-${EXISTING_CONFIG[GATEWAY]:-}}
CORES=${RALF_LXC_CORES:-${EXISTING_CONFIG[CORES]:-}}
MEMORY=${RALF_LXC_MEMORY:-${EXISTING_CONFIG[MEMORY]:-}}
DISK_SIZE=${RALF_LXC_DISK:-${EXISTING_CONFIG[DISK_SIZE]:-}}
STORAGE=${RALF_LXC_STORAGE:-${EXISTING_CONFIG[STORAGE]:-local-lvm}}
MP0_HOST=${RALF_LXC_MP0_HOST:-${EXISTING_CONFIG[MP0_HOST]:-/srv/ralf}}
MP1_HOST=${RALF_LXC_MP1_HOST:-${EXISTING_CONFIG[MP1_HOST]:-}}

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

if [[ $DRY_RUN != 0 ]]; then
  DRY_RUN=1
fi

if [[ $DRY_RUN -eq 1 ]]; then
  CONFIG_FILE=$(mktemp -t ralf-lxc-config.XXXXXX)
else
  CONFIG_FILE=$CONFIG_FILE_TARGET
fi

calculate_dynamic_defaults

prompt_for_setting CORES "vCPU cores" "$DEFAULT_CORES"
prompt_for_setting MEMORY "Memory (MiB)" "$DEFAULT_MEMORY"
prompt_for_setting DISK_SIZE "Root disk size" "$DEFAULT_DISK_SIZE"

log INFO "Planned container resources: cores=${CORES}, memory=${MEMORY}MiB, disk=${DISK_SIZE}"

FINAL_CONFIG[VMID]=$VMID
FINAL_CONFIG[HOSTNAME]=$HOSTNAME
FINAL_CONFIG[STORAGE]=$STORAGE
FINAL_CONFIG[BRIDGE]=$BRIDGE
FINAL_CONFIG[IP_ASSIGNMENT]=$IP_ASSIGNMENT
FINAL_CONFIG[GATEWAY]=$GATEWAY
FINAL_CONFIG[MP0_HOST]=$MP0_HOST
FINAL_CONFIG[MP1_HOST]=$MP1_HOST

save_final_config

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
  log INFO "Container $VMID already exists; ensuring configuration matches overrides"
fi

run_reconcile_script "$VMID"
install_reconcile_hook

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
