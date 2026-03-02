# AGENTS

Purpose: Shell scripts for NixOS setup, maintenance, and Windows package management.

## Directory Structure

```
scripts/
├── sh/                           # Shell scripts (Linux/WSL)
│   ├── update.sh                 # Daily update script (NixOS rebuild + optional winget)
│   ├── nixos-wsl-postinstall.sh  # Post-install setup for NixOS WSL
│   ├── treefmt.sh                # Code formatting
│   └── tests/
│       └── integration_test.sh   # NixOS インテグレーションテスト（ツール存在確認）
└── powershell/                   # PowerShell scripts (Windows)
    ├── install.ps1               # メインインストールスクリプト（UAC 自動昇格付き）
    ├── install.admin.ps1         # 管理者権限ハンドラー実行
    ├── install.user.ps1          # ユーザー権限ハンドラー実行
    ├── Debug-WingetDetection.ps1 # winget 検出デバッグ用
    ├── PSScriptAnalyzerSettings.psd1 # PSScriptAnalyzer 設定
    ├── lib/                      # 共通ライブラリ (see powershell/AGENTS.md)
    ├── handlers/                 # セットアップハンドラー 12 個 (see handlers/AGENTS.md)
    └── tests/                    # Pester テストスイート (see tests/AGENTS.md)
```

## Shell Scripts (Linux/WSL)

### nixos-wsl-postinstall.sh

Post-install setup script run after NixOS WSL import.

#### Sync Modes

| Mode             | Description                                          |
| ---------------- | ---------------------------------------------------- |
| `link` (default) | Creates symlink ~/.dotfiles -> Windows dotfiles path |
| `repo`           | Copies dotfiles to ~/.dotfiles via rsync             |
| `nix`            | Copies only nix/ directory                           |
| `none`           | No sync, manual setup required                       |

#### Key Options

- `--sync-mode <mode>`: Sync mode (default: link)
- `--sync-source <path>`: Source directory (default: script's parent dir)
- `--repo-dir <path>`: Target directory (default: /home/<user>/.dotfiles)
- `--flake-name <name>`: Flake host name (default: nixos)
- `--force`: Allow overwriting existing repo-dir

#### Flow

1. Create ~/.dotfiles (symlink or copy based on sync-mode)
2. Generate user/host nix files if missing
3. Run nixos-rebuild switch
4. Sync back flake.lock if sync-back=lock

## PowerShell Scripts (Windows)

PowerShell スクリプトの詳細は [powershell/AGENTS.md](./powershell/AGENTS.md) を参照。

### install.ps1

メインインストールスクリプト。UAC 自動昇格付きでセットアップハンドラーを実行する。

**Usage:**

```powershell
# GitHub から直接取得してインストール
irm https://raw.githubusercontent.com/rurusasu/dotfiles/main/scripts/powershell/install.ps1 | iex

# ローカルで実行（管理者権限不要。スクリプトが自動で UAC 昇格）
.\scripts\powershell\install.ps1
```
