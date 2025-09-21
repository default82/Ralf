#!/usr/bin/env bash
set -euo pipefail
REPO_URL=${GITOPS_REPO:-"git@your.git/ralf.git"}
WORKDIR=${GITOPS_PATH:-"/srv/ralf"}
BRANCH=${GITOPS_BRANCH:-"main"}

log() { echo "[gitops] $*"; }

if [ ! -d "$WORKDIR/.git" ]; then
  log "Cloning repository $REPO_URL"
  git clone "$REPO_URL" "$WORKDIR"
fi

cd "$WORKDIR"
log "Fetching updates"
git fetch origin "$BRANCH"
CURRENT_HEAD=$(git rev-parse HEAD)
LATEST_HEAD=$(git rev-parse "origin/$BRANCH")

if [ "$CURRENT_HEAD" != "$LATEST_HEAD" ]; then
  log "Updating working tree"
  git reset --hard "origin/$BRANCH"
  log "Running lint checks"
  make lint || { log "Lint failed"; exit 1; }
  log "Running smoke tests"
  make test || { log "Smoke tests failed"; exit 1; }
  log "Triggering build"
  make build
else
  log "No changes detected"
fi
