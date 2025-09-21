#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR=${REPO_DIR:-/srv/ralf}
AIDER_BIN=${AIDER_BIN:-aider}
DEFAULT_ALLOWED_BRANCHES=(main feature/local-ai-hybrid)

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
  OPENAI_API_BASE       Base URL for the API (default: http://localhost:11434/v1)
  OPENAI_API_KEY        API key to present (default: ollama)
  OLLAMA_MODEL          Model name to request from aider (default: llama3:8b)
  AIDER_BIN             aider executable to invoke (default: aider)
  REPO_DIR              Repository path to guard (default: /srv/ralf)
  RALF_ALLOWED_BRANCHES Space-separated list of allowed branches
                        (default: "main feature/local-ai-hybrid"; can also be
                        configured via `git config ralf.allowedBranches`)

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

allow_any_branch=false
allowed_branches=()

if [[ "${RALF_ALLOWED_BRANCHES-}" == "*" ]]; then
  allow_any_branch=true
elif [[ -n "${RALF_ALLOWED_BRANCHES-}" ]]; then
  read -r -a allowed_branches <<<"${RALF_ALLOWED_BRANCHES}"
else
  config_allowed_branches=$(git -C "${REPO_DIR}" config --get ralf.allowedBranches || true)
  if [[ "${config_allowed_branches}" == "*" ]]; then
    allow_any_branch=true
  elif [[ -n "${config_allowed_branches}" ]]; then
    read -r -a allowed_branches <<<"${config_allowed_branches}"
  else
    allowed_branches=("${DEFAULT_ALLOWED_BRANCHES[@]}")
  fi
fi

if [[ "${current_branch}" == "detached" ]]; then
  log WARN "Repository is in a detached HEAD state; continuing"
elif [[ "${allow_any_branch}" != true ]]; then
  if [[ ${#allowed_branches[@]} -eq 0 ]]; then
    log WARN "No allowed branches configured; skipping branch validation"
  else
    branch_allowed=false
    for branch in "${allowed_branches[@]}"; do
      if [[ "${current_branch}" == "${branch}" ]]; then
        branch_allowed=true
        break
      fi
    done
    if [[ "${branch_allowed}" != true ]]; then
      log WARN "Current branch '${current_branch}' is not in the allowed set (${allowed_branches[*]}); continuing"
    fi
  fi
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
AGENTS.md files in the repository, encourage good git hygiene, remind the user
to work on allowed branches (default: main, feature/local-ai-hybrid, or
branches configured via RALF_ALLOWED_BRANCHES or git config ralf.allowedBranches),
and help the user make well-scoped commits that keep the worktree clean.
PROMPT

log INFO "Launching aider in ${REPO_DIR}"

exec "${AIDER_BIN}" \
  --model "${OLLAMA_MODEL}" \
  --system-prompt "${SYSTEM_PROMPT}" \
  "$@"
