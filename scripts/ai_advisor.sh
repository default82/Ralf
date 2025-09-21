#!/usr/bin/env bash
set -euo pipefail

CONTEXT_PATH="${1:-reports/ai/context/latest.redacted}"
TEMPLATE_PATH="${AI_PROMPT_TEMPLATE:-ai/prompts/advisor_request.tmpl}"
REPORT_DIR="${AI_REPORT_DIR:-reports/ai}"
MODEL="${OPENAI_MODEL:-gpt-4o-mini}"
ENDPOINT="${OPENAI_ENDPOINT:-https://api.openai.com/v1/chat/completions}"

if [[ ! -f "${CONTEXT_PATH}" ]]; then
  echo "context ${CONTEXT_PATH} not found" >&2
  exit 1
fi

if [[ ! -f "${TEMPLATE_PATH}" ]]; then
  echo "prompt template ${TEMPLATE_PATH} not found" >&2
  exit 1
fi

for bin in jq curl; do
  if ! command -v "${bin}" >/dev/null 2>&1; then
    echo "required dependency '${bin}' not found in PATH" >&2
    exit 1
  fi
done

API_KEY="${OPENAI_API_KEY:-}"
if [[ -z "${API_KEY}" && -f secrets/ai.sops.yaml ]]; then
  if command -v sops >/dev/null 2>&1; then
    API_KEY=$(sops -d --extract '"openai.api_key"' secrets/ai.sops.yaml 2>/dev/null || true)
  fi
fi

if [[ -z "${API_KEY}" ]]; then
  echo "OpenAI API key missing. Export OPENAI_API_KEY or configure secrets/ai.sops.yaml" >&2
  exit 1
fi

mkdir -p "${REPORT_DIR}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RAW_RESPONSE="${REPORT_DIR}/${TIMESTAMP}.json"
SUMMARY_RESPONSE="${REPORT_DIR}/${TIMESTAMP}.txt"

PAYLOAD=$(jq -n --rawfile tmpl "${TEMPLATE_PATH}" --rawfile ctx "${CONTEXT_PATH}" --arg model "${MODEL}" '
  ($tmpl | gsub("\\{\\{CONTEXT\\}\\}"; $ctx)) as $prompt |
  {
    model: $model,
    temperature: 0,
    messages: [
      {role: "system", content: "You are the RALF homelab advisor. Only provide actionable infrastructure diffs."},
      {role: "user", content: $prompt}
    ]
  }
')

curl -sS -X POST "${ENDPOINT}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d "${PAYLOAD}" \
  -o "${RAW_RESPONSE}"

if [[ ! -s "${RAW_RESPONSE}" ]]; then
  echo "Empty response saved to ${RAW_RESPONSE}" >&2
  exit 1
fi

jq -r '.choices[0].message.content // ""' "${RAW_RESPONSE}" > "${SUMMARY_RESPONSE}"

printf 'advisor response stored at %s and %s\n' "${RAW_RESPONSE}" "${SUMMARY_RESPONSE}"
