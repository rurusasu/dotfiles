# アーキテクチャ

このリポジトリの全体アーキテクチャと設計について説明します。

## 設計原則

**「OS ごとに 1 コマンドで同じ開発環境へ収束する」** を目標に、以下の原則で管理する。

1. **Unix の導入・設定は Nix module、Windows の導入情報は独立した manifest**
   - Unix CLI / GUI の導入・package 選択・設定・連携・専用の実行依存をアプリごとの module にまとめ、すべての実 module の `default.nix` を自動検出し、構成側の型付き option で有効化
   - enable・単純な package list・単一代入は `nix/defaults.nix` の必要な構成へ直接記載。設定・package override・生成・連携を持つアプリは module にまとめる
   - 通常の CLI・GUI とユーザー設定は Home Manager、OS 固有の設定・権限・システムサービス・連携は `nix/defaults.nix` の各 OS ブロックが管理。Homebrew と cask は `nix/defaults.nix` に宣言
   - Windows は `windows/winget/packages.json` を直接管理し、GUI アプリを導入。npm/pnpm manifest は空
   - 機能と OS の所有境界は [分割の理由と編集先](./nix/package-management.md#分割の理由と編集先) を参照
2. **ユーザー設定は Unix と Windows の責務を分離**
   - Unix の Codex、shell、Git、terminal、editor は Home Manager が管理
   - chezmoi は Windows 専用で、Unix にはファイルもスクリプトも配布しない
   - 共通 action/key は `nix/home/keybindings/bindings.nix`、アプリの設定・生成関数は `nix/modules/`、OS 基盤設定と型付き option による有効化は `nix/defaults.nix` に置く。macOS/native NixOS の設定は Nix が所有する。Windows は標準デスクトップを使用し、Nix からデスクトップ設定を生成・配布しない（[責務と対応範囲・移行状況](./chezmoi/omarchy.md)）
3. **システム収束は OS に適した宣言レイヤーへ分離**
   - Windows: PowerShell handlers + winget
   - macOS: nix-darwin + nix-homebrew
   - 非 NixOS Linux: standalone Home Manager（ユーザー環境のみ、OS service は管理しない）
   - NixOS/WSL: NixOS module
4. **Full support は runtime acceptance までを契約に含める**
   - Unix では必須 CLI、Docker profile では Docker、Compose、hello-world も確認。Windows は GUI アプリの導入検証だけを行う
   - installer は同じコマンドを安全に再実行できる

## 全体構造

```
dotfiles/
├── nix/                    # Cross-platform declarative configuration
│   ├── home/               # Shared keybindings and Windows export
│   │   └── keybindings/    # Shared keys and Windows export
│   ├── treefmt.nix         # project treefmt configuration and formatter dependencies
│   ├── defaults.nix        # OS settings, typed enable options and outputs
│   ├── discover-modules.nix # Recursive default.nix discovery by evaluation scope
│   ├── modules/            # App-owned packages, settings, integrations and dependencies
│   │   └── editors/nvim/   # Neovim, plugins, LSPs and runtime/toolchains
│   └── tests/
│       ├── discover.nix    # Recursive unit/build discovery, no per-test registry
│       ├── unit/           # *.nix: nix-unit expressions and configuration values
│       ├── build/          # *.check.nix: named build, runtime, and artifact checks
│       └── fixtures/       # Shared test inputs
├── chezmoi/                # User dotfiles (shell/git/terminal/VS Code/LLM)
├── scripts/                # All scripts
│   ├── sh/                 # Shell scripts (Linux/WSL)
│   └── powershell/         # PowerShell scripts (Windows)
├── windows/                # Windows-side config files
│   ├── winget/             # Independently maintained GUI packages.json
│   ├── npm/                # Empty independent packages.json
│   ├── pnpm/               # Empty independent packages.json
│   └── .wslconfig          # WSL configuration
├── docs/                   # Documentation
├── Taskfile.yml            # Task runner (WSL 経由で nix fmt 等を実行)
├── taskfiles/              # Feature-scoped Taskfiles
├── install.cmd             # Windows one-command entrypoint
├── install.sh              # macOS/Linux one-command dispatcher
├── flake.nix               # Nix flake entry point
└── flake.lock
```

## セットアップフロー

| Platform    | Entrypoint     | System layer                             | User layer               | Runtime                        |
| ----------- | -------------- | ---------------------------------------- | ------------------------ | ------------------------------ |
| Windows     | `install.cmd`  | Winget + WSL 基盤（初回のみ）            | NixOS-WSL + Home Manager | Windows GUI + WSL2 / NixOS     |
| macOS ARM64 | `./install.sh` | nix-darwin + nix-homebrew                | Home Manager             | Docker Desktop / native Hermes |
| Other Linux | `./install.sh` | none                                     | Home Manager             | not managed                    |
| NixOS       | `./install.sh` | NixOS generation + host hardware profile | Home Manager             | rootful Docker                 |

Windows の通常セットアップは `install.cmd` から GUI/Winget と WSL/NixOS-WSL のフェーズを順に実行し、既存アプリを自動アンインストールしません。`-UserPhaseOnly` を指定すると GUI アプリ導入だけを実行します。WSL 基盤が未導入なら UAC 昇格と Windows の再起動が必要になることがあり、再起動後に同じ入口を再実行します。distro の登録と NixOS/Home Manager の適用は元のユーザーで行います。Unix の Full support の共通フローは `preflight → Nix/bootstrap → system switch → Home Manager → runtime acceptance` です。macOS では Docker Desktop と native Hermes の宣言済み構成を適用します。失敗時はその phase で停止し、同じ入口を再実行します。

非 NixOS Linux は `Nix/bootstrap → Home Manager` のみを実行します。

`./install.sh` は必要に応じて Nix を導入し、毎回 flake input を更新してから
OS の rebuild または Home Manager の switch を実行します。進捗とエラーは
各コマンドの出力をそのまま表示し、更新や反映に失敗した場合は終了します。
flake inputs だけを更新する場合は `nix flake update` を使います。

## 役割分担

`nix/defaults.nix` にホスト定義と Home Manager 設定、構成生成・登録を集約し、
`flake.nix` は `perSystem` と `configurations` を公開します。CPU は `system` 引数で選択します。
`systemDefaults` に共通設定と OS 別の基盤設定・enable option をまとめます。`nix/discover-modules.nix` が実 module の `default.nix` を自動検出し、通常は Home Manager、`nixos/` / `darwin/` / `system/` 配下はそれぞれ対応する OS の評価へ接続します。アプリごとの import パス登録・公開 catalog は作りません。
`home-manager.sharedModules` に共通・OS 別ユーザー設定をまとめ、構成登録の `specialArgs.platform` で OS を選択します。
Lix・GC・Home Manager 接続と共通ユーザー設定を一つの `systemDefaults` に宣言し、standalone も同じ `sharedModules` を再利用します。
GC 日時は各 OS ブロック、standalone GC は `systemDefaults.home-manager.sharedModules`、公開構成は `configurations` に宣言します。
ユーザー名・stateVersion の変更先は `systemDefaults` 内の `defaults` です。
Darwin は `system.primaryUser`、WSL は上書き可能な `wsl.defaultUser` を使い、統合 Home Manager は OS のユーザー名・ホーム・Nix package を標準継承します。
共通配列と Windows export は `nix/home/keybindings/`、アプリの導入・設定・サービス・生成関数は `nix/modules/` が所有します。
共通フォント package は NixOS / nix-darwin 統合時には system、standalone 時には Home Manager が供給します。

| 役割                    | ツール                  | 説明                                                          |
| ----------------------- | ----------------------- | ------------------------------------------------------------- |
| Unix CLI / GUI 定義     | Nix / Home Manager      | アプリごとの module が導入・設定・連携・専用の実行依存を所有  |
| Unix ユーザーパッケージ | Home Manager            | macOS、NixOS、Ubuntu、Debian で共通の `home.packages`         |
| Windows パッケージ      | winget                  | 独立した GUI manifest を WingetHandler が適用                 |
| macOS システム          | nix-darwin/nix-homebrew | Homebrew、Docker Desktop、Home Manager を 1 generation で適用 |
| NixOS システム          | NixOS module            | native/WSL host、Docker、Home Manager を generation に統合    |
| Unix ユーザー設定       | Home Manager            | shell、Git、terminal、editor の設定を宣言                     |
| Windows 設定            | chezmoi                 | Windows のユーザー設定のみを配布                              |
| 受入検証                | platform verifier       | runtime acceptance と drift を検出                            |

WSL の Git 設定は、ユーザー設定を Home Manager、共有 checkout の信頼設定を
NixOS `programs.git.config.safe.directory` が所有します。再構築 wrapper はローカルの
`--flake` から canonical path を求め、今回の checkout 一件だけを宣言に渡します。
system trust は全ユーザーに適用されるため、親ディレクトリ、wildcard、過去の checkout は追加しません。
installer は `~/.gitconfig` や XDG Git config を追記・コピーせず、mutable include も作りません。
初回 postinstall の更新・構築は明示的な `path:` provider、適用後は Git provider を使用します。
checkout を移動した場合も、新しい信頼設定の適用には明示的な初回 `path:` 構築が必要です。

macOS の Docker Desktop と CLI artifacts は公式 Homebrew `docker-desktop` Cask が所有します。
installer は `/Applications/Docker.app` への正確なリンクだけを管理し、他の app や Nix store を
指すリンク、既存ファイルとの衝突では停止します。旧 Nix Docker Desktop の自動停止・リンク移行は
終了しています。新規 Cask 登録や欠けたリンクの修復時は、失敗に備えて現行リンクの状態を保持し、
検証成功後に確定します。Docker volume とユーザーデータはこのリンク処理の対象外です。

## Hermes Runtime and Bootstrap Ownership

macOS と Linux/WSL の Hermes は、固定した `hermes-agent` flake input の公式 Home
Manager module を使います。gateway は Linux/WSL の systemd、macOS の launchd が
native user service として管理します。Windows は指定した NixOS-WSL 内の同じ
CLI と service を使います。runtime state は root Hermes home（既定値 `~/.hermes`）
に保持します。

| 所有者        | 正本                                       | 責務                                                                              |
| ------------- | ------------------------------------------ | --------------------------------------------------------------------------------- |
| Hermes root   | `nix/modules/ai_agents/hermes/default.nix` | 公式 Home Manager module による導入、Desktop、gateway、root 設定、外部 LCM plugin |
| 共通 MCP      | `nix/modules/ai_agents/mcp/default.nix`    | Codex と root Hermes が共有する `MCP_DOCKER` / `chrome` / `xapi` / `pipedream`    |
| MCP package   | `nix/modules/ai_agents/mcp-packages.nix`   | `mcp-servers` の Chrome 既製 package と、`xurl` の upstream source を使う         |
| Named profile | 各 profile の Git source                   | `config.yaml` と個別 secret refs。公式 `hermes profile install` / `update` で反映 |
| 運用コマンド  | `taskfiles/hermes/taskfile.yml`            | gateway 操作、公式 profile 更新、lifelog の Git 同期、X API 認証                  |

Chrome と X API MCP は、独立した native Home Manager service `mcp-chrome` /
`mcp-xapi` が管理します。各 service は `mcp-proxy` で1つの persistent stdio child を
保持し、client は `http://127.0.0.1:8765/mcp` / `http://127.0.0.1:8766/mcp` に
接続します。Linux/WSL は systemd user service、macOS は launchd agent を使います。
Chrome は Nix 管理のブラウザを headless で起動し、display や WSLg は不要です。
root Hermes home の `.browser` は `mcp-chrome`、`.xurl` cache は `mcp-xapi` が保持します。
xurl の固定 path `~/.xurl` は Home Manager が XDG configuration を経由して既存 cache
へリンクし、既存実体との衝突では反映を
停止します。named profile は root の MCP 設定を継承しないため、各 Git source に
gateway 参照または対応する URL の定義が必要です。既存の loopback URL は保持します。
Pipedream の OAuth は client ごとに行います。

X API 認証 task は `mcp-xapi` を停止してから interactive OAuth を行い、token の
同期成功後に service を再起動します。これにより認証中の同時 cache 更新を避けます。

旧 Hermes Docker Agent / Dashboard、Browser/noVNC、X API sidecar の
Compose 設定、image、Docker 固有 adapter は削除済みです。既存 Docker volume、
browser profile、OAuth cache、secret、session、memory、log は自動移行・削除しません。
`MCP_DOCKER` と system の Docker 管理は独立して維持します。

lifelog の正規 path は `${HERMES_HOME}/shared/lifelog` です。
`hermes:repository:sync` はこの既存 checkout の commit を native Git で pull/push
します。旧 `${HERMES_HOME}/core/lifelog` の自動移行や削除は行いません。

## Local MLflow service

`docker/local-ai-services/compose.yml` manages the pinned MLflow tracking server.
`task mlflow:up` starts it; `task mlflow:verify` checks its HTTP health endpoint.
Persistent state remains under `MLFLOW_DATA_DIR` (default: `~/.local/share/mlflow`).
The `local-ai-services` bridge network is independent of the native Hermes
runtime. No inference provider or model download is configured here.

## パッケージ管理フロー

```text
nix/modules/**/default.nix ── scope ごとに自動検出
├── 各アプリ module ───── enable に従う package 選択・設定・連携・専用の実行依存
└── editors/nvim/ ─────── Neovim・LSP・整形ツール・toolchain・プラグイン

nix/defaults.nix:systemDefaults ── 共通 OS / Home Manager 設定と有効化だけの標準宣言

windows/winget/packages.json ── Windows GUI を直接宣言
windows/{npm,pnpm}/packages.json ── 独立した空 manifest
```

### ツール追加手順

1. enable・単純な package list・単一代入は `nix/defaults.nix` の必要な構成へ直接書く。設定・package override・生成・連携を持つ場合はアプリ module にまとめる。設定・連携も管理するアプリは標準の `programs.<name>.enable`、設定をユーザーが管理するアプリや標準 module のないアプリは `home.packages` を使う。Neovim の LSP・整形ツール・toolchain・プラグイン実行依存は `editors/nvim/` に置く。
2. 設定を持つ実 module はアプリ配下の `default.nix` とし、自動検出させる。OS module は `nixos/` / `darwin/` / `system/` 配下に置く。`nix/defaults.nix` には型付き enable option を指定し、個別の import パス登録・公開 catalog は追加しない。純粋な factory・renderer は通常の関数として維持する。Homebrew / nix-homebrew・cask と OS 基盤設定は `defaults.nix` の各 OS ブロックが担当する。
3. Windows に追加する場合は `windows/winget/packages.json` の既存 schema に合わせ、package ID・導入・検証情報を直接記述する。
4. 各 OS の通常インストーラーで反映する。具体的な入口と所有境界は [パッケージ管理](./nix/package-management.md) を参照する。

Windows 専用のアプリも同じ WinGet manifest に直接追加する。Unix の Nix module に Windows install metadata は置かない。

---

## PowerShell ハンドラーシステム

Windows の実行順序は `taskfiles/install/taskfile.yml` が管理します。
`install.cmd` → `install.ps1` → `Invoke-WindowsInstallTask.ps1` → Taskfile の順に進み、
GUI 導入、WSL 初期化、`nrs`、chezmoi 適用を実行します。
`Invoke-WindowsInstallPhase.ps1` は各 phase に必要な handler だけを明示して読み込みます。

| Handler    | 役割                                        | 呼び出し元                       |
| ---------- | ------------------------------------------- | -------------------------------- |
| Winget     | Windows manifest の導入・検証               | `install.user.ps1`               |
| WslInstall | WSL 基盤の有効化、必要時の昇格・再起動通知  | `Invoke-WindowsInstallPhase.ps1` |
| NixOSWSL   | distro 導入、初回同期、既存 distro の再利用 | `Invoke-WindowsInstallPhase.ps1` |
| Chezmoi    | chezmoi 初期化・Windows 設定の適用          | `Invoke-WindowsInstallPhase.ps1` |

`lib/SetupHandler.ps1` は共有の `SetupContext` / `SetupResult` / `SetupHandlerBase` と
結果表示を提供します。未使用 handler の動的探索・ソート・一括実行は行いません。
`CanApply()` は判定専用、`Apply()` は適用結果を `SetupResult` で返します。
外部コマンドは `lib/Invoke-ExternalCommand.ps1` の wrapper を使用します。
NixOS の通常 rebuild は公開タスク `nrs` に集約します。

---
## 外部コマンドラッパー

テストでモック可能にするため、すべての外部コマンドをラップ関数経由で実行します。

**実装場所**: [scripts/powershell/lib/Invoke-ExternalCommand.ps1](../scripts/powershell/lib/Invoke-ExternalCommand.ps1)

### 主なラッパー関数

```powershell
# WSL コマンド
function Invoke-Wsl {
    param([string[]]$ArgumentList)
    & wsl.exe @ArgumentList
}

# chezmoi コマンド
function Invoke-Chezmoi {
    param([string[]]$ArgumentList)
    & chezmoi.exe @ArgumentList
}

# ファイル操作
function Invoke-TestPath { param([string]$Path); Test-Path $Path }
function Invoke-GetContent { param([string]$Path); Get-Content $Path }
function Invoke-CopyItem { param([string]$Source, [string]$Destination); Copy-Item $Source $Destination }
```

### テストでのモック

```powershell
Mock Invoke-Wsl { return "Mocked output" }
Should -Invoke Invoke-Wsl -Times 1 -Exactly
```
---

## テスト戦略

検証は「静的契約 → build → 破壊的 convergence → runtime acceptance」の順で強くなります。

| Workflow         | Runner                     | Guarantee                                                                      |
| ---------------- | -------------------------- | ------------------------------------------------------------------------------ |
| `ci-nix.yml`     | hosted Linux/macOS/Windows | Nix lint・format・build・Windows manifest 検査と OS 別 installer / runtime E2E |
| `ci-chezmoi.yml` | hosted Windows             | chezmoi の Windows 管理対象と template BOM 検査                                |

通常 CI はこの2本に集約します。`codeql.yml` は独立した Actions セキュリティ検査として維持します。
選別ルールは `.github/actions/detect-ci-changes/action.yml` の Bash に直接定義し、外部 manifest と専用 Python detector は持ちません。
Git の差分を共有検査用の `nix`・`chezmoi`・`other` と、構成適用用の `linux`・`darwin`・`wsl`・`windows` に分類し、workflow の `if` で実行条件を定義します。
Nix 設定は Nix、Windows の chezmoi 設定は chezmoi、共通 installer・scripts・Taskfile・Docker・workflow・テストは全分類を選択します。
共有キー設定、flake input、Windows manifest は Nix と chezmoi を両方選択します。
通常の docs / README / AGENTS はスキップしますが、配布対象の agent 設定などの Markdown はその所属分類で検証します。
分類は排他的ではなく、複数変更の和集合を実行します。Windows manifest の変更は共有 checks と Windows installer、OS 固有 host の変更は該当 OS の build / E2E を選択します。
共有 Nix module や flake input、共通スクリプトは依存する各 OS を選択し、配布するキーバインド help 文書も実行対象に含めます。

各検証ジョブの名前・OS runner・実際の runtime assertion を維持します。Changes ジョブは各 workflow に一つだけ置きます。
workflow は常時起動し、対象外の検証ジョブだけを `if` でスキップします。検出失敗はチェック失敗とし、手動実行は全分類を有効にします。
PR は merge-base からの差分を使い、削除・移動元も含めます。NUL 区切りでファイル名を扱い、push のゼロ base SHA では empty tree と比較します。
`ci-nix.yml` の `complete` は必要な build / E2E の success と、対象外ジョブの skipped を確認します。
Linux の nix-unit・custom-package-builds・workspace-cycle と Windows キー設定生成・manifest 検査は `check` ジョブに集約し、`linux-build` からの二重ビルド参照をなくします。
Nix の成果物は GitHub Actions cache に保存し、WSL artifact では取得可能な公開依存の payload を省きます。詳細は [CI cache](../docker/bootstrap-ci-tools/README.md#nix-成果物の再利用) を参照してください。

WSL job は一時 NixOS-WSL 環境で native Nix/Home Manager switch、既存 `~/.hermes` state の保持、CLI 起動、user service の再起動と active 状態を検証します。
Windows の Docker Desktop の実機適用は installer 末尾の local acceptance が判定します。macOS は Darwin job で nix-darwin switch を実行します。
詳細は [WSL Hermes E2E](../scripts/powershell/ci/Invoke-NixosWslE2E.ps1) を参照してください。

NixOS の hosted VM job は installer の再実行と Docker・Compose の runtime acceptance を検証します。非 NixOS Linux は standalone Home Manager の build と installer の mocked contract が対象です。pull request では hosted contract、declarative build、Linux runtime E2E の全checkが成功し、approval待ちやqueued jobがないことをmerge条件にします。

---

## 関連ドキュメント

- [パッケージ管理](./nix/package-management.md)
- [chezmoi ドキュメント](./chezmoi/)
- [フォーマッター設定](./formatter/)
- [ハンドラー開発ガイド](./scripts/powershell/handler-development.md)
- [Hermes bootstrap design](./hermes-agent/bootstrap-design.md)
- [Hermes bootstrap core plan](./hermes-agent/plans/2026-07-21-hermes-bootstrap-core.md)
- [Hermes installer integration plan](./hermes-agent/plans/2026-07-21-hermes-bootstrap-integration.md)
- [Hermes distribution repositories plan](./hermes-agent/plans/2026-07-21-hermes-distributions.md)
- [Hermes bootstrap operations](./hermes-agent/bootstrap.md)
