#!/usr/bin/env bash
set -euo pipefail

PLAN_FILE=${1:-}
INVENTORY_FILE=${2:-/root/ralf/inventory.json}
LOG_DIR="/root/ralf/logs"
LOG_FILE="${LOG_DIR}/provider.log"
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "[PVE] Provider gestartet $(date)"

if [[ -z "$PLAN_FILE" || ! -f "$PLAN_FILE" ]]; then
  echo "[PVE][ERROR] Plan-Datei fehlt: $PLAN_FILE" >&2
  exit 1
fi

require_cmd() {
  local cmd=$1
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "[PVE][ERROR] Benötigtes Kommando '$cmd' nicht gefunden." >&2
    exit 1
  }
}

for bin in jq pct pveam pvesh lspci; do
  require_cmd "$bin"
done

PLAN_JSON=$(cat "$PLAN_FILE")
SITE_CODE=$(jq -r '.site_code' <<<"$PLAN_JSON")
ADDRESSING_MODE=$(jq -r '.networking.addressing_mode' <<<"$PLAN_JSON")
BASE_NET=$(jq -r '.networking.base_network' <<<"$PLAN_JSON")
GATEWAY_OCTET=$(jq -r '.networking.gateway_octet' <<<"$PLAN_JSON")
KI_STACK=$(jq -r '.ki_stack' <<<"$PLAN_JSON")
DOMAIN_BASE=$(jq -r '.domain.base_domain' <<<"$PLAN_JSON")

IFS='.' read -r BASE_A BASE_B <<<"$BASE_NET"

ensure_template() {
  local template="local:vztmpl/debian-12-standard_12.0-1_amd64.tar.zst"
  if ! pveam list local | awk '{print $1}' | grep -q "$template"; then
    echo "[PVE] Lade Debian LXC Template..."
    pveam update
    pveam download local debian-12-standard_12.0-1_amd64.tar.zst
  fi
  echo "$template"
}

TEMPLATE=$(ensure_template)

echo "[PVE] Verwende Template $TEMPLATE"

compute_ip() {
  local category=$1
  local host=$2
  printf "%s.%s.%s.%s" "$BASE_A" "$BASE_B" "$category" "$host"
}

compute_gateway() {
  local category=$1
  printf "%s.%s.%s.%s" "$BASE_A" "$BASE_B" "$category" "$GATEWAY_OCTET"
}

slugify() {
  local value=$1
  value=${value,,}
  value=${value//_/}
  value=${value//./-}
  value=${value// /-}
  echo "$value"
}

stack_from_category() {
  local category=$1
  if (( category <= 40 )); then
    echo "core"
  elif (( category <= 90 )); then
    echo "platform"
  elif (( category <= 120 )); then
    echo "apps"
  else
    echo "misc"
  fi
}

GPU_VENDOR="none"
GPU_DEVICES=()

detect_gpu() {
  local lspci_output
  lspci_output=$(lspci -nn | tr '[:upper:]' '[:lower:]')
  if grep -q "nvidia" <<<"$lspci_output"; then
    GPU_VENDOR="nvidia"
    GPU_DEVICES=(/dev/nvidiactl /dev/nvidia0 /dev/nvidia-uvm /dev/nvidia-uvm-tools)
  elif grep -q "amd" <<<"$lspci_output" && grep -q "vga" <<<"$lspci_output"; then
    GPU_VENDOR="amd"
    GPU_DEVICES=(/dev/dri/renderD128 /dev/kfd)
  elif grep -q "intel" <<<"$lspci_output"; then
    GPU_VENDOR="intel"
    GPU_DEVICES=(/dev/dri/renderD128)
  else
    GPU_VENDOR="none"
    GPU_DEVICES=()
  fi
}

detect_gpu

echo "[PVE] GPU erkannt: ${GPU_VENDOR}"

inventory_entries=()

jq -r '.services | to_entries[] | @base64' <<<"$PLAN_JSON" | while read -r entry; do
  _jq() { echo "$entry" | base64 --decode | jq -r "$1"; }
  SERVICE_NAME=$(_jq '.key')
  CATEGORY=$(_jq '.value.category')
  HOST_OCTET=$(_jq '.value.host_octet')
  EXPOSURE=$(_jq '.value.exposure')
  FQDN=$(_jq '.value.fqdn')
  CTID="${CATEGORY}${HOST_OCTET}"
  HOSTNAME="${SERVICE_NAME}.${DOMAIN_BASE}"
  SHORT_NAME=$(slugify "$SERVICE_NAME")
  STACK=$(stack_from_category "$CATEGORY")
  TAGS="role-${SHORT_NAME};cat-${CATEGORY}-${SHORT_NAME};site-${SITE_CODE};env-prod;stack-${STACK}"

  echo "[PVE] Verarbeite Dienst ${SERVICE_NAME} (CTID ${CTID})"

  NETCONF="name=eth0,bridge=vmbr0"
  IP_ADDRESS=""
  if [[ "$ADDRESSING_MODE" == "dhcp" ]]; then
    NETCONF+="\,ip=dhcp"
  else
    IP_ADDRESS=$(compute_ip "$CATEGORY" "$HOST_OCTET")
    GATEWAY=$(compute_gateway "$CATEGORY")
    NETCONF+="\,ip=${IP_ADDRESS}/24,gw=${GATEWAY}"
  fi

  if pct status "$CTID" >/dev/null 2>&1; then
    echo "[PVE] Container ${CTID} existiert bereits. Aktualisiere Tags und Netzwerk."
    pct stop "$CTID" >/dev/null 2>&1 || true
    pct set "$CTID" --hostname "$HOSTNAME" --net0 "$NETCONF" --features nesting=1 >/dev/null
  else
    echo "[PVE] Erzeuge Container ${CTID}"
    pct create "$CTID" "$TEMPLATE" \
      --hostname "$HOSTNAME" \
      --cores 2 \
      --memory 4096 \
      --swap 1024 \
      --rootfs local-lvm:8 \
      --unprivileged 1 \
      --features nesting=1 \
      --onboot 1 \
      --start 0 \
      --net0 "$NETCONF"
  fi

  pct set "$CTID" -tags "$TAGS" >/dev/null

  if [[ "$SERVICE_NAME" == "ralf-ki" ]]; then
    echo "[PVE] GPU-Zuweisung für KI-Container"
    case "$GPU_VENDOR" in
      nvidia)
        pct set "$CTID" --mp0 /dev/nvidiactl,mp=/dev/nvidiactl,ro=0 >/dev/null 2>&1 || true
        pct set "$CTID" --mp1 /dev/nvidia0,mp=/dev/nvidia0,ro=0 >/dev/null 2>&1 || true
        pct set "$CTID" --mp2 /dev/nvidia-uvm,mp=/dev/nvidia-uvm,ro=0 >/dev/null 2>&1 || true
        pct set "$CTID" --mp3 /dev/nvidia-uvm-tools,mp=/dev/nvidia-uvm-tools,ro=0 >/dev/null 2>&1 || true
        pct set "$CTID" -lxc.cgroup2.devices.allow "c 195:* rwm" >/dev/null 2>&1 || true
        ;;
      amd)
        pct set "$CTID" --mp0 /dev/dri,mp=/dev/dri,ro=0 >/dev/null 2>&1 || true
        pct set "$CTID" --mp1 /dev/kfd,mp=/dev/kfd,ro=0 >/dev/null 2>&1 || true
        pct set "$CTID" -lxc.cgroup2.devices.allow "c 226:* rwm" >/dev/null 2>&1 || true
        ;;
      intel)
        pct set "$CTID" --mp0 /dev/dri,mp=/dev/dri,ro=0 >/dev/null 2>&1 || true
        pct set "$CTID" -lxc.cgroup2.devices.allow "c 226:* rwm" >/dev/null 2>&1 || true
        ;;
      none)
        echo "[PVE] Keine GPU verfügbar – CPU-Modus."
        ;;
    esac
  fi

  echo "[PVE] Starte Container ${CTID}"
  pct start "$CTID" || pct start "$CTID"

  sleep 5

  if [[ -z "$IP_ADDRESS" ]]; then
    IP_ADDRESS=$(pct exec "$CTID" -- bash -lc "ip -4 addr show dev eth0 | awk '/inet / {print \$2}' | cut -d/ -f1" || true)
  fi

  if [[ -z "$IP_ADDRESS" ]]; then
    echo "[PVE][WARN] IP-Adresse von ${CTID} konnte nicht ermittelt werden."
  else
    echo "[PVE] IP-Adresse: ${IP_ADDRESS}"
  fi

  if [[ "$SERVICE_NAME" == "ralf-ki" ]]; then
    echo "[PVE] Installiere KI-Stack ($KI_STACK)"
    pct exec "$CTID" -- bash -lc "mkdir -p /root/ralf && echo '$KI_STACK' > /root/ralf/ki_stack_selected"
    case "$KI_STACK" in
      CPU_OLLAMA)
        pct exec "$CTID" -- bash -lc 'apt-get update && apt-get install -y curl gnupg ca-certificates && curl https://ollama.ai/install.sh | bash' || true
        ;;
      GPU_NVIDIA_OLLAMA)
        pct exec "$CTID" -- bash -lc 'apt-get update && apt-get install -y nvidia-driver nvidia-cuda-toolkit curl && curl https://ollama.ai/install.sh | bash' || true
        ;;
      GPU_NVIDIA_VLLM)
        pct exec "$CTID" -- bash -lc 'apt-get update && apt-get install -y docker.io python3-pip && systemctl enable --now docker && pip3 install vllm' || true
        ;;
      GPU_AMD_ROCM_OLLAMA)
        pct exec "$CTID" -- bash -lc 'apt-get update && apt-get install -y rocm-hip-runtime curl && curl https://ollama.ai/install.sh | bash' || true
        ;;
      GPU_AMD_ROCM_VLLM)
        pct exec "$CTID" -- bash -lc 'apt-get update && apt-get install -y docker.io python3-pip rocm-hip-runtime && systemctl enable --now docker && pip3 install vllm' || true
        ;;
      GPU_INTEL_EXPERIMENTAL)
        pct exec "$CTID" -- bash -lc 'apt-get update && apt-get install -y intel-opencl-icd beignet-opencl-icd ocl-icd-libopencl1 curl && curl https://ollama.ai/install.sh | bash' || true
        ;;
      REMOTE)
        pct exec "$CTID" -- bash -lc 'apt-get update && apt-get install -y curl jq' || true
        ;;
      *)
        echo "[PVE][WARN] Unbekannter KI-Stack $KI_STACK"
        ;;
    esac
  fi

  entry_json=$(jq -n \
    --arg name "$SERVICE_NAME" \
    --arg ctid "$CTID" \
    --arg ip "${IP_ADDRESS:-unknown}" \
    --arg exposure "$EXPOSURE" \
    --arg fqdn "$FQDN" \
    '{name:$name, ctid:$ctid, ip:$ip, exposure:$exposure, fqdn:$fqdn}')
  inventory_entries+=("$entry_json")

done

printf '%s\n' "${inventory_entries[@]}" | jq -s '{containers: ., generated: now}' > "$INVENTORY_FILE"

echo "[PVE] Inventar gespeichert in $INVENTORY_FILE"
