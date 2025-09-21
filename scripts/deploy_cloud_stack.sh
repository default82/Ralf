#!/usr/bin/env bash
set -euo pipefail

printf '\n=== Cloud AI deploy ===\n'

echo "This script expects cloud credentials via environment variables."
echo "It provisions infrastructure using Terraform and syncs the model registry."
echo "Adjust terraform backend configuration before running."

if [ ! -d "infra" ]; then
  echo "[!] No infra/ directory found. Aborting." >&2
  exit 1
fi

terraform -chdir=infra init
terraform -chdir=infra apply "$@"
