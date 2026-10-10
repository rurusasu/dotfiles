# Dotfiles

[![NixOS](https://img.shields.io/badge/NixOS-26.05-5277C3?logo=nixos&logoColor=white)](https://nixos.org/)
[![Home Manager](https://img.shields.io/badge/Home_Manager-Nix-5277C3?logo=nixos&logoColor=white)](https://github.com/nix-community/home-manager)
[![WSL](https://img.shields.io/badge/WSL-2-0078D6?logo=windows&logoColor=white)](https://docs.microsoft.com/en-us/windows/wsl/)
[![Bootstrap CI](https://github.com/rurusasu/dotfiles/actions/workflows/ci-nix.yml/badge.svg)](https://github.com/rurusasu/dotfiles/actions/workflows/ci-nix.yml)
[![Other CI](https://github.com/rurusasu/dotfiles/actions/workflows/ci-other.yml/badge.svg)](https://github.com/rurusasu/dotfiles/actions/workflows/ci-other.yml)
[![ci-chezmoi](https://github.com/rurusasu/dotfiles/actions/workflows/ci-chezmoi.yml/badge.svg)](https://github.com/rurusasu/dotfiles/actions/workflows/ci-chezmoi.yml)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Windows、macOS、NixOS、Ubuntu、Debian を 1 コマンドで収束させる個人用 dotfiles リポジトリです。パッケージ定義は Nix catalog、ユーザー設定は Home Manager と chezmoi、OS サービスは各プラットフォームの宣言レイヤーで一元管理します。

## 技術スタック

| Category           | Technology                                                |
| ------------------ | --------------------------------------------------------- |
| OS                 | Windows + NixOS-WSL, macOS, NixOS, Ubuntu, Debian         |
| Package catalog    | Nix Flakes (`nix/packages/catalog/`、公開入口 `sets.nix`) |
| System convergence | winget handlers, nix-darwin, NixOS                        |
| User environment   | Home Manager + chezmoi                                    |
| Containers         | Docker Desktop / rootful Docker + Docker Compose          |
| Formatter          | treefmt-nix                                               |

## クイックスタート

clone 後、OS ごとの入口を 1 回実行します。installer は Nix、OS パッケージ、
Unix は Home Manager、Windows は chezmoi と明示的に選択した optional profile を適用します。
Docker profile では最後に runtime acceptance も実行します。途中で失敗した場合も
同じコマンドを再実行できます。

macOS / Linux の `./install.sh` は、Nix が未導入なら初回だけ導入し、
その後は flake inputs を最新に更新して OS の Nix 構成を `switch` します。
Windows / WSL も `switch` 前に inputs を更新します。更新に失敗した場合は反映しません。
リポジトリの pull / merge と独自パッケージの更新は別途行います。

```bash
# macOS の独自パッケージを更新するとき
task darwin:update
./install.sh
```

Codex CLI の個別インストールは行わず、ChatGPT アプリ付属の CLI を使います。
Node.js/npm はカタログ、Unix の dsh は Nix module、Windows の dsh は npm が導入します。
pnpm と Bun は導入しません。

### Windows

PowerShell または Command Prompt で実行します。管理者処理は installer が必要に応じて分離します。

```powershell
git clone https://github.com/rurusasu/dotfiles.git
cd dotfiles
.\install.cmd
```

`install.cmd` は宣言済みの Windows パッケージと通常の WSL ディストリビューションとしての
NixOS-WSL を適用します。Hermes は NixOS 内に Nix/Home Manager で直接導入し、
systemd user service として実行します。Windows に Hermes や Docker Desktop を導入する処理はありません。
NixOS/Hermes の直接実行に Docker は不要です。既に導入済みの Docker Desktop の連携と Docker runtime acceptance は
PowerShell で `scripts/powershell/install.ps1` に
`-Options @{ EnableDockerDesktopIntegration = $true }` を渡した場合だけ実行します。
Docker Desktop の VHDX 拡張も同じ入口の `-Options @{ ExpandDockerVhd = $true }` で明示的に選択します。

### macOS (Apple Silicon)

macOS 26 以降の Apple Silicon Mac で実行します。Nix のシステムコンポーネントを
導入するため、初回は管理者パスワードの入力が必要です。

```bash
git clone https://github.com/rurusasu/dotfiles.git
cd dotfiles
./install.sh
```

`./install.sh` は宣言済みの macOS パッケージ、Docker Desktop と native Hermes を
適用します。機能別の選択フラグは不要です。
Docker Desktop のライセンス同意と初期設定も nix-darwin の activation で管理するため、
実行前の環境変数設定は不要です。初期設定済みの環境では既存の完了マーカーを引き継ぎます。
macOS / NixOS / WSL の Docker 設定は [`nix/modules/docker.nix`](./nix/modules/docker.nix) に集約しています。
Docker の設定は同モジュールが所有し、installer に Docker 用の環境変数はありません。
1Password の環境変数は Home Manager が管理します。

macOS の初回導入には Lix installer を使い、nix-darwin の `nix.package` も
`pkgs.lixPackageSets.stable.lix` に統一します。既存の Nix 環境は nix-darwin の反映で
Lix に切り替わります。nix-darwin がシステムを収束させ、nix-homebrew が選択した
Homebrew formula/cask を管理します。Home Manager も同じコマンド内で
適用します。macOS では WSL や NixOS を導入しません。

macOS 構成では、Hermes Desktop は公式 Homebrew Cask
`hermes-desktop` として nix-homebrew から導入され、Agent CLI と gateway は
Nix/Home Manager が管理する native per-user service として起動します。
Docker Compose は Chromium / Browser MCP / X API MCP の sidecar を提供します。
旧 Docker Agent / Dashboard とその bootstrap の実行経路は削除済みです。
既存の Docker volume は変更せず、Hermes の設定や runtime state は Nix store
に保存しません。

詳細は [Hermes Desktop の運用](./docs/hermes-agent/desktop.md) を参照してください。

Tart CLI もこの macOS activation で導入されますが、約25GBの VM image は通常の `./install.sh` では取得しません。大容量ダウンロードを開始するタイミングを分離するため、初回だけ次を実行します。

```bash
task tart:prepare
task tart:run
```

`task tart:prepare` は `TART_HOME`（既定値 `~/.tart`）の空き容量を確認し、`tahoe-base` が既に存在する場合は再取得せず終了します。image、VM 名、必要空き容量は次で変更できます。

`task tart:run` は VM を起動し、 GitHub `main` の
commit hash を取得します。VM に最後に正常適用した hash と一致すれば何もせず、
更新時だけ `~/.dotfiles` を更新して、通常の `install.sh` で macOS のアプリと
OS・Home Manager 設定をまとめて適用します。Tart 専用の最小パッケージ
集合やインストーラーは持ちません。適用に失敗した場合は hash を進めないため次回に再試行
されます。

既存 guest の旧専用 CLI profile は、OS 管理のコマンドを確認した後に移行します。
旧 profile を指す管理済みリンクだけを削除し、通常ファイル・別のリンク・
Nix store のパッケージ本体は削除しません。

```bash
DOTFILES_TART_IMAGE=ghcr.io/cirruslabs/macos-tahoe-base:latest \
DOTFILES_TART_VM_NAME=tahoe-base \
DOTFILES_TART_MIN_FREE_GIB=40 \
task tart:prepare
```

`latest` image の更新は通常の dotfiles activation では自動実行しません。既存 VM を更新する場合は、必要な VM の退避・削除を確認してから明示的に再作成してください。

### Linux / NixOS

Linux では同じ入口が `/etc/NIXOS` を見て自動振り分けします。

```bash
git clone https://github.com/rurusasu/dotfiles.git
cd dotfiles
./install.sh
```

- NixOS: `nixos-rebuild switch` に Home Manager と rootful Docker を含めます。
- その他の Linux（Ubuntu / Debian など）: Nix を必要に応じて導入し、Home Manager を適用します。ユーザー環境のみを管理し、Docker・systemd・既存アカウントは変更しません。

NixOS は現在の `/etc/nixos/hardware-configuration.nix` を必須の host profile として読み込みます。固定ディスク構成はリポジトリに持たず、このファイルが存在しない場合は activation 前に停止します。

### 成功条件と CI

システム統合の installer は必須 CLI を acceptance で確認し、Docker を選択した profile では Docker daemon、Compose、`docker run --rm hello-world` も確認します。非 NixOS Linux は Home Manager の build・activation までが対象です。CI は GitHub-hosted Actions だけで完結し、Nix の option、package、flake output は Nix-native `nix-unit`、Windows は PowerShell/Pester、macOS の installer/runtime 契約は Bats で検証します。NixOS は hosted VM E2E で installer の再実行と Docker・Compose の runtime acceptance を検証します。

標準の hosted Windows/macOS runner では Docker Desktop の VM を起動しないため、その実機固有部分は各 OS で one-command installer を実行した際の acceptance が判定します。ローカル acceptance が失敗した場合、installer はセットアップ成功を表示しません。

## 方針

Nix catalog は各 OS の provider を定義し、OS の宣言レイヤーと Home Manager がそれを消費します。chezmoi は Windows 専用の設定を配布します。Unix の Codex、shell、Git、terminal、editor などは Home Manager が管理します。

- ユーザー設定: Unix は `nix/home/` と `nix/modules/`、Windows は `chezmoi/`
- Home Manager: `nix/home/common.nix`
- macOS system: `nix/hosts/aarch64-darwin/default.nix` が entrypoint、`configuration.nix` が system/cask/activation の実体
- 非 NixOS Linux: `nix/hosts/<system>/home.nix` と standalone Home Manager
- NixOS / WSL: `nix/hosts/<system>/<environment>/default.nix` が entrypoint、`configuration.nix` が host 固有設定
- パッケージ provider catalog: `nix/packages/catalog/`、既存 consumer の公開入口: `nix/packages/sets.nix`

package データ、provider 選択、installer metadata、host 動作を分け、各定義は一度だけ管理します。
SSOT と巨大な 1 ファイルを同一視せず、変更理由ごとに編集先を決めます。
詳細は [パッケージ管理の分割方針](./docs/nix/package-management.md#分割の理由と編集先) を参照してください。

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

ホスト設定は全 OS で同じ分割を標準とします。`default.nix` は import の入口に限定し、system、service、user、cask、activation などのホスト固有設定は `configuration.nix` に置きます。

```
nix/hosts/
├── darwin/
│   ├── default.nix          # nix-darwin entrypoint
│   └── configuration.nix    # macOS system/cask/activation
├── linux/
│   ├── default.nix          # NixOS entrypoint
│   └── configuration.nix    # native NixOS configuration
└── wsl/
    ├── default.nix          # NixOS-WSL entrypoint
    └── configuration.nix    # WSL configuration
```

## 日常の使い方

### 設定の更新

WSL 内で実行:

```bash
# flake inputs の更新と NixOS の反映
nrs  # alias for: task --dir ~/.dotfiles nrs

# installer でも inputs の更新と反映
~/.dotfiles/install.sh
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

設定の配置は [ディレクトリ構造](./docs/chezmoi/structure.md)、デスクトップとターミナルの操作範囲は [キーバインド統一方針](./docs/chezmoi/keybindings.md) を参照。

### Windows Terminal

- 設定ソース: `chezmoi/terminals/windows-terminal/settings.json`
- 共通 prefix: `Ctrl+Space`（AutoHotkey adapter）。続けて `v` で左右分割、`-` で上下分割、`x` でペインを閉じる

### WezTerm

- 設定ソース: `chezmoi/terminals/wezterm/wezterm.lua`
- Leader key: `Ctrl+Space`
- prefix に続けて `v` で左右分割、`-` で上下分割、`x` でペインを閉じる

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
docker compose -f docker/hermes-service/compose.yml ps
```

NixOS では `readlink /run/current-system`、`nixos-rebuild list-generations`、`systemctl status docker.service docker.socket` を確認します。非 NixOS Linux の通常検証は `./scripts/sh/verify-environment.sh` を使い、Docker は管理対象外です。macOS は `darwin-rebuild --list-generations` と Docker Desktop の起動状態を確認します。Windows は次を実行します。

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
