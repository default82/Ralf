#!/usr/bin/env bash
set -euo pipefail

COMMAND=${1:-help}

usage() {
  cat <<USAGE
Usage: ralf.sh <command>

Commands:
  bootstrap      Run initial Proxmox bootstrap
  images         Build golden images
  deploy-core    Deploy core services stack
  deploy-matrix  Deploy Matrix Synapse backbone
  deploy-services Deploy service catalog workloads
  check-backups  Verify encrypted backup restores
  net-scan       Run on-demand network scan
  health         Run health checks
  logs           Tail GitOps runner logs
  help           Show this message
USAGE
}

case "$COMMAND" in
  bootstrap)
    make bootstrap
    ;;
  images)
    make images
    ;;
  deploy-core)
    make apply CORE_ONLY=true
    ;;
  deploy-matrix)
    make deploy-matrix
    ;;
  deploy-services)
    make apply SERVICES_ONLY=true
    ;;
  check-backups)
    make verify-backups
    ;;
  net-scan)
    ./scripts/ralf-net-scan.sh --once
    ;;
  health)
    ansible-playbook ansible/playbooks/deploy-core.yaml --check
    ;;
  logs)
    journalctl -u gitops-runner.service -f
    ;;
  help|*)
    usage
    ;;
esac
