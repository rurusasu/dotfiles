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

## BEGIN X/TWITTER URL ROUTING RULES

- **NEVER use `web_fetch` for `x.com` or `twitter.com` URLs.** These sites require JS rendering and `web_fetch` always returns an error page.
- To retrieve X/Twitter post content, use the Grok API `x_search` tool via `curl`:
  ```bash
  curl -s https://api.x.ai/v1/responses \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $XAI_API_KEY" \
    -d '{
      "model": "grok-4-1-fast",
      "input": [{"role": "user", "content": "Find the tweet by @{handle} with status ID {id}"}],
      "tools": [{"type": "x_search"}]
    }'
  ```
- Extract `handle` and `id` from the URL pattern: `x.com/{handle}/status/{id}` or `twitter.com/{handle}/status/{id}`.
- For general X/Twitter trend searches, use `x_search` with a descriptive query instead of a specific status ID.
- `$XAI_API_KEY` is available as an environment variable inside this container.

## END X/TWITTER URL ROUTING RULES

## END OPENCLAW CODEX-FIRST RULES
EOF
fi

# Symlink Claude Code skills into workspace so OpenClaw (Codex) can use them directly.
claude_skills="/home/bun/.claude/skills"
workspace_skills="$workspace_dir/skills"
if [ -d "$claude_skills" ]; then
  mkdir -p "$workspace_skills"
  for skill_dir in "$claude_skills"/*/; do
    skill_name="$(basename "$skill_dir")"
    target="$workspace_skills/$skill_name"
    if [ -L "$target" ]; then
      rm "$target"
    elif [ -d "$target" ]; then
      rm -rf "$target"
    fi
    ln -s "$skill_dir" "$target"
  done
fi

exec openclaw "$@"
