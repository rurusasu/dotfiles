# Hermes Agent で 1Password を使う

Hermes コンテナには公式の 1Password CLI (`op`) を含めています。Hermes の
組み込み連携は `op://Vault/Item/field` 参照を起動時に解決します。実シークレットや
サービスアカウントトークンはリポジトリへ保存しません。

## 自動設定

`task hermes:bootstrap` が、既存のSA参照
個人アカウント `my.1password.com` の
`op://openclaw/3bgd5qtytxuvuauauyqr2p4iki/credential` からSAを取得し、
HERMESデータディレクトリの0600 `.op.env` に保存します。その後、defaultと全named
profileの `config.yaml` にDashboard、GitHub、Discordの `op://` 参照を冪等に登録します。

1Passwordアイテムの作成やSAの発行は行いません。既存の8アイテムを検証し、Google
Calendarの認証情報はMCPが要求する0600 JSONファイルとして引き続き同期します。

```bash
task hermes:bootstrap
```

SAの読み取りに失敗した場合は、ホストの1Password CLIで対象アカウントへサインインし、
もう一度同じコマンドを実行してください。SA値をDiscord、Git、シェル引数、ログへ貼り付けないでください。

`sync` は参照を解決できるか確認する dry-run です。

```bash
docker exec hermes /opt/hermes/.venv/bin/hermes \
  secrets onepassword sync
```

named profile で個別の参照を使う場合は、対象 profile の `HERMES_HOME` を指定して
同じコマンドを実行します。

```bash
docker exec hermes env HERMES_HOME=/opt/data/profiles/rick \
  /opt/hermes/.venv/bin/hermes secrets onepassword status
```

サービスアカウントの発行・保存・ローテーションは1Password側で行います。このリポジトリには
`op://` 参照と非秘密設定だけを置き、SA値はruntimeデータディレクトリの `.op.env` にのみ保存します。
