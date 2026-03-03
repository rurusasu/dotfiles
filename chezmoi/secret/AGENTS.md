# secret

Purpose: Shell-startup secret injection via 1Password CLI.
Expected contents:

- env.sh: Bash/Zsh secret loader (GH_TOKEN, TAVILY_API_KEY via `op read`).
- env.ps1: PowerShell secret loader (same secrets).

Notes:

- Deployed to `~/.config/shell/secret.sh` and `~/.config/shell/secret.ps1`.
- Sourced by .bashrc, .zshrc, and Microsoft.PowerShell_profile.ps1.
- No actual secrets stored here — only `op://` references resolved at runtime.
- Covers: Linux bash/zsh, WSL NixOS, Git Bash (Windows), PowerShell.

## 1Password アイテム一覧 (動作確認済み)

| 環境変数 | op:// パス | 用途 |
|---------|-----------|------|
| `GH_TOKEN` | `op://Personal/GitHubUsedUserPAT/credential` | gh CLI・GitHub MCP サーバー (Windows/NixOS 汎用) |
| `TAVILY_API_KEY` | `op://Personal/TavilyUsedUserPAT/credential` | Tavily MCP サーバー |

- アイテムカテゴリ: `API_CREDENTIAL` (認証情報フィールド = `credential`)
- OpenClaw 専用 PAT は `Handler.OpenClaw.ps1` が `op://Personal/GitHubUsedOpenClawPAT/credential` を直接参照

## 前提条件

- 1Password デスクトップアプリの CLI 統合を有効化:
  設定 → 開発者 → 「1Password CLI との統合を有効にする」
- `op` が PATH に存在しない場合は各ローダーが自動スキップする
