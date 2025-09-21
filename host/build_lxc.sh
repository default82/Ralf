#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME=$(basename "$0")

usage() {
  cat <<'USAGE'
Usage: host/build_lxc.sh [OPTIONS]

Options:
  --dry-run        Preview the build steps without executing them (default)
  --vmid <id>      VMID to use for the container (default: 9999)
  --template <tpl> Template image identifier (default: local:vztmpl/ralf-template.tar.zst)
  --storage <name> Storage target for the rootfs (default: local)
  --help           Show this message and exit
USAGE
}

DRY_RUN=true
VMID=9999
TEMPLATE="local:vztmpl/ralf-template.tar.zst"
STORAGE="local"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --vmid)
      VMID="$2"
      shift 2
      ;;
    --template)
      TEMPLATE="$2"
      shift 2
      ;;
    --storage)
      STORAGE="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "${SCRIPT_NAME}: unknown option '$1'" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$DRY_RUN" != true ]]; then
  echo "[build-lxc] ERROR: Non dry-run builds are not supported in this environment." >&2
  echo "[build-lxc] Please invoke with --dry-run to preview the build steps." >&2
  exit 1
fi

echo "==> RALF LXC build plan"
printf '[dry-run] Would run: pct destroy %s || true\n' "${VMID}"
printf '[dry-run] Would run: pct create %s %s --storage %s --hostname ralf-ai --memory 2048 --net0 name=eth0,bridge=vmbr0,ip=dhcp,type=veth\n' "${VMID}" "${TEMPLATE}" "${STORAGE}"
printf '[dry-run] Would run: pct set %s --onboot 1 --startup order=2\n' "${VMID}"
printf '[dry-run] Would run: pct push %s wrapper/ralf-ai /usr/local/bin/ralf-ai --perms 0755\n' "${VMID}"
printf '[dry-run] Would run: pct exec %s -- ralf-ai --help\n' "${VMID}"
echo "==> Dry run complete"
