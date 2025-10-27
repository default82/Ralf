#!/usr/bin/env bash
# Validate Gitea backup archives restored from Proxmox Backup Server snapshots.

set -euo pipefail

usage() {
  cat <<USAGE
Usage: $0 <restore-directory> [--expect-version <version>]

Arguments:
  restore-directory  Directory containing the restored Gitea dump archive or unpacked files.

Options:
  --expect-version <version>  Optional Gitea version string that must match the dump metadata.

Environment:
  TAR     Override tar binary used to inspect .tar(.gz) archives (default: tar).
  UNZIP   Override unzip binary for .zip archives (default: unzip).
USAGE
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

RESTORE_DIR="$1"
shift

EXPECTED_VERSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --expect-version)
      shift
      EXPECTED_VERSION="${1:-}"
      if [[ -z "$EXPECTED_VERSION" ]]; then
        echo "--expect-version requires a value" >&2
        exit 1
      fi
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
fi

if [[ ! -d "$RESTORE_DIR" ]]; then
  echo "Restore directory $RESTORE_DIR does not exist" >&2
  exit 1
fi

TAR_BIN="${TAR:-tar}"
UNZIP_BIN="${UNZIP:-unzip}"

ARCHIVE=$(find "$RESTORE_DIR" -maxdepth 2 -type f \( -name 'gitea-dump*.tar' -o -name 'gitea-dump*.tar.gz' -o -name 'gitea-dump*.zip' \) | head -n 1)

INSPECT_DIR=""
CLEANUP_DIR=""

extract_archive() {
  local archive="$1"
  local tmpdir
  tmpdir=$(mktemp -d "gitea-restore.XXXX")
  CLEANUP_DIR="$tmpdir"
  case "$archive" in
    *.tar|*.tar.gz)
      echo "Extracting $archive"
      "$TAR_BIN" -xf "$archive" -C "$tmpdir"
      ;;
    *.zip)
      echo "Extracting $archive"
      "$UNZIP_BIN" -q "$archive" -d "$tmpdir"
      ;;
    *)
      echo "Unsupported archive format: $archive" >&2
      exit 1
      ;;
  esac
  INSPECT_DIR="$tmpdir"
}

cleanup() {
  if [[ -n "$CLEANUP_DIR" ]]; then
    rm -rf "$CLEANUP_DIR"
  fi
}

trap cleanup EXIT

if [[ -n "$ARCHIVE" ]]; then
  extract_archive "$ARCHIVE"
else
  INSPECT_DIR="$RESTORE_DIR"
fi

if [[ ! -f "$INSPECT_DIR/gitea-dump.json" ]]; then
  echo "gitea-dump.json not found in $INSPECT_DIR" >&2
  exit 1
fi

echo "Found gitea-dump.json"

if [[ -f "$INSPECT_DIR/app.ini" ]]; then
  echo "Found app.ini configuration snapshot"
elif [[ -f "$INSPECT_DIR/custom/conf/app.ini" ]]; then
  echo "Found app.ini configuration snapshot under custom/conf"
else
  echo "Warning: app.ini configuration snapshot missing" >&2
fi

METADATA_JSON=$(python3 <<'PYCODE'
import json
import sys
from pathlib import Path

dump_json = Path(sys.argv[1])
with dump_json.open("r", encoding="utf-8") as handle:
    metadata = json.load(handle)

print(metadata.get("Version", ""))
print(metadata.get("DatabaseType", ""))
print(metadata.get("HasAttachments", False))
PYCODE
"$INSPECT_DIR/gitea-dump.json")

DUMP_VERSION=$(printf '%s' "$METADATA_JSON" | sed -n '1p')
DB_TYPE=$(printf '%s' "$METADATA_JSON" | sed -n '2p')
HAS_ATTACHMENTS=$(printf '%s' "$METADATA_JSON" | sed -n '3p')

echo "Dump version: ${DUMP_VERSION:-unknown}"
echo "Database type: ${DB_TYPE:-unknown}"
echo "Contains attachments: $HAS_ATTACHMENTS"

if [[ -n "$EXPECTED_VERSION" && "$DUMP_VERSION" != "$EXPECTED_VERSION" ]]; then
  echo "Expected Gitea version $EXPECTED_VERSION but dump reports $DUMP_VERSION" >&2
  exit 1
fi

if find "$INSPECT_DIR" -maxdepth 1 -type d -name 'repos' | grep -q .; then
  echo "Repositories directory present"
else
  echo "Warning: repositories directory missing" >&2
fi

echo "Gitea restore check completed successfully"
