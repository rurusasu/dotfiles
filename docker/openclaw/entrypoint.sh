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
_config_out="/home/app/.openclaw/openclaw.json"
if [ -f "$_config_tmpl" ]; then
  _config_tmp="${_config_out}.tmp.$$"
  sed -e "s|@@GITHUB_TOKEN@@|${GITHUB_TOKEN}|g" -e "s|@@XAI_API_KEY@@|${XAI_API_KEY:-}|g" "$_config_tmpl" >"$_config_tmp"
  mv "$_config_tmp" "$_config_out"
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
  mkdir -p /home/app/.gemini
  tmp="/home/app/.gemini/.settings.json.tmp.$$"
  cp /app/gemini.settings.json "$tmp"
  mv "$tmp" /home/app/.gemini/settings.json
fi

# Ensure ACPX uses Gemini in ACP server mode.
if [ -f /app/acpx.config.json ]; then
  mkdir -p /home/app/.acpx
  tmp="/home/app/.acpx/.config.json.tmp.$$"
  cp /app/acpx.config.json "$tmp"
  mv "$tmp" /home/app/.acpx/config.json
fi

# --- Pre-create agent directories from rendered config ---
# Slack agent dirs are created dynamically on first message, but auth seeding
# runs at startup. Pre-create dirs so auth tokens are ready before first use.
if [ -f "$_config_out" ]; then
  CONFIG_PATH="$_config_out" node -e "
    const fs = require('fs');
    const path = require('path');
    const cfg = JSON.parse(fs.readFileSync(process.env.CONFIG_PATH, 'utf8'));
    const agents = (cfg.agents && cfg.agents.list) || [];
    const baseDir = '/home/app/.openclaw/agents';
    let created = 0;
    for (const a of agents) {
      const agentDir = path.join(baseDir, a.id, 'agent');
      const authFile = path.join(agentDir, 'auth-profiles.json');
      if (!fs.existsSync(agentDir)) {
        fs.mkdirSync(agentDir, { recursive: true, mode: 0o700 });
      }
      if (!fs.existsSync(authFile)) {
        fs.writeFileSync(authFile, JSON.stringify({ profiles: {}, usageStats: {} }, null, 2), { mode: 0o600 });
        created++;
      }
    }
    if (created > 0) console.log('[entrypoint] pre-created auth-profiles for ' + created + ' agent(s)');
  " || echo "[entrypoint] WARNING: agent dir pre-creation failed" >&2
fi

# --- Auth seeding helper: inject a provider profile into all agent auth-profiles ---
# Shared by Codex and Anthropic seeding below.
# Inputs are passed via env vars (not shell interpolation) to prevent injection.
_seed_auth_profile() {
  SEED_PROVIDER="$1" SEED_PROFILE="$2" SEED_LABEL="$3" node -e "
    const fs = require('fs');
    const os = require('os');
    const path = require('path');
    const provider = process.env.SEED_PROVIDER;
    const label = process.env.SEED_LABEL;
    const profile = JSON.parse(process.env.SEED_PROFILE);
    const baseDir = '/home/app/.openclaw/agents';
    let agents;
    try {
      agents = fs.existsSync(baseDir)
        ? fs.readdirSync(baseDir).filter(d => {
            try { return fs.statSync(path.join(baseDir, d)).isDirectory(); }
            catch(e) { return false; }
          })
        : [];
    } catch(e) { console.error('[entrypoint] ' + label + ': failed to scan agent dirs:', e.message); process.exit(1); }
    let updated = 0;
    for (const agent of agents) {
      const f = path.join(baseDir, agent, 'agent', 'auth-profiles.json');
      try {
        const d = JSON.parse(fs.readFileSync(f, 'utf8'));
        const key = provider + ':default';
        const existing = d.profiles[key];
        if (existing
            && existing.access === profile.access
            && (existing.refresh || null) === (profile.refresh || null)) continue;
        d.profiles[key] = profile;
        if (d.usageStats) delete d.usageStats[key];
        // Atomic write: temp file + rename to prevent corruption on crash.
        const tmp = f + '.tmp.' + process.pid;
        fs.writeFileSync(tmp, JSON.stringify(d, null, 2), { mode: 0o600 });
        fs.renameSync(tmp, f);
        updated++;
      } catch(e) {
        console.error('[entrypoint] ' + label + ': failed for agent ' + agent + ':', e.message);
      }
    }
    if (updated > 0) console.log('[entrypoint] ' + label + ': injected into ' + updated + ' agent(s)');
    else console.log('[entrypoint] ' + label + ': tokens already current (or no agent dirs)');
  " || echo "[entrypoint] $3: injection skipped" >&2
}

# Codex OAuth: seed auth-profiles.json from host's ~/.codex/auth.json (ro mount).
# OpenClaw manages its own refresh cycle; we only inject the initial token.
_codex_auth="/app/codex-auth.json"
if [ -f "$_codex_auth" ] && [ -s "$_codex_auth" ]; then
  _codex_profile=$(CODEX_AUTH_PATH="$_codex_auth" node -e "
    const fs = require('fs');
    const src = JSON.parse(fs.readFileSync(process.env.CODEX_AUTH_PATH, 'utf8'));
    if (!src.tokens || !src.tokens.access_token) process.exit(1);
    console.log(JSON.stringify({
      type: 'oauth',
      provider: 'openai-codex',
      access: src.tokens.access_token,
      refresh: src.tokens.refresh_token || null,
      expires: src.tokens.expires_at || (Date.now() + 864000000),
      accountId: src.tokens.account_id || ''
    }));
  " 2>/dev/null) && _seed_auth_profile "openai-codex" "$_codex_profile" "codex-auth" ||
    echo "[entrypoint] codex-auth: no valid tokens found, skipping"
else
  echo "[entrypoint] codex-auth: no host auth file mounted, skipping"
fi

# Anthropic OAuth: seed auth-profiles.json from Claude Code's .credentials.json.
# Claude Code stores OAuth tokens at ~/.claude/.credentials.json (mounted from host).
_claude_creds="/home/app/.claude/.credentials.json"
if [ -f "$_claude_creds" ] && [ -s "$_claude_creds" ]; then
  _anthropic_profile=$(CLAUDE_CREDS_PATH="$_claude_creds" node -e "
    const fs = require('fs');
    const src = JSON.parse(fs.readFileSync(process.env.CLAUDE_CREDS_PATH, 'utf8'));
    const oauth = src.claudeAiOauth;
    if (!oauth || !oauth.accessToken) process.exit(1);
    console.log(JSON.stringify({
      type: 'oauth',
      provider: 'anthropic',
      access: oauth.accessToken,
      refresh: oauth.refreshToken || null,
      expires: oauth.expiresAt || (Date.now() + 864000000),
      accountId: ''
    }));
  " 2>/dev/null) && _seed_auth_profile "anthropic" "$_anthropic_profile" "anthropic-auth" ||
    echo "[entrypoint] anthropic-auth: no valid tokens found, skipping"
else
  echo "[entrypoint] anthropic-auth: no Claude credentials file found, skipping"
fi

# Claude Code: ensure credentials dir exists and set container-safe defaults.
mkdir -p /home/app/.claude
if [ ! -f /home/app/.claude/settings.json ]; then
  cat >/home/app/.claude/settings.json <<'CEOF'
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

workspace_dir="${OPENCLAW_WORKSPACE_POSIX:-/app/data/workspace}"

# Ensure lifelog repo exists in workspace.
# On host bind mounts (Windows NTFS), cp -au preserves source permissions which
# become immutable on NTFS — sandbox cannot write to copied dirs.
# Use git clone instead so files get native host permissions.
_lifelog_dst="$workspace_dir/lifelog"
_lifelog_src="/app/data/lifelog"
if [ -d "$_lifelog_dst/.git" ]; then
  echo "[entrypoint] lifelog: already present in workspace, skipping"
elif [ -d "$_lifelog_src/.git" ]; then
  _lifelog_remote="$(git -C "$_lifelog_src" remote get-url origin 2>/dev/null || true)"
  if [ -n "$_lifelog_remote" ]; then
    [ -L "$_lifelog_dst" ] && rm -f "$_lifelog_dst"
    rm -rf "$_lifelog_dst"
    if git clone --depth 1 "$_lifelog_remote" "$_lifelog_dst" 2>&1; then
      echo "[entrypoint] lifelog: cloned from $_lifelog_remote"
    else
      echo "[entrypoint] WARNING: lifelog clone failed; continuing without lifelog" >&2
    fi
  else
    echo "[entrypoint] lifelog: source has no remote, skipping"
  fi
fi

# Clone or pull workspace from remote.
# Runs before AGENTS.md creation guard so that cloned/pulled AGENTS.md is preserved.
# On clone: remote files overwrite any pre-existing files with the same name.
_workspace_remote="${OPENCLAW_WORKSPACE_REMOTE:-https://github.com/rurusasu/openclaw-workspace.git}"
if [ ! -d "$workspace_dir/.git" ]; then
  # No .git — attempt initial clone into existing (possibly non-empty) directory.
  echo "[entrypoint] workspace: .git not found, cloning from $_workspace_remote"
  # /tmp is a small tmpfs (64 MB); use /app/data (named volume) for the temp clone
  # so that large repos don't hit "No space left on device".
  _tmp_clone="/app/data/.tmp-workspace-clone.$$"
  rm -rf "$_tmp_clone"
  mkdir -p "$_tmp_clone"
  # NOTE: this EXIT trap replaces any prior EXIT trap; do not add other EXIT traps above this point.
  trap 'rm -rf "$_tmp_clone"' EXIT
  if git clone --depth 1 "$_workspace_remote" "$_tmp_clone" 2>&1; then
    # Move .git into workspace dir, then checkout to apply remote files.
    mv "$_tmp_clone/.git" "$workspace_dir/.git"
    if git -C "$workspace_dir" checkout -- . 2>&1; then
      echo "[entrypoint] workspace: cloned ok ($(git -C "$workspace_dir" rev-parse --short HEAD))"
    else
      echo "[entrypoint] WARNING: workspace checkout failed after clone — .git exists but working tree may be incomplete" >&2
    fi
  else
    echo "[entrypoint] WARNING: workspace clone failed — continuing without git" >&2
  fi
  rm -rf "$_tmp_clone"
  trap - EXIT
elif git -C "$workspace_dir" remote get-url origin >/dev/null 2>&1; then
  if git -C "$workspace_dir" pull --ff-only 2>&1; then
    echo "[entrypoint] workspace: git pull ok ($(git -C "$workspace_dir" rev-parse --short HEAD))"
  else
    echo "[entrypoint] WARNING: workspace git pull failed — continuing with local state" >&2
  fi
fi

# Enforce Claude-first child-session policy inside workspace instructions.
# On host bind mounts, the gateway user (UID 1000) may not have write permission.
# Skip file modifications if the file is not writable.
workspace_agents="$workspace_dir/AGENTS.md"
if [ ! -f "$workspace_agents" ]; then
  if mkdir -p "$workspace_dir" 2>/dev/null && cat >"$workspace_agents" <<'EOF'; then true; else echo "[entrypoint] WARNING: cannot create workspace AGENTS.md (read-only bind mount?); skipping" >&2; fi
# AGENTS.md - Workspace
EOF
fi

if [ ! -w "$workspace_agents" ]; then
  echo "[entrypoint] workspace AGENTS.md is not writable; skipping policy injection"
else

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

  # Inject Cognee skill feedback rules.
  if ! grep -q "BEGIN COGNEE FEEDBACK RULES" "$workspace_agents"; then
    cat >>"$workspace_agents" <<'EOF'

## BEGIN COGNEE FEEDBACK RULES

- `/feedback <スキル名> <問題内容>` コマンドでスキルのフィードバックを記録できる
- フィードバック記録時は cognee-skills MCP の `log_skill_execution` を
  `success=false, error="ユーザー指摘: <問題内容>"` で呼び出すこと
- スコアが閾値以下に下がると自動改善が発火する

## END COGNEE FEEDBACK RULES
EOF
  fi

fi # end: workspace_agents writable check

# --- PostToolUse hook for skill execution logging ---
_claude_settings="/home/app/.claude/settings.json"
if [ -f "$_claude_settings" ]; then
  # Merge PostToolUse hook into existing settings
  if ! grep -q "log-skill-execution" "$_claude_settings" 2>/dev/null; then
    _tmp=$(mktemp)
    if node -e "
      const fs = require('fs');
      const s = JSON.parse(fs.readFileSync('$_claude_settings', 'utf8'));
      s.hooks = s.hooks || {};
      s.hooks.PostToolUse = s.hooks.PostToolUse || [];
      s.hooks.PostToolUse.push({ matcher: '', hooks: [{ type: 'command', command: 'node /app/data/hooks/log-skill-execution.js' }] });
      fs.writeFileSync('$_tmp', JSON.stringify(s, null, 2));
    " && mv "$_tmp" "$_claude_settings"; then
      echo "[entrypoint] PostToolUse hook wired into Claude Code settings"
    else
      rm -f "$_tmp"
      echo "[entrypoint] WARNING: failed to wire PostToolUse hook" >&2
    fi
  fi
else
  # Create minimal settings with hook
  cat >"$_claude_settings" <<'HOOKEOF'
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "node /app/data/hooks/log-skill-execution.js"
          }
        ]
      }
    ]
  }
}
HOOKEOF
  echo "[entrypoint] created Claude Code settings with PostToolUse hook"
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
  # On host bind mounts, skip if workspace is not writable.
  if [ -w "$workspace_dir" ]; then
    [ -L "$workspace_dir/skills/superpowers" ] && rm -f "$workspace_dir/skills/superpowers"
    mkdir -p "$workspace_dir/skills/superpowers"
    cp -rLf "$_sp_dir/skills/." "$workspace_dir/skills/superpowers/"
  else
    echo "[entrypoint] superpowers: workspace not writable; skipping skill copy"
  fi

  echo "[entrypoint] superpowers: wired to agents ($(git -C "$_sp_dir" rev-parse --short HEAD 2>/dev/null || echo 'unknown'))"
else
  echo "[WARN] superpowers: skills/ directory not found; skipping agent wiring"
fi

# Copy Claude Code skills into workspace so sandbox containers can read them.
# Sandbox only mounts /app/data/workspace/ → /workspace/; symlink targets
# outside that tree (/home/app/.claude/skills/) are invisible inside the sandbox.
claude_skills="/home/app/.claude/skills"
workspace_skills="$workspace_dir/skills"
if [ -d "$claude_skills" ] && [ -w "$workspace_dir" ]; then
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
elif [ -d "$claude_skills" ]; then
  echo "[entrypoint] claude-skills: workspace not writable; skipping skill copy"
fi

# --- Invalidate stale skill snapshots ---
# On container restart, new skills (e.g. superpowers) may have been added.
# OpenClaw caches a skills snapshot per session in sessions.json (version: 0).
# Snapshots with version 0 are never auto-refreshed (refresh requires version > 0).
# Removing skillsSnapshot from all session entries forces a fresh rebuild on next turn.
_sessions_dir="/home/app/.openclaw/agents"
if [ -d "$_sessions_dir" ]; then
  find "$_sessions_dir" -name "sessions.json" -type f 2>/dev/null | while read -r _sf; do
    if grep -q '"skillsSnapshot"' "$_sf" 2>/dev/null; then
      node -e "
        const fs = require('fs');
        const d = JSON.parse(fs.readFileSync('$_sf','utf-8'));
        let n = 0;
        for (const k of Object.keys(d)) { if (d[k].skillsSnapshot) { delete d[k].skillsSnapshot; n++; } }
        if (n > 0) { const tmp = '$_sf' + '.tmp.' + process.pid; fs.writeFileSync(tmp, JSON.stringify(d, null, 2)); fs.renameSync(tmp, '$_sf'); console.log('[entrypoint] invalidated', n, 'stale skill snapshots in', '$_sf'); }
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
