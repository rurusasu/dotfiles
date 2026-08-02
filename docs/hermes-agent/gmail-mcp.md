# Hermes Gmail MCP

Hermes の Gmail MCP は公式エンドポイント
`https://gmailmcp.googleapis.com/mcp/v1` を使い、root/default と各 named
profile で個別に OAuth を完了します。OAuth トークンは各 profile home の
`mcp-tokens/gmail.json` にだけ保存され、`0600` 以外のキャッシュは無効として
扱われます。トークンや OAuth client の値をコマンド引数、設定 YAML、ログに
書かないでください。

## Google Cloud の事前準備

1. 同じ Google Cloud project で Gmail API と Google の Gmail MCP API を有効にします。
2. OAuth consent screen を設定し、利用者をテストユーザーとして許可します。
3. Calendar MCP で使っている既存の OAuth client を再利用します。client ID/secret は
   bootstrap が private profile `.env` にのみ配置するため、手入力や新しい
   1Password item は不要です。
4. 同意画面では
   `https://www.googleapis.com/auth/gmail.readonly` と
   `https://www.googleapis.com/auth/gmail.compose` のみを許可します。

bootstrap 済みであることを確認してから、profile ごとに認証します。

```bash
task hermes:gmail:auth PROFILE=rick
task hermes:gmail:test PROFILE=rick
```

`default` は root home (`/opt/data`) を使い、named profile は
`/opt/data/profiles/<profile>` を使います。profile 名は実在する mounted home と
照合されるため、未導入の profile は認証を開始しません。

`hermes mcp login gmail` は設定の `connect_timeout: 315` を使い、OAuth callback
用に少なくとも 315 秒待機します。表示された URL を browser で開いて同意し、
container に届かない callback は、表示される redirect URL を同じ対話端末に
貼り戻してください。これは OAuth callback の通常動作であり、トークン内容を
表示する必要はありません。

Windows では同じ操作を native Docker Compose 経由で実行します。

```powershell
task hermes:gmail:auth PROFILE=rick
task hermes:gmail:test PROFILE=rick
```

この構成が公開するのは、検索・スレッド/メッセージ取得・ラベル一覧・下書き一覧・
下書き作成だけです。送信、削除、ラベルの作成・更新・削除は含みません。`test` は
MCP 接続と allowlist の発見だけを行い、メール送信・削除・変更は実行しません。
