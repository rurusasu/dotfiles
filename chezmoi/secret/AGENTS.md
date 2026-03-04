# chezmoi/secret: 1Password 経由の環境変数注入

## 管理対象

- `env.sh`（bash/zsh）
- `env.ps1`（PowerShell）

## ルール

- 実シークレットは保存しない。`op://` 参照のみ保持する。
- `op` がない環境で安全にスキップできる実装を維持する。
- 追加する環境変数は用途を明確にする。
