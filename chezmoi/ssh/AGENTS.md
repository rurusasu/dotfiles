# chezmoi/ssh: SSH 設定テンプレート

## 編集対象

- `config.tmpl`

## 変更ルール

- 1Password SSH Agent の OS 別パス分岐を維持する。
- GitHub host alias 変更時は既存リポジトリ接続への影響を確認する。
- 秘密鍵の実体は置かない。
- 公開鍵は deploy スクリプト内で `onepasswordRead` により 1Password から取得し `~/.ssh/signing_key.pub` に配置する。
- 1Password 参照先: `op://Personal/xnoq6xbcdktkph76e2bg37ou6y/public key`（GitHub SSH_KEY アイテム）
