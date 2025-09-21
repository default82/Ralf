#!/usr/bin/env bash
set -euo pipefail

INPUT_PATH="${1:-reports/ai/context/latest.raw}"
OUTPUT_PATH="${2:-reports/ai/context/latest.redacted}"

if [[ ! -f "${INPUT_PATH}" ]]; then
  echo "input context ${INPUT_PATH} not found" >&2
  exit 1
fi

python3 - "$INPUT_PATH" "$OUTPUT_PATH" <<'PY'
import re
import sys

input_path, output_path = sys.argv[1:3]
with open(input_path, "r", encoding="utf-8") as fh:
    data = fh.read()

patterns = [
    (re.compile(r"((?:password|passphrase|passwd)\s*[:=]\s*)([^\s,]+)", re.IGNORECASE), r"\1***REDACTED***"),
    (re.compile(r"((?:api_?key|token|secret|bearer)\s*[:=]\s*)([A-Za-z0-9_\-\.\+/=]+)", re.IGNORECASE), r"\1***REDACTED***"),
    (re.compile(r"(ssh-[a-z0-9-]+)\s+[A-Za-z0-9+/=]+", re.IGNORECASE), r"\1 ***REDACTED***"),
]

for pattern, replacement in patterns:
    data = pattern.sub(replacement, data)

data = re.sub(r"-----BEGIN [^-]+-----.*?-----END [^-]+-----", "-----BEGIN REDACTED-----\n***REDACTED***\n-----END REDACTED-----", data, flags=re.DOTALL)

with open(output_path, "w", encoding="utf-8") as fh:
    fh.write(data)
PY

printf 'redacted context written to %s\n' "${OUTPUT_PATH}"
