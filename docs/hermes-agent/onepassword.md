# Hermes Agent で 1Password を使う

Nix 管理の native Hermes と同期 helper は公式の 1Password CLI (`op`) を使います。
Hermes の組み込み連携は `op://Vault/Item/field` 参照を起動時に解決します。
実シークレットやサービスアカウントトークンはリポジトリへ保存しません。

## 自動設定

`task hermes:sync` が、既存のSA参照
個人アカウント `my.1password.com` の
`op://openclaw/3bgd5qtytxuvuauauyqr2p4iki/credential` を使ってSAを取得します。
SA token と item payload はプロセス間の pipe でのみ渡し、ファイルやログには保存しません。
Nix が `~/.hermes/bootstrap-manifest.yaml` として配置する manifest の宣言から、
default と全 named profile の `config.yaml` に
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
task hermes:sync
```

SAの読み取りに失敗した場合は、ホストの1Password CLIで対象アカウントへサインインし、
もう一度同じコマンドを実行してください。SA値をDiscord、Git、シェル引数、ログへ貼り付けないでください。

SA の読み取りに失敗した場合は、ホストの 1Password CLI で対象アカウントへサインインし、
もう一度同じコマンドを実行してください。SA 値を Discord、Git、シェル引数、ログへ貼り付けないでください。

`sync` は manifest に宣言された秘密情報を同期し、profile と shared repository の状態も反映します。
Hermes 組み込み 1Password 連携の dry-run は次のとおりです。

```bash
hermes secrets onepassword sync
```

named profile で個別の参照を使う場合は、対象 profile の `HERMES_HOME` を指定して
同じコマンドを実行します。

```bash
HERMES_HOME="$HOME/.hermes/profiles/rick" hermes secrets onepassword status
```

サービスアカウントの発行・保存・ローテーションは1Password側で行います。このリポジトリには
`op://` 参照と非秘密設定だけを置き、SA 値は同期プロセスのメモリ上だけで扱います。
