# Chezmoi の使い方

## Windows での初回適用

リポジトリのルートで実行します。chezmoi 自体は Windows installer が WinGet で導入します。

```powershell
chezmoi init --source "$PWD/chezmoi"
task chezmoi
```

`task chezmoi` は Windows の WezTerm 設定を適用します。NixOS-WSL では実行しません。

## 更新

```powershell
task chezmoi
```

差分を確認する場合:

```powershell
chezmoi --source "$PWD/chezmoi" diff
```

## 配置先とプロファイル

chezmoi が管理するファイルは `%USERPROFILE%/.config/wezterm/wezterm.lua` です。Windows WezTerm は PowerShell を既定シェルとして起動します。NixOS-WSL は別の `NixOS (WSL)` launcher profile から起動します。

macOS、Linux、NixOS-WSL 内部の WezTerm 設定は Home Manager が管理し、Windows 用 chezmoi source からは配布しません。
