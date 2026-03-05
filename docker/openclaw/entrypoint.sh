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

# Claude Code: ensure credentials dir exists and set container-safe defaults.
mkdir -p /home/bun/.claude
if [ ! -f /home/bun/.claude/settings.json ]; then
  cat >/home/bun/.claude/settings.json <<'CEOF'
{"permissions":{"allow":["Bash(*)","Read(*)","Write(*)","Edit(*)","Glob(*)","Grep(*)"],"deny":[]},"hasCompletedOnboarding":true}
CEOF
fi
# Claude Code expects $HOME/.claude.json at the HOME root.
# In this container, that file is bind-mounted from the host via docker-compose.

# Enforce Codex-first child-session policy inside workspace instructions.
workspace_dir="/app/data/workspace"
workspace_agents="$workspace_dir/AGENTS.md"
if [ ! -f "$workspace_agents" ]; then
  mkdir -p "$workspace_dir"
  cat >"$workspace_agents" <<'EOF'
# AGENTS.md - Workspace
EOF
fi
if ! grep -q "BEGIN OPENCLAW CODEX-FIRST RULES" "$workspace_agents"; then
  cat >>"$workspace_agents" <<'EOF'

## BEGIN OPENCLAW CODEX-FIRST RULES

- Default child tasks to Codex via `sessions_spawn` (without `runtime:"acp"`, `agentId:"main"`), unless Claude or Gemini is explicitly requested.
- Use Claude child sessions via `sessions_spawn(runtime:"acp", agentId:"claude")` for Claude-specific capabilities.
- Use Gemini child sessions only when needed for Gemini-specific capabilities.
- For ACP child runs, treat `accepted` as enqueue only and verify completion with `sessions_send(timeoutSeconds>0)`.
- If `sessions_send` returns empty payload, confirm child output from gateway logs (`[agent:nested]`).

## END OPENCLAW CODEX-FIRST RULES
EOF
fi

# Prefer Docker secret for GitHub auth and export for gh CLI compatibility.
if [ -f /run/secrets/github_token ]; then
  token="$(cat /run/secrets/github_token)"
  export GITHUB_TOKEN="$token"
  export GH_TOKEN="$token"
fi

exec openclaw "$@"
