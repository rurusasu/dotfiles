# Dotfiles

[![NixOS](https://img.shields.io/badge/NixOS-26.05-5277C3?logo=nixos&logoColor=white)](https://nixos.org/)
[![Home Manager](https://img.shields.io/badge/Home_Manager-Nix-5277C3?logo=nixos&logoColor=white)](https://github.com/nix-community/home-manager)
[![WSL](https://img.shields.io/badge/WSL-2-0078D6?logo=windows&logoColor=white)](https://docs.microsoft.com/en-us/windows/wsl/)
[![PowerShell Tests](https://github.com/rurusasu/dotfiles/actions/workflows/test-powershell.yml/badge.svg)](https://github.com/rurusasu/dotfiles/actions/workflows/test-powershell.yml)
[![codecov](https://codecov.io/gh/rurusasu/dotfiles/branch/main/graph/badge.svg?flag=powershell)](https://codecov.io/gh/rurusasu/dotfiles)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

NixOS/Home Manager + chezmoi を使った dotfiles の一元管理リポジトリ

## 技術スタック

| Category | Technology |
|----------|------------|
| OS | NixOS (WSL2) |
| Package Manager | Nix Flakes |
| User Config | Chezmoi + Home Manager |
| Shell | Zsh + Starship |
| Editor | Neovim (nixvim) |
| Terminal | Windows Terminal, WezTerm |
| Formatter | treefmt-nix |

## クイックスタート

Windows PowerShell で以下を実行:

```powershell
# 1. リポジトリをクローン
git clone https://github.com/rurusasu/dotfiles.git
cd dotfiles

# 2. インストール実行（管理者権限は自動で取得されます）
.\install.ps1
```

これにより:
1. NixOS WSL がダウンロード・インポートされる
2. `~/.dotfiles` がこのリポジトリへのシンボリックリンクとして作成される
3. `nixos-rebuild switch` が実行され設定が適用される
4. Windows 側のユーザー設定は chezmoi apply で適用する

## 方針

Nix はパッケージ/システム設定、chezmoi はユーザー設定を管理します。

- ユーザー設定: `chezmoi/`
- Home Manager: `nix/profiles/home/` (packages, tmux, nixvim, extensions)
- ホスト設定: `nix/hosts/`
- ターミナル設定: `chezmoi/dot_config/wezterm/wezterm.lua` と `chezmoi/AppData/Local/.../LocalState/settings.json`

## ディレクトリ構造

```
dotfiles/
├── chezmoi/                # User dotfiles (shell/git/terminal/VS Code/LLM)
├── nix/                    # NixOS/Home Manager configuration
│   ├── flakes/             # Flake inputs/outputs
│   ├── hosts/              # Host-specific configs
│   ├── home/               # Home Manager base
│   ├── profiles/           # Reusable config profiles
│   ├── modules/            # Custom NixOS modules
│   ├── lib/                # Helper functions
│   ├── overlays/           # Nixpkgs overlays
│   ├── packages/           # Custom packages
│   └── templates/          # Config templates
├── scripts/                # All scripts
│   ├── sh/                 # Shell scripts (Linux/WSL)
│   │   ├── update.sh           # Daily update script
│   │   ├── nixos-wsl-postinstall.sh
│   │   └── treefmt.sh
│   └── powershell/         # PowerShell scripts (Windows)
│       ├── update-windows-settings.ps1
│       ├── update-wslconfig.ps1
│       └── export-settings.ps1
├── windows/                # Windows-side config files
│   ├── winget/             # Package management
│   └── .wslconfig          # WSL configuration
├── install.ps1             # NixOS WSL installer (auto-elevates to admin)
├── flake.nix               # Nix flake entry point
└── flake.lock
```

## 日常の使い方

### 設定の更新

WSL 内で実行:

```bash
# 方法1: update.sh を使う（NixOS rebuild + winget 適用を一括実行）
~/.dotfiles/scripts/sh/update.sh

# 方法2: エイリアスを使う（NixOS rebuildのみ）
nrs  # alias for: sudo nixos-rebuild switch --flake ~/.dotfiles --impure
```

Windows 側のファイルを編集すると、`~/.dotfiles` シンボリックリンク経由で即座に WSL から参照可能。

### ターミナル設定を Windows に適用

Windows で chezmoi を実行して適用:

```powershell
# 方法1: GitHub から直接取得（クローン不要）
winget install -e --id twpayne.chezmoi
chezmoi init rurusasu/dotfiles --source-path chezmoi
chezmoi apply

# 方法2: ローカルにクローン済みの場合
chezmoi init --source <クローン先>\chezmoi
chezmoi apply
```

または同梱スクリプトで一括適用（ローカルコピーがある場合）:

```powershell
.\scripts\powershell\apply-chezmoi.ps1 -InstallChezmoi
```

## フォーマット (treefmt)

以下を treefmt で整形します:

- Nix: `nixfmt`
- JSON/YAML/Markdown: `prettier`
- TOML: `taplo`
- Lua: `stylua`
- Shell: `shfmt`
- PowerShell: `pwsh` + `PSScriptAnalyzer`

```bash
nix fmt
```

または:

```bash
./scripts/sh/treefmt.sh
```

pre-commit を使う場合:

```bash
pre-commit install
```

PowerShell (.ps1) の整形は PSScriptAnalyzer の `Invoke-Formatter` を使用します:

```powershell
pwsh -NoProfile -Command "Install-Module PSScriptAnalyzer -Scope CurrentUser"
```

TOML/Lua はそれぞれ設定ファイルで整形幅などを調整しています:

- `.taplo.toml`
- `stylua.toml`

## WSL 設定 (.wslconfig)

`.wslconfig` は `windows/.wslconfig` で管理し、以下で適用:

```powershell
.\scripts\powershell\update-wslconfig.ps1
wsl --shutdown
```

## キーパス

| Location | Description |
|----------|-------------|
| `~/.dotfiles` | Windows dotfiles へのシンボリックリンク |
| `nixosConfigurations.nixos` | WSL ホスト用 Flake attribute |
| `chezmoi/dot_config/wezterm/wezterm.lua` | WezTerm 設定 |
| `chezmoi/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json` | Windows Terminal 設定 |

## ターミナル設定

### Windows Terminal
- 設定ソース: `chezmoi/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json`
- キーバインド: `Ctrl+Alt+H` (水平分割), `Ctrl+Alt+V` (垂直分割), `Ctrl+Alt+X` (ペイン閉じる)

### WezTerm
- 設定ソース: `chezmoi/dot_config/wezterm/wezterm.lua`
- Leader key: `Ctrl+Space`
- キーバインド: `Ctrl+Alt+H` (水平分割), `Ctrl+Alt+V` (垂直分割), `Ctrl+Alt+X` (ペイン閉じる)

## トラブルシューティング

### ビルドエラー

```bash
# ドライランでエラーを確認
sudo nixos-rebuild dry-build --flake ~/.dotfiles --impure
```

### Windows Terminal 設定が反映されない

1. Windows で `chezmoi apply` を実行
2. Windows Terminal を再起動
