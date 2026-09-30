# 1Password CLI on Windows

## 結論

Windows で `op` を非対話実行する場合は、`op read` / `op inject` / `op vault list`
などに `--cache=false` を付ける。

1Password desktop app integration の認可は Windows では `op.exe` のプロセス単位。
子プロセスから複数回 `op` を呼ぶと、それぞれ別の認可要求になる。
`op signin` を別の PowerShell プロセスで先に実行しても、その認可状態は後続の
`chezmoi apply` に引き継がれない。

そのため Windows の `task chezmoi` は、apply 前に Kaggle、SSH 公開鍵、MCP設定の
任意secret参照を1回の `op inject` でまとめて取得し、`chezmoi apply` の子プロセスへ
一時的に環境変数で渡す。batch取得が失敗した場合は任意secretをすべてスキップし、
個別の `op read` を再試行せずにapplyを続行する。直接 `chezmoi apply` を実行した場合は、
従来どおり必要なdeploy scriptが個別にsecretを取得する。

今回の実測では、`op --debug vault list --format=json --account my.1password.com` は
1Password app integration の `NmRequestAuthorization` と `NmRequestDelegatedSession`
までは成功したが、その後に cache daemon へ接続しようとして timeout した。
`--cache=false` を付けると同じ環境で exit 0 になった。

## 使う形

```powershell
op --cache=false read "op://Private/Example/credential" --account my.1password.com
```

```powershell
op --cache=false inject --in-file env.tpl --account my.1password.com
```

`Start-Process` で stdout / stderr を redirect する wrapper でも同じ。

```powershell
$process = Start-Process `
  -FilePath $opBin `
  -ArgumentList @('--cache=false', 'inject', '--in-file', $template, '--account', $account) `
  -PassThru `
  -WindowStyle Hidden `
  -RedirectStandardOutput $stdout `
  -RedirectStandardError $stderr
```

## 調査時の見方

`op whoami` の `account is not signed in` だけで失敗と断定しない。
desktop app integration では delegated session の途中で一時的にこの表示が出ることがある。

まず次を確認する。

```powershell
op --cache=false --debug vault list --format=json --account my.1password.com
```

見るポイント:

- `Session delegation enabled`
- `NM request: NmRequestAuthorization`
- `NM response: Success`
- `NM request: NmRequestDelegatedSession`
- `NM response: Success`

ここまで進むなら、1Password app integration には到達している。
その後に timeout する場合は cache や wrapper timeout を疑う。

## timeout

初回の delegated session は数秒で終わらないことがある。
shell 起動や deploy script で `op` を呼ぶ場合は、timeout を短くしすぎない。

目安:

- shell startup fallback / runtime deploy read: 最大 180 秒まで待機し、失敗時は warning で続行する。
- GUI launcher: 既定では `op` を呼ばない。`DOTFILES_GUI_EAGER_SECRET_LOAD=1` で opt-in した場合だけ、短めの timeout 後に token なし起動へ fallback する。
- 必須 secret: timeout したら明示的に失敗させる。

deploy script の `WaitForExit` が設定している 180 秒は、呼び出し側が `op` を待つ上限。
`op` 自身が先に `context deadline exceeded` を返した場合は、この上限を延ばしても解消しない。
その場合は 1Password desktop app のロック状態と CLI integration を確認し、次の読み取り専用コマンドで
app integration / account 接続を診断する。

```powershell
op --cache=false --debug vault list --format=json --account my.1password.com
```

deploy の1Password read失敗は任意secretのskipとして処理し、chezmoi apply は続行する。
CI はこのfallbackとtimeout設定を検証するが、実アカウントの応答時間は検証しない。

## `op run` について

`op run --env-file` は、子プロセスへ env をまとめて渡すための手段。
全アプリを `op run` で起動する必要はない。
この repo の Orca / WezTerm launcher は、UX 優先で direct 起動を既定にする。
GUI process の起動前に secret が必要な場合だけ `DOTFILES_GUI_EAGER_SECRET_LOAD=1`
を設定して opt-in する。

WezTerm / Orca が内部で PowerShell を起動すると profile が読まれるため、
`~\.config\shell\secret.ps1` も `DOTFILES_FORCE_SECRET_LOAD=1` が無い限り
即 return する。plain terminal startup では `op read` に進ませない。

1Password app integration が有効なら、任意のプロセスから `op --cache=false read` や
`op --cache=false inject` を呼べる。

## Chezmoi

Windows で `chezmoi` template から `op` を間接実行する場合も、非対話であれば
`--cache=false` を付ける。

ただし、この repo では通常の `.tmpl` から `onepasswordRead` を直接呼ばない。
詳しくは [README.md](./README.md) を参照。

## SSH Agent

Windows の SSH agent は named pipe を使う。

```sshconfig
Host *
    IdentityAgent "//./pipe/openssh-ssh-agent"
```

Git Bash の SSH は named pipe に接続できないため、Windows OpenSSH を使う。

```gitconfig
[core]
  sshCommand = C:/Windows/System32/OpenSSH/ssh.exe
```

`gpg.ssh.program` は 1Password の signer を使う。

```gitconfig
[gpg "ssh"]
  program = C:/Program Files/1Password/app/8/op-ssh-sign.exe
```

`%APPDATA%\1Password\ssh\agent.toml` は、1Password SSH Agent が offer する鍵を
whitelist で絞るために使う。各 `[[ssh-keys]]` は item ID、vault、account で
曖昧さを避ける。
