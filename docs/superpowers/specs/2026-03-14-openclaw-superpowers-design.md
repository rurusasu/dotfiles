# OpenClaw Superpowers Integration Design

## Summary

OpenClaw コンテナ内の全エージェント（Codex, Claude Code, Gemini CLI, 将来追加分）に [obra/superpowers](https://github.com/obra/superpowers) スキルフレームワークを搭載する。

## Approach

**統一パス方式（entrypoint clone/pull）**を採用。

- `/app/data/superpowers` に `obra/superpowers` を1回 clone
- 各エージェントのスキル検出パスにシンボリックリンクで配線
- コンテナ再起動時に `git pull --ff-only` で自動更新
- ネットワークエラー時は既存版で続行（非致命的）

### Why this approach

- **ホスト側設定ほぼ不要**: Handler 変更なし、bind mount 追加なし（docker-compose.yml に tmpfs 1行追加のみ）
- **更新が簡単**: コンテナ再起動 = 自動更新。再ビルド不要
- **エラーに強い**: clone/pull 失敗は WARN ログのみ。コンテナ起動を妨げない
- **拡張が容易**: 新エージェント追加 = symlink 1行追加

## Data Flow

```
初回起動:
  git clone --depth 1 --single-branch https://github.com/obra/superpowers.git /app/data/superpowers

再起動時:
  git -C /app/data/superpowers pull --ff-only || warn

リンク配線:
  /app/data/superpowers/
    │
    ├─ skills/ ─────┬── ~/.agents/skills/superpowers          (Codex, OpenCode, 汎用)
    │               ├── /app/data/workspace/skills/superpowers (workspace 経由)
    │               └── (将来のエージェント用にここに追加)
    │
    └─ (リポジトリ全体) ── ~/.gemini/extensions/superpowers   (Gemini CLI)
```

Claude Code: ホストの `~/.claude` が `CLAUDE_CREDENTIALS_DIR` 経由でマウント済み。ホスト側で superpowers plugin がインストール済みならコンテナ内でもそのまま動作する。

### Read-only filesystem の制約

コンテナは `read_only: true` で動作する。`/home/bun/.agents/` はどの writable mount にも含まれていないため、docker-compose.yml に tmpfs を追加する必要がある:

```yaml
tmpfs:
  - /tmp:size=64m,mode=1777
  - /home/bun/.agents:size=1m,mode=0755   # ← 追加
```

tmpfs で十分な理由: `~/.agents/skills/superpowers` はシンボリックリンク1本のみ（永続化不要、毎起動 entrypoint が再作成）。

### Gemini bind-mount の副作用

`GEMINI_CREDENTIALS_DIR` がホストの `~/.gemini` を指している場合、`~/.gemini/extensions/superpowers` シンボリックリンクがホスト側に漏れる。このリンクはコンテナ内パス `/app/data/superpowers` を指すため、ホスト上ではダングリングリンクになる。

- ホスト側の Gemini CLI には **影響なし**（ダングリングリンクは無視される）
- ホスト側で superpowers を使いたい場合は `gemini extensions install` で別途インストールする

## Changes

### 1. `docker/openclaw/entrypoint.sh`

既存の `# Symlink Claude Code skills into workspace` セクションの前に superpowers clone/pull + 配線セクションを追加。

```sh
# --- Superpowers: clone or update obra/superpowers ---
# $workspace_dir is defined earlier in entrypoint.sh as "/app/data/workspace"
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

### 2. `docker/openclaw/docker-compose.yml`

`~/.agents/` 用の tmpfs を追加:

```yaml
tmpfs:
  - /tmp:size=64m,mode=1777
  - /home/bun/.agents:size=1m,mode=0755   # superpowers symlink for Codex/OpenCode
```

### 3. `docker/openclaw/tests/test-entrypoint.sh`

superpowers symlink 配線のテストを追加。テストでは git clone/pull は実行せず、事前にダミーの superpowers ディレクトリを作成して配線ロジックのみを検証する（既存テストと同じパターン）。

テストケース:
- symlink 配線: 3箇所（`~/.agents/skills/superpowers`, `~/.gemini/extensions/superpowers`, `workspace/skills/superpowers`）にリンクが張られる
- skills ディレクトリなし: リンク配線がスキップされる
- 再実行で既存リンクが更新される（冪等性）

### 4. `docker/openclaw/AGENTS.md`

superpowers セクションを追加。以下を含める:

- superpowers が利用可能であること
- 自動更新の仕組み（再起動で `git pull`）
- **新エージェント追加手順**: entrypoint.sh の配線セクションに symlink を追加する方法

## Adding a New Agent (documentation for AGENTS.md)

新しい ACP エージェントに superpowers を配線するには:

1. そのエージェントのスキル検出パスを確認する（公式ドキュメントまたは `obra/superpowers` の README 参照）
2. `entrypoint.sh` の `# --- Superpowers: wire to agent skill-discovery paths ---` セクションに `ln -sfn` を追加:

```sh
# <AgentName> (<discovery-path> に skills/ または repo 全体をリンク)
mkdir -p "$HOME/<agent-config-dir>"
ln -sfn "$_sp_dir/skills" "$HOME/<agent-config-dir>/superpowers"
```

3. エージェントによっては `skills/` ではなくリポジトリ全体をリンクする必要がある（Gemini CLI のように）

一般的なパターン:
| エージェント | リンク先 | リンク対象 |
|---|---|---|
| Codex / OpenCode | `~/.agents/skills/superpowers` | `skills/` |
| Gemini CLI | `~/.gemini/extensions/superpowers` | リポジトリ全体 |
| Copilot CLI | `~/.agents/skills/superpowers` | `skills/` (要確認) |
| Kiro CLI | `~/.agents/skills/superpowers` | `skills/` (要確認) |

## Error Handling

| シナリオ | 挙動 |
|---|---|
| 初回 clone 失敗（ネットワークなし） | WARN ログ、superpowers なしで続行 |
| pull 失敗（ネットワークなし） | WARN ログ、キャッシュ版で続行 |
| pull 失敗（conflicting changes） | `--ff-only` が reject、キャッシュ版で続行 |
| `/app/data` volume なし | clone 先がないため失敗、WARN で続行 |

いずれのケースもコンテナ起動は妨げない。

## Out of Scope

- Dockerfile の変更（git は既にインストール済み）
- Handler.OpenClaw.ps1 の変更
- ホスト側の superpowers 管理
