# Claude Code Subagents Best Practices

最終確認: 2026-02-19
主要参照: Claude Code 公式ドキュメント（subagents）

## 1. まず決めること

- 配置先を決める
  - プロジェクト専用: `.claude/agents/`
  - ユーザー共通: `~/.claude/agents/`（この repo では `chezmoi/dot_claude/agents/`）
- 1 subagent = 1責務にする（例: `code-reviewer`, `log-analyzer`）
- `description` には「いつ使うか」を具体的に書く（Claude が委譲判断に使う）

## 2. フロントマター設計

推奨最小構成:

```markdown
---
name: code-reviewer
description: Review staged changes for bugs and regressions before commit.
tools: Read, Grep, Glob, Bash
model: sonnet
---
```

- `name`: `kebab-case` で短く明確に
- `description`: タスク条件・対象・期待成果を1文で
- `tools`: 最小権限（不要な書き込み系は外す）
- `model`: 迷ったら `sonnet`。軽量反復は `haiku`、高難度のみ `opus`

## 3. 本文プロンプトの書き方

- 最初に役割を1-2行で固定
- 次に入出力を明示
  - 入力: 「何を受け取るか」
  - 出力: 「どの形式で返すか」
- 判定基準を箇条書きで固定（品質、セキュリティ、テスト観点など）
- 「やらないこと」を書く（責務肥大を防ぐ）

## 4. 運用ベストプラクティス

- `/agents` で新規作成し、生成された雛形を編集する
- 変更後はセッションを再起動して再読込を確実化する
- サブエージェントはネストさせず、オーケストレーションは親側で行う
- 実験用と本番用を分ける（`*-experimental` など）
- プロジェクト専用 subagent はリポジトリで管理しレビュー対象にする

## 4.1 Hooks 連携パターン（推奨）

subagent 運用でも hooks は有効。
「毎回必ず実行したい処理」は prompt ではなく hooks に寄せる。

- 設定ファイル
  - ユーザー共通: `~/.claude/settings.json`（この repo では `chezmoi/dot_claude/settings.json.tmpl`）
  - プロジェクト専用: `.claude/settings.json`
  - agent 専用: 各 subagent の frontmatter `hooks`（例: `python-coding.md`）

### 使い分け

- subagent frontmatter `hooks`
  - その subagent 実行中だけ有効
  - role 固有の制約（例: `python-coding` では Python 以外の編集を拒否）に使う
- `settings.json` の `hooks`
  - メインセッションで有効
  - `SubagentStart` / `SubagentStop` を含む全体ポリシーや監査向け処理に使う
- 推奨イベント
  - `PreToolUse`: 危険操作のブロック、入力検証
  - `PostToolUse`: フォーマット/静的チェック通知
  - `SubagentStop`: サブエージェント完了時の集約処理
- ベストプラクティス
  - hook コマンドは小さく保つ（1責務）
  - `timeout` を必ず設定する
  - 失敗時挙動を明確化する（`exit 2` はブロッキング）
  - スクリプト参照は絶対パスまたは `"$CLAUDE_PROJECT_DIR"` を使う
  - 機密ファイル（`.env`、鍵、トークン）へのアクセスを明示的に除外する

### 例: Python 実装 subagent と hooks の役割分離

- subagent (`python-coding.md`) は実装に専念する
- テスト実行は別 agent に委譲する
- hooks は「禁止操作のブロック」や「完了通知」などの強制ルールだけを担当する

## 5. アンチパターン

- 巨大な万能 subagent を1つ作る
- `description` が短すぎて委譲条件が不明
- 強い権限をデフォルト付与する
- 出力形式を指定せず、毎回フォーマットがぶれる

## 6. テンプレート

```markdown
---
name: <kebab-case-name>
description: <when to use this agent and expected result>
tools: Read, Grep, Glob
model: sonnet
---

You are a specialized subagent for <domain>.

## Scope

- Do: <task A>
- Do: <task B>
- Don't: <out of scope>

## Input

- <input contract>

## Output

- <format contract>

## Quality Bar

- <check 1>
- <check 2>
```

## 7. この repo での配置

- Source of truth: `chezmoi/dot_claude/agents/`
- 配布先: `~/.claude/agents/`（chezmoi 適用時）
- 反映:
  - `chezmoi apply`
  - 必要なら Claude Code セッション再起動

## References

- <https://docs.anthropic.com/en/docs/claude-code/sub-agents>
- <https://docs.anthropic.com/en/docs/claude-code/settings>
- <https://docs.anthropic.com/en/docs/claude-code/hooks>
- <https://docs.anthropic.com/en/docs/claude-code/hooks-guide>
