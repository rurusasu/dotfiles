# chezmoi/dot_claude/agents: subagent 設計基準

## 設計ルール

1. 1 subagent = 1責務。
2. frontmatter の `description` は委譲条件を明確に書く。
3. `tools` は最小権限にする。
4. 入力契約・出力契約・品質基準を本文で固定する。

## 運用ルール

- 作成/更新後は `chezmoi apply` とセッション再起動で反映確認。
- 常時強制したい処理は prompt ではなく hooks に寄せる。
- 実験用 agent は本番用と分離する。

## 参照

- <https://docs.anthropic.com/en/docs/claude-code/sub-agents>
- <https://docs.anthropic.com/en/docs/claude-code/hooks>
