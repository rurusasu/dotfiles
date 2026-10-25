# Hermes Agent で 1Password を使う

Hermes の公式 1Password 連携が `op://Vault/Item/field` を起動時に解決します。
実シークレットや Service Account token はリポジトリへ保存しません。

## 設定と確認

root の参照は `nix/modules/ai_agents/hermes/default.nix` の
`services.hermes-agent.settings.secrets.onepassword` に宣言します。
named profile の `config.yaml` と個別の `op://` 参照は、その profile の Git 正本で管理します。

公式 CLI で root と named profile の設定を確認できます。

```bash
hermes secrets onepassword status
hermes -p rick secrets onepassword status
```

読み取りに失敗した場合は、`op` のサインイン状態と対象項目の権限を確認してください。
Grok の X Search には `op://openclaw/xAI-Grok-Twitter/console/apikey` の読み取り権限が必要です。

## Pipedream MCP の認証

Google Drive / Gmail / Google Calendar は Pipedream の OAuth で接続します。
client ごとの認証とアプリ選択は [Gmail MCP](gmail-mcp.md) を参照してください。
既存の Google JSON・token ファイルは保持します。
Git 認証は既存の 1Password SSH agent と `~/.ssh/config` を使います。
profile の導入・更新は [Desktop and Agent](desktop.md) を参照してください。
