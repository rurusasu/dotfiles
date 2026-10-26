# Dotfiles

[![NixOS](https://img.shields.io/badge/NixOS-26.05-5277C3?logo=nixos&logoColor=white)](https://nixos.org/)
[![Home Manager](https://img.shields.io/badge/Home_Manager-Nix-5277C3?logo=nixos&logoColor=white)](https://github.com/nix-community/home-manager)
[![WSL](https://img.shields.io/badge/WSL-2-0078D6?logo=windows&logoColor=white)](https://docs.microsoft.com/en-us/windows/wsl/)
[![Bootstrap CI](https://github.com/rurusasu/dotfiles/actions/workflows/ci-nix.yml/badge.svg)](https://github.com/rurusasu/dotfiles/actions/workflows/ci-nix.yml)
[![Chezmoi CI](https://github.com/rurusasu/dotfiles/actions/workflows/ci-chezmoi.yml/badge.svg)](https://github.com/rurusasu/dotfiles/actions/workflows/ci-chezmoi.yml)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Windows の GUI アプリと、macOS、NixOS、Ubuntu、Debian の環境を管理する個人用 dotfiles リポジトリです。Unix のパッケージ導入と設定は Nix module / Home Manager、Windows の GUI 導入は独立した WinGet manifest、ユーザー設定は chezmoi、OS サービスは各プラットフォームの宣言レイヤーで管理します。Windows installer は NixOS-WSL の導入と設定適用も行います。

## 技術スタック

| Category           | Technology                                               |
| ------------------ | -------------------------------------------------------- |
| OS                 | Windows + NixOS-WSL, macOS, NixOS, Ubuntu, Debian        |
| Packages           | Unix: Nix modules (`nix/modules/`)、Windows: WinGet JSON |
| System convergence | winget handlers, nix-darwin, NixOS                       |
| User environment   | Home Manager + chezmoi                                   |
| Containers         | Docker Desktop / rootful Docker + Docker Compose         |
| Formatter          | treefmt-nix                                              |

## クイックスタート

clone 後、OS ごとの入口を実行します。Unix の installer は Nix、OS パッケージ、
Home Manager を適用します。Windows の installer は GUI アプリの導入・更新と NixOS-WSL の設定適用を行います。
Unix の Docker profile では最後に runtime acceptance も実行します。途中で失敗した場合も
同じコマンドを再実行できます。

macOS / Linux の `./install.sh` は、Nix が未導入なら初回だけ導入し、
その後は flake inputs を最新に更新して OS の Nix 構成を `switch` します。
WSL も `switch` 前に inputs を更新します。更新に失敗した場合は反映しません。
リポジトリの pull / merge は別途行います。

- macOS: flake inputs を更新してから、nix-darwin / Home Manager と Homebrew パッケージを反映します。
- Linux / NixOS: flake inputs を更新し、その OS の構成と Home Manager を反映します。
- Windows: GUI profile のアプリを既存の WinGet で install / upgrade し、NixOS-WSL を導入・設定します。
  Windows の CLI パッケージと chezmoi は導入・適用しません。WSL 基盤の有効化だけ管理者権限で行います。

```bash
# flake inputs だけを更新するとき
nix flake update
```

Codex CLI の個別インストールは行わず、ChatGPT アプリ付属の CLI を使います。
単純な CLI の有効化・package 宣言は `nix/defaults.nix` に直接書きます。設定・package override・生成・連携を持つアプリは `nix/modules/` にまとめます。
ユーザー環境の Python は Hermes 同梱の interpreter を使います。uv はプロジェクトの依存管理に使い、Python を別途インストールしません。
Windows の GUI profile は Node.js/npm や dsh を導入しません。
pnpm と Bun は導入しません。

### Windows

既存の PowerShell と WinGet が必要です。PowerShell または Command Prompt で実行します。

```powershell
git clone https://github.com/rurusasu/dotfiles.git
cd dotfiles
.\install.cmd
```

`install.cmd` は宣言済みの GUI アプリを導入・更新した後、NixOS-WSL を導入し、checkout の同期と NixOS/Home Manager の適用を行います。WezTerm と Windows Terminal も対象です。
既存の NixOS ディストリビューションと保存済み `stateVersion` は再利用します。WSL 基盤が未導入の場合だけ UAC で有効化し、再起動後の再実行を案内します。登録と設定適用は元のユーザーで行います。
Windows の CLI パッケージ導入、chezmoi の設定配布、Docker Desktop 連携、VHDX 拡張は実行しません。
既存ソフトウェアのアンインストールや古い Startup ショートカットの削除も行いません。

GUI アプリだけをセットアップする場合は、WSL を呼び出さず次を実行します。

```powershell
.\install.cmd -UserPhaseOnly
```

実行順序は `taskfiles/install/taskfile.yml` が管理します。Task が見つからなければ、installer 専用の実行ファイルを `%LOCALAPPDATA%\dotfiles\tools\task` に取得します。永続 PATH は変更しません。
既定の登録名は `NixOS`、同期方式は `link` です。`-DistroName`、`-InstallDir`、`-ReleaseTag`、`-SyncMode`、`-SyncBack`、`-StateVersion`、`-ForcePostInstall` で指定できます。
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
ログインユーザーで実行すると、そのアカウントを `system.primaryUser` に設定し、
Home Manager と Homebrew にも使用します。スクリプト自体に `sudo` は付けません。
Docker Desktop のライセンス同意と初期設定も nix-darwin の activation で管理するため、
実行前の環境変数設定は不要です。初期設定済みの環境では既存の完了マーカーを引き継ぎます。
macOS / NixOS / WSL の Docker 設定は [`nix/modules/docker.nix`](./nix/modules/docker.nix) に集約しています。
Docker の設定は同モジュールが所有し、installer に Docker 用の環境変数はありません。
1Password の環境変数は Home Manager が管理します。

macOS / Linux の初回導入には [Lix installer](https://lix.systems/install/) を使います。
macOS / NixOS / WSL の `nix.package` と standalone Home Manager の CLI・GC は
`pkgs.lixPackageSets.stable.lix` に統一します。既存のシステム管理下の Nix は
nix-darwin / NixOS の反映で Lix に切り替わります。
nix-darwin がシステムを収束させ、nix-homebrew が選択した
Homebrew formula/cask を管理します。Home Manager も同じコマンド内で
適用します。macOS では WSL や NixOS を導入しません。

macOS では `darwin-uninstaller` を有効にします。
Lix installer で新規導入した macOS / Linux では `/nix/lix-installer` と receipt が保持され、
[installer の uninstall](https://git.lix.systems/lix-project/lix-installer#uninstalling) を利用できます。
アンインストールは Nix 環境を削除するため、実行前に必要な設定・データを退避してください。
macOS では nix-darwin を先に解除します。NixOS / WSL は OS が Nix を管理するため、
Lix installer のアンインストール対象ではありません。
既存の standalone Linux では Home Manager が CLI を切り替え、既存 daemon は元の導入方法で管理します。

macOS / Linux 構成では、`nix/modules/ai_agents/hermes/` が upstream の Home Manager
module を使い、Hermes CLI・Desktop・native gateway の導入と設定を管理します。Linux は native NixOS、WSLg、standalone Home Manager で利用できます。
gateway は Nix/Home Manager が管理する native per-user service として起動します。
Codex と root Hermes は共通の MCP 定義から、native `mcp-chrome` / `mcp-xapi`
service に HTTP で接続します。各 service が1つの stdio process を保持し、既存の
`http://127.0.0.1:8765/mcp` / `http://127.0.0.1:8766/mcp` を使います。ブラウザは
headless のため display や WSLg は不要です。Chrome DevTools MCP は `mcp-servers` input の
既製 Nix package、xurl は `xurl` input に固定した upstream source を使い、
通常の `nix flake update` で更新します。
既存の `~/.hermes/.browser` と `~/.hermes/.xurl` は保持します。native xurl の
`~/.xurl` は Home Manager が XDG 経由で既存 cache へリンクし、既存実体との衝突では
反映を停止します。MCP service は Linux の systemd user service / macOS の launchd が
管理します。Hermes 用 Docker Agent / Dashboard / browser / X API sidecar は
削除済みです。既存の Docker volume と Hermes の runtime state はそのまま保持します。

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
- その他の Linux（Ubuntu / Debian など）: Lix を必要に応じて導入し、Home Manager を適用します。初回の Lix installer は管理者権限で daemon・ビルド用アカウントを構成します。その後の Home Manager はユーザー環境を管理し、Docker・OS のサービス・既存アカウントは変更しません。

native NixOS 構成は `/etc/nixos/hardware-configuration.nix` がある場合だけ公開します。ユーザー名と各 stateVersion は `nix/defaults.nix:systemDefaults` 内の `defaults` で管理します。

### 成功条件と CI

Unix のシステム統合 installer は必須 CLI を acceptance で確認し、Docker を選択した profile では Docker daemon、Compose、`docker run --rm hello-world` も確認します。非 NixOS Linux は Home Manager の build・activation までが対象です。Windows の installer は GUI アプリの導入結果を検証します。CI は GitHub-hosted Actions だけで完結し、Nix の option、package、flake output は Nix-native `nix-unit`、Windows は PowerShell/Pester、macOS の installer/runtime 契約は Bats で検証します。NixOS は hosted VM E2E で installer の再実行と Docker・Compose の runtime acceptance を検証します。

標準の hosted macOS runner では Docker Desktop の VM を起動しないため、その実機固有部分は macOS の installer を実行した際の acceptance が判定します。ローカル acceptance が失敗した場合、installer はセットアップ成功を表示しません。Windows の GUI installer は Docker runtime acceptance を実行しません。

## 方針

Unix の導入とアプリ設定は `nix/modules/`、Windows の導入情報は `windows/winget/packages.json` で管理します。chezmoi は Windows 専用の設定を配布します。Unix の Codex、shell、Git、terminal、editor などは Home Manager が管理します。

- 共通・OS 別の system / ユーザー設定: `nix/defaults.nix:systemDefaults`
- Home Manager: 同じ `home-manager.sharedModules` を統合構成と standalone で共有
- OS 選択: 末尾の構成登録で `specialArgs.platform` を指定
- Windows のユーザー設定: `chezmoi/`
- Unix CLI / GUI の導入・設定・連携・専用の実行依存: `nix/modules/` のアプリごとの module。enable・単純な package list・単一代入は必要な構成へ直接記載。Windows の GUI 導入: `windows/winget/packages.json`

Unix CLI / GUI はアプリごとの module が package 選択・設定・連携・専用の実行依存を所有します。enable・単純な package list・単一代入だけなら module を作らず必要な構成へ直接書きます。共通・OS 別構成は module の外で明示的な imports により組み立てます。
通常の CLI・GUI とユーザー設定は Home Manager、OS 固有の設定・権限・システムサービス・連携は `nix/defaults.nix`、Windows の導入情報は独立した manifest が管理します。
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
├── scripts/powershell/install.ps1 # Windows GUI + NixOS-WSL installer entrypoint
└── flake.nix               # Nix flake entry point
```

システム設定、Home Manager の共通・OS 別設定、ホスト情報、公開構成は
`nix/defaults.nix` に集約します。CPU architecture は `system` 引数で選択します。

```text
nix/defaults.nix
├── systemDefaults             # shared OS / Home Manager settings and metadata
├── perSystem                  # apps and packages
└── configurations             # public Darwin / NixOS / Home Manager outputs
```

`nix/home/keybindings/` は共通キー配列と Windows export、`nix/modules/` はアプリの設定・サービス・生成関数を保持します。
`nix/defaults.nix` は OS 基盤設定と module 選択を担当します。

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
- JSON/YAML: `oxfmt`
- TOML: `taplo`
- Lua: `stylua`
- Shell: `shfmt`
- PowerShell: `pwsh` + `PSScriptAnalyzer`

```bash
nix fmt
```

Markdown も dprint で自動整形します。設定とプラグインは Nix で管理します。

pre-commit を使う場合:

```bash
pre-commit install
```

PowerShell (.ps1) の整形は PSScriptAnalyzer の `Invoke-Formatter` を使用します:

```powershell
pwsh -NoProfile -Command "Install-Module PSScriptAnalyzer -Scope CurrentUser"
```

TOML・Lua・JSON/YAML・Markdown の整形設定は [nix/treefmt.nix](nix/treefmt.nix) に宣言します。
設定ファイルは Nix store に生成され、`nix fmt` と `nix develop` 内の `treefmt` が直接参照します。

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
- タブ・ペイン操作は Windows Terminal 標準のキー操作を使用（常駐キー変換は不要）

### WezTerm

- 設定ソース: Windows は `chezmoi/terminals/wezterm/wezterm.lua`、Unix は `nix/modules/terminals/wezterm/default.nix` と `wezterm.lua`
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
hermes gateway status
docker info
```

NixOS では `readlink /run/current-system`、`nixos-rebuild list-generations`、`systemctl status docker.service docker.socket` を確認します。非 NixOS Linux は `home-manager generations` で適用済みのユーザー環境を確認します。Docker は管理対象外です。macOS は `darwin-rebuild --list-generations` と Docker Desktop の起動状態を確認します。Windows は PowerShell / WinGet / WSL とエラー内容を確認して installer を再実行します。WSL の個別 setup は [NixOS-WSL インストール](./docs/nix/nixos-wsl-install.md)を参照してください。

```powershell
.\install.cmd -NoPause
```

### macOS の WezTerm

WezTerm は Nix package として管理します。旧 `wezterm@nightly` cask が残っている場合は、
[WezTerm の旧 provider](./docs/nix/homebrew-cask-troubleshooting.md#wezterm) を参照してください。

### Windows Terminal 設定が反映されない

1. Windows で `chezmoi apply` を実行
2. Windows Terminal を再起動
