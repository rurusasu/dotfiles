# Hermes Agent で 1Password を使う

Hermes コンテナには公式の 1Password CLI (`op`) を含めています。Hermes の
組み込み連携は `op://Vault/Item/field` 参照を起動時に解決します。実シークレットや
サービスアカウントトークンはリポジトリへ保存しません。

## 自動設定

`task hermes:bootstrap` が、既存のSA参照
個人アカウント `my.1password.com` の
`op://openclaw/3bgd5qtytxuvuauauyqr2p4iki/credential` からSAを取得し、
HERMESデータディレクトリの0600 `.op.env` に保存します。その後、
`bootstrap-manifest.yaml` の宣言から、defaultと全named profileの `config.yaml` に
Dashboard、GitHub、Discord、xAI/Grokの設定を冪等に反映します。manifestで宣言した
環境変数は1Passwordから解決した値を実行用 `.env` に同期し、Hermesのruntime
`onepassword.env` には同じキーの `op://` 参照を残しません。手動管理の未宣言キーは保持します。

環境変数名とprofile適用範囲もmanifestから生成されるため、profileや1Password項目を
追加する場合は固定リストではなくmanifestを変更します。profile固有の項目は
`profiles`、全profileに適用する項目は省略（または `all`）します。

1Passwordアイテムの作成やSAの発行は行いません。manifestに宣言した項目を検証し、
Google Calendarの認証情報はMCPが要求する0600 JSONファイルとして引き続き同期します。
GrokのX Searchを利用するには、Service Accountが
`op://openclaw/xAI-Grok-Twitter/console/apikey` を読み取れるよう、1Password側で
対象itemへの権限を別途付与してください。

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
