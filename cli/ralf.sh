#!/usr/bin/env bash
set -euo pipefail

COMMAND=${1:-help}

usage() {
  cat <<USAGE
Usage: ralf.sh <command>

Commands:
  lint           Run ShellCheck on automation scripts
  test           Execute Makefile smoke tests
  build          Build the local AI LXC image
  help           Show this message
USAGE
}

case "$COMMAND" in
  lint)
    make lint
    ;;
  test)
    make test
    ;;
  build)
    make build
    ;;
  help|*)
    usage
    ;;
esac
