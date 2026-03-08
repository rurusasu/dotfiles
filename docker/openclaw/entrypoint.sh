#!/bin/sh
set -eu

# --- GitHub token: read from Docker secret (file-based) and export ---
_secret_file="/run/secrets/github_token"
if [ -f "$_secret_file" ]; then
  GITHUB_TOKEN="$(cat "$_secret_file")"
  export GITHUB_TOKEN
  GH_TOKEN="$GITHUB_TOKEN"
  export GH_TOKEN
else
  echo "[FATAL] Docker secret not found: $_secret_file" >&2
  echo "[FATAL] Run the Handler (install.user.ps1) to write secrets to ~/.openclaw/secrets/ and update .env." >&2
  exit 1
fi
if [ -z "$GITHUB_TOKEN" ]; then
  echo "[FATAL] GitHub token is empty (secret file exists but is blank)." >&2
  echo "[FATAL] Re-run the Handler or verify 1Password PAT." >&2
  exit 1
fi

# --- xAI API key: read from Docker secret (file-based, optional) and export ---
_xai_secret_file="/run/secrets/xai_api_key"
if [ -f "$_xai_secret_file" ]; then
  _xai_key="$(cat "$_xai_secret_file")"
  if [ -n "$_xai_key" ]; then
    XAI_API_KEY="$_xai_key"
    export XAI_API_KEY
  fi
fi
# --- Log secret injection status ---
_gh_len=$(printf "%s" "$GITHUB_TOKEN" | wc -c)
_xai_status="not set"
if [ -n "${XAI_API_KEY:-}" ]; then _xai_status="ok ($(printf "%s" "$XAI_API_KEY" | wc -c) chars)"; fi
echo "[entrypoint] secrets: GITHUB_TOKEN=${_gh_len} chars, XAI_API_KEY=${_xai_status}"

# --- Render config template: replace @@PLACEHOLDERS@@ with runtime secrets ---
_config_tmpl="/app/openclaw.json.tmpl"
_config_out="/home/bun/.openclaw/openclaw.json"
if [ -f "$_config_tmpl" ]; then
  sed -e "s|@@GITHUB_TOKEN@@|${GITHUB_TOKEN}|g" -e "s|@@XAI_API_KEY@@|${XAI_API_KEY:-}|g" "$_config_tmpl" >"$_config_out"
  echo "[entrypoint] config rendered to $_config_out"
fi

# Validate GIT_ASKPASS script exists and is executable
if [ ! -x "${GIT_ASKPASS:-/usr/local/bin/git-credential-askpass.sh}" ]; then
  echo "[FATAL] GIT_ASKPASS script not found or not executable: ${GIT_ASKPASS:-/usr/local/bin/git-credential-askpass.sh}" >&2
  exit 1
fi

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

# --- Verify sandbox images exist (build must be done on host via `task sandbox:build`) ---
_sandbox_base="openclaw-sandbox:bookworm-slim"
_sandbox_common="openclaw-sandbox-common:bookworm-slim"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  _missing=""
  docker image inspect "$_sandbox_base" >/dev/null 2>&1 || _missing="$_sandbox_base"
  docker image inspect "$_sandbox_common" >/dev/null 2>&1 || _missing="$_missing $_sandbox_common"
  if [ -n "$_missing" ]; then
    echo "[entrypoint] WARNING: sandbox image(s) missing:$_missing" >&2
    echo "[entrypoint] Run 'task sandbox:build' on the host to build them." >&2
  else
    echo "[entrypoint] sandbox images: $_sandbox_base ok, $_sandbox_common ok"
  fi
else
  echo "[entrypoint] docker CLI not available or socket not mounted; skipping sandbox image check"
fi

# Proxy Docker socket as TCP so sandbox containers can use Docker CLI.
# Unix sockets don't propagate through Docker Desktop named volumes,
# so we expose the socket as TCP on a loopback port instead.
workspace_dir="/app/data/workspace"
_docker_proxy_port=2375
if [ -S /var/run/docker.sock ]; then
  socat TCP-LISTEN:$_docker_proxy_port,bind=0.0.0.0,fork,reuseaddr UNIX-CONNECT:/var/run/docker.sock &
  echo "[entrypoint] docker socket proxied to tcp://0.0.0.0:$_docker_proxy_port"
fi

# Mirror /app/data/lifelog into workspace so sandbox can read it at /workspace/lifelog.
_lifelog_src="/app/data/lifelog"
_lifelog_dst="$workspace_dir/lifelog"
if [ -d "$_lifelog_src" ]; then
  # Remove stale symlink from previous config
  [ -L "$_lifelog_dst" ] && rm -f "$_lifelog_dst"
  mkdir -p "$_lifelog_dst"
  cp -au "$_lifelog_src/." "$_lifelog_dst/" 2>&1
  echo "[entrypoint] lifelog synced to $_lifelog_dst ($(du -sh "$_lifelog_dst" | cut -f1))"
fi

# Enforce Codex-first child-session policy inside workspace instructions.
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

- For research, web fetching, news collection, and investigative tasks, spawn a Claude Code sub-agent: `sessions_spawn(runtime:"acp", agentId:"claude")`.
- Claude Code has access to `web_fetch`, `web_search`, skills (`/app/data/workspace/skills/`), and shell tools. Delegate data gathering to it.
- Skills in `/app/data/workspace/skills/` contain detailed procedures. Follow the SKILL.md in each skill directory.
- **NEVER use `web_fetch` for `x.com` or `twitter.com` URLs.** They require JS rendering and always fail. Use Grok API `x_search` via `curl` + `$XAI_API_KEY` (see `skills/news/SKILL.md`).
- Default other child tasks to Codex via `sessions_spawn` (without `runtime:"acp"`), unless Claude or Gemini is explicitly requested.
- Use Gemini child sessions only when needed for Gemini-specific capabilities.
- For ACP child runs, treat `accepted` as enqueue only and verify completion with `sessions_send(timeoutSeconds>0)`.
- If `sessions_send` returns empty payload, confirm child output from gateway logs (`[agent:nested]`).

## END OPENCLAW CODEX-FIRST RULES
EOF
fi

# Inject built-in sandbox rules into workspace AGENTS.md.
if ! grep -q "BEGIN SANDBOX RULES" "$workspace_agents"; then
  cat >>"$workspace_agents" <<'EOF'

## BEGIN SANDBOX RULES

- Tool execution (`shell_exec`, `file_write`, etc.) runs inside an isolated Docker sandbox container.
- The sandbox image (`openclaw-sandbox-common:bookworm-slim`) includes: Python 3, Node.js, git, curl, jq.
- Sandbox containers have no network access (`network: "none"`) and no secrets.
- Each session gets its own sandbox container (`scope: "session"`), destroyed when the session ends.
- The workspace is mounted read-write at `/workspace` inside the sandbox.
- To run Python code, use `shell_exec("python3 script.py")` directly — no HTTP API needed.
- To run Node.js code, use `shell_exec("node script.js")` directly.
- To install packages, the sandbox network must be temporarily enabled or packages must be pre-installed in the image.
- **Path mapping**: `/app/data/workspace/` on the host container corresponds to `/workspace/` inside the sandbox. Always use `/workspace/` paths in sandbox tools (`shell_exec`, `file_write`, etc.). For example, write lifelog files to `/workspace/lifelog/`, NOT `/app/data/lifelog/`.

## END SANDBOX RULES
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
