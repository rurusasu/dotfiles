# chezmoi/ssh: SSH 設定テンプレート

## 編集対象

- `config.tmpl`

## 変更ルール

- 1Password SSH Agent の OS 別パス分岐を維持する。
- GitHub host alias 変更時は既存リポジトリ接続への影響を確認する。
- 秘密鍵の実体は置かない。
- 公開鍵は deploy スクリプト内で `onepasswordRead` により 1Password から取得し `~/.ssh/signing_key.pub` に配置する。
- 1Password 参照先: `op://Personal/xnoq6xbcdktkph76e2bg37ou6y/public key`（GitHub SSH_KEY アイテム）

## deploy スクリプトの注意点

- `config.tmpl` はテンプレートファイルなので、deploy スクリプト内で `{{ include "ssh/config.tmpl" }}` を使ってインライン展開すること。
- `Deploy-File` でファイルパスをコピーすると `ssh/config` を探すが存在しないため無言で失敗する。
- Windows では Git Bash の SSH は named pipe (`//./pipe/openssh-ssh-agent`) に接続できない。`core.sshCommand = C:/Windows/System32/OpenSSH/ssh.exe` で Windows OpenSSH を使用すること。
