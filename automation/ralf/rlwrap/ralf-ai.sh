#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="/srv/ralf"
AIDER_BIN=${AIDER_BIN:-aider}

log() {
  local level="$1"
  shift
  printf '[%s] %s: %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$level" "$*" >&2
}

show_help() {
  cat <<'USAGE'
ralf-ai - Repo Assistant for Local Fixes

Usage: ralf-ai [--help] [--] [AIDER ARGUMENTS...]

Launch aider with repository safeguards and sensible defaults for an
OpenAI-compatible Ollama endpoint.

Environment variables:
  OPENAI_API_BASE  Base URL for the API (default: http://localhost:11434/v1)
  OPENAI_API_KEY   API key to present (default: ollama)
  OLLAMA_MODEL     Model name to request from aider (default: llama3:8b)
  AIDER_BIN        aider executable to invoke (default: aider)

Additional arguments are forwarded directly to aider.
USAGE
}

if [[ "${1-}" == "--help" || "${1-}" == "-h" ]]; then
  show_help
  exit 0
fi

OPENAI_API_BASE=${OPENAI_API_BASE:-http://localhost:11434/v1}
OPENAI_API_KEY=${OPENAI_API_KEY:-ollama}
OLLAMA_MODEL=${OLLAMA_MODEL:-llama3:8b}
OPENAI_MODEL=${OPENAI_MODEL:-$OLLAMA_MODEL}

export OPENAI_API_BASE OPENAI_API_KEY OPENAI_MODEL

log INFO "Using OpenAI base ${OPENAI_API_BASE} with model ${OPENAI_MODEL}"

if [[ ! -d "${REPO_DIR}" ]]; then
  log INFO "Creating repository directory ${REPO_DIR}"
  mkdir -p "${REPO_DIR}"
fi

if [[ ! -d "${REPO_DIR}/.git" ]]; then
  log INFO "Initialising git repository in ${REPO_DIR}"
  git init "${REPO_DIR}" >/dev/null
fi

if ! git -C "${REPO_DIR}" symbolic-ref HEAD >/dev/null 2>&1; then
  log INFO "Setting default branch to main"
  git -C "${REPO_DIR}" symbolic-ref HEAD refs/heads/main
fi

current_branch=$(git -C "${REPO_DIR}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)
if [[ "${current_branch}" != "main" ]]; then
  log WARN "Current branch '${current_branch}' differs from default 'main'; continuing"
fi

if [[ -n "$(git -C "${REPO_DIR}" status --porcelain)" ]]; then
  log ERROR "Repository has uncommitted changes"
  exit 1
fi

if ! command -v "${AIDER_BIN}" >/dev/null 2>&1; then
  log ERROR "aider executable '${AIDER_BIN}' not found"
  exit 127
fi

read -r -d '' SYSTEM_PROMPT <<'PROMPT' || true
You are Ralf, the Repo Assistant for Local Fixes. Follow instructions from any
AGENTS.md files in the repository, encourage good git hygiene, and help the
user make well-scoped commits that keep the worktree clean.
PROMPT

log INFO "Launching aider in ${REPO_DIR}"

exec "${AIDER_BIN}" \
  --model "${OLLAMA_MODEL}" \
  --system-prompt "${SYSTEM_PROMPT}" \
  "$@"
