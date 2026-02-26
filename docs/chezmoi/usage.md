# Chezmoi の使い方

## インストール

### Windows

```powershell
winget install -e --id twpayne.chezmoi
```

### Linux/WSL (NixOS)

NixOS では `nixos-rebuild switch` で chezmoi が自動インストールされます（`nix/core/cli.nix` で定義）。

```bash
# install.ps1 実行後は chezmoi が使える状態
chezmoi --version

# 手動で chezmoi を追加インストールしたい場合
nix profile install nixpkgs#chezmoi
```

## 適用方法

### 方法 1: GitHub から直接取得（クローン不要）

最もシンプルな方法。リポジトリをクローンせずに適用できます。

**Windows:**

```powershell
chezmoi init rurusasu/dotfiles --source-path chezmoi
chezmoi apply
```

**Linux/WSL:**

```bash
chezmoi init rurusasu/dotfiles --source-path chezmoi
chezmoi apply
```

### 方法 2: ローカルコピーから適用

リポジトリをクローン済みの場合。

**Windows:**

```powershell
chezmoi init --source D:\dotfiles\chezmoi
chezmoi apply
```

**WSL (シンボリックリンク経由):**

```bash
chezmoi init --source ~/.dotfiles/chezmoi
chezmoi apply
```

### 方法 3: 同梱スクリプトで一括適用

Windows でリポジトリがある場合:

```powershell
.\scripts\powershell\apply-chezmoi.ps1 -InstallChezmoi
```

このスクリプトは:

1. chezmoi がなければ winget でインストール
2. chezmoi init を実行
3. chezmoi apply を実行

## 設定の更新

ファイルを編集後:

```bash
chezmoi apply
```

差分を確認:

```bash
chezmoi diff
```

## ターミナル設定の適用フロー

```
┌──────────────────────────────────────────────────────────────┐
│  Chezmoi (source of truth)                                   │
│  chezmoi/AppData/Local/.../settings.json                    │
│  chezmoi/dot_config/wezterm/wezterm.lua                      │
└──────────────────────────────────────────────────────────────┘
                            │
                            │ chezmoi apply (Windows)
                            ↓
┌──────────────────────────────────────────────────────────────┐
│                         Windows                              │
│  %LOCALAPPDATA%\...\WindowsTerminal\settings.json            │
│  %USERPROFILE%\.config\wezterm\wezterm.lua                   │
└──────────────────────────────────────────────────────────────┘
                            │
                            │ chezmoi apply (WSL/Linux)
                            ↓
┌──────────────────────────────────────────────────────────────┐
│                         WSL/Linux                            │
│  ~/.config/wezterm/wezterm.lua                               │
└──────────────────────────────────────────────────────────────┘
```

## プラットフォームサポート

- Windows (ネイティブ)
- Linux
- WSL (Windows Subsystem for Linux)
- DevContainer
