# Hermes Gmail MCP

Hermes の Gmail は Google Calendar と同じ共有 OAuth 方式です。Google の
会社向けリモート Gmail MCP API は使いません。標準 Gmail API とローカル stdio
MCP (`gmail-mcp`) を使い、root/default と全 named profile が
`/opt/data/google-gmail-mcp` の同じ資格情報を参照します。

## Google Cloud の準備

1. Calendar と同じ個人用 Google Cloud project で標準 Gmail API
   (`gmail.googleapis.com`) を有効にします。
2. OAuth consent screen に個人 Google アカウントをテストユーザーとして追加します。
3. Gmail 用の `gmail.readonly` と `gmail.compose` を許可します。
4. bootstrap が `openclaw/Google Calendar MCP` の desktop OAuth client JSONを
   Gmailの共有ディレクトリへ再利用します。

Gmailトークンはホストの
`~/.hermes/google-gmail-mcp/credentials.json` に mode `0600` で保存され、
bootstrap後も保持されます。全 profile の `config.yaml` は同じ`gmail-mcp`
設定とトークンを参照します。

## 認証と確認

認証は profile ごとではなく一度だけです。OAuth callback をホストで受けるため、
コンテナ内ではなくホストの `npx` から実行します。

```bash
task hermes:gmail:auth
```

生成された共有資格情報を有効にするため、認証後にHermesを再起動します。

各 profile の接続確認は個別に行います。

```bash
task hermes:gmail:test PROFILE=default
task hermes:gmail:test PROFILE=rick
```

公開ツールは検索、メール/スレッド取得、受信トレイ・ラベル一覧、下書き作成だけです。
`send_email` は allowlist に含めないため、Hermes から送信はできません。
