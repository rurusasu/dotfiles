# OpenClaw Superpowers Integration Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** OpenClaw コンテナ内の全エージェント（Codex, Claude Code, Gemini CLI）に obra/superpowers スキルフレームワークを搭載し、再起動時に自動更新する仕組みを構築する。

**Architecture:** entrypoint.sh で `/app/data/superpowers` に obra/superpowers を shallow clone し、各エージェントのスキル検出パスにシンボリックリンクで配線する。再起動時は `git pull --ff-only` で自動更新。clone/pull の失敗は非致命的（WARN ログで続行）。

**Tech Stack:** Shell script (POSIX sh), Docker Compose, Git

**Spec:** `docs/superpowers/specs/2026-03-14-openclaw-superpowers-design.md`

---

## Chunk 1: Infrastructure + Entrypoint

### Task 1: docker-compose.yml に tmpfs 追加

コンテナは `read_only: true` で動作するため、Codex/OpenCode のスキル検出パス `~/.agents/` を書き込み可能にする tmpfs が必要。

**Files:**

- Modify: `docker/openclaw/docker-compose.yml:26-27`

- [ ] **Step 1: tmpfs に ~/.agents 追加**

`docker/openclaw/docker-compose.yml` の既存 tmpfs セクションに1行追加:

```yaml
tmpfs:
  - /tmp:size=64m,mode=1777
  - /home/bun/.agents:size=1m,mode=0755
```

- [ ] **Step 2: Commit**

```bash
git add docker/openclaw/docker-compose.yml
git commit -m "feat(openclaw): add tmpfs for ~/.agents skill discovery path"
```

---

### Task 2: entrypoint.sh に superpowers clone/pull セクション追加

`# Symlink Claude Code skills into workspace` セクション（L175）の前に superpowers の clone/pull + 配線ロジックを追加する。

**Files:**

- Modify: `docker/openclaw/entrypoint.sh` (L174 の前に挿入)

- [ ] **Step 1: superpowers clone/pull セクションを追加**

`# Symlink Claude Code skills into workspace` コメント（L175）の直前に以下を挿入:

```sh
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

  # Workspace skills (alongside existing Claude skills symlinks)
  mkdir -p "$workspace_dir/skills"
  ln -sfn "$_sp_dir/skills" "$workspace_dir/skills/superpowers"

  echo "[entrypoint] superpowers: wired to agents ($(git -C "$_sp_dir" rev-parse --short HEAD 2>/dev/null || echo 'unknown'))"
else
  echo "[WARN] superpowers: skills/ directory not found; skipping agent wiring"
fi
```

- [ ] **Step 2: startup health summary に superpowers ステータスを追加**

`# --- Startup health summary ---` セクション内（`# 2. Agent policy block` の前）に以下を追加:

```sh
# 2. Superpowers status
if [ -d "/app/data/superpowers/skills" ]; then
  _sp_rev="$(git -C /app/data/superpowers rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
  echo "[entrypoint]   superpowers: rev=$_sp_rev"
else
  echo "[entrypoint]   superpowers: not available"
fi
```

既存の `# 2. Agent policy block` と `# 3. Old policy cleanup` のコメント番号をそれぞれ `# 3.` と `# 4.` に更新する。

- [ ] **Step 3: Commit**

```bash
git add docker/openclaw/entrypoint.sh
git commit -m "feat(openclaw): add superpowers clone/pull and agent wiring in entrypoint"
```

---

## Chunk 2: Tests

### Task 3: test-entrypoint.sh に superpowers 配線テストを追加

テストでは git clone/pull は実行せず、ダミーの superpowers ディレクトリを作成して配線ロジックのみを検証する（既存の skills symlink テストと同じパターン）。

**Files:**

- Modify: `docker/openclaw/tests/test-entrypoint.sh`

- [ ] **Step 1: superpowers 配線の関数を追加**

既存の `run_skills_symlink` 関数の後（L124 付近）に以下を追加:

```sh
run_superpowers_wiring() {
  _sp_dir="$1"
  _home="$2"
  _workspace_dir="$3"

  if [ -d "$_sp_dir/skills" ]; then
    mkdir -p "$_home/.agents/skills"
    ln -sfn "$_sp_dir/skills" "$_home/.agents/skills/superpowers"

    mkdir -p "$_home/.gemini/extensions"
    ln -sfn "$_sp_dir" "$_home/.gemini/extensions/superpowers"

    mkdir -p "$_workspace_dir/skills"
    ln -sfn "$_sp_dir/skills" "$_workspace_dir/skills/superpowers"
  fi
}
```

- [ ] **Step 2: Test Suite 4（superpowers 配線テスト）を追加**

Test Suite 3 の GitHub authentication chain の前（L319 付近、`# ============================================================` の前）に以下を追加:

```sh
# ============================================================
# Test Suite 4: Superpowers wiring
# ============================================================
printf "\n=== Superpowers wiring ===\n"

# --- Setup: create dummy superpowers repo structure ---
sp_dir="$WORK/superpowers"
sp_home="$WORK/sp_home"
sp_workspace="$WORK/sp_workspace"
mkdir -p "$sp_dir/skills/brainstorming"
printf "# Brainstorming\n" >"$sp_dir/skills/brainstorming/SKILL.md"
mkdir -p "$sp_dir/skills/writing-plans"
printf "# Writing Plans\n" >"$sp_dir/skills/writing-plans/SKILL.md"
mkdir -p "$sp_dir/docs"
printf "# README\n" >"$sp_dir/docs/README.md"

run_superpowers_wiring "$sp_dir" "$sp_home" "$sp_workspace"

if $HAS_SYMLINKS; then
  assert "agents/skills/superpowers symlink exists" \
    '[ -L "$sp_home/.agents/skills/superpowers" ]'

  assert "agents/skills/superpowers points to skills/" \
    'readlink "$sp_home/.agents/skills/superpowers" | grep -q "superpowers/skills"'

  assert "gemini/extensions/superpowers symlink exists" \
    '[ -L "$sp_home/.gemini/extensions/superpowers" ]'

  assert "gemini/extensions/superpowers points to full repo (not skills/)" \
    'readlink "$sp_home/.gemini/extensions/superpowers" | grep -q "superpowers$"'

  assert "workspace/skills/superpowers symlink exists" \
    '[ -L "$sp_workspace/skills/superpowers" ]'
else
  assert "agents/skills/superpowers dir exists (copy mode)" \
    '[ -d "$sp_home/.agents/skills/superpowers" ]'

  assert "gemini/extensions/superpowers dir exists (copy mode)" \
    '[ -d "$sp_home/.gemini/extensions/superpowers" ]'

  assert "workspace/skills/superpowers dir exists (copy mode)" \
    '[ -d "$sp_workspace/skills/superpowers" ]'
fi

assert "superpowers SKILL.md accessible via agents path" \
  '[ -f "$sp_home/.agents/skills/superpowers/brainstorming/SKILL.md" ]'

assert "superpowers SKILL.md accessible via workspace path" \
  '[ -f "$sp_workspace/skills/superpowers/brainstorming/SKILL.md" ]'

assert "gemini extension has full repo (docs/ visible)" \
  '[ -f "$sp_home/.gemini/extensions/superpowers/docs/README.md" ]'

# --- Test: idempotency (re-run updates symlinks) ---
run_superpowers_wiring "$sp_dir" "$sp_home" "$sp_workspace"

if $HAS_SYMLINKS; then
  assert "agents symlink survives re-run" \
    '[ -L "$sp_home/.agents/skills/superpowers" ]'
else
  assert "agents dir survives re-run (copy mode)" \
    '[ -d "$sp_home/.agents/skills/superpowers" ]'
fi

assert "SKILL.md still accessible after re-run" \
  '[ -f "$sp_home/.agents/skills/superpowers/brainstorming/SKILL.md" ]'

# --- Test: no skills dir = no-op ---
sp_empty="$WORK/sp_empty"
sp_home2="$WORK/sp_home2"
sp_ws2="$WORK/sp_ws2"
mkdir -p "$sp_empty"

run_superpowers_wiring "$sp_empty" "$sp_home2" "$sp_ws2"

assert "skips wiring when skills/ dir is absent" \
  '[ ! -d "$sp_home2/.agents" ]'

# --- Test: .git exists but skills/ missing (corrupted clone) ---
sp_corrupt="$WORK/sp_corrupt"
sp_home3="$WORK/sp_home3"
sp_ws3="$WORK/sp_ws3"
mkdir -p "$sp_corrupt/.git"

run_superpowers_wiring "$sp_corrupt" "$sp_home3" "$sp_ws3"

assert "skips wiring when .git exists but skills/ is absent" \
  '[ ! -d "$sp_home3/.agents" ]'
```

- [ ] **Step 3: Test Suite 番号の修正**

既存の `# Test Suite 3: GitHub authentication chain` のコメントを `# Test Suite 5: GitHub authentication chain` に変更。

- [ ] **Step 4: テストをローカルで実行して確認**

Run: `bash docker/openclaw/tests/test-entrypoint.sh`
Expected: 全テスト PASS（GitHub authentication chain は SKIPPED）

- [ ] **Step 5: Commit**

```bash
git add docker/openclaw/tests/test-entrypoint.sh
git commit -m "test(openclaw): add superpowers wiring tests"
```

---

## Chunk 3: Documentation

### Task 4: AGENTS.md に superpowers セクションと新エージェント追加手順を追加

**Files:**

- Modify: `docker/openclaw/AGENTS.md`

- [ ] **Step 1: superpowers セクションを追加**

`## スキルとサブエージェント` セクション（L267 付近）の末尾、`### スキル変更のコミット手順` の前に以下を追加:

````markdown
### Superpowers（obra/superpowers）

[obra/superpowers](https://github.com/obra/superpowers) スキルフレームワークがコンテナ内の全エージェントに自動配信される。

**仕組み:**

- `entrypoint.sh` が `/app/data/superpowers` に `obra/superpowers` を shallow clone
- 各エージェントのスキル検出パスにシンボリックリンクで配線:

| エージェント     | 検出パス                                             | リンク対象     |
| ---------------- | ---------------------------------------------------- | -------------- |
| Codex / OpenCode | `~/.agents/skills/superpowers`                       | `skills/`      |
| Gemini CLI       | `~/.gemini/extensions/superpowers`                   | リポジトリ全体 |
| Claude Code      | ホスト側 marketplace plugin がマウント経由で利用可能 |
| Workspace 経由   | `/app/data/workspace/skills/superpowers`             | `skills/`      |

**更新:**

- コンテナ再起動時に `git pull --ff-only` で自動更新
- pull 失敗時はキャッシュ版で続行（コンテナ起動を妨げない）

**新しい ACP エージェントに superpowers を追加する手順:**

1. そのエージェントのスキル検出パスを確認（公式ドキュメントまたは obra/superpowers の README 参照）
2. `entrypoint.sh` の `# --- Superpowers: wire to agent skill-discovery paths ---` セクションに追加:

```sh
# <AgentName>
mkdir -p "$HOME/<agent-config-dir>"
ln -sfn "$_sp_dir/skills" "$HOME/<agent-config-dir>/superpowers"
```
````

3. 検出パスが read-only FS 上の場合、`docker-compose.yml` の tmpfs に追加:

```yaml
tmpfs:
  - /home/bun/<agent-config-dir>:size=1m,mode=0755
```

4. Gemini CLI のようにリポジトリ全体を期待するエージェントは `$_sp_dir` をリンク（`$_sp_dir/skills` ではなく）
5. `tests/test-entrypoint.sh` の `run_superpowers_wiring` にリンク先を追加しテストを更新

````

- [ ] **Step 2: Commit**

```bash
git add docker/openclaw/AGENTS.md
git commit -m "docs(openclaw): add superpowers section and new agent wiring guide to AGENTS.md"
````

---

### Task 5: コンテナ内テスト実行で最終確認

- [ ] **Step 1: イメージを再ビルドしてテスト実行**

```bash
cd docker/openclaw
docker compose build
docker compose run --rm openclaw sh /app/tests/test-entrypoint.sh
```

Expected: 全テスト PASS

- [ ] **Step 2: コンテナ起動して entrypoint ログ確認**

```bash
docker compose up -d
docker compose logs openclaw | grep superpowers
```

Expected:

```
[entrypoint] superpowers: cloning...
[entrypoint] superpowers: wired to agents (abc1234)
[entrypoint]   superpowers: rev=abc1234
```

- [ ] **Step 3: symlink 配線を手動確認**

```bash
docker exec openclaw ls -la /home/bun/.agents/skills/superpowers
docker exec openclaw ls -la /home/bun/.gemini/extensions/superpowers
docker exec openclaw ls -la /app/data/workspace/skills/superpowers
```

Expected: 3箇所すべてが `/app/data/superpowers` (または `skills/`) へのシンボリックリンク
