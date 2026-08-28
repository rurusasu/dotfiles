# Dotfiles

[![NixOS](https://img.shields.io/badge/NixOS-26.05-5277C3?logo=nixos&logoColor=white)](https://nixos.org/)
[![Home Manager](https://img.shields.io/badge/Home_Manager-Nix-5277C3?logo=nixos&logoColor=white)](https://github.com/nix-community/home-manager)
[![WSL](https://img.shields.io/badge/WSL-2-0078D6?logo=windows&logoColor=white)](https://docs.microsoft.com/en-us/windows/wsl/)
[![Bootstrap CI](https://github.com/rurusasu/dotfiles/actions/workflows/ci-bootstrap.yml/badge.svg)](https://github.com/rurusasu/dotfiles/actions/workflows/ci-bootstrap.yml)
[![ci-powershell](https://github.com/rurusasu/dotfiles/actions/workflows/ci-powershell.yml/badge.svg)](https://github.com/rurusasu/dotfiles/actions/workflows/ci-powershell.yml)
[![ci-chezmoi](https://github.com/rurusasu/dotfiles/actions/workflows/ci-chezmoi.yml/badge.svg)](https://github.com/rurusasu/dotfiles/actions/workflows/ci-chezmoi.yml)
[![ci-consistency](https://github.com/rurusasu/dotfiles/actions/workflows/ci-consistency.yml/badge.svg)](https://github.com/rurusasu/dotfiles/actions/workflows/ci-consistency.yml)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Windows、macOS、NixOS、Ubuntu、Debian を 1 コマンドで収束させる個人用 dotfiles リポジトリです。パッケージ定義は Nix catalog、ユーザー設定は Home Manager と chezmoi、OS サービスは各プラットフォームの宣言レイヤーで一元管理します。

## 技術スタック

| Category           | Technology                                         |
| ------------------ | -------------------------------------------------- |
| OS                 | Windows + NixOS-WSL, macOS, NixOS, Ubuntu, Debian  |
| Package catalog    | Nix Flakes (`nix/packages/sets.nix`)               |
| System convergence | winget handlers, nix-darwin, System Manager, NixOS |
| User environment   | Home Manager + chezmoi                             |
| Containers         | Docker Desktop / rootful Docker + Docker Compose   |
| Formatter          | treefmt-nix                                        |

## クイックスタート

clone 後、OS ごとの入口を 1 回実行します。installer は Nix、OS パッケージ、
Home Manager、chezmoi と明示的に選択した optional profile を適用します。
Docker profile では最後に runtime acceptance も実行します。途中で失敗した場合も
同じコマンドを再実行できます。

### Windows

PowerShell または Command Prompt で実行します。管理者処理は installer が必要に応じて分離します。

```powershell
git clone https://github.com/rurusasu/dotfiles.git
cd dotfiles
.\install.cmd
```

引数なしの `install.cmd` は core 環境だけを適用し、Ollama、Docker Desktop、
Hindsight、Hermes、Chrome、Discord、Chromium/browser-mcp は導入しません。
必要な構成だけを明示的に追加します。

```powershell
.\install.cmd -WithOllama # Ollama のみ
.\install.cmd -WithDocker # Docker のみ
.\install.cmd -WithMLflow # Ollama + Docker + MLflow
.\install.cmd -WithHindsight # Ollama + Docker + MLflow + Hindsight
.\install.cmd -WithHermes # Ollama + Docker + MLflow + Hindsight + Hermes + Chrome + Discord + browser-mcp
```

### macOS (Apple Silicon)

macOS 26 以降の Apple Silicon Mac で実行します。Nix のシステムコンポーネントを
導入するため、初回は管理者パスワードの入力が必要です。

```bash
git clone https://github.com/rurusasu/dotfiles.git
cd dotfiles
./install.sh
```

引数なしでは core 環境だけを適用し、Ollama、Docker Desktop、Hindsight、
Hermes、Chrome、Discord は install/update/起動の対象にしません。必要な構成だけを
明示的に追加します。`--with-docker` と `--with-hermes` の runtime は、chezmoi と
editor 同期が完了してから起動します。

```bash
./install.sh --with-ollama # Ollama のみ
./install.sh --with-docker # Ollama + Docker + 独立 Hindsight
./install.sh --with-hermes # 上記 + Hermes + Chrome + Discord + browser-mcp
```

Nix installer と nix-darwin がシステムを収束させ、nix-homebrew が選択した
Homebrew formula/cask を管理します。Home Manager と chezmoi も同じコマンド内で
適用します。macOS では WSL や NixOS を導入しません。

Tart CLI もこの macOS activation で導入されますが、約25GBの VM image は通常の `./install.sh` では取得しません。大容量ダウンロードを開始するタイミングを分離するため、初回だけ次を実行します。

```bash
task tart:prepare
task tart:run
```

`task tart:prepare` は `TART_HOME`（既定値 `~/.tart`）の空き容量を確認し、`tahoe-base` が既に存在する場合は再取得せず終了します。image、VM 名、必要空き容量は次で変更できます。

`task tart:run` はホストの Hindsight を起動し、VM の起動後に GitHub `main` の
commit hash を取得します。VM に最後に正常適用した hash と一致すれば何もせず、
更新時だけ `~/.dotfiles` を更新して、git・chezmoi・Neovim・Codex と WezTerm、
chezmoi 設定を適用します。適用に失敗した場合は hash を進めないため次回に再試行
されます。SSH reverse forward により VM の Codex も
`http://127.0.0.1:8888` の共有 Hindsight bank を利用します。

```bash
DOTFILES_TART_IMAGE=ghcr.io/cirruslabs/macos-tahoe-base:latest \
DOTFILES_TART_VM_NAME=tahoe-base \
DOTFILES_TART_MIN_FREE_GIB=40 \
task tart:prepare
```

`latest` image の更新は通常の dotfiles activation では自動実行しません。既存 VM を更新する場合は、必要な VM の退避・削除を確認してから明示的に再作成してください。

### NixOS / Ubuntu / Debian

Linux では同じ入口が `/etc/NIXOS` と `/etc/os-release` を見て自動振り分けします。

```bash
git clone https://github.com/rurusasu/dotfiles.git
cd dotfiles
./install.sh
```

- NixOS: `nixos-rebuild switch` に Home Manager と rootful Docker を含めます。
- Ubuntu / Debian: Nix を必要に応じて導入し、System Manager + Home Manager + rootful Docker を適用します。
- どちらも既存ユーザーの UID、GID、home、primary group を保持します。

NixOS は現在の `/etc/nixos/hardware-configuration.nix` を必須の host profile として読み込みます。固定ディスク構成はリポジトリに持たず、このファイルが存在しない場合は activation 前に停止します。

### その他の Linux

Full support ではありません。Docker や systemd の収束を行わない Home Manager のみの fallback を、明示的に opt-in した場合だけ実行できます。

```bash
DOTFILES_ALLOW_USER_ONLY=1 ./install.sh
```

### 成功条件と CI

「コマンドが終了した」だけでは成功扱いにしません。必須 CLI と chezmoi drift を acceptance で確認し、Docker を選択した profile では Docker daemon、Compose、`docker run --rm hello-world` も確認します。CI は GitHub-hosted Actions だけで完結し、Windows は PowerShell/Pester、macOS は Bats と nix-darwin build で installer 契約を検証します。Ubuntu、Debian、NixOS は hosted E2E で installer を 2 回適用し、Docker と Compose の runtime acceptance まで実行します。

標準の hosted Windows/macOS runner では Docker Desktop の VM を起動しないため、その実機固有部分は各 OS で one-command installer を実行した際の acceptance が判定します。ローカル acceptance が失敗した場合、installer はセットアップ成功を表示しません。

## 方針

Nix catalog は各 OS の provider を定義し、OS の宣言レイヤーと Home Manager がそれを消費します。chezmoi は shell、Git、terminal、editor などの設定ファイルを管理します。

- ユーザー設定: `chezmoi/`
- Home Manager: `nix/home/common.nix`
- macOS: `nix/hosts/darwin/`
- Ubuntu / Debian: `nix/system-manager/`
- NixOS / WSL: `nix/hosts/`
- パッケージ provider catalog: `nix/packages/sets.nix`

## ディレクトリ構造

詳細は [docs/architecture.md](./docs/architecture.md) を参照。

```
dotfiles/
├── chezmoi/                # User dotfiles (chezmoi)
├── nix/                    # NixOS configuration
├── scripts/                # Shell/PowerShell scripts
├── windows/                # Windows-side config files
├── docs/                   # Documentation
├── Taskfile.yml            # Task runner
├── taskfiles/              # Feature-scoped Taskfiles
├── install.sh              # macOS / NixOS / Ubuntu / Debian launcher
├── install.cmd             # Windows launcher for install.ps1
├── scripts/powershell/install.ps1 # NixOS WSL installer entrypoint
└── flake.nix               # Nix flake entry point
```

## 日常の使い方

### 設定の更新

WSL 内で実行:

```bash
# 方法1: update.sh を使う（NixOS rebuild + winget 適用を一括実行）
~/.dotfiles/scripts/sh/update.sh

# 方法2: エイリアスを使う（NixOS rebuild + profile 更新 + Hermes bootstrap）
nrs  # alias for: task --dir ~/.dotfiles nrs
```

Windows 側のファイルを編集すると、`~/.dotfiles` シンボリックリンク経由で即座に WSL から参照可能。

### ターミナル設定を Windows に適用

chezmoi を使って Windows に設定を適用します。詳細は [docs/chezmoi/](./docs/chezmoi/) を参照。

```powershell
# GitHub から直接取得（クローン不要・推奨）
winget install -e --id twpayne.chezmoi
chezmoi init rurusasu/dotfiles --source-path chezmoi && chezmoi apply

# 同梱スクリプトで一括適用
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

| Location                    | Description                             |
| --------------------------- | --------------------------------------- |
| `~/.dotfiles`               | Windows dotfiles へのシンボリックリンク |
| `nixosConfigurations.nixos` | WSL ホスト用 Flake attribute            |
| `chezmoi/`                  | User dotfiles (chezmoi source)          |

## ターミナル設定

詳細は [docs/chezmoi/structure.md](./docs/chezmoi/structure.md) を参照。

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

### installer が途中で停止した

同じ installer を再実行すると、完了済みの宣言状態を再利用して停止した phase から収束できます。runtime だけを再確認する場合:

```bash
./scripts/sh/verify-environment.sh --runtime
systemctl status system-manager.target docker.service docker.socket
docker compose -f docker/hermes-agent/compose.yml ps
```

NixOS では `system-manager.target` の代わりに `readlink /run/current-system` と `nixos-rebuild list-generations` を確認します。macOS は `darwin-rebuild --list-generations` と Docker Desktop の起動状態を確認します。Windows は次を実行します。

```powershell
.\scripts\powershell\Test-Environment.ps1 -Runtime
```

### macOS の WezTerm nightly cask

`wezterm@nightly` は nix-darwin の Homebrew cask として管理されます。
Homebrew cask の適用に失敗する場合は、[Homebrew cask のトラブルシューティング](./docs/nix/homebrew-cask-troubleshooting.md)
を参照してください。

### Windows Terminal 設定が反映されない

1. Windows で `chezmoi apply` を実行
2. Windows Terminal を再起動
