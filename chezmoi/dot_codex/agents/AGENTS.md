# chezmoi/dot_codex/agents: Codex role 設計基準

## 必須フロー

1. `agents/<role>.toml` を作成。
2. `config.toml` に `[agents.<role>]` と `config_file` を追加。
3. `chezmoi apply` で反映。

## 設計ルール

- 1 role = 1責務。
- `description` で利用条件を明示。
- 共通ポリシーは親 `config.toml` に集約。
- role ファイルは差分のみ持たせる。

## 制約

- sub-agent 実行時は新規承認が必要な操作が失敗しやすい。
- 未知の `[agents.<name>]` フィールドは使わない。

## 参照

- <https://developers.openai.com/codex/multi-agent>
- <https://developers.openai.com/codex/config-reference>
