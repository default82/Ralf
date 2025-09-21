#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Provision a local LXC lab on a Proxmox node for exercising the RALF playbooks.

Options:
  -b, --bridge BRIDGE       Proxmox bridge to attach (default: vmbr0)
  -s, --storage STORAGE     Proxmox storage backend for rootfs (default: local-lvm)
  -t, --template PATH       LXC template path (default: local:vztmpl/debian-12-standard_12.0-1_amd64.tar.zst)
  -g, --gateway GATEWAY     IPv4 gateway for service VLAN (default: 10.23.20.1)
  -k, --ssh-key PATH        Inject SSH public key into each container
  -r, --recreate            Recreate containers if they already exist
  -n, --dry-run             Print actions without executing pct commands
  -h, --help                Show this help text

The script expects to run on a Proxmox host with pct available.
Container definitions use "auto" in the gateway column to inherit the default value from --gateway.
USAGE
}

err() {
  echo "[!] $*" >&2
}

die() {
  err "$1"
  exit "${2:-1}"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found in PATH"
}

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY-RUN: $*"
    return 0
  fi
  echo "+ $*"
  "$@"
}

BRIDGE="vmbr0"
STORAGE="local-lvm"
TEMPLATE="local:vztmpl/debian-12-standard_12.0-1_amd64.tar.zst"
DEFAULT_GATEWAY_V4="10.23.20.1"
SSH_KEY=""
RECREATE=0
DRY_RUN=0
declare -a PROCESSED=()

# Container specification: CTID HOSTNAME IPV4/MASK GATEWAY MEMORY(MiB) ROOTFS(GB) CORES
read -r -d '' CONTAINERS <<'SPEC'
201 dns01 10.23.20.10/23 auto 512 4 1
202 caddy01 10.23.20.20/23 auto 1024 8 2
203 auth01 10.23.20.30/23 auto 1024 8 2
204 mon01 10.23.20.40/23 auto 2048 8 2
205 backup01 10.23.30.10/24 10.23.30.1 2048 12 2
206 vaultwarden01 10.23.20.50/23 auto 1024 8 2
207 mail01 10.23.20.60/23 auto 2048 12 2
208 homeassistant01 10.23.20.70/23 auto 2048 12 3
SPEC

ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--bridge)
      BRIDGE="$2"; shift 2 ;;
    -s|--storage)
      STORAGE="$2"; shift 2 ;;
    -t|--template)
      TEMPLATE="$2"; shift 2 ;;
    -g|--gateway)
      DEFAULT_GATEWAY_V4="$2"; shift 2 ;;
    -k|--ssh-key)
      SSH_KEY="$2"; shift 2 ;;
    -r|--recreate)
      RECREATE=1; shift ;;
    -n|--dry-run)
      DRY_RUN=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    --)
      shift; break ;;
    -*)
      usage
      die "Unknown option: $1" ;;
    *)
      ARGS+=("$1"); shift ;;
  esac
done

if [[ ${#ARGS[@]} -gt 0 ]]; then
  usage
  die "Unexpected positional arguments: ${ARGS[*]}"
fi

require_cmd pct

if [[ -n "$SSH_KEY" ]]; then
  [[ -f "$SSH_KEY" ]] || die "SSH key '$SSH_KEY' not found"
fi

prepare_container() {
  local ctid="$1" hostname="$2" ipv4="$3" gateway="$4" mem="$5" rootfs_gb="$6" cores="$7"

  if pct status "$ctid" >/dev/null 2>&1; then
    if [[ "$RECREATE" -eq 1 ]]; then
      run pct stop "$ctid" || true
      run pct destroy "$ctid" || true
    else
      err "Container $ctid ($hostname) already exists; skipping (use --recreate to rebuild)"
      return
    fi
  fi

  local net_opts="name=eth0,bridge=${BRIDGE},hwaddr=$(generate_mac "$ctid"),ip=${ipv4},gw=${gateway}"
  local rootfs="${STORAGE}:${rootfs_gb}"

  local create_args=("$ctid" "$TEMPLATE" "--hostname" "$hostname" \
                     "--rootfs" "$rootfs" "--cores" "$cores" "--memory" "$mem" \
                     "--net0" "$net_opts" "--description" "RALF lab container ${hostname}" \
                     "--onboot" "1" "--unprivileged" "1" "--features" "nesting=1,keyctl=1")

  if [[ -n "$SSH_KEY" ]]; then
    create_args+=("--ssh-public-keys" "$SSH_KEY")
  fi

  run pct create "${create_args[@]}"
  run pct set "$ctid" --startup order="$ctid"
  run pct start "$ctid"
}

generate_mac() {
  local ctid="$1"
  printf 'de:ad:%02x:%02x:%02x:%02x' $(( (ctid >> 8) & 0xff )) $(( ctid & 0xff )) $(( RANDOM & 0xff )) $(( RANDOM & 0xff ))
}

summary() {
  printf '\nProvisioned/validated containers:\n'
  if [[ ${#PROCESSED[@]} -eq 0 ]]; then
    printf '  (none created)\n'
  else
    for entry in "${PROCESSED[@]}"; do
      printf '  - %s\n' "$entry"
    done
  fi
  printf '\nUse "pct console <CTID>" or SSH to the assigned addresses once the first boot sequence finishes.\n'
}

main() {
  PROCESSED=()
  while read -r ctid hostname ipv4 gateway mem rootfs_gb cores; do
    [[ -z "$ctid" ]] && continue
    [[ "$ctid" =~ ^# ]] && continue
    local resolved_gateway="$gateway"
    if [[ -z "$resolved_gateway" || "$resolved_gateway" == auto ]]; then
      resolved_gateway="$DEFAULT_GATEWAY_V4"
    fi
    PROCESSED+=("${ctid} ${hostname} -> ${ipv4} (gw ${resolved_gateway})")
    prepare_container "$ctid" "$hostname" "$ipv4" "$resolved_gateway" "$mem" "$rootfs_gb" "$cores"
  done <<< "$CONTAINERS"

  summary
}

main "$@"
