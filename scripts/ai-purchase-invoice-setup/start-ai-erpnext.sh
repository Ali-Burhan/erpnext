#!/usr/bin/env bash
set -euo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_FILE="$BENCH_DIR/.ollama-model"

if [ ! -s "$MODEL_FILE" ]; then
  echo "Missing configured Ollama model file: $MODEL_FILE" >&2
  echo "Run setup-frappe.sh again to finish the AI setup." >&2
  exit 1
fi

OLLAMA_MODEL="$(cat "$MODEL_FILE")"
[[ "$OLLAMA_MODEL" =~ ^[A-Za-z0-9._:-]+$ ]] || {
  echo "Invalid model name in $MODEL_FILE." >&2
  exit 1
}

cd "$BENCH_DIR"
sudo systemctl start ollama

for _ in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:11434/api/tags >/dev/null; then
    break
  fi
  sleep 1
done

if ! curl -fsS http://127.0.0.1:11434/api/tags >/dev/null; then
  echo "Ollama did not become ready at http://127.0.0.1:11434." >&2
  exit 1
fi

if ! ollama list | awk 'NR > 1 { print $1 }' | grep -Fxq "$OLLAMA_MODEL"; then
  ollama pull "$OLLAMA_MODEL"
fi

echo "Starting ERPNext with Ollama model $OLLAMA_MODEL."
exec bench start
