# OpenClaw entrypoint.sh: Claude-first ポリシー + workspace pull + ヘルスチェック

## 概要

OpenClaw の `entrypoint.sh` に3つの機能を追加する:

1. **Claude-first ポリシー**: 子セッションのデフォルトエージェントを Codex → Claude Code に変更
2. **workspace git pull**: 起動時に `openclaw-workspace` リポジトリの最新を pull
3. **ヘルスチェックログ**: 上記が正常動作したかを起動時に確認・出力

## 背景

- OpenClaw の main エージェント（Codex）は ToS 上そのまま維持する必要がある
- Claude Code は ACP 経由（`sessions_spawn(runtime:"acp", agentId:"claude")`）で呼び出すことで、Claude Code CLI の正規 OAuth 認証を使い ToS に準拠する
- 現在の CODEX-FIRST ポリシーでは子タスクがデフォルトで Codex に振られるが、品質と安定性の観点から Claude Code をデフォルトにしたい

## 変更ファイル

`docker/openclaw/entrypoint.sh` のみ

## 設計

### 処理順序

```
lifelog sync
  ↓
workspace git pull (新規)
  ↓
AGENTS.md ファイル作成ガード (既存: ファイルが無ければ作成)
  ↓
旧 CODEX-FIRST ブロック削除 (新規)
  ↓
CLAUDE-FIRST ブロック注入 (新規: 既存の CODEX-FIRST 注入を置換)
  ↓
SANDBOX RULES 注入 (既存)
  ↓
skills symlink (既存)
  ↓
ヘルスチェックログ (新規)
  ↓
exec openclaw
```

**重要**: git pull は AGENTS.md ファイル作成ガードの前に実行する。pull でリポジトリから AGENTS.md を取得できれば、作成ガードはスキップされる。

### 1. Claude-first ポリシー

#### 旧ブロックの削除

起動時に `BEGIN OPENCLAW CODEX-FIRST RULES` 〜 `END OPENCLAW CODEX-FIRST RULES` が AGENTS.md に存在すれば `sed` で削除する。既存コンテナの volume に前回起動時のブロックが残っている場合に対応するための処理。旧ブロックが存在しない場合（クリーンブートなど）は no-op。

```sh
# Remove legacy CODEX-FIRST block if present (migration from previous policy).
if grep -q "BEGIN OPENCLAW CODEX-FIRST RULES" "$workspace_agents" 2>/dev/null; then
  sed -i '/## BEGIN OPENCLAW CODEX-FIRST RULES/,/## END OPENCLAW CODEX-FIRST RULES/d' "$workspace_agents"
  echo "[entrypoint] removed legacy CODEX-FIRST policy block"
fi
```

#### 新ブロックの注入

`BEGIN OPENCLAW CLAUDE-FIRST RULES` が無ければ以下を追記:

```
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
```

### 2. workspace git pull

**配置**: lifelog sync の後、AGENTS.md ファイル作成ガードの前

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

設計方針:

- `--ff-only`（ブランチ指定なし）: 現在チェックアウト中のブランチをそのまま pull する。main 以外のブランチにも対応
- `--ff-only` は fast-forward 不可能な場合（コンフリクト、diverged history）に失敗する。ローカルに未コミットの変更がある場合も同様に失敗する
- 失敗しても起動を止めない（WARNING を出して既存のローカル状態で継続）
- remote がなければスキップ（非 git 環境への対応）

### 3. ヘルスチェックログ

**配置**: `exec openclaw "$@"` の直前

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

確認項目:

1. **workspace の git 状態** — rev と未コミットファイル数
2. **Claude-first ポリシーの注入確認** — 新ブロックが存在するか
3. **旧 CODEX-FIRST ブロックの削除確認** — 残骸が無いか

正常時の出力例:

```
[entrypoint] === STARTUP HEALTH ===
[entrypoint]   workspace: rev=b3d4246 dirty_files=0
[entrypoint]   agent_policy: claude-first OK
[entrypoint]   old_policy_cleanup: clean
[entrypoint] === END HEALTH ===
```

## ToS 準拠の根拠

- main エージェント（`"default": true`）は Codex のまま変更しない
- Claude Code は ACP 経由で Claude Code CLI として起動される
- Claude Code CLI は正規クライアントであり、自身の OAuth 認証を使用するため ToS に抵触しない
- `openclaw.docker.json.tmpl` の agents.list は変更しない
