# chezmoi/dot_claude: Claude Code 設定

## 管理対象

- `settings.json`
- `CLAUDE.md`
- `agents/`
- `plugins/`

## ルール

- セッション全体の運用ルールは `CLAUDE.md` へ。
- 役割別挙動は `agents/` へ分離する。
- ツール追加時は deploy 後に実際の読込を確認する。
