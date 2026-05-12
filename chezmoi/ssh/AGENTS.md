# chezmoi/ssh: SSH 設定テンプレート

## 編集対象

- `config.tmpl`

## 変更ルール

- 1Password SSH Agent の OS 別パス分岐を維持する。
- GitHub host alias 変更時は既存リポジトリ接続への影響を確認する。
- 秘密鍵の実体は置かない。
- 公開鍵は deploy スクリプト内で `onepasswordRead` により 1Password から取得し配置する:
  - `~/.ssh/signing_key.pub` — personal (`Host github.com`)
  - `~/.ssh/github_work.pub` — work (`Host github-work`)
- 1Password 参照先:
  - personal: `op://Private/xnoq6xbcdktkph76e2bg37ou6y/public key` (rurusasu account, default chezmoi account)
  - work: `op://Employee/GitHub Work/public key` (kohei-miki-im8 account, account UUID `FXVKKR2KWFCMHGMEA7HQYK6XRE` を `onepasswordRead` の 2nd 引数で明示指定)
- `Host github-work` alias は LIF-182 で導入した `[includeIf "hasconfig:remote.*.url:git@github-work:**"]` の hook となる。work repo の remote URL を `git@github-work:org/repo` に変えると work identity (`~/.gitconfig-work`) が自動適用される。

## deploy スクリプトの注意点

- `config.tmpl` はテンプレートファイルなので、deploy スクリプト内で `{{ include "ssh/config.tmpl" }}` を使ってインライン展開すること。
- `Deploy-File` でファイルパスをコピーすると `ssh/config` を探すが存在しないため無言で失敗する。
- Windows では Git Bash の SSH は named pipe (`//./pipe/openssh-ssh-agent`) に接続できない。`core.sshCommand = C:/Windows/System32/OpenSSH/ssh.exe` で Windows OpenSSH を使用すること。
