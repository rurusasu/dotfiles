# chezmoi/shells: シェル初期化設定

## 管理対象

- `bashrc`, `zshrc`, `profile`
- `Microsoft.PowerShell_profile.ps1`

## 変更ルール

1. 共通機能は bash/zsh/pwsh で挙動を揃える。
2. 秘密情報は直接書かず `~/.config/shell/secret.*` を source する。
3. alias 追加は既存キーと衝突しないことを確認する。

## 反映

```bash
chezmoi apply
```
