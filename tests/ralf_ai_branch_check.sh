#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
RALF_AI_SCRIPT="${REPO_ROOT}/automation/ralf/rlwrap/ralf-ai.sh"
AIDER_STUB=$(command -v true)

setup_repo() {
  local dir
  dir=$(mktemp -d)
  if ! git -C "${dir}" init -b main >/dev/null 2>&1; then
    git -C "${dir}" init >/dev/null 2>&1
    git -C "${dir}" checkout -b main >/dev/null 2>&1
  fi
  touch "${dir}/.keep"
  git -C "${dir}" add .keep >/dev/null 2>&1
  git -C "${dir}" commit -m "Initial commit" >/dev/null 2>&1
  echo "${dir}"
}

assert_no_branch_warning() {
  local output="$1"
  if grep -q "not in the allowed set" <<<"${output}"; then
    echo "Unexpected branch warning: ${output}" >&2
    exit 1
  fi
}

assert_branch_warning() {
  local output="$1"
  if ! grep -q "not in the allowed set" <<<"${output}"; then
    echo "Expected branch warning missing" >&2
    echo "Output was: ${output}" >&2
    exit 1
  fi
}

repo_default=$(setup_repo)
repo_custom=""

cleanup() {
  if [[ -n "${repo_default:-}" ]]; then
    rm -rf "${repo_default}" 2>/dev/null || true
  fi
  if [[ -n "${repo_custom:-}" ]]; then
    rm -rf "${repo_custom}" 2>/dev/null || true
  fi
}

trap cleanup EXIT

output=$(REPO_DIR="${repo_default}" AIDER_BIN="${AIDER_STUB}" "${RALF_AI_SCRIPT}" 2>&1 || true)
assert_no_branch_warning "${output}"

git -C "${repo_default}" checkout -b feature/local-ai-hybrid >/dev/null 2>&1
output=$(REPO_DIR="${repo_default}" AIDER_BIN="${AIDER_STUB}" "${RALF_AI_SCRIPT}" 2>&1 || true)
assert_no_branch_warning "${output}"

git -C "${repo_default}" checkout main >/dev/null 2>&1
git -C "${repo_default}" config ralf.allowedBranches "main experiment"
git -C "${repo_default}" checkout -b experiment >/dev/null 2>&1
output=$(REPO_DIR="${repo_default}" AIDER_BIN="${AIDER_STUB}" "${RALF_AI_SCRIPT}" 2>&1 || true)
assert_no_branch_warning "${output}"

repo_custom=$(setup_repo)
git -C "${repo_custom}" checkout -b experiment >/dev/null 2>&1
output=$(REPO_DIR="${repo_custom}" RALF_ALLOWED_BRANCHES="main" AIDER_BIN="${AIDER_STUB}" "${RALF_AI_SCRIPT}" 2>&1 || true)
assert_branch_warning "${output}"

echo "ralf-ai branch checks passed"
