#!/usr/bin/env bash
# Validate that a Proxmox Backup Server snapshot can be restored into a scratch directory.

set -euo pipefail

usage() {
  cat <<USAGE
Usage: $0 <backup-type/backup-id> <namespace> [target-prefix]

Environment:
  PBS_REPOSITORY   Repository definition for proxmox-backup-client (e.g. "pbs@pam@backup@pbs01:ralf")
  PBS_PASSWORD_FILE Optional path to a password file passed to proxmox-backup-client.

The script restores the newest snapshot for the given backup identifier into a
throw-away directory inside /tmp. Restored files are removed automatically when
the script exits successfully.
USAGE
}

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

if [[ -z "${PBS_REPOSITORY:-}" ]]; then
  echo "PBS_REPOSITORY must be set (example: 'pbs@pam@backup@pbs01:ralf')" >&2
  exit 1
fi

BACKUP_ID="$1"
NAMESPACE="$2"
TARGET_PREFIX="${3:-/tmp/${BACKUP_ID//\//_}-restore}"

if ! command -v proxmox-backup-client >/dev/null 2>&1; then
  echo "proxmox-backup-client binary not found in PATH" >&2
  exit 1
fi

SNAPSHOT_JSON=$(proxmox-backup-client snapshots "$BACKUP_ID" --repository "$PBS_REPOSITORY" --ns "$NAMESPACE" --output-format json)
LATEST_SNAPSHOT=$(printf '%s' "$SNAPSHOT_JSON" | python3 <<'PYCODE'
import json
import sys

data = json.load(sys.stdin)
if not data:
    raise SystemExit

latest = sorted(data, key=lambda entry: entry.get("snapshot", ""), reverse=True)[0]
print(latest.get("snapshot", ""))
PYCODE
)

if [[ -z "$LATEST_SNAPSHOT" ]]; then
  echo "No snapshots found for $BACKUP_ID in namespace $NAMESPACE" >&2
  exit 1
fi

RESTORE_DIR=$(mktemp -d "${TARGET_PREFIX}.XXXX")
trap 'rm -rf "$RESTORE_DIR"' EXIT

echo "Restoring snapshot $BACKUP_ID/$LATEST_SNAPSHOT into $RESTORE_DIR"
RESTORE_ARGS=("$BACKUP_ID/$LATEST_SNAPSHOT" "$RESTORE_DIR" --repository "$PBS_REPOSITORY" --ns "$NAMESPACE")
if [[ -n "${PBS_PASSWORD_FILE:-}" ]]; then
  RESTORE_ARGS+=(--password-file "$PBS_PASSWORD_FILE")
fi

proxmox-backup-client restore "${RESTORE_ARGS[@]}"

echo "Listing restored files:"
find "$RESTORE_DIR" -maxdepth 2 -type f -print

echo "Restore smoke-test completed successfully"
