# Claude-first Entrypoint Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Change OpenClaw's child-session policy from Codex-first to Claude-first, add workspace git pull on startup, and add startup health check logging.

**Architecture:** All changes are in `docker/openclaw/entrypoint.sh`. Three features are added in order: workspace git pull (before AGENTS.md injection), Claude-first policy (replacing Codex-first injection), and health check logging (before `exec openclaw`). Tests in `docker/openclaw/tests/test-entrypoint.sh` are updated to match.

**Tech Stack:** POSIX shell (`/bin/sh`), sed, grep, git

**Spec:** `docs/superpowers/specs/2026-03-14-claude-first-entrypoint-design.md`

---

## Task 1: Add workspace git pull to entrypoint.sh

**Files:**

- Modify: `docker/openclaw/entrypoint.sh:107-108` (insert after lifelog sync, before AGENTS.md injection)

- [ ] **Step 1: Add git pull block after lifelog sync (line 107)**

Insert after line 107 (`fi` closing lifelog sync), before line 109 (`# Enforce Codex-first`):

```sh
# Pull latest workspace from remote (if it's a git repo with a remote).
# Runs before AGENTS.md creation guard so that pulled AGENTS.md is preserved.
if [ -d "$workspace_dir/.git" ] && git -C "$workspace_dir" remote get-url origin >/dev/null 2>&1; then
  if git -C "$workspace_dir" pull --ff-only 2>&1; then
    echo "[entrypoint] workspace: git pull ok ($(git -C "$workspace_dir" rev-parse --short HEAD))"
  else
    echo "[entrypoint] WARNING: workspace git pull failed — continuing with local state" >&2
  fi
fi
```

- [ ] **Step 2: Commit**

```bash
git add docker/openclaw/entrypoint.sh
git commit -m "feat(openclaw): add workspace git pull on startup"
```

---

## Task 2: Replace Codex-first with Claude-first policy in entrypoint.sh

**Files:**

- Modify: `docker/openclaw/entrypoint.sh:109-133` (the CODEX-FIRST injection block — line numbers shift after Task 1)

- [ ] **Step 1: Add old CODEX-FIRST block deletion logic**

After the AGENTS.md file creation guard (`if [ ! -f "$workspace_agents" ]; then ... fi`), before the CLAUDE-FIRST injection, insert:

```sh
# Remove legacy CODEX-FIRST block if present (migration from previous policy).
if grep -q "BEGIN OPENCLAW CODEX-FIRST RULES" "$workspace_agents" 2>/dev/null; then
  sed -i '/## BEGIN OPENCLAW CODEX-FIRST RULES/,/## END OPENCLAW CODEX-FIRST RULES/d' "$workspace_agents"
  echo "[entrypoint] removed legacy CODEX-FIRST policy block"
fi
```

- [ ] **Step 2: Replace the CODEX-FIRST injection with CLAUDE-FIRST**

Replace the existing block (lines 109-133 in the original file, approximately lines 118-142 after Task 1 insertion; the `if ! grep -q "BEGIN OPENCLAW CODEX-FIRST RULES"` block) with:

```sh
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
```

- [ ] **Step 3: Update the comment above the block**

Change:

```sh
# Enforce Codex-first child-session policy inside workspace instructions.
```

To:

```sh
# Enforce Claude-first child-session policy inside workspace instructions.
```

- [ ] **Step 4: Commit**

```bash
git add docker/openclaw/entrypoint.sh
git commit -m "feat(openclaw): replace Codex-first with Claude-first child-session policy"
```

---

## Task 3: Add startup health check logging to entrypoint.sh

**Files:**

- Modify: `docker/openclaw/entrypoint.sh` (insert before `exec openclaw "$@"`, the last line)

- [ ] **Step 1: Add health check block before exec**

Insert before the final `exec openclaw "$@"` line:

```sh
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

# 2. Agent policy block
if grep -q "BEGIN OPENCLAW CLAUDE-FIRST RULES" "$workspace_agents" 2>/dev/null; then
  echo "[entrypoint]   agent_policy: claude-first OK"
elif grep -q "BEGIN OPENCLAW CODEX-FIRST RULES" "$workspace_agents" 2>/dev/null; then
  echo "[entrypoint]   agent_policy: WARNING — codex-first still present"
else
  echo "[entrypoint]   agent_policy: WARNING — no policy block found"
fi

# 3. Old policy cleanup confirmation
if grep -q "CODEX-FIRST" "$workspace_agents" 2>/dev/null; then
  echo "[entrypoint]   old_policy_cleanup: FAILED — CODEX-FIRST remnants found"
else
  echo "[entrypoint]   old_policy_cleanup: clean"
fi

echo "[entrypoint] === END HEALTH ==="
```

- [ ] **Step 2: Commit**

```bash
git add docker/openclaw/entrypoint.sh
git commit -m "feat(openclaw): add startup health check logging"
```

---

## Task 4: Update tests for Claude-first policy

**Files:**

- Modify: `docker/openclaw/tests/test-entrypoint.sh`

- [ ] **Step 1: Update `run_agents_injection` function**

Replace the function body (lines 39-66) to match the new entrypoint logic:

1. Add CODEX-FIRST deletion logic (sed removal)
2. Replace CODEX-FIRST block content with CLAUDE-FIRST block content
3. Update grep guard from `"BEGIN OPENCLAW CODEX-FIRST RULES"` to `"BEGIN OPENCLAW CLAUDE-FIRST RULES"`

New `run_agents_injection` function:

```sh
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
```

- [ ] **Step 2: Update Test Suite 1 assertions**

Replace all `CODEX-FIRST` references in assertions with `CLAUDE-FIRST`:

```sh
assert "contains BEGIN marker" \
  'grep -q "BEGIN OPENCLAW CLAUDE-FIRST RULES" "$ws1/AGENTS.md"'

assert "contains END marker" \
  'grep -q "END OPENCLAW CLAUDE-FIRST RULES" "$ws1/AGENTS.md"'
```

Update idempotency test:

```sh
count_before=$(grep -c "BEGIN OPENCLAW CLAUDE-FIRST RULES" "$ws1/AGENTS.md")
run_agents_injection "$ws1"
count_after=$(grep -c "BEGIN OPENCLAW CLAUDE-FIRST RULES" "$ws1/AGENTS.md")

assert "idempotent: marker count unchanged after re-run ($count_before -> $count_after)" \
  '[ "$count_before" = "$count_after" ]'
```

Update existing-file test:

```sh
assert "appends rules to existing file" \
  'grep -q "BEGIN OPENCLAW CLAUDE-FIRST RULES" "$ws2/AGENTS.md"'
```

- [ ] **Step 3: Add migration test (CODEX-FIRST → CLAUDE-FIRST)**

Add after the existing-file test (before Test Suite 2):

```sh
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
```

- [ ] **Step 4: Run tests locally**

Run: `sh docker/openclaw/tests/test-entrypoint.sh`
Expected: All tests PASS (GitHub auth tests will be SKIPPED outside container)

- [ ] **Step 5: Commit**

```bash
git add docker/openclaw/tests/test-entrypoint.sh
git commit -m "test(openclaw): update tests for Claude-first policy and add migration test"
```

---

## Task 5: Final verification

- [ ] **Step 1: Review complete entrypoint.sh**

Read `docker/openclaw/entrypoint.sh` and verify:

1. git pull block is between lifelog sync and AGENTS.md injection
2. CODEX-FIRST deletion logic is after the creation guard, before CLAUDE-FIRST injection
3. CLAUDE-FIRST injection replaces CODEX-FIRST
4. Health check is before `exec openclaw`
5. No CODEX-FIRST references remain (except in deletion logic)

- [ ] **Step 2: Run full test suite**

Run: `sh docker/openclaw/tests/test-entrypoint.sh`
Expected: All tests PASS

- [ ] **Step 3: Commit (if any fixes needed)**

Only if fixes were applied during verification.
