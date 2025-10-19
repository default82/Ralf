#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME=svc-n8n
CTID_VAR=N8N_CTID
IP_VAR=N8N_IPV4
GATEWAY_VAR=N8N_GW
HOSTNAME_VAR=N8N_FQDN
CPU_VAR=N8N_CPUS
MEM_VAR=N8N_MEMORY
DISK_VAR=N8N_DISK

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VARS_FILE="${PROJECT_ROOT}/infra/network/preflight.vars.source"
LOGGER_BIN=$(command -v logger || true)
LOG_TAG=${LOG_TAG:-pct-${CONTAINER_NAME}}
DEFAULT_CPUS=${DEFAULT_CPUS:-1}
DEFAULT_MEMORY=${DEFAULT_MEMORY:-2048}
DEFAULT_DISK=${DEFAULT_DISK:-6G}

tlog(){
  local level=$1; shift
  local msg=$*
  [[ -n ${LOGGER_BIN:-} ]] && ${LOGGER_BIN} -t "${LOG_TAG}" "${level}: ${msg}" || true
  printf '%s: %s\n' "${level}" "${msg}"
}

if [[ -f ${VARS_FILE} ]]; then
  # shellcheck disable=SC1090
  source "${VARS_FILE}"
fi

if ! command -v pct >/dev/null 2>&1; then
  tlog "ERROR" "pct CLI nicht gefunden"
  exit 1
fi

get_value()
{
  local var_name=$1 prompt=$2 default=$3
  local value=${!var_name:-}
  if [[ -z ${value} || ${value} == ASK_RUNTIME ]]; then
    read -rp "${prompt} [${default}]: " value
    value=${value:-${default}}
  fi
  printf '%s' "${value}"
}

ctid=$(get_value "${CTID_VAR}" "CTID für ${CONTAINER_NAME}" "")
if [[ -z ${ctid} ]]; then
  tlog "ERROR" "CTID wird benötigt"
  exit 1
fi

if pct status "${ctid}" >/dev/null 2>&1; then
  tlog "INFO" "Container ${CONTAINER_NAME} (${ctid}) existiert bereits"
  exit 0
fi

ip=$(get_value "${IP_VAR}" "IPv4 (CIDR)" "")
gateway=$(get_value "${GATEWAY_VAR}" "Gateway IPv4" "")
hostname=$(get_value "${HOSTNAME_VAR}" "FQDN" "${CONTAINER_NAME}.home.arpa")
cpus=$(get_value "${CPU_VAR}" "vCPUs" "${DEFAULT_CPUS}")
mem=$(get_value "${MEM_VAR}" "Memory (MB)" "${DEFAULT_MEMORY}")
disk=$(get_value "${DISK_VAR}" "Diskgröße" "${DEFAULT_DISK}")
bridge=${RALF_BRIDGE:-vmbr0}

if [[ -z ${RALF_TEMPLATE_PATH:-} ]]; then
  read -rp "Template-Pfad (z. B. local:vztmpl/ubuntu-24.04-standard_20240512.tar.zst): " RALF_TEMPLATE_PATH
fi
if [[ -z ${RALF_STORAGE_TARGET:-} ]]; then
  read -rp "Storage-Target (z. B. local-lvm): " RALF_STORAGE_TARGET
fi

NETCONF="name=eth0,bridge=${bridge}"
if [[ -n ${ip} ]]; then
  NETCONF+=",ip=${ip}"
fi
if [[ -n ${gateway} ]]; then
  NETCONF+=",gw=${gateway}"
fi

ROOTFS="${RALF_STORAGE_TARGET}:${disk}"

if [[ -f ${HOME}/.ssh/id_ed25519.pub ]]; then
  SSH_KEY=${HOME}/.ssh/id_ed25519.pub
elif [[ -f ${HOME}/.ssh/id_rsa.pub ]]; then
  SSH_KEY=${HOME}/.ssh/id_rsa.pub
else
  read -rp "Pfad zum SSH-Pubkey: " SSH_KEY
fi

tlog "INFO" "Erzeuge Container ${CONTAINER_NAME} (${ctid})"
pct create "${ctid}" "${RALF_TEMPLATE_PATH}" \
  -storage "${RALF_STORAGE_TARGET}" \
  -rootfs "${ROOTFS}" \
  -hostname "${hostname}" \
  -features nesting=1 \
  -unprivileged 1 \
  -onboot 1 \
  -ostype ubuntu \
  -password '' \
  -ssh-public-keys "${SSH_KEY}" \
  -cores "${cpus}" \
  -memory "${mem}" \
  -net0 "${NETCONF}"

pct set "${ctid}" -timezone "${RALF_TIMEZONE:-Europe/Berlin}" >/dev/null 2>&1 || true
pct start "${ctid}"
tlog "INFO" "Container ${CONTAINER_NAME} gestartet"
