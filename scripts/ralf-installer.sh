#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

require_repo_root() {
  if [[ ! -f "${PROJECT_ROOT}/README.md" ]]; then
    echo "Error: unable to locate repository root." >&2
    exit 1
  fi
}

prompt() {
  local message="$1"
  local default_value="$2"
  local response
  if [[ -n "${default_value}" ]]; then
    read -r -p "${message} [${default_value}]: " response || true
  else
    read -r -p "${message}: " response || true
  fi
  if [[ -z "${response}" ]]; then
    response="${default_value}"
  fi
  echo "${response}"
}

trim() {
  local value="$1"
  # shellcheck disable=SC2001
  echo "${value}" | sed 's/^\s*//;s/\s*$//'
}

backup_file() {
  local file_path="$1"
  if [[ -f "${file_path}" ]]; then
    local backup_path="${file_path}.$(date +%Y%m%d%H%M%S).bak"
    cp "${file_path}" "${backup_path}"
    echo "Backed up ${file_path} -> ${backup_path}"
  fi
}

write_inventory() {
  local inventory_path="${PROJECT_ROOT}/inventory/hosts.yaml"
  backup_file "${inventory_path}"

  cat > "${inventory_path}" <<EOF
all:
  children:
    proxmox:
      hosts:
EOF
  for idx in "${!PROXMOX_NAMES[@]}"; do
    printf "        %s:\n          ansible_host: %s\n" "${PROXMOX_NAMES[$idx]}" "${PROXMOX_IPS[$idx]}" >> "${inventory_path}"
  done

  cat >> "${inventory_path}" <<'EOCORE'
    core:
      hosts:
EOCORE
  for service in dns caddy auth monitoring backups; do
    printf "        %s:\n          ansible_host: %s\n" "${SERVICE_HOSTNAMES[$service]}" "${SERVICE_IPS[$service]}" >> "${inventory_path}"
  done

  cat >> "${inventory_path}" <<'EOSVC'
    services:
      hosts:
EOSVC
  for service in vaultwarden mail homeassistant; do
    printf "        %s:\n          ansible_host: %s\n" "${SERVICE_HOSTNAMES[$service]}" "${SERVICE_IPS[$service]}" >> "${inventory_path}"
  done

  echo "Updated ${inventory_path}."
}

write_group_vars() {
  local groups_path="${PROJECT_ROOT}/inventory/groups.yaml"
  backup_file "${groups_path}"

  {
    cat <<EOHEAD
all:
  vars:
    ansible_user: root
    acme_email: ${ACME_EMAIL}
    domain: ${HOMELAB_DOMAIN}
    dns_forwarders:
EOHEAD
    for forwarder in "${DNS_FORWARDERS[@]}"; do
      printf "      - %s\n" "${forwarder}"
    done
    cat <<EOGROUPS
proxmox:
  vars:
    proxmox_api_user: ${PROXMOX_API_USER}
    proxmox_api_token: ${PROXMOX_API_TOKEN}
core:
  vars:
    monitoring_contact: ${MONITORING_CONTACT}
services:
  vars:
    service_owner: ${SERVICE_OWNER}
EOGROUPS
  } > "${groups_path}"
  echo "Updated ${groups_path}."
}

write_vlan_plan() {
  local vlan_path="${PROJECT_ROOT}/network/vlan-plan.yaml"
  backup_file "${vlan_path}"

  {
    cat <<EOVLAN
cidr: ${GLOBAL_CIDR}
vlans:
  - id: ${MGMT_VLAN}
    name: mgmt
    subnet: ${MGMT_SUBNET}
    gateway: ${MGMT_GATEWAY}
  - id: ${SERVICES_VLAN}
    name: services
    subnet: ${SERVICES_SUBNET}
    gateway: ${SERVICES_GATEWAY}
  - id: ${STORAGE_VLAN}
    name: storage
    subnet: ${STORAGE_SUBNET}
    gateway: ${STORAGE_GATEWAY}
  - id: ${DMZ_VLAN}
    name: dmz
    subnet: ${DMZ_SUBNET}
    gateway: ${DMZ_GATEWAY}
dns:
  domain: ${HOMELAB_DOMAIN}
  servers:
EOVLAN
    printf "    - %s\n" "${SERVICE_IPS[dns]}"
    cat <<EOINGRESS
ingress:
  caddy:
    acme: true
    email: ${ACME_EMAIL}
    policy: avoid_port_forwards
EOINGRESS
  } > "${vlan_path}"
  echo "Updated ${vlan_path}."
}

write_proxmox_bridges() {
  local bridges_path="${PROJECT_ROOT}/network/proxmox-bridges.yaml"
  backup_file "${bridges_path}"

  cat > "${bridges_path}" <<EOBRIDGE
vmbr0:
  address: ${VMBR0_ADDRESS}
  gateway: ${MGMT_GATEWAY}
  bridge_ports: ${BRIDGE_INTERFACE}
  vlans: [${MGMT_VLAN}, ${SERVICES_VLAN}, ${STORAGE_VLAN}, ${DMZ_VLAN}]
lxc_defaults:
  unprivileged: true
  features:
    - nesting
EOBRIDGE
  echo "Updated ${bridges_path}."
}

print_summary() {
  cat <<EOSUM
========================================
RALF installation manifest written.

Proxmox nodes:
EOSUM
  for idx in "${!PROXMOX_NAMES[@]}"; do
    printf "  - %s (%s)\n" "${PROXMOX_NAMES[$idx]}" "${PROXMOX_IPS[$idx]}"
  done
  cat <<EOSERVICES

Service LXCs:
EOSERVICES
  for service in dns caddy auth monitoring backups vaultwarden mail homeassistant; do
    printf "  - %s: %s (%s)\n" "${service}" "${SERVICE_HOSTNAMES[$service]}" "${SERVICE_IPS[$service]}"
  done
  cat <<EONET

Network layout:
  CIDR: ${GLOBAL_CIDR}
  Management: VLAN ${MGMT_VLAN} / ${MGMT_SUBNET}
  Services: VLAN ${SERVICES_VLAN} / ${SERVICES_SUBNET}
  Storage: VLAN ${STORAGE_VLAN} / ${STORAGE_SUBNET}
  DMZ: VLAN ${DMZ_VLAN} / ${DMZ_SUBNET}

Next steps:
  - Seed your LXC templates with scripts/lisa_build_lxc.sh.
  - Run make bootstrap to prepare Proxmox.
  - Execute make apply once ready to deploy services.
========================================
EONET
}

main() {
  require_repo_root

  HOMELAB_DOMAIN=$(prompt "Homelab primary domain" "homelab.lan")
  ACME_EMAIL=$(prompt "ACME contact email" "admin@${HOMELAB_DOMAIN}")
  DNS_FORWARDERS_RAW=$(prompt "Comma-separated upstream DNS forwarders" "1.1.1.1,9.9.9.9")
  read -r -a DNS_FORWARDERS <<< "$(echo "${DNS_FORWARDERS_RAW}" | tr ',' '\n')"
  for idx in "${!DNS_FORWARDERS[@]}"; do
    DNS_FORWARDERS[$idx]="$(trim "${DNS_FORWARDERS[$idx]}")"
  done

  GLOBAL_CIDR=$(prompt "Global network CIDR" "10.23.0.0/16")
  MGMT_SUBNET=$(prompt "Management subnet" "10.23.10.0/24")
  MGMT_GATEWAY=$(prompt "Management gateway" "10.23.10.1")
  MGMT_VLAN=$(prompt "Management VLAN ID" "10")

  SERVICES_SUBNET=$(prompt "Services subnet" "10.23.20.0/24")
  SERVICES_GATEWAY=$(prompt "Services gateway" "10.23.20.1")
  SERVICES_VLAN=$(prompt "Services VLAN ID" "20")


  STORAGE_SUBNET=$(prompt "Storage subnet" "10.23.30.0/24")
  STORAGE_GATEWAY=$(prompt "Storage gateway" "10.23.30.1")
  STORAGE_VLAN=$(prompt "Storage VLAN ID" "30")


  DMZ_SUBNET=$(prompt "DMZ subnet" "10.23.40.0/24")
  DMZ_GATEWAY=$(prompt "DMZ gateway" "10.23.40.1")
  DMZ_VLAN=$(prompt "DMZ VLAN ID" "40")

  BRIDGE_INTERFACE=$(prompt "Physical interface for vmbr0" "eno1")
  VMBR0_ADDRESS=$(prompt "vmbr0 address" "10.23.10.2/24")

  PROXMOX_API_USER=$(prompt "Proxmox API user" "root@pam")
  PROXMOX_API_TOKEN=$(prompt "Proxmox API token" "changeme")
  MONITORING_CONTACT=$(prompt "Monitoring contact email" "oncall@${HOMELAB_DOMAIN}")
  SERVICE_OWNER=$(prompt "Service owner identifier" "homelab")

  local node_count
  node_count=$(prompt "Number of Proxmox nodes" "1")
  if ! [[ "${node_count}" =~ ^[0-9]+$ ]] || [[ "${node_count}" -lt 1 ]]; then
    echo "Invalid node count: ${node_count}" >&2
    exit 1
  fi

  PROXMOX_NAMES=()
  PROXMOX_IPS=()
  for ((i=1; i<=node_count; i++)); do
    local default_name="pve$((i-1))"

    local name ip
    name=$(prompt "Hostname for Proxmox node #${i}" "${default_name}")
    ip=$(prompt "Management IP for ${name}" "${default_ip}")
    PROXMOX_NAMES+=("${name}")
    PROXMOX_IPS+=("${ip}")
  done

  declare -gA SERVICE_HOSTNAMES
  declare -gA SERVICE_IPS

  declare -A default_names=(
    [dns]="dns01"
    [caddy]="caddy01"
    [auth]="auth01"
    [monitoring]="mon01"
    [backups]="backup01"
    [vaultwarden]="vaultwarden01"
    [mail]="mail01"
    [homeassistant]="homeassistant01"
  )


  )

  echo "\nConfigure service LXCs (one per service)."
  for service in dns caddy auth monitoring backups vaultwarden mail homeassistant; do

    local host_prompt="Hostname for ${service} LXC"
    local ip_prompt="IP address for ${service} (${service} runs in its own LXC)"
    local hostname ip
    hostname=$(prompt "${host_prompt}" "${default_names[$service]}")

    SERVICE_HOSTNAMES[$service]="${hostname}"
    SERVICE_IPS[$service]="${ip}"
  done

  write_inventory
  write_group_vars
  write_vlan_plan
  write_proxmox_bridges
  print_summary
}

main "$@"
