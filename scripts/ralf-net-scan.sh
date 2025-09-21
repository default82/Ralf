#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $0 [--cidr CIDR] [--output DIR] [--once|--loop]

Scan the homelab network and emit JSON reports under reports/scans/.
Defaults are derived from vars/ralf-installer.yaml when available.

  --cidr CIDR    Override network CIDR (e.g. 10.23.0.0/16)
  --output DIR   Directory to store reports (default: reports/scans)
  --once         Run one scan and exit (default)
  --loop         Sleep and rescan forever
  -h, --help     Show this help
USAGE
}

cidr=""
output_dir="reports/scans"
run_once=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cidr)
      cidr="$2"
      shift 2
      ;;
    --output)
      output_dir="$2"
      shift 2
      ;;
    --once)
      run_once=1
      shift
      ;;
    --loop)
      run_once=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$cidr" ]] && [[ -f vars/ralf-installer.yaml ]] && command -v yq >/dev/null 2>&1; then
  cidr=$(yq '.network_cidr' vars/ralf-installer.yaml)
fi

if [[ -z "$cidr" ]]; then
  echo "[net-scan] No CIDR provided; defaulting to 10.23.0.0/16" >&2
  cidr="10.23.0.0/16"
fi

mkdir -p "$output_dir"

run_scan() {
  local timestamp=$(date -u +%Y%m%dT%H%M%SZ)
  local outfile="${output_dir}/scan-${timestamp}.json"
  local hosts_json="[]"
  local scanner="nmap"
  local notes=""

  if command -v nmap >/dev/null 2>&1; then
    mapfile -t hosts < <(nmap -sn "$cidr" -oG - | awk '/Up$/{print $2}')
    if [[ ${#hosts[@]} -gt 0 ]]; then
      if command -v jq >/dev/null 2>&1; then
        hosts_json=$(printf '%s\n' "${hosts[@]}" | jq -R . | jq -s .)
      else
        hosts_json="["
        for host in "${hosts[@]}"; do
          hosts_json+="\"${host}\","
        done
        hosts_json="${hosts_json%,}]"
      fi
    else
      hosts_json="[]"
    fi
  else
    scanner="ping"
    notes="nmap not available; performed limited gateway ping"
    gateway=$(echo "$cidr" | cut -d'/' -f1 | awk -F. '{printf "%s.%s.%s.1", $1, $2, $3}')
    if ping -c1 -W1 "$gateway" >/dev/null 2>&1; then
      if command -v jq >/dev/null 2>&1; then
        hosts_json=$(printf '%s\n' "$gateway" | jq -R . | jq -s .)
      else
        hosts_json="[\"$gateway\"]"
      fi
    fi
  fi

  cat > "$outfile" <<JSON
{
  "timestamp": "${timestamp}",
  "cidr": "${cidr}",
  "scanner": "${scanner}",
  "hosts_up": ${hosts_json},
  "notes": "${notes}"
}
JSON
  echo "[net-scan] Report written to ${outfile}"
}

run_scan

if (( ! run_once )); then
  while true; do
    sleep 86400
    run_scan
  done
fi
