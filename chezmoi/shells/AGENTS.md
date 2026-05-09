# chezmoi/shells: シェル初期化設定

## 管理対象

- `bashrc`, `profile`（Linux/macOS 向け）
- `Microsoft.PowerShell_profile.ps1`（Windows 向け）

> **zshrc は Home Manager が管理する。** `programs.zsh` を使う全 HM 管理プラットフォーム
> （NixOS/WSL、macOS via nix-darwin、standalone Linux）では `nix/home/common.nix` の
> `programs.zsh` が SSOT。chezmoi は zshrc をデプロイしない。

## 変更ルール

1. bash/pwsh の共通機能は挙動を揃える。
2. 秘密情報は直接書かず `~/.config/shell/secret.*` を source する。
3. alias 追加は既存キーと衝突しないことを確認する。
4. zsh の alias・設定は `nix/home/common.nix`（全プラットフォーム共通）または
   `nix/home/wsl/users.nix`（WSL 固有）の `programs.zsh` に書く。

## 反映

```bash
chezmoi apply
```
