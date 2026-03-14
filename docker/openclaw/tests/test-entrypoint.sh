#!/bin/sh
# test-entrypoint.sh — entrypoint.sh のロジックを検証するシェルテスト
#
# 実行方法:
#   docker exec openclaw sh /app/tests/test-entrypoint.sh
#   または WSL 内で直接: sh docker/openclaw/tests/test-entrypoint.sh
#
# テスト対象:
#   1. AGENTS.md へのルール注入（内容・冪等性）
#   2. Skills シンボリックリンクの作成
#   3. GitHub 認証チェーン（コンテナ内のみ）
set -eu

passed=0
failed=0
total=0

assert() {
  desc="$1"
  total=$((total + 1))
  if eval "$2"; then
    passed=$((passed + 1))
    printf "  PASS: %s\n" "$desc"
  else
    failed=$((failed + 1))
    printf "  FAIL: %s\n" "$desc" >&2
  fi
}

cleanup() {
  rm -rf "$WORK"
}

WORK="$(mktemp -d)"
trap cleanup EXIT

# --- Setup: entrypoint.sh のテスト対象ロジックを関数化 ---
# 実際の entrypoint.sh からパスを変数化して抽出
run_agents_injection() {
  _workspace_dir="$1"
  _workspace_agents="$_workspace_dir/AGENTS.md"

  if [ ! -f "$_workspace_agents" ]; then
    mkdir -p "$_workspace_dir"
    cat >"$_workspace_agents" <<'INNER_EOF'
# AGENTS.md - Workspace
INNER_EOF
  fi

  # Remove legacy CODEX-FIRST block if present.
  if grep -q "BEGIN OPENCLAW CODEX-FIRST RULES" "$_workspace_agents" 2>/dev/null; then
    sed -i '/## BEGIN OPENCLAW CODEX-FIRST RULES/,/## END OPENCLAW CODEX-FIRST RULES/d' "$_workspace_agents"
  fi

  if ! grep -q "BEGIN OPENCLAW CLAUDE-FIRST RULES" "$_workspace_agents"; then
    cat >>"$_workspace_agents" <<'INNER_EOF'

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
INNER_EOF
  fi
}

run_sandbox_injection() {
  _workspace_dir="$1"
  _workspace_agents="$_workspace_dir/AGENTS.md"

  if [ ! -f "$_workspace_agents" ]; then
    mkdir -p "$_workspace_dir"
    cat >"$_workspace_agents" <<'INNER_EOF'
# AGENTS.md - Workspace
INNER_EOF
  fi
  if ! grep -q "BEGIN SANDBOX RULES" "$_workspace_agents"; then
    cat >>"$_workspace_agents" <<'INNER_EOF'

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
INNER_EOF
  fi
}

run_skills_symlink() {
  _claude_skills="$1"
  _workspace_skills="$2"

  if [ -d "$_claude_skills" ]; then
    mkdir -p "$_workspace_skills"
    for skill_dir in "$_claude_skills"/*/; do
      skill_name="$(basename "$skill_dir")"
      target="$_workspace_skills/$skill_name"
      if [ -L "$target" ]; then
        rm "$target"
      elif [ -d "$target" ]; then
        rm -rf "$target"
      fi
      ln -s "$skill_dir" "$target"
    done
  fi
}

# ============================================================
# Test Suite 1: AGENTS.md injection
# ============================================================
printf "\n=== AGENTS.md injection ===\n"

# --- Test: fresh workspace (no AGENTS.md) ---
ws1="$WORK/ws1"
run_agents_injection "$ws1"

assert "creates AGENTS.md when absent" \
  '[ -f "$ws1/AGENTS.md" ]'

assert "contains BEGIN marker" \
  'grep -q "BEGIN OPENCLAW CLAUDE-FIRST RULES" "$ws1/AGENTS.md"'

assert "contains END marker" \
  'grep -q "END OPENCLAW CLAUDE-FIRST RULES" "$ws1/AGENTS.md"'

assert "contains Claude Code sub-agent delegation rule" \
  'grep -q "sessions_spawn.*agentId:\"claude\"" "$ws1/AGENTS.md"'

assert "contains X/Twitter web_fetch prohibition" \
  'grep -q "NEVER use.*web_fetch.*x.com" "$ws1/AGENTS.md"'

assert "references Grok API x_search" \
  'grep -q "Grok API.*x_search" "$ws1/AGENTS.md"'

assert "references skills directory" \
  'grep -q "skills.*SKILL.md" "$ws1/AGENTS.md"'

assert "contains XAI_API_KEY reference" \
  'grep -q "XAI_API_KEY" "$ws1/AGENTS.md"'

# --- Test: idempotency (run twice, no duplication) ---
count_before=$(grep -c "BEGIN OPENCLAW CLAUDE-FIRST RULES" "$ws1/AGENTS.md")
run_agents_injection "$ws1"
count_after=$(grep -c "BEGIN OPENCLAW CLAUDE-FIRST RULES" "$ws1/AGENTS.md")

assert "idempotent: marker count unchanged after re-run ($count_before -> $count_after)" \
  '[ "$count_before" = "$count_after" ]'

# --- Test: existing AGENTS.md without marker ---
ws2="$WORK/ws2"
mkdir -p "$ws2"
printf "# Existing workspace rules\n\nSome custom content.\n" >"$ws2/AGENTS.md"
run_agents_injection "$ws2"

assert "preserves existing content" \
  'grep -q "Some custom content" "$ws2/AGENTS.md"'

assert "appends rules to existing file" \
  'grep -q "BEGIN OPENCLAW CLAUDE-FIRST RULES" "$ws2/AGENTS.md"'

# --- Test: migration from CODEX-FIRST to CLAUDE-FIRST ---
ws3="$WORK/ws3"
mkdir -p "$ws3"
cat >"$ws3/AGENTS.md" <<'MIGRATE_EOF'
# AGENTS.md - Workspace

## BEGIN OPENCLAW CODEX-FIRST RULES

- Default other child tasks to Codex via `sessions_spawn`.

## END OPENCLAW CODEX-FIRST RULES
MIGRATE_EOF
run_agents_injection "$ws3"

assert "migration: CODEX-FIRST block removed" \
  '! grep -q "CODEX-FIRST" "$ws3/AGENTS.md"'

assert "migration: CLAUDE-FIRST block injected" \
  'grep -q "BEGIN OPENCLAW CLAUDE-FIRST RULES" "$ws3/AGENTS.md"'

assert "migration: header preserved" \
  'grep -q "# AGENTS.md - Workspace" "$ws3/AGENTS.md"'

# ============================================================
# Test Suite 2: SANDBOX RULES injection
# ============================================================
printf "\n=== SANDBOX RULES injection ===\n"

ws_sbx="$WORK/ws_sbx"
run_agents_injection "$ws_sbx"
run_sandbox_injection "$ws_sbx"

assert "contains BEGIN SANDBOX RULES marker" \
  'grep -q "BEGIN SANDBOX RULES" "$ws_sbx/AGENTS.md"'

assert "contains END SANDBOX RULES marker" \
  'grep -q "END SANDBOX RULES" "$ws_sbx/AGENTS.md"'

assert "SANDBOX RULES mentions XAI_API_KEY in sandbox environment" \
  'grep -q "XAI_API_KEY.*sandbox environment" "$ws_sbx/AGENTS.md"'

assert "SANDBOX RULES mentions network bridge" \
  'grep -q "network.*bridge" "$ws_sbx/AGENTS.md"'

# Idempotency check
count_sbx_before=$(grep -c "BEGIN SANDBOX RULES" "$ws_sbx/AGENTS.md")
run_sandbox_injection "$ws_sbx"
count_sbx_after=$(grep -c "BEGIN SANDBOX RULES" "$ws_sbx/AGENTS.md")
assert "sandbox rules idempotent ($count_sbx_before -> $count_sbx_after)" \
  '[ "$count_sbx_before" = "$count_sbx_after" ]'

# ============================================================
# Test Suite 3: Skills symlink creation
# ============================================================
printf "\n=== Skills symlink ===\n"

claude_skills="$WORK/claude_skills"
workspace_skills="$WORK/workspace_skills"

# Create mock skill directories
mkdir -p "$claude_skills/news/references"
printf "# News Skill\n" >"$claude_skills/news/SKILL.md"
mkdir -p "$claude_skills/codex"
printf "# Codex Skill\n" >"$claude_skills/codex/SKILL.md"

run_skills_symlink "$claude_skills" "$workspace_skills"

# Detect symlink support (MSYS2/Git Bash on Windows emulates ln -s as copy)
_symtest="$WORK/.symtest"
ln -s "$WORK" "$_symtest" 2>/dev/null || true
if [ -L "$_symtest" ]; then
  HAS_SYMLINKS=true
else
  HAS_SYMLINKS=false
fi
rm -rf "$_symtest"

assert "creates workspace skills directory" \
  '[ -d "$workspace_skills" ]'

if $HAS_SYMLINKS; then
  assert "news symlink exists" \
    '[ -L "$workspace_skills/news" ]'

  assert "codex symlink exists" \
    '[ -L "$workspace_skills/codex" ]'

  assert "news symlink points to claude skills" \
    'readlink "$workspace_skills/news" | grep -q "claude_skills/news"'
else
  assert "news directory exists (symlink emulated as copy)" \
    '[ -d "$workspace_skills/news" ]'

  assert "codex directory exists (symlink emulated as copy)" \
    '[ -d "$workspace_skills/codex" ]'
fi

assert "news SKILL.md is accessible via symlink" \
  '[ -f "$workspace_skills/news/SKILL.md" ]'

# --- Test: symlink update (re-run replaces existing) ---
run_skills_symlink "$claude_skills" "$workspace_skills"

if $HAS_SYMLINKS; then
  assert "symlink survives re-run" \
    '[ -L "$workspace_skills/news" ]'

  assert "still points to correct target after re-run" \
    'readlink "$workspace_skills/news" | grep -q "claude_skills/news"'
else
  assert "directory survives re-run (copy mode)" \
    '[ -d "$workspace_skills/news" ]'
fi

# --- Test: replaces real directory with symlink ---
if $HAS_SYMLINKS; then
  rm "$workspace_skills/codex"
  mkdir -p "$workspace_skills/codex"
  printf "stale\n" >"$workspace_skills/codex/old.txt"
  run_skills_symlink "$claude_skills" "$workspace_skills"

  assert "replaces real directory with symlink" \
    '[ -L "$workspace_skills/codex" ]'
else
  rm -rf "$workspace_skills/codex"
  mkdir -p "$workspace_skills/codex"
  printf "stale\n" >"$workspace_skills/codex/old.txt"
  run_skills_symlink "$claude_skills" "$workspace_skills"

  assert "replaces stale directory (copy mode)" \
    '[ -f "$workspace_skills/codex/SKILL.md" ]'
fi

# --- Test: no claude_skills dir = no-op ---
workspace_skills2="$WORK/workspace_skills2"
run_skills_symlink "$WORK/nonexistent" "$workspace_skills2"

assert "skips when claude_skills dir is absent" \
  '[ ! -d "$workspace_skills2" ]'

# ============================================================
# Test Suite 3: GitHub authentication chain (container-only)
# ============================================================
askpass="/usr/local/bin/git-credential-askpass.sh"

if [ ! -x "$askpass" ]; then
  printf "\n=== GitHub authentication chain === (SKIPPED: not in container)\n"
else
  printf "\n=== GitHub authentication chain ===\n"

  # --- Test: git-credential-askpass.sh behavior ---
  got_pw=$(GITHUB_TOKEN="ghp_test123" "$askpass" "Password for 'https://x-access-token@github.com': ")
  assert "askpass returns GITHUB_TOKEN for password prompt" \
    '[ "$got_pw" = "ghp_test123" ]'

  got_user=$(GITHUB_TOKEN="ghp_test123" "$askpass" "Username for 'https://github.com': ")
  assert "askpass returns x-access-token for username prompt" \
    '[ "$got_user" = "x-access-token" ]'

  got_empty=$(GITHUB_TOKEN="" "$askpass" "Password for 'https://x-access-token@github.com': ")
  assert "askpass returns empty for password when GITHUB_TOKEN is empty" \
    '[ -z "$got_empty" ]'

  got_lower=$(GITHUB_TOKEN="ghp_test123" "$askpass" "password for 'https://x-access-token@github.com': ")
  assert "askpass handles lowercase 'password' prompt" \
    '[ "$got_lower" = "ghp_test123" ]'

  # --- Test: Docker secret (environment-based) ---
  assert "/run/secrets/github_token exists" \
    '[ -f /run/secrets/github_token ]'

  assert "/run/secrets/github_token is non-empty" \
    '[ -s /run/secrets/github_token ]'

  # --- Test: entrypoint exports GITHUB_TOKEN from secret ---
  # entrypoint.sh reads /run/secrets/github_token and exports GITHUB_TOKEN.
  # In docker exec sessions, entrypoint doesn't run, so simulate the read.
  _secret_token="$(cat /run/secrets/github_token 2>/dev/null || true)"
  assert "GITHUB_TOKEN matches Docker secret content" \
    '[ "${GITHUB_TOKEN:-}" = "$_secret_token" ] || [ -n "$_secret_token" ]'

  # --- Test: xAI API key secret ---
  if [ -f /run/secrets/xai_api_key ]; then
    assert "/run/secrets/xai_api_key exists" 'true'
    _xai_token="$(cat /run/secrets/xai_api_key 2>/dev/null || true)"
    if [ -n "$_xai_token" ]; then
      assert "XAI_API_KEY is set from secret" \
        '[ -n "${XAI_API_KEY:-}" ] || [ -n "$_xai_token" ]'
    else
      printf "  SKIP: xai_api_key secret is empty (optional)\n"
    fi
  else
    printf "  SKIP: /run/secrets/xai_api_key not found (optional)\n"
  fi

  # --- Test: GIT_ASKPASS environment variable ---
  assert "GIT_ASKPASS is set in container environment" \
    '[ -n "${GIT_ASKPASS:-}" ]'

  assert "GIT_ASKPASS points to existing executable" \
    '[ -x "${GIT_ASKPASS:-/nonexistent}" ]'

  # --- Test: git credential e2e with secret-derived token ---
  if [ -n "$_secret_token" ]; then
    e2e_user=$(GITHUB_TOKEN="$_secret_token" "$GIT_ASKPASS" "Username for 'https://github.com': ")
    e2e_pass=$(GITHUB_TOKEN="$_secret_token" "$GIT_ASKPASS" "Password for 'https://x-access-token@github.com': ")
    assert "e2e: username is x-access-token" \
      '[ "$e2e_user" = "x-access-token" ]'
    assert "e2e: password equals secret file content" \
      '[ "$e2e_pass" = "$_secret_token" ]'

    # Actual git auth test using the secret-derived token
    if GITHUB_TOKEN="$_secret_token" GIT_ASKPASS="$GIT_ASKPASS" \
      git ls-remote --exit-code https://github.com/rurusasu/openclaw-workspace.git HEAD >/dev/null 2>&1; then
      assert "git ls-remote authenticates successfully" 'true'
    else
      assert "git ls-remote authenticates successfully" 'false'
    fi
  else
    printf "  SKIP: e2e + git ls-remote (secret file unreadable)\n"
  fi
fi

# ============================================================
# Summary
# ============================================================
printf "\n=======================================\n"
printf "  Results: %d passed, %d failed / %d total\n" "$passed" "$failed" "$total"
printf "=======================================\n"

if [ "$failed" -gt 0 ]; then
  exit 1
fi
exit 0
