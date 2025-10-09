#!/usr/bin/env bash
set -euo pipefail

PLAN_FILE=${1:-/root/ralf/plan.json}

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "{}" > "$PLAN_FILE"
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[plan_tui][ERROR] Benötigtes Kommando '$1' nicht gefunden." >&2
    exit 1
  }
}

for bin in jq whiptail; do
  require_cmd "$bin"
done

PLAN_JSON=$(cat "$PLAN_FILE")

SITE_CODE=$(jq -r '.site_code // "DU"' <<<"$PLAN_JSON")
HOSTNAME=$(jq -r '.hostname // "pve-du-00"' <<<"$PLAN_JSON")
ADDRESSING_MODE=$(jq -r '.networking.addressing_mode // "dhcp"' <<<"$PLAN_JSON")
BASE_NETWORK=$(jq -r '.networking.base_network // "192.168"' <<<"$PLAN_JSON")
GATEWAY_OCTET=$(jq -r '.networking.gateway_octet // 1' <<<"$PLAN_JSON")
KI_STACK=$(jq -r '.ki_stack // "CPU_OLLAMA"' <<<"$PLAN_JSON")
HAS_PUBLIC_DOMAIN=$(jq -r '.domain.has_public_domain // false' <<<"$PLAN_JSON")
BASE_DOMAIN=$(jq -r '.domain.base_domain // "ralf.local"' <<<"$PLAN_JSON")
ACME_EMAIL=$(jq -r '.domain.acme_email // "admin@example.com"' <<<"$PLAN_JSON")
PXE_MODE=$(jq -r '.pxe.mode // "router_relay"' <<<"$PLAN_JSON")
DISCOVERY_VLAN=$(jq -r '.pxe.discovery_vlan // 250' <<<"$PLAN_JSON")
OMADA_ENABLED=$(jq -r '.omada.enabled // false' <<<"$PLAN_JSON")
OMADA_CONTROLLER=$(jq -r '.omada.controller_url // ""' <<<"$PLAN_JSON")
OMADA_SITE=$(jq -r '.omada.site // ""' <<<"$PLAN_JSON")
OMADA_USER=$(jq -r '.omada.username // ""' <<<"$PLAN_JSON")
OMADA_PASS=$(jq -r '.omada.password // ""' <<<"$PLAN_JSON")

SITE_CODE=$(whiptail --inputbox "Site-Code" 10 70 "$SITE_CODE" 3>&1 1>&2 2>&3) || exit 1
HOSTNAME=$(whiptail --inputbox "Hostname für den PVE-Host" 10 70 "$HOSTNAME" 3>&1 1>&2 2>&3) || exit 1

ADDRESSING_MODE=$(whiptail --menu "Adressierung der Container" 18 70 5 \
  "dhcp" "DHCP (Standard)" \
  "static" "Statische /24-Netze pro Kategorie" 3>&1 1>&2 2>&3) || exit 1

if [[ "$ADDRESSING_MODE" == "static" ]]; then
  BASE_NETWORK=$(whiptail --inputbox "Basisnetz (erste zwei Oktette)" 10 70 "$BASE_NETWORK" 3>&1 1>&2 2>&3) || exit 1
  GATEWAY_OCTET=$(whiptail --inputbox "Gateway-Host (4. Oktett)" 10 70 "$GATEWAY_OCTET" 3>&1 1>&2 2>&3) || exit 1
  if ! whiptail --yesno "Statische IP-Zuordnung bestätigen?" 10 70; then
    ADDRESSING_MODE="dhcp"
  fi
fi

CATEGORY_JSON=()
CATEGORY_MENU_ARGS=()
while IFS='|' read -r code name; do
  new_name=$(whiptail --inputbox "Kategorie ${code} Bezeichnung" 10 70 "$name" 3>&1 1>&2 2>&3) || new_name="$name"
  CATEGORY_JSON+=("$(jq -n --arg code "$code" --arg name "$new_name" '{code: ($code|tonumber), name: $name}')")
  CATEGORY_MENU_ARGS+=("$code" "$new_name")
done < <(
  jq -r '.networking.categories[]? | "\(.code)|\(.name)"' <<<"$PLAN_JSON"
)

if [[ ${#CATEGORY_JSON[@]} -eq 0 ]]; then
  for default in \
    "10|Netzwerkdienste" "20|Datenbanken" "30|Backup & Sicherheit" \
    "40|Web & Verwaltungsoberflächen" "50|Verzeichnisdienste & Authentifizierung" \
    "60|Medienserver & Verwaltung" "70|Dokumenten- & Wissensmanagement" \
    "80|Monitoring & Logging" "90|Künstliche Intelligenz & Datenverarbeitung" \
    "100|Automatisierung" "110|Kommunikation und Steuerung" \
    "120|Spiele" "200|funktionale VM"; do
    code=${default%%|*}
    name=${default#*|}
    CATEGORY_JSON+=("$(jq -n --arg code "$code" --arg name "$name" '{code: ($code|tonumber), name: $name}')")
    CATEGORY_MENU_ARGS+=("$code" "$name")
  done
fi

SERVICES_JSON=()
while read -r entry; do
  svc=$(echo "$entry" | jq -r '.key')
  category=$(echo "$entry" | jq -r '.value.category')
  host_octet=$(echo "$entry" | jq -r '.value.host_octet')
  exposure=$(echo "$entry" | jq -r '.value.exposure')
  fqdn=$(echo "$entry" | jq -r '.value.fqdn')

  category=$(whiptail --menu "Kategorie für ${svc}" 20 78 10 "${CATEGORY_MENU_ARGS[@]}" 3>&1 1>&2 2>&3) || exit 1
  host_octet=$(whiptail --inputbox "Host-Octet für ${svc} (1-254)" 10 70 "$host_octet" 3>&1 1>&2 2>&3) || exit 1
  exposure=$(whiptail --menu "Exposure für ${svc}" 15 70 5 \
    "public" "Über Caddy öffentlich erreichbar" \
    "local" "Nur intern (tls internal)" 3>&1 1>&2 2>&3) || exit 1
  fqdn=$(whiptail --inputbox "FQDN für ${svc}" 10 70 "$fqdn" 3>&1 1>&2 2>&3) || exit 1

  SERVICES_JSON+=("$(jq -n --arg name "$svc" --arg category "$category" --arg host "$host_octet" --arg exposure "$exposure" --arg fqdn "$fqdn" '{($name): {category: ($category|tonumber), host_octet: ($host|tonumber), exposure: $exposure, fqdn: $fqdn}}')")
done < <(
  jq -c '.services | to_entries[]' <<<"$PLAN_JSON"
)

if [[ ${#SERVICES_JSON[@]} -eq 0 ]]; then
  declare -A DEFAULT_SERVICES=(
    ["ralf-edge"]="40|80|public|edge.${BASE_DOMAIN}"
    ["ralf-ki"]="90|10|local|ki.${BASE_DOMAIN}"
    ["ralf-gitea"]="40|11|local|gitea.${BASE_DOMAIN}"
    ["ralf-netbox"]="40|12|public|netbox.${BASE_DOMAIN}"
    ["ralf-db"]="20|3|local|db.${BASE_DOMAIN}"
    ["ralf-n8n"]="100|14|public|n8n.${BASE_DOMAIN}"
    ["ralf-matrix"]="110|15|public|matrix.${BASE_DOMAIN}"
    ["ralf-secrets"]="30|16|local|secrets.${BASE_DOMAIN}"
    ["ralf-foreman"]="100|7|local|foreman.${BASE_DOMAIN}"
  )
  for svc in "${!DEFAULT_SERVICES[@]}"; do
    IFS='|' read -r cat host exp fqdn <<<"${DEFAULT_SERVICES[$svc]}"
    SERVICES_JSON+=("$(jq -n --arg name "$svc" --arg category "$cat" --arg host "$host" --arg exposure "$exp" --arg fqdn "$fqdn" '{($name): {category: ($category|tonumber), host_octet: ($host|tonumber), exposure: $exposure, fqdn: $fqdn}}')")
  done
fi

if whiptail --yesno "Öffentliche Domain & ACME verwenden?" 10 70 --defaultno; then
  HAS_PUBLIC_DOMAIN=true
  BASE_DOMAIN=$(whiptail --inputbox "Basis-Domain" 10 70 "$BASE_DOMAIN" 3>&1 1>&2 2>&3) || exit 1
  ACME_EMAIL=$(whiptail --inputbox "ACME E-Mail" 10 70 "$ACME_EMAIL" 3>&1 1>&2 2>&3) || exit 1
else
  HAS_PUBLIC_DOMAIN=false
fi

PXE_MODE=$(whiptail --menu "PXE-Modus" 15 70 5 \
  "disabled" "Kein PXE" \
  "router_relay" "DHCP extern, Foreman nur TFTP/HTTPBoot" \
  "foreman_dhcp" "Foreman übernimmt DHCP" 3>&1 1>&2 2>&3) || exit 1
DISCOVERY_VLAN=$(whiptail --inputbox "Discovery VLAN" 10 70 "$DISCOVERY_VLAN" 3>&1 1>&2 2>&3) || exit 1

if whiptail --yesno "Omada-Integration aktivieren?" 10 70; then
  OMADA_ENABLED=true
  OMADA_CONTROLLER=$(whiptail --inputbox "Omada Controller URL" 10 70 "$OMADA_CONTROLLER" 3>&1 1>&2 2>&3) || exit 1
  OMADA_SITE=$(whiptail --inputbox "Omada Site" 10 70 "$OMADA_SITE" 3>&1 1>&2 2>&3) || exit 1
  OMADA_USER=$(whiptail --inputbox "Omada Benutzer" 10 70 "$OMADA_USER" 3>&1 1>&2 2>&3) || exit 1
  OMADA_PASS=$(whiptail --passwordbox "Omada Passwort" 10 70 "$OMADA_PASS" 3>&1 1>&2 2>&3) || OMADA_PASS="$OMADA_PASS"
else
  OMADA_ENABLED=false
fi

KI_STACK=$(whiptail --menu "KI-Stack Auswahl" 20 78 10 \
  "CPU_OLLAMA" "CPU-basierte Ollama Installation" \
  "GPU_NVIDIA_OLLAMA" "NVIDIA GPU mit Ollama" \
  "GPU_NVIDIA_VLLM" "NVIDIA GPU mit vLLM (Docker)" \
  "GPU_AMD_ROCM_OLLAMA" "AMD ROCm Ollama (Best Effort)" \
  "GPU_AMD_ROCM_VLLM" "AMD ROCm vLLM (Best Effort)" \
  "GPU_INTEL_EXPERIMENTAL" "Intel GPU Experimentell" \
  "REMOTE" "Kein lokales Modell" 3>&1 1>&2 2>&3) || exit 1

CATEGORIES_JSON=$(printf '%s\n' "${CATEGORY_JSON[@]}" | jq -s '.')
SERVICES_JSON_COMBINED=$(printf '%s\n' "${SERVICES_JSON[@]}" | jq -s 'add')

UPDATED_PLAN=$(jq -n \
  --arg site_code "$SITE_CODE" \
  --arg hostname "$HOSTNAME" \
  --arg addressing_mode "$ADDRESSING_MODE" \
  --arg base_network "$BASE_NETWORK" \
  --arg gateway_octet "$GATEWAY_OCTET" \
  --argjson categories "$CATEGORIES_JSON" \
  --argjson services "$SERVICES_JSON_COMBINED" \
  --argjson has_public_domain "$HAS_PUBLIC_DOMAIN" \
  --arg base_domain "$BASE_DOMAIN" \
  --arg acme_email "$ACME_EMAIL" \
  --arg pxe_mode "$PXE_MODE" \
  --arg discovery_vlan "$DISCOVERY_VLAN" \
  --argjson omada_enabled "$OMADA_ENABLED" \
  --arg omada_controller "$OMADA_CONTROLLER" \
  --arg omada_site "$OMADA_SITE" \
  --arg omada_user "$OMADA_USER" \
  --arg omada_pass "$OMADA_PASS" \
  --arg ki_stack "$KI_STACK" \
  '{
    site_code: $site_code,
    hostname: $hostname,
    networking: {
      addressing_mode: $addressing_mode,
      base_network: $base_network,
      gateway_octet: ($gateway_octet|tonumber),
      categories: $categories
    },
    services: $services,
    pxe: {
      mode: $pxe_mode,
      discovery_vlan: ($discovery_vlan|tonumber)
    },
    domain: {
      has_public_domain: $has_public_domain,
      base_domain: $base_domain,
      acme_email: $acme_email
    },
    omada: {
      enabled: $omada_enabled,
      controller_url: $omada_controller,
      site: $omada_site,
      username: $omada_user,
      password: $omada_pass
    },
    ki_stack: $ki_stack
  }')

cp "$PLAN_FILE" "${PLAN_FILE}.bak" 2>/dev/null || true
echo "$UPDATED_PLAN" | jq '.' > "$PLAN_FILE"

echo "[plan_tui] Plan unter $PLAN_FILE gespeichert"
