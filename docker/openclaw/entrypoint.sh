#!/bin/sh
set -eu

# Host ~/.gemini may contain MCP commands that are unavailable in this container.
# Force a minimal settings.json on each boot to keep ACPX Gemini startup stable.
if [ -f /app/gemini.settings.json ]; then
  mkdir -p /home/bun/.gemini
  tmp="/home/bun/.gemini/.settings.json.tmp.$$"
  cp /app/gemini.settings.json "$tmp"
  mv "$tmp" /home/bun/.gemini/settings.json
fi

# Ensure ACPX uses Gemini in ACP server mode.
if [ -f /app/acpx.config.json ]; then
  mkdir -p /home/bun/.acpx
  tmp="/home/bun/.acpx/.config.json.tmp.$$"
  cp /app/acpx.config.json "$tmp"
  mv "$tmp" /home/bun/.acpx/config.json
fi

# Prefer Docker secret for GitHub auth and export for gh CLI compatibility.
if [ -f /run/secrets/github_token ]; then
  token="$(cat /run/secrets/github_token)"
  export GITHUB_TOKEN="$token"
  export GH_TOKEN="$token"
fi

exec openclaw "$@"
