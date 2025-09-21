#!/usr/bin/env bash
set -euo pipefail

printf '\n=== Local AI bootstrap ===\n'

if ! command -v ollama >/dev/null 2>&1; then
  echo "[!] ollama not found. Install from https://ollama.ai/ first." >&2
  exit 1
fi

MODEL="${1:-llama3:8b}"

echo "Pulling model ${MODEL}..."
ollama pull "${MODEL}"

echo "Model download complete."
