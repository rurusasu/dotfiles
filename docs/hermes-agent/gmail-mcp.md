# Google MCP via Pipedream

共通 MCP `pipedream` は `https://mcp.pipedream.net/v2` に接続します。
認証画面で [Gmail](https://mcp.pipedream.com/app/gmail)、
[Google Calendar](https://mcp.pipedream.com/app/google_calendar)、
[Google Drive](https://mcp.pipedream.com/app/google_drive) を選択して Google アカウントを接続します。
旧ローカル MCP の tool 名・allowlist は自動継承されず、公開機能と OAuth 権限は Pipedream の設定に従います。

Home Manager の設定反映後、使う client ごとにユーザーが OAuth を実行します。

```bash
codex mcp login pipedream
hermes mcp login pipedream
```

Codex の OAuth コマンドは [OpenAI の MCP 案内](https://learn.chatgpt.com/docs/extend/mcp?surface=cli) を参照してください。

Hermes の named profile は root の MCP 設定を継承しません。
Git 正本側に共通 gateway 参照または同じ remote URL を設定してから認証します。

```text
hermes -p NAME mcp login pipedream
```

private profile の移行、OAuth 認証、実環境への反映は未実施です。
旧ローカル Gmail / Calendar MCP の定義は削除し、無効化設定も残しません。
既存の実環境の設定・Google JSON・token ファイルは変更しません。
