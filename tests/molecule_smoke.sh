#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

if ! command -v molecule >/dev/null 2>&1; then
  echo "molecule is not installed; skipping Molecule smoke tests" >&2
  exit 0
fi

mapfile -t scenarios < <(find "${REPO_ROOT}/ansible/roles" -path '*/molecule/*/molecule.yml')

if [[ ${#scenarios[@]} -eq 0 ]]; then
  echo "No Molecule scenarios found; skipping" >&2
  exit 0
fi

for scenario_file in "${scenarios[@]}"; do
  scenario_dir=$(dirname "${scenario_file}")
  role_dir=$(dirname "$(dirname "${scenario_dir}")")
  scenario_name=$(basename "${scenario_dir}")
  pushd "${role_dir}" >/dev/null
  molecule test -s "${scenario_name}"
  popd >/dev/null
done
