# Sandbox XAI API Key Injection & Secret Policy — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable xAI Grok API access from OpenClaw sandbox containers and establish a documented secret injection policy.

**Architecture:** Add `XAI_API_KEY` to the sandbox env block in the chezmoi config template (uses existing `@@PLACEHOLDER@@` sed substitution). Update AGENTS.md to correct stale `network: "none"` references and add a secret policy section. Update entrypoint.sh's SANDBOX RULES heredoc.

**Tech Stack:** chezmoi templates (JSON), shell scripts (entrypoint.sh), Markdown (AGENTS.md)

**Spec:** `docs/superpowers/specs/2026-03-13-sandbox-xai-secret-policy-design.md`

---

## Chunk 1: Config & Entrypoint Changes

### Task 1: Add XAI_API_KEY to sandbox env in config template

**Files:**

- Modify: `chezmoi/dot_openclaw/openclaw.docker.json.tmpl:79-86`

- [ ] **Step 1: Add XAI_API_KEY to sandbox env block**

In `chezmoi/dot_openclaw/openclaw.docker.json.tmpl`, locate the `"env"` object inside `agents.defaults.sandbox.docker` (lines 79-86). Add `"XAI_API_KEY": "@@XAI_API_KEY@@"` after the `"GH_TOKEN"` line:

```json
          "env": {
            "GITHUB_TOKEN": "@@GITHUB_TOKEN@@",
            "GH_TOKEN": "@@GITHUB_TOKEN@@",
            "XAI_API_KEY": "@@XAI_API_KEY@@",
            "PLAYWRIGHT_BROWSERS_PATH": "/root/.cache/ms-playwright",
```

No changes to `entrypoint.sh` are needed — the existing sed at line 41 already handles `@@XAI_API_KEY@@` substitution:

```
sed -e "s|@@GITHUB_TOKEN@@|${GITHUB_TOKEN}|g" -e "s|@@XAI_API_KEY@@|${XAI_API_KEY:-}|g" ...
```

- [ ] **Step 2: Verify the template is valid JSON (minus chezmoi directives)**

Run:

```bash
chezmoi execute-template < chezmoi/dot_openclaw/openclaw.docker.json.tmpl 2>&1 | head -5
```

Expected: no JSON syntax errors (chezmoi template errors about missing data are OK).

- [ ] **Step 3: Commit**

```bash
git add chezmoi/dot_openclaw/openclaw.docker.json.tmpl
git commit -m "fix(openclaw): add XAI_API_KEY to sandbox env for Grok API access"
```

### Task 2: Update SANDBOX RULES heredoc in entrypoint.sh

**Files:**

- Modify: `docker/openclaw/entrypoint.sh:143`

- [ ] **Step 1: Add XAI_API_KEY availability line to SANDBOX RULES heredoc**

In `docker/openclaw/entrypoint.sh`, find the SANDBOX RULES heredoc (line 136-155). After line 143 (`Sandbox containers use network: "bridge"...`), add:

```
- `$XAI_API_KEY` is available in the sandbox environment for Grok API calls (`x_search`). Use `curl` with this key for X/Twitter content retrieval.
```

The CODEX-FIRST RULES block (line 125) already mentions `$XAI_API_KEY` — no change needed there.

- [ ] **Step 2: Add SANDBOX RULES injection function and tests to test-entrypoint.sh**

In `docker/openclaw/tests/test-entrypoint.sh`, the existing `run_agents_injection` function only injects CODEX-FIRST RULES. The SANDBOX RULES heredoc (entrypoint.sh L136-155) is a separate injection. Add a new `run_sandbox_injection` function that mirrors the SANDBOX RULES heredoc from entrypoint.sh (including the new `XAI_API_KEY` line), and add test assertions.

After the `run_agents_injection` function (line 66), add:

```bash
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
```

After the existing CODEX-FIRST test assertions (around line 138, after the idempotency tests), add a new test suite section:

```bash
# --- Test: SANDBOX RULES injection ---
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
```

- [ ] **Step 3: Commit**

```bash
git add docker/openclaw/entrypoint.sh docker/openclaw/tests/test-entrypoint.sh
git commit -m "docs(openclaw): document XAI_API_KEY availability in sandbox rules"
```

## Chunk 2: AGENTS.md Documentation Fixes

### Task 3: Fix stale network references in AGENTS.md

**Files:**

- Modify: `docker/openclaw/AGENTS.md:66,422,432,433,486`

- [ ] **Step 1: Fix description text at L66**

Change:

```
sandbox コンテナの隔離は `agents.defaults.sandbox.docker` 設定（`network: "none"` 等）で制御する。
```

To:

```
sandbox コンテナの隔離は `agents.defaults.sandbox.docker` 設定（`network: "bridge"` 等）で制御する。
```

- [ ] **Step 2: Fix JSON code block at L422**

Change:

```
    "network": "none"
```

To:

```
    "network": "bridge"
```

- [ ] **Step 3: Fix security bullet at L432**

Change:

```
- sandbox コンテナは `network: "none"`（外部通信不可）
```

To:

```
- sandbox コンテナは `network: "bridge"`（外部通信可能 — Playwright E2E、API 呼び出し等に必要）
```

- [ ] **Step 4: Fix security bullet at L433**

Change:

```
- sandbox コンテナにシークレットは注入されない
```

To:

```
- sandbox コンテナに注入するシークレットは許可リストで管理する（下記「Sandbox シークレットポリシー」参照）
```

- [ ] **Step 5: Fix troubleshooting section at L486**

Change:

```
- sandbox 内でパッケージインストールが失敗
  - `docker.network: "none"` のためネットワーク不可
  - `docker.setupCommand` で事前インストールするか、カスタムイメージを使う
```

To:

```
- sandbox 内でパッケージインストールが失敗
  - sandbox イメージにプリインストールされていないパッケージは `docker.setupCommand` で事前インストールするか、カスタムイメージを使う
```

- [ ] **Step 6: Commit**

```bash
git add docker/openclaw/AGENTS.md
git commit -m "docs(openclaw): fix stale network:none references in AGENTS.md"
```

### Task 4: Add Sandbox Secret Policy section to AGENTS.md

**Files:**

- Modify: `docker/openclaw/AGENTS.md` (after line ~491, before the final line)

- [ ] **Step 1: Add the policy section**

Insert the following after the `参照:` / `- https://docs.openclaw.ai/gateway/sandboxing` line at the end of the sandbox section:

```markdown
### Sandbox シークレットポリシー

sandbox コンテナに注入するシークレットはホワイトリスト方式で管理する。

#### 判断基準（2条件の AND）

1. **必要性**: sandbox 内のツール実行で必要であること
2. **スコープ**: read-only または限定スコープの API キーであること

#### 許可リスト（sandbox env に渡すもの）

| キー                        | 用途                  | スコープ              | 判断理由                                    |
| --------------------------- | --------------------- | --------------------- | ------------------------------------------- |
| `GITHUB_TOKEN` / `GH_TOKEN` | git clone, gh CLI     | repo read/write       | sandbox のコア操作に必須                    |
| `XAI_API_KEY`               | Grok API（X投稿取得） | read-only（x_search） | sandbox 内 curl で必要 + read-only スコープ |

#### 拒否リスト（絶対に sandbox に渡さないもの）

| キー                                 | 理由                                                 |
| ------------------------------------ | ---------------------------------------------------- |
| Telegram bot token                   | メッセージ送信権限を持つ。sandbox に不要             |
| Slack bot/app token                  | チャネル投稿・読み取り権限を持つ。sandbox に不要     |
| Gateway auth token                   | Gateway 管理権限。sandbox に渡すと自身を操作可能     |
| 1Password サービスアカウントトークン | 全シークレットへのアクセス権。sandbox に渡すのは論外 |

#### 新しいキーを追加するときのチェックリスト

1. sandbox 内のツール実行で本当に必要か？（Gateway 側で処理できないか）
2. キーのスコープは read-only or 限定的か？
3. 拒否リストに該当しないか？
4. `openclaw.docker.json.tmpl` の env + この許可リスト両方を更新したか？
```

- [ ] **Step 2: Commit**

```bash
git add docker/openclaw/AGENTS.md
git commit -m "docs(openclaw): add sandbox secret injection policy to AGENTS.md"
```

### Task 5: Final validation

- [ ] **Step 1: Run task commit to verify all lints and tests pass**

```bash
task commit
```

Expected: all tests pass, lint/fmt clean.

- [ ] **Step 2: Verify the changes end-to-end**

```bash
# Check the template has XAI_API_KEY in sandbox env
grep -A2 "GH_TOKEN" chezmoi/dot_openclaw/openclaw.docker.json.tmpl | grep XAI_API_KEY

# Check AGENTS.md has no remaining "none" in sandbox network context (L473 Playwright section is OK - it mentions "none" only as contrast)
grep -n 'network.*"none"' docker/openclaw/AGENTS.md
# Expected: only L473 (Playwright section: `"none"` では不可) should remain

# Check entrypoint SANDBOX RULES mentions XAI_API_KEY
grep 'XAI_API_KEY.*sandbox' docker/openclaw/entrypoint.sh
```
