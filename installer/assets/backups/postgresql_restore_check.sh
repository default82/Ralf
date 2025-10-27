#!/usr/bin/env bash
# Validate PostgreSQL backups restored from Proxmox Backup Server snapshots.

set -euo pipefail

usage() {
  cat <<USAGE
Usage: $0 <restore-directory> [connection-uri]

Arguments:
  restore-directory  Directory containing the restored PostgreSQL dump archive.
  connection-uri     Optional libpq URI to load the archive into a disposable database
                     (default: skip import, run integrity checks only).

Environment:
  PGUSER, PGPASSWORD, PGHOST, PGPORT may be used when connection-uri is omitted
  and pg_restore targets a local PostgreSQL instance.
USAGE
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

RESTORE_DIR="$1"
CONNECTION_URI="${2:-}"

if [[ ! -d "$RESTORE_DIR" ]]; then
  echo "Restore directory $RESTORE_DIR does not exist" >&2
  exit 1
fi

ARCHIVE=$(find "$RESTORE_DIR" -maxdepth 2 -type f \( -name '*.dump' -o -name '*.sql' -o -name '*.tar' \) | head -n 1)
if [[ -z "$ARCHIVE" ]]; then
  echo "No PostgreSQL dump archive found in $RESTORE_DIR" >&2
  exit 1
fi

echo "Found archive $ARCHIVE"

if ! command -v pg_restore >/dev/null 2>&1; then
  echo "pg_restore command not found" >&2
  exit 1
fi

pg_restore --list "$ARCHIVE" >/dev/null

echo "Archive manifest looks valid"

if [[ -n "$CONNECTION_URI" ]]; then
  for binary in psql pg_dump; do
    if ! command -v "$binary" >/dev/null 2>&1; then
      echo "$binary command not found" >&2
      exit 1
    fi
  done

  TMP_DB="restore_check_${RANDOM}"
  echo "Creating temporary database $TMP_DB"
  psql "$CONNECTION_URI" -v ON_ERROR_STOP=1 -c "CREATE DATABASE \"$TMP_DB\" TEMPLATE=template0;"
  cleanup() {
    psql "$CONNECTION_URI" -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS \"$TMP_DB\";" >/dev/null 2>&1 || true
  }
  trap cleanup EXIT

  echo "Restoring archive into $TMP_DB"
  pg_restore --clean --if-exists --no-owner --dbname="${CONNECTION_URI}?dbname=$TMP_DB" "$ARCHIVE"
  echo "Running integrity check (pg_dump schema-only)"
  pg_dump --schema-only --dbname="${CONNECTION_URI}?dbname=$TMP_DB" >/dev/null
  echo "PostgreSQL restore test completed successfully"
else
  echo "Skipping database import; manifest check completed"
fi
