# chezmoi/dot_codex: Codex CLI 設定

## 管理対象

- `config.toml`
- `agents/*.toml`
- `rules/*.rules`
- `AGENTS.override.md`

## ルール

- 実運用の指示は `AGENTS.override.md` に書く。
- マルチエージェント設定は `config.toml` の `[agents.*]` と `agents/*.toml` を対で管理する。
- MCP 追加時は依存コマンドと認証方式を明記する。
