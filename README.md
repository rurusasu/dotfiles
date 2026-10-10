# Dotfiles

[![NixOS](https://img.shields.io/badge/NixOS-26.05-5277C3?logo=nixos&logoColor=white)](https://nixos.org/)
[![Home Manager](https://img.shields.io/badge/Home_Manager-Nix-5277C3?logo=nixos&logoColor=white)](https://github.com/nix-community/home-manager)
[![WSL](https://img.shields.io/badge/WSL-2-0078D6?logo=windows&logoColor=white)](https://docs.microsoft.com/en-us/windows/wsl/)
[![Bootstrap CI](https://github.com/rurusasu/dotfiles/actions/workflows/ci-nix.yml/badge.svg)](https://github.com/rurusasu/dotfiles/actions/workflows/ci-nix.yml)
[![Other CI](https://github.com/rurusasu/dotfiles/actions/workflows/ci-other.yml/badge.svg)](https://github.com/rurusasu/dotfiles/actions/workflows/ci-other.yml)
[![ci-chezmoi](https://github.com/rurusasu/dotfiles/actions/workflows/ci-chezmoi.yml/badge.svg)](https://github.com/rurusasu/dotfiles/actions/workflows/ci-chezmoi.yml)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Windows の GUI アプリと、macOS、NixOS、Ubuntu、Debian の環境を管理する個人用 dotfiles リポジトリです。パッケージ定義は Nix catalog、ユーザー設定は Home Manager と chezmoi、OS サービスは各プラットフォームの宣言レイヤーで一元管理します。NixOS-WSL は Windows の GUI installer とは別に手動で導入します。

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

clone 後、OS ごとの入口を実行します。Unix の installer は Nix、OS パッケージ、
Home Manager を適用します。Windows の installer は GUI アプリだけを導入・更新します。
Unix の Docker profile では最後に runtime acceptance も実行します。途中で失敗した場合も
同じコマンドを再実行できます。

更新も同じ入口を使います。macOS / Linux は `./install.sh`、Windows は
`.\install.cmd` を再実行してください。既存の optional profile を更新する場合も、
初回と同じ profile 引数を指定します。リポジトリ自体の pull / merge は自動では行いません。

- macOS: flake inputs と Orca・Dia の独自 Nix 定義を更新してから、
  nix-darwin / Home Manager と選択済み Homebrew パッケージを反映します。
- Linux / NixOS: flake inputs を更新し、その OS の構成と Home Manager を反映します。
- Windows: GUI profile のアプリを既存の WinGet で install / upgrade します。
  CLI、管理者フェーズ、chezmoi、WSL の setup は実行しません。

macOS の独自パッケージ更新は `version` / URL / hash をチェックアウト内で更新します。
差分は `git diff` で確認できます。取得エラーがある場合は独自定義を書き換えず、
システム反映前に停止します（先行する `flake.lock` の更新は残ります）。
GitHub API の認証には、設定されていれば `GH_TOKEN`、次に `GITHUB_TOKEN` を使用します。
レート制限時は認証設定を確認して再実行してください。固定版 / オフライン検証向けの
`DOTFILES_SKIP_FLAKE_UPDATE=1` は、Unix の flake 更新と macOS の独自パッケージ更新を
スキップします。必要な依存パッケージは事前にキャッシュされている必要があります。

### Windows

既存の PowerShell と WinGet が必要です。PowerShell または Command Prompt で実行します。

```powershell
git clone https://github.com/rurusasu/dotfiles.git
cd dotfiles
.\install.cmd
```

`install.cmd` は宣言済みの GUI アプリだけを導入・更新します。WezTerm と Windows Terminal も対象です。
CLI の導入、管理者フェーズ、chezmoi の設定配布、WSL/NixOS、Docker Desktop 連携、VHDX 拡張は実行しません。
既存ソフトウェアのアンインストールや古い Startup ショートカットの削除も行いません。

NixOS-WSL は別途、[公式手順](https://nix-community.github.io/NixOS-WSL/install.html)に従って
`nixos.wsl` をダウンロードします。未導入の場合、WSL 2.4.4 以降では次のように導入できます。

```powershell
wsl --install --from-file "$env:USERPROFILE\Downloads\nixos.wsl"
wsl -d NixOS
```

既定の登録名は `NixOS` です。初回起動後、WSL 内で
`scripts/sh/nixos-wsl-postinstall.sh` を手動実行して NixOS/Home Manager を適用します。
実行例と同期・stateVersion の注意点は [NixOS-WSL インストール](./docs/nix/nixos-wsl-install.md)を参照してください。

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

Unix のシステム統合 installer は必須 CLI を acceptance で確認し、Docker を選択した profile では Docker daemon、Compose、`docker run --rm hello-world` も確認します。非 NixOS Linux は Home Manager の build・activation までが対象です。Windows の installer は GUI アプリの導入結果を検証します。CI は GitHub-hosted Actions だけで完結し、Nix の option、package、flake output は Nix-native `nix-unit`、Windows は PowerShell/Pester、macOS の installer/runtime 契約は Bats で検証します。NixOS は hosted VM E2E で installer の再実行と Docker・Compose の runtime acceptance を検証します。

標準の hosted macOS runner では Docker Desktop の VM を起動しないため、その実機固有部分は macOS の installer を実行した際の acceptance が判定します。ローカル acceptance が失敗した場合、installer はセットアップ成功を表示しません。Windows の GUI installer は Docker runtime acceptance を実行しません。

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
├── scripts/powershell/install.ps1 # Windows GUI-app installer entrypoint
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
# 方法1: update.sh を使う（NixOS rebuild + winget 適用を一括実行）
~/.dotfiles/scripts/sh/update.sh

# 方法2: エイリアスを使う（NixOS rebuild + profile 更新 + Hermes bootstrap）
nrs  # alias for: task --dir ~/.dotfiles nrs
```

Windows 側のファイルを編集すると、`~/.dotfiles` シンボリックリンク経由で即座に WSL から参照可能。

### ターミナル設定を Windows に適用

必要な場合だけ、GUI installer とは別に chezmoi を使って Windows に設定を手動適用します。`install.cmd` はこの処理を実行しません。詳細は [docs/chezmoi/](./docs/chezmoi/) を参照。

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

NixOS では `readlink /run/current-system`、`nixos-rebuild list-generations`、`systemctl status docker.service docker.socket` を確認します。非 NixOS Linux の通常検証は `./scripts/sh/verify-environment.sh` を使い、Docker は管理対象外です。macOS は `darwin-rebuild --list-generations` と Docker Desktop の起動状態を確認します。Windows は PowerShell / WinGet とエラー内容を確認して GUI installer を再実行します。WSL の手動 setup は [NixOS-WSL インストール](./docs/nix/nixos-wsl-install.md)を参照してください。

```powershell
.\install.cmd -NoPause
```

### macOS の WezTerm nightly cask

`wezterm@nightly` は nix-darwin の Homebrew cask として管理されます。
Homebrew cask の適用に失敗する場合は、[Homebrew cask のトラブルシューティング](./docs/nix/homebrew-cask-troubleshooting.md)
を参照してください。

### Windows Terminal 設定が反映されない

1. Windows で `chezmoi apply` を実行
2. Windows Terminal を再起動
