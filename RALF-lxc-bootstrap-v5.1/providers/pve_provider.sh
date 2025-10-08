#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../scripts/common.sh"

PLAN=""
INV=""
KI_CHOICE_FILE=""

pkg(){ apt-get update -y; DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"; }

ensure_template(){
  pveam update
  local storage template_pattern best
  storage=$(jq -r '.pve.storage' "$CONFIG_FILE")
  template_pattern=$(jq -r '.pve.template_pattern' "$CONFIG_FILE")
  best=$(pveam available | awk -v pat="$template_pattern" '$2 ~ pat {print $2}' | tail -n1)
  if [[ -z "$best" ]]; then
    echo "[!] Kein Template gefunden für Muster ${template_pattern}" >&2
    exit 1
  fi
  if ! pveam list "$storage" | grep -q "$best"; then pveam download "$storage" "$best"; fi
  echo "$storage" > /tmp/pve_storage.txt
  echo "$best" > /tmp/pve_template.txt
}

calc_ip(){
  local base; base=$(jq -r '.ip_base' "$PLAN")
  local o1=$(echo "$base" | cut -d. -f1); local o2=$(echo "$base" | cut -d. -f2)
  local cat="$1"; local host="$2"
  echo "${o1}.${o2}.${cat}.${host}"
}

next_mp_index(){
  local cfg="$1" idx max=-1
  while IFS=: read -r key _; do
    if [[ $key =~ ^mp([0-9]+)$ ]]; then
      idx=${BASH_REMATCH[1]}
      (( idx > max )) && max=$idx
    fi
  done <<< "$cfg"
  echo $((max + 1))
}

map_devices(){
  local ctid="$1"; shift
  local cfg="$(pct config "$ctid" 2>/dev/null || true)"
  local idx="$(next_mp_index "$cfg")"
  local dev
  for dev in "$@"; do
    [[ -e "$dev" ]] || continue
    if grep -q "mp[0-9]\+: ${dev}," <<< "$cfg"; then
      continue
    fi
    pct set "$ctid" "-mp${idx}" "$dev",mp="$dev" || true
    cfg+=$'\n'"mp${idx}: ${dev},mp=${dev}"
    idx=$((idx + 1))
  done
}

map_nvidia(){ local ctid="$1"; map_devices "$ctid" /dev/nvidiactl /dev/nvidia0 /dev/nvidia-uvm /dev/nvidia-uvm-tools; { echo "lxc.cgroup2.devices.allow: c 195:* rwm"; echo "lxc.cgroup2.devices.allow: c 507:* rwm"; } >> "/etc/pve/lxc/${ctid}.conf"; }
map_amd(){ local ctid="$1"; map_devices "$ctid" /dev/kfd /dev/dri; { echo "lxc.cgroup2.devices.allow: c 226:* rwm"; echo "lxc.cgroup2.devices.allow: c 235:* rwm"; } >> "/etc/pve/lxc/${ctid}.conf"; }
map_intel(){ local ctid="$1"; map_devices "$ctid" /dev/dri; { echo "lxc.cgroup2.devices.allow: c 226:* rwm"; } >> "/etc/pve/lxc/${ctid}.conf"; }

hw_scan(){
  GPU_INFO="$(lspci | grep -i -E 'vga|3d' || true)"
  HAS_NVIDIA=0; HAS_AMD=0; HAS_INTEL=0
  echo "$GPU_INFO" | grep -qi nvidia && HAS_NVIDIA=1
  echo "$GPU_INFO" | grep -qi -E 'amd|ati' && HAS_AMD=1
  echo "$GPU_INFO" | grep -qi intel && HAS_INTEL=1
  VRAM="unknown"; command -v nvidia-smi >/dev/null 2>&1 && VRAM="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader | head -n1 | tr -d '[:space:]')"
}

choose_ki_stack(){
  local reco="CPU_OLLAMA"
  if [[ $HAS_NVIDIA -eq 1 ]]; then reco="GPU_NVIDIA_OLLAMA"
  elif [[ $HAS_AMD -eq 1 ]]; then reco="GPU_AMD_ROCM_OLLAMA"
  elif [[ $HAS_INTEL -eq 1 ]]; then reco="GPU_INTEL_EXPERIMENTAL"; fi

  CHOICE=$(whiptail --title "KI-Stack" --radiolist "GPU erkannt. Wähle Stack:" 18 88 7 \
    "CPU_OLLAMA"             "Ollama (CPU)"                          $( [[ $reco == "CPU_OLLAMA" ]] && echo ON || echo OFF ) \
    "GPU_NVIDIA_OLLAMA"      "Ollama (NVIDIA/CUDA)"                  $( [[ $reco == "GPU_NVIDIA_OLLAMA" ]] && echo ON || echo OFF ) \
    "GPU_NVIDIA_VLLM"        "vLLM (Docker, NVIDIA)"                 OFF \
    "GPU_AMD_ROCM_OLLAMA"    "Ollama (AMD/ROCm, best effort)"        $( [[ $reco == "GPU_AMD_ROCM_OLLAMA" ]] && echo ON || echo OFF ) \
    "GPU_AMD_ROCM_VLLM"      "vLLM (Docker, AMD ROCm, best effort)"  OFF \
    "GPU_INTEL_EXPERIMENTAL" "Intel iGPU (experimentell, CPU Fallback)" $( [[ $reco == "GPU_INTEL_EXPERIMENTAL" ]] && echo ON || echo OFF ) \
    "REMOTE"                 "Kein lokales Modell"                   OFF \
    3>&1 1>&2 2>&3) || CHOICE="$reco"
  mkdir -p "$(dirname "$KI_CHOICE_FILE")"
  echo "$CHOICE" > "$KI_CHOICE_FILE"
}

create_ct(){
  local ctid="$1" name="$2" mem="$3" cores="$4" tags="$5" ipconf="$6"
  local storage=$(cat /tmp/pve_storage.txt); local tmpl=$(cat /tmp/pve_template.txt)
  if pct status "$ctid" >/dev/null 2>&1; then echo "[i] CT $ctid existiert"; return; fi
  pct create "$ctid" "${storage}:vztmpl/${tmpl}" \
    -hostname "$name" -cores "$cores" -memory "$mem" \
    -features nesting=1,keyctl=1 -onboot 1 -ostype debian \
    -net0 "name=eth0,bridge=vmbr0,${ipconf}"
  if pct set "$ctid" -tags "$tags" 2>/dev/null; then :; else echo "tags: $tags" >> "/etc/pve/lxc/${ctid}.conf" || true; fi
}

setup_ki_in_ct(){
  local ctid="$1" choice="$2"
  pct start "$ctid" || true; sleep 3
  case "$choice" in
    CPU_OLLAMA|GPU_NVIDIA_OLLAMA|GPU_AMD_ROCM_OLLAMA|GPU_INTEL_EXPERIMENTAL)
      pct exec "$ctid" -- bash -lc "apt-get update -y && apt-get install -y curl ca-certificates"
      pct exec "$ctid" -- bash -lc "curl -fsSL https://ollama.com/install.sh | sh"
      pct exec "$ctid" -- bash -lc "systemctl enable --now ollama"
      ;;
    GPU_NVIDIA_VLLM)
      pct exec "$ctid" -- bash -lc "apt-get update -y && apt-get install -y ca-certificates curl gnupg lsb-release"
      pct exec "$ctid" -- bash -lc "install -m 0755 -d /etc/apt/keyrings"
      pct exec "$ctid" -- bash -lc "curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
      pct exec "$ctid" -- bash -lc "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(. /etc/os-release && echo $VERSION_CODENAME) stable\" > /etc/apt/sources.list.d/docker.list"
      pct exec "$ctid" -- bash -lc "apt-get update -y && apt-get install -y docker-ce docker-ce-cli containerd.io nvidia-container-toolkit || true"
      pct exec "$ctid" -- bash -lc "nvidia-ctk runtime configure --runtime=docker || true && systemctl restart docker || true"
      pct exec "$ctid" -- bash -lc "docker run -d --gpus all --name vllm --restart unless-stopped -p 8000:8000 vllm/vllm-openai:latest --model mistralai/Mistral-7B-Instruct --max-model-len 8192"
      ;;
    REMOTE) : ;;
  esac
}

resource_value(){
  local svc="$1" field="$2" fallback="$3"
  local val
  val=$(jq -r --arg svc "$svc" --arg field "$field" '.resources[$svc][$field] // empty' "$CONFIG_FILE")
  if [[ -z "$val" || "$val" == "null" ]]; then
    echo "$fallback"
  else
    echo "$val"
  fi
}

collect_ips(){
  mkdir -p "$(dirname "$INV")"
  echo '{}' | jq '.' > "$INV"
  for name in $(jq -r '.services | keys[]' "$PLAN"); do
    ctid=$(jq -r ".services[\"$name\"].ctid" "$PLAN")
    pct start "$ctid" || true; sleep 2
    ip=$(pct exec "$ctid" -- bash -lc "hostname -I | awk '{print $1}'" | tr -d '\r')
    jq --arg n "$name" --arg ip "$ip" '. + {($n): {"ip":$ip}}' "$INV" > "$INV.tmp" && mv "$INV.tmp" "$INV"
  done
  echo "[*] Inventar: $INV"; cat "$INV"
}

main(){
  pkg jq whiptail
  PLAN=$(jq -r '.plan_path' "$CONFIG_FILE")
  INV=$(jq -r '.inventory_path' "$CONFIG_FILE")
  KI_CHOICE_FILE=$(jq -r '.ki_choice_path' "$CONFIG_FILE")
  [[ -f "$PLAN" ]] || { echo "Plan fehlt: $PLAN"; exit 1; }
  ensure_template
  hw_scan
  choose_ki_stack

  local addr=$(jq -r '.addressing' "$PLAN"); local gw_oct=$(jq -r '.gateway_octet' "$PLAN")
  for name in $(jq -r '.services | keys[]' "$PLAN"); do
    ctid=$(jq -r ".services[\"$name\"].ctid" "$PLAN")
    catcode=$(jq -r ".services[\"$name\"].category" "$PLAN")
    host=$(jq -r ".services[\"$name\"].host_octet" "$PLAN")
    mem=$(resource_value "$name" "memory" 2048)
    cores=$(resource_value "$name" "cores" 2)
    tags=$(jq -r ".services[\"$name\"].tags | join(\";\")" "$PLAN")

    if [[ "$addr" == "static" ]]; then
      ip=$(calc_ip "$catcode" "$host")
      gw=$(echo "$ip" | awk -F. -v g=$gw_oct '{printf "%s.%s.%s.%s",$1,$2,$3,g}')
      ipconf="ip=${ip}/24,gw=${gw}"
    else ipconf="ip=dhcp"; fi

    create_ct "$ctid" "$name" "$mem" "$cores" "$tags" "$ipconf"
  done

  ki_ctid=$(jq -r '.services["ralf-ki"].ctid' "$PLAN")
  [[ $HAS_NVIDIA -eq 1 ]] && map_nvidia "$ki_ctid"
  [[ $HAS_AMD -eq 1 ]] && map_amd "$ki_ctid" || true
  [[ $HAS_INTEL -eq 1 ]] && map_intel "$ki_ctid" || true

  setup_ki_in_ct "$ki_ctid" "$(cat "$KI_CHOICE_FILE")"
  collect_ips
}
main "$@"
