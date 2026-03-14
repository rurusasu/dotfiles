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
# --- Gemini API key (embedding): read from Docker secret ---
_gemini_secret_file="/run/secrets/gemini_api_key"
if [ -f "$_gemini_secret_file" ]; then
  _gemini_key="$(cat "$_gemini_secret_file")"
  if [ -n "$_gemini_key" ]; then
    GEMINI_API_KEY="$_gemini_key"
    export GEMINI_API_KEY
  fi
fi
# --- Log secret injection status ---
_gh_len=$(printf "%s" "$GITHUB_TOKEN" | wc -c)
_xai_status="not set"
if [ -n "${XAI_API_KEY:-}" ]; then _xai_status="ok ($(printf "%s" "$XAI_API_KEY" | wc -c) chars)"; fi
_gemini_status="not set"
if [ -n "${GEMINI_API_KEY:-}" ]; then _gemini_status="ok ($(printf "%s" "$GEMINI_API_KEY" | wc -c) chars)"; fi
echo "[entrypoint] secrets: GITHUB_TOKEN=${_gh_len} chars, XAI_API_KEY=${_xai_status}, GEMINI_API_KEY=${_gemini_status}"

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

workspace_dir="/app/data/workspace"

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

# Pull latest workspace from remote (if it's a git repo with a remote).
# Runs before AGENTS.md creation guard so that pulled AGENTS.md is preserved.
if [ -d "$workspace_dir/.git" ] && git -C "$workspace_dir" remote get-url origin >/dev/null 2>&1; then
  if git -C "$workspace_dir" pull --ff-only 2>&1; then
    echo "[entrypoint] workspace: git pull ok ($(git -C "$workspace_dir" rev-parse --short HEAD))"
  else
    echo "[entrypoint] WARNING: workspace git pull failed — continuing with local state" >&2
  fi
fi

# Enforce Claude-first child-session policy inside workspace instructions.
workspace_agents="$workspace_dir/AGENTS.md"
if [ ! -f "$workspace_agents" ]; then
  mkdir -p "$workspace_dir"
  cat >"$workspace_agents" <<'EOF'
# AGENTS.md - Workspace
EOF
fi

# Remove legacy CODEX-FIRST block if present (migration from previous policy).
if grep -q "BEGIN OPENCLAW CODEX-FIRST RULES" "$workspace_agents" 2>/dev/null; then
  sed -i '/## BEGIN OPENCLAW CODEX-FIRST RULES/,/## END OPENCLAW CODEX-FIRST RULES/d' "$workspace_agents"
  echo "[entrypoint] removed legacy CODEX-FIRST policy block"
fi

if ! grep -q "BEGIN OPENCLAW CLAUDE-FIRST RULES" "$workspace_agents"; then
  cat >>"$workspace_agents" <<'EOF'

## BEGIN OPENCLAW CLAUDE-FIRST RULES

- すべてのタスクはデフォルトで Claude Code に委譲する: `sessions_spawn(runtime:"acp", agentId:"claude")`
- Claude Code は `web_fetch`, `web_search`, skills, shell tools にアクセスできる
- Skills は `/app/data/workspace/skills/` に配置。各スキルの SKILL.md に従うこと
- **NEVER use `web_fetch` for `x.com` or `twitter.com` URLs.** Grok API `x_search` via `curl` + `$XAI_API_KEY` を使用
- Codex 子セッションは明示的に要求された場合のみ: `sessions_spawn` (without `runtime:"acp"`)
- Gemini 子セッションは明示的に要求された場合のみ: `sessions_spawn(runtime:"acp", agentId:"gemini")`
- ACP 子セッションでは `accepted` は enqueue のみ。`sessions_send(timeoutSeconds>0)` で完了確認すること
- `sessions_send` が空 payload を返した場合、gateway ログ (`[agent:nested]`) で実出力を確認

## END OPENCLAW CLAUDE-FIRST RULES
EOF
fi

# Inject built-in sandbox rules into workspace AGENTS.md.
if ! grep -q "BEGIN SANDBOX RULES" "$workspace_agents"; then
  cat >>"$workspace_agents" <<'EOF'

## BEGIN SANDBOX RULES

- Tool execution (`shell_exec`, `file_write`, etc.) runs inside an isolated Docker sandbox container.
- The sandbox image (`openclaw-sandbox-common:bookworm-slim`) includes: Python 3, Node.js, git, curl, jq, gh CLI, Playwright CLI, Chromium.
- Sandbox containers use `network: "bridge"` (external access available for pnpm install, Playwright E2E, etc.).
- `$XAI_API_KEY` is available in the sandbox environment for Grok API calls (`x_search`). Use `curl` with this key for X/Twitter content retrieval.
- Sandbox containers have NO access to the Docker daemon (no `DOCKER_HOST`). Docker build/run must be done on the gateway side.
- Each session gets its own sandbox container (`scope: "session"`), destroyed when the session ends.
- The workspace is mounted read-write at `/workspace` inside the sandbox.
- To run Python code, use `shell_exec("python3 script.py")` directly.
- To run Node.js code, use `shell_exec("node script.js")` directly.
- Playwright CLI (`@playwright/cli`) is available for E2E testing. `@playwright/test` is not installed.
- SYS_ADMIN is not required — Playwright launches Chromium with `--no-sandbox` by default.
- **Path mapping**: `/app/data/workspace/` on the gateway corresponds to `/workspace/` inside the sandbox. Always use `/workspace/` paths in sandbox tools.

## END SANDBOX RULES
EOF
fi

# --- Superpowers: clone or update obra/superpowers ---
_sp_dir="/app/data/superpowers"
_sp_repo="https://github.com/obra/superpowers.git"

if [ ! -d "$_sp_dir/.git" ]; then
  echo "[entrypoint] superpowers: cloning..."
  if ! git clone --depth 1 --single-branch "$_sp_repo" "$_sp_dir" 2>&1; then
    echo "[WARN] superpowers clone failed; skills unavailable"
  fi
else
  if ! git -C "$_sp_dir" pull --ff-only 2>&1; then
    echo "[WARN] superpowers pull failed; using cached version"
  fi
fi

# --- Superpowers: wire to agent skill-discovery paths ---
if [ -d "$_sp_dir/skills" ]; then
  # Codex / OpenCode / generic (~/.agents/skills/ -- writable via tmpfs)
  mkdir -p "$HOME/.agents/skills"
  ln -sfn "$_sp_dir/skills" "$HOME/.agents/skills/superpowers"

  # Gemini CLI (~/.gemini/extensions/ expects full repo, not just skills/)
  mkdir -p "$HOME/.gemini/extensions"
  ln -sfn "$_sp_dir" "$HOME/.gemini/extensions/superpowers"

  # Workspace skills — copy (not symlink) so sandbox containers can read them.
  # Sandbox only mounts /app/data/workspace/ → /workspace/; symlink targets
  # outside that tree are invisible inside the sandbox.
  # Remove stale symlink first to avoid cp "same file" error.
  [ -L "$workspace_dir/skills/superpowers" ] && rm -f "$workspace_dir/skills/superpowers"
  mkdir -p "$workspace_dir/skills/superpowers"
  cp -rLf "$_sp_dir/skills/." "$workspace_dir/skills/superpowers/"

  echo "[entrypoint] superpowers: wired to agents ($(git -C "$_sp_dir" rev-parse --short HEAD 2>/dev/null || echo 'unknown'))"
else
  echo "[WARN] superpowers: skills/ directory not found; skipping agent wiring"
fi

# Copy Claude Code skills into workspace so sandbox containers can read them.
# Sandbox only mounts /app/data/workspace/ → /workspace/; symlink targets
# outside that tree (/home/bun/.claude/skills/) are invisible inside the sandbox.
claude_skills="/home/bun/.claude/skills"
workspace_skills="$workspace_dir/skills"
if [ -d "$claude_skills" ]; then
  mkdir -p "$workspace_skills"
  for skill_dir in "$claude_skills"/*/; do
    skill_name="$(basename "$skill_dir")"
    target="$workspace_skills/$skill_name"
    # Remove stale symlink or previous copy
    if [ -L "$target" ]; then
      rm "$target"
    elif [ -d "$target" ]; then
      rm -rf "$target"
    fi
    cp -rL "$skill_dir" "$target"
  done
fi

# --- Invalidate stale skill snapshots ---
# On container restart, new skills (e.g. superpowers) may have been added.
# OpenClaw caches a skills snapshot per session in sessions.json (version: 0).
# Snapshots with version 0 are never auto-refreshed (refresh requires version > 0).
# Removing skillsSnapshot from all session entries forces a fresh rebuild on next turn.
_sessions_dir="/home/bun/.openclaw/agents"
if [ -d "$_sessions_dir" ]; then
  find "$_sessions_dir" -name "sessions.json" -type f 2>/dev/null | while read -r _sf; do
    if grep -q '"skillsSnapshot"' "$_sf" 2>/dev/null; then
      node -e "
        const fs = require('fs');
        const d = JSON.parse(fs.readFileSync('$_sf','utf-8'));
        let n = 0;
        for (const k of Object.keys(d)) { if (d[k].skillsSnapshot) { delete d[k].skillsSnapshot; n++; } }
        if (n > 0) { fs.writeFileSync('$_sf', JSON.stringify(d, null, 2)); console.log('[entrypoint] invalidated', n, 'stale skill snapshots in', '$_sf'); }
      " 2>/dev/null || true
    fi
  done
fi

# --- Startup health summary ---
echo "[entrypoint] === STARTUP HEALTH ==="

# 1. Workspace git status
if [ -d "$workspace_dir/.git" ]; then
  _ws_rev="$(git -C "$workspace_dir" rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
  _ws_dirty="$(git -C "$workspace_dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  echo "[entrypoint]   workspace: rev=$_ws_rev dirty_files=$_ws_dirty"
else
  echo "[entrypoint]   workspace: not a git repo"
fi

# 2. Superpowers status
if [ -d "/app/data/superpowers/skills" ]; then
  _sp_rev="$(git -C /app/data/superpowers rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
  _sp_count="$(find /app/data/superpowers/skills -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')"
  echo "[entrypoint]   superpowers: rev=$_sp_rev skills=$_sp_count"
else
  echo "[entrypoint]   superpowers: not available"
fi

# 3. Agent policy block
if grep -q "BEGIN OPENCLAW CLAUDE-FIRST RULES" "$workspace_agents" 2>/dev/null; then
  echo "[entrypoint]   agent_policy: claude-first OK"
elif grep -q "BEGIN OPENCLAW CODEX-FIRST RULES" "$workspace_agents" 2>/dev/null; then
  echo "[entrypoint]   agent_policy: WARNING — codex-first still present"
else
  echo "[entrypoint]   agent_policy: WARNING — no policy block found"
fi

# 4. Old policy cleanup confirmation
if grep -q "CODEX-FIRST" "$workspace_agents" 2>/dev/null; then
  echo "[entrypoint]   old_policy_cleanup: FAILED — CODEX-FIRST remnants found"
else
  echo "[entrypoint]   old_policy_cleanup: clean"
fi

echo "[entrypoint] === END HEALTH ==="

exec openclaw "$@"
