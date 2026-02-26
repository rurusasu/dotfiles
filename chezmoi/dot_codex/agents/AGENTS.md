# Codex Sub-Agent Best Practices

このディレクトリは Codex のサブエージェント用ロール設定 (`*.toml`) を管理します。
この repo では `chezmoi` を source of truth とし、展開先は `~/.codex/agents/` です。

## Purpose

- 役割ごとの設定ファイルを `agents/*.toml` で分離する
- `config.toml` の `[agents.<name>]` と対で運用する
- チーム共有可能な形で、再現性のあるロール定義を維持する

## Required Workflow (This Repository)

1. `chezmoi/dot_codex/agents/<role>.toml` を作成する
2. `chezmoi/dot_codex/config.toml.tmpl` の `[agents.<role>]` に以下を追加する
   - `description`
   - `config_file = "~/.codex/agents/<role>.toml"`
3. `chezmoi apply` で `~/.codex/` へ反映する

## Design Guidelines

- 1 role = 1 responsibility（例: 実装専任、レビュー専任、探索専任）
- `description` は「いつ使うか」を具体化する（ロール選択に使われる）
- `config_file` はロール特化の差分だけを持たせる
- 共通ポリシーは親セッション（`config.toml`）に寄せる

## Recommended Role Overrides

必要に応じて、ロール設定 (`agents/*.toml`) で次を上書きします。

- `model`
- `model_reasoning_effort`
- `sandbox_mode`（read-only ロールなど）
- `developer_instructions`

## Safety / Behavior Notes

- サブエージェントは親の sandbox/approval を継承する
- サブエージェントは non-interactive approval で実行されるため、新規承認が必要な操作は失敗する
- `[agents.<name>]` の未知フィールドは reject される
- `config_file` の相対パスは、その設定を宣言した `config.toml` 基準で解決される

## Hooks Compatibility

- Codex CLI の sub-agent には、Claude Code の `PreToolUse` / `PostToolUse` / `SubagentStop` のような hooks は現時点でない
- そのため、event-driven な自動フック処理は `agents.<name>` だけでは実装できない

### Alternative Pattern with Rules

- 危険コマンド抑止や承認強制は `rules` で実装する
- 実行手順の固定は `developer_instructions` に明示する
- 「テストは別 agent」などの役割分離は sub-agent 設計で担保する

## Skills Notes

- スキル自体は `SKILL.md` を含むディレクトリとして管理する
- 有効/無効の制御は `config.toml` の `[[skills.config]]` で行う
- ロールで前提スキルがある場合は、`developer_instructions` に利用方針を明示する

### Skills Example

`config.toml` 側でスキルを有効化:

```toml
[[skills.config]]
name = "python-clean-architecture"
path = "~/.codex/skills/python-clean-architecture"
enabled = true

[[skills.config]]
name = "python-docstring"
path = "~/.codex/skills/python-docstring"
enabled = true
```

agent 側で利用方針を明示:

```toml
developer_instructions = """
Python 実装では `python-clean-architecture` と `python-docstring` を優先して使う。
新規コードと修正コードの両方で、構造設計と docstring 品質を担保する。
"""
```

## Minimal Example

`config.toml` 側:

```toml
[agents.python_coding]
description = "Python implementation-only agent (no test execution)."
config_file = "~/.codex/agents/python_coding.toml"
```

`agents/python_coding.toml` 側:

```toml
model = "gpt-5.3-codex"
model_reasoning_effort = "medium"
developer_instructions = "Python実装を担当。テスト実行は担当しない。"
```

## Sources (Official)

最終確認日: 2026-02-19

- <https://developers.openai.com/codex/multi-agent>
- <https://developers.openai.com/codex/config-reference>
- <https://developers.openai.com/codex/skills>
- <https://developers.openai.com/codex/team-config>
