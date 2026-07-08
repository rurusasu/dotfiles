# chezmoi/ssh: SSH 設定テンプレート

## 編集対象

- `config.tmpl`

## 変更ルール

- 1Password SSH Agent / signing の OS 別パス分岐は `docs/1password/` を確認する。
- GitHub host alias 変更時は既存リポジトリ接続への影響を確認する。
- 秘密鍵の実体は置かない。
- 公開鍵の 1Password 取得方針は `docs/1password/README.md` と OS 別 docs に従う。
- `Host github-work` alias は LIF-182 で導入した `[includeIf "hasconfig:remote.*.url:git@github-work:**"]` の hook となる。work repo の remote URL を `git@github-work:org/repo` に変えると work identity (`~/.gitconfig-work`) が自動適用される。

## deploy スクリプトの注意点

- `config.tmpl` はテンプレートファイルなので、deploy スクリプト内で `{{ include "ssh/config.tmpl" }}` を使ってインライン展開すること。
- `Deploy-File` でファイルパスをコピーすると `ssh/config` を探すが存在しないため無言で失敗する。
- Windows では Git Bash の SSH は named pipe (`//./pipe/openssh-ssh-agent`) に接続できない。`core.sshCommand = C:/Windows/System32/OpenSSH/ssh.exe` で Windows OpenSSH を使用すること。
