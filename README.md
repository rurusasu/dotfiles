# Dotfiles

[![NixOS](https://img.shields.io/badge/NixOS-26.05-5277C3?logo=nixos&logoColor=white)](https://nixos.org/)
[![Home Manager](https://img.shields.io/badge/Home_Manager-Nix-5277C3?logo=nixos&logoColor=white)](https://github.com/nix-community/home-manager)
[![WSL](https://img.shields.io/badge/WSL-2-0078D6?logo=windows&logoColor=white)](https://docs.microsoft.com/en-us/windows/wsl/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

NixOS/Home Manager を使った dotfiles の一元管理リポジトリ

## 技術スタック

| Category | Technology |
|----------|------------|
| OS | NixOS (WSL2) |
| Package Manager | Nix Flakes |
| User Config | Home Manager |
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
4. Windows Terminal / WezTerm の設定が Windows に適用される

## 方針

NixOS/WSL を含む複数環境で共通運用するため、すべての設定は Nix で管理します。

- ユーザー設定: `nix/profiles/home/` (Home Manager)
- ホスト設定: `nix/hosts/`
- ターミナル設定: `nix/profiles/home/programs/terminals/`

## ディレクトリ構造

```
dotfiles/
├── nix/                    # NixOS/Home Manager configuration
│   ├── flakes/             # Flake inputs/outputs
│   ├── hosts/              # Host-specific configs
│   ├── home/               # Home Manager base
│   ├── profiles/           # Reusable config profiles
│   │   └── home/programs/
│   │       └── terminals/  # Windows Terminal, WezTerm
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
# 方法1: update.sh を使う（NixOS rebuild + Windows設定適用を一括実行）
~/.dotfiles/scripts/sh/update.sh

# 方法2: エイリアスを使う（NixOS rebuildのみ）
nrs  # alias for: sudo nixos-rebuild switch --flake ~/.dotfiles --impure
```

Windows 側のファイルを編集すると、`~/.dotfiles` シンボリックリンク経由で即座に WSL から参照可能。

### ターミナル設定を Windows に適用

`nixos-rebuild switch` 後、Windows Terminal と WezTerm の設定を Windows に適用:

```powershell
# 管理者権限で実行
.\scripts\powershell\update-windows-settings.ps1
```

または `update.sh` を使用すると、NixOS rebuild 後に自動で適用するか確認されます。

## フォーマット (treefmt)

Nix の整形は treefmt で行います:

```bash
nix fmt
```

または:

```bash
./scripts/sh/treefmt.sh
```

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
| `nix/profiles/home/programs/terminals/` | ターミナル設定 (Windows Terminal, WezTerm) |

## ターミナル設定

### Windows Terminal
- 設定ソース: `nix/profiles/home/programs/terminals/windows-terminal/`
- キーバインド: `Ctrl+Shift+H` (水平分割), `Ctrl+Shift+V` (垂直分割), `Ctrl+Shift+X` (ペイン閉じる)

### WezTerm
- 設定ソース: `nix/profiles/home/programs/terminals/wezterm/`
- Leader key: `Ctrl+Q`
- キーバインド: `Leader+h` (水平分割), `Leader+v` (垂直分割), `Leader+x` (ペイン閉じる)

## トラブルシューティング

### ビルドエラー

```bash
# ドライランでエラーを確認
sudo nixos-rebuild dry-build --flake ~/.dotfiles --impure
```

### Windows Terminal 設定が反映されない

1. WSL で `nixos-rebuild switch` を実行
2. Windows で `.\scripts\powershell\update-windows-settings.ps1` を管理者権限で実行
3. Windows Terminal を再起動
