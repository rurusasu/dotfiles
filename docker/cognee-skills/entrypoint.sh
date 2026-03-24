#!/bin/sh
set -e

# Read Gemini API key from Docker secret
_gemini_secret="/run/secrets/gemini_api_key"
if [ -f "$_gemini_secret" ]; then
  _key=$(cat "$_gemini_secret")
  if [ -n "$_key" ]; then
    export LLM_API_KEY="$_key"
    export EMBEDDING_API_KEY="$_key"
    echo "[entrypoint] GEMINI_API_KEY loaded from secret"
  fi
fi

# FalkorDB adapter registration
export COGNEE_FALKORDB_AUTO_REGISTER=1

echo "[entrypoint] starting cognee-mcp-skills (transport=${TRANSPORT_MODE:-http})"
exec python /app/src/server.py --transport "${TRANSPORT_MODE:-http}" --host 0.0.0.0 --port 8000
