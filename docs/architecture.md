# アーキテクチャ

このリポジトリの全体アーキテクチャと設計について説明します。

## 設計原則

**「OS ごとに 1 コマンドで同じ開発環境へ収束する」** を目標に、以下の原則で管理する。

1. **Nix catalog がパッケージ provider の Single Source of Truth (SSOT)**
   - 全ツールと OS ごとの provider metadata は `nix/packages/catalog/` のカテゴリ別ファイルに一度だけ定義
   - provider 選択は `providers/`、配布 metadata は `install/`、host の動作は `nix/hosts/` などに分離し、`sets.nix` は既存 API を維持する合成入口
   - SSOT は単一定義を意味し、単一ファイルを意味しない。変更理由による境界は [分割の理由と編集先](./nix/package-management.md#分割の理由と編集先) を参照
   - Unix 系 CLI は Home Manager、macOS cask は nix-homebrew、Linux system package は NixOS が消費
   - Windows は `nix build .#winget-export` で GUI 選択に限定した winget JSON と空の npm/pnpm JSON を導出
2. **ユーザー設定は Unix と Windows の責務を分離**
   - Unix の Codex、shell、Git、terminal、editor は Home Manager が管理
   - chezmoi は Windows 専用で、Unix にはファイルもスクリプトも配布しない
   - デスクトップキー配列は例外として、共通 action/key・設定生成関数・ユーザー設定を `nix/home/keybindings/`、OS の service/有効化・競合解除を `nix/hosts/` に分ける。macOS/native NixOS の設定は Nix が所有する。Windows の GlazeWM 設定と補助スクリプトは生成契約のみ保持し、現在の GUI-only 構成では配布しない（[責務と対応範囲・移行状況](./chezmoi/omarchy.md)）
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
│   ├── packages/
│   │   ├── catalog/        # ★ SSOT: category-scoped package/provider data
│   │   ├── providers/      # Provider normalization, selection, validation
│   │   ├── install/        # Installer/manifest metadata
│   │   ├── sets.nix        # Stable public API and composition
│   │   └── winget.nix      # winget/npm/pnpm JSON 生成 derivation
│   ├── home/               # Shared Home Manager configuration
│   │   └── keybindings/    # Shared keys and user settings
│   ├── formatter.nix       # treefmt-nix and formatter dependencies
│   ├── hosts/              # OS-specific system and Home Manager configuration
│   ├── modules/            # Custom NixOS modules (system-level)
│   └── tests/
│       ├── unit/           # nix-unit: Nix expressions and configuration values
│       ├── build/          # Build, runtime, artifact and NixOS VM checks
│       └── fixtures/       # Shared test inputs
├── chezmoi/                # User dotfiles (shell/git/terminal/VS Code/LLM)
├── scripts/                # All scripts
│   ├── sh/                 # Shell scripts (Linux/WSL)
│   └── powershell/         # PowerShell scripts (Windows)
├── windows/                # Windows-side config files (generated + static)
│   ├── winget/             # packages.json (generated from nix)
│   ├── pnpm/               # packages.json (generated from nix)
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

| Platform    | Entrypoint     | System layer                             | User layer       | Runtime                        |
| ----------- | -------------- | ---------------------------------------- | ---------------- | ------------------------------ |
| Windows     | `install.cmd`  | 既存 PowerShell + winget（GUI のみ）     | 自動設定配布なし | CLI / WSL 構築なし             |
| macOS ARM64 | `./install.sh` | nix-darwin + nix-homebrew                | Home Manager     | Docker Desktop / native Hermes |
| Other Linux | `./install.sh` | none                                     | Home Manager     | not managed                    |
| NixOS       | `./install.sh` | NixOS generation + host hardware profile | Home Manager     | rootful Docker                 |

Windows は GUI アプリ導入だけを実行し、既存アプリを自動アンインストールしません。Unix の Full support の共通フローは `preflight → Nix/bootstrap → system switch → Home Manager → Compose → runtime acceptance` です。macOS では Docker Desktop と native Hermes の宣言済み構成を適用します。失敗時はその phase で停止し、同じ入口を再実行します。

非 NixOS Linux は `Nix/bootstrap → Home Manager` のみを実行します。

`./install.sh` は必要に応じて Nix を導入し、毎回 flake input を更新してから
OS の rebuild または Home Manager の switch を実行します。進捗とエラーは
各コマンドの出力をそのまま表示し、更新や反映に失敗した場合は終了します。
macOS のカスタムパッケージ更新は `task darwin:update` で実行します。

## 役割分担

構成登録は `nix/hosts/configurations.nix` に集約し、`flake.nix` から読み込みます。
ホストは system 名で分類し、同じ system 内の native NixOS と WSL は `nixos/` と `wsl/` に分けます。
Darwin は `nix/hosts/aarch64-darwin/`、Linux は `nix/hosts/{x86_64-linux,aarch64-linux}/` に置きます。
Linux の共通設定は `nix/hosts/shared/linux-home.nix` と `shared/nixos/` に置き、CPU ごとに複製しません。
OS 固有の Home Manager 設定とパッケージ選択は `hosts/` が所有し、OS 非依存のユーザー設定は `nix/home/` に残します。

| 役割                    | ツール                  | 説明                                                          |
| ----------------------- | ----------------------- | ------------------------------------------------------------- |
| Provider 定義 (SSOT)    | Nix catalog             | package、winget、npm、Darwin cask を一元定義                  |
| Unix ユーザーパッケージ | Home Manager            | macOS、NixOS、Ubuntu、Debian で共通の `home.packages`         |
| Windows パッケージ      | winget                  | GUI 選択から生成した JSON を WingetHandler が適用             |
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

On macOS and Linux/WSL, the pinned `hermes-agent` flake input and Home Manager
module manage the Hermes CLI and gateway as a native user service: systemd on
Linux/WSL and launchd on macOS. On Windows, Hermes is managed through the
configured NixOS WSL distribution. Nix/Home Manager installs it directly in
NixOS, and `NixRebuildHandler` validates the Linux user service and CLI after
rebuild. No Hermes package or separate Hermes handler is installed on Windows.
Docker Desktop integration is opt-in through `EnableDockerDesktopIntegration`;
NixOS uses its native Docker engine for container workloads independently.
Native state remains at `~/.hermes` in the Linux user's home.

`docker/hermes-service/compose.yml` provides only Chromium, Browser MCP, and
X API MCP sidecars. Browser state is bind-mounted from `~/.hermes/.browser`
(or `HERMES_BROWSER_DATA_DIR`); X API credentials use `~/.hermes/.xurl`
(or `HERMES_DATA_DIR/.xurl`). These sidecars do not mount `hermes-data`.
The retired Docker Agent, Dashboard, container bootstrap, and Docker CLI
adapters have no supported execution path. Existing Docker volumes are left
untouched. Root and named-profile homes are applied by native bootstrap from
source repositories; secrets, memories, sessions, and logs remain local runtime
data. An operator-led migration requires a verified backup and an explicit
policy for resolving conflicting paths before data is copied.

| Owner                  | Source                                                                                    | Responsibility                                                                                         |
| ---------------------- | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| Dotfiles               | [rurusasu/dotfiles](https://github.com/rurusasu/dotfiles)                                 | Sidecar Compose wiring, native bootstrap, manifest, host adapters, operator Taskfile and documentation |
| Nix + Home Manager     | `flake.nix`, `nix/modules/hermes-agent/default.nix`                                       | Pinned CLI package and native gateway user service on macOS and Linux/WSL                              |
| Root distribution      | [rurusasu/hermes-profile-alfred](https://github.com/rurusasu/hermes-profile-alfred)       | `root-distribution.yaml` and root declarative config, policy, cron, scripts, and MCP blocks            |
| Rick distribution      | [rurusasu/hermes-profile-rick](https://github.com/rurusasu/hermes-profile-rick)           | Official `distribution.yaml` and Rick declarative content                                              |
| Hoffman distribution   | [rurusasu/hermes-profile-hoffman](https://github.com/rurusasu/hermes-profile-hoffman)     | Official `distribution.yaml` and Hoffman declarative content                                           |
| Risarisa distribution  | [rurusasu/hermes-profile-risarisa](https://github.com/rurusasu/hermes-profile-risarisa)   | Official `distribution.yaml` and Risarisa declarative content                                          |
| Nancy distribution     | [rurusasu/hermes-profile-nancy](https://github.com/rurusasu/hermes-profile-nancy)         | Official `distribution.yaml` and Nancy declarative content                                             |
| Kuroda distribution    | [rurusasu/hermes-profile-kuroda](https://github.com/rurusasu/hermes-profile-kuroda)       | Official `distribution.yaml` and Kuroda declarative content                                            |
| Shiraishi distribution | [rurusasu/hermes-profile-shiraishi](https://github.com/rurusasu/hermes-profile-shiraishi) | Official `distribution.yaml` and Shiraishi declarative content                                         |
| Shared data            | [rurusasu/lifelog](https://github.com/rurusasu/lifelog)                                   | The one locked read-write checkout at `${HERMES_HOME}/shared/lifelog`                                  |

`${HERMES_HOME}/shared/lifelog` is canonical; `${HERMES_HOME}/core/lifelog` is unmanaged.
Bootstrap neither migrates nor deletes the old checkout. If it contains data,
follow the [manual migration procedure](hermes-agent/bootstrap.md#shared-repository-layout-and-manual-migration)
before running bootstrap, verifying that the canonical checkout retains local
changes and commits. Profile homes are never Git repositories. The default
profile owns shared-lifelog synchronization through the common bootstrap command.

## Local MLflow service

`docker/local-ai-services/compose.yml` manages the pinned MLflow tracking server.
`task mlflow:up` starts it; `task mlflow:verify` checks its HTTP health endpoint.
Persistent state remains under `MLFLOW_DATA_DIR` (default: `~/.local/share/mlflow`).
The `local-ai-services` bridge network is independent of the Hermes browser and
MCP sidecars. No inference provider or model download is configured here.

## パッケージ管理フロー

```
nix/packages/catalog/ (package/provider metadata の SSOT)
  + providers/ (選択・検証) + install/ (配布 metadata)
  → nix/packages/sets.nix (公開 API)
├── Home Manager ───────── macOS / NixOS / Ubuntu / Debian CLI
├── darwinCasks ── declarative nix-homebrew casks
├── darwinBrews ────────── nix-homebrew formulas
├── wingetMap + npmMap ─── generated Windows manifests
├── supportReport ──────── per-OS provider/unsupported evidence
└── providerErrors ─────── CI failure when coverage is missing
```

### ツール追加手順

1. `nix/packages/catalog/` の該当カテゴリにエントリを追加:
   ```nix
   mypackage = { pkg = pkgs.mypackage; winget = "Publisher.Package"; category = "dev"; };
   ```
   Windows 相当がない場合は `winget = null` とし、provider coverage に未対応理由を明記する。
2. `nix build .#winget-export` で winget/npm/pnpm JSON を再生成
3. `nixos-rebuild switch` で Linux 反映、`winget import` で Windows 反映

### Windows 専用アプリの追加

`nix/packages/install/windows-only.nix` の `windowsOnly` と対応する
`windowsOnlySupport` に追加し、macOS/Linux で対応しない理由を記録する。
生成物の更新・検証は [パッケージ管理](./nix/package-management.md) に従う。

---

## PowerShell ハンドラーシステム

`install.ps1` で使用するハンドラーベースのセットアップシステム。

### 基底クラス: SetupHandlerBase

**場所**: [scripts/powershell/lib/SetupHandler.ps1](../scripts/powershell/lib/SetupHandler.ps1#L114-L180)

```powershell
class SetupHandlerBase {
    [string]$Name          # ハンドラー名（表示用）
    [string]$Description   # 説明
    [int]$Order            # 実行順序（小さい方が先に実行）

    # 実行可否判定（サブクラスで実装）
    [bool] CanApply([SetupContext]$context) { return $false }

    # 実行処理（サブクラスで実装）
    [SetupResult] Apply([SetupContext]$context) { throw "Not implemented" }

    # ヘルパーメソッド
    [SetupResult] CreateSuccessResult([string]$message)
    [SetupResult] CreateFailureResult([string]$message, [System.Exception]$error)
    [void] WriteInfo([string]$message)
    [void] WriteSuccess([string]$message)
    [void] WriteError([string]$message)
}
```

### セットアップコンテキスト: SetupContext

**場所**: [scripts/powershell/lib/SetupHandler.ps1](../scripts/powershell/lib/SetupHandler.ps1#L25-L83)

```powershell
class SetupContext {
    [string]$RootPath          # プロジェクトルート
    [string]$DistroName        # WSL ディストリビューション名
    [string]$InstallDir        # インストールディレクトリ
    [hashtable]$SharedData     # ハンドラー間の共有データ

    SetupContext([string]$rootPath) {
        $this.RootPath = $rootPath
        $this.SharedData = @{}
    }
}
```

**SharedData の使用例**:

```powershell
# ハンドラー A（Order 10）が共有データを設定
$context.SharedData["VhdPath"] = "C:\path\to.vhdx"

# ハンドラー B（Order 20）が共有データを使用
$vhdPath = $context.SharedData["VhdPath"]
```

### ハンドラー実行順序

現在の `install.cmd` / `install.user.ps1` は WingetHandler だけを実行します。以下は独立呼び出しやテストのために保持している旧構成のハンドラー一覧であり、通常の Windows セットアップの実行順序ではありません。

| Order | Phase | Admin | ハンドラー      | ソースファイル                                                                            | 説明                                 |
| ----- | ----- | ----- | --------------- | ----------------------------------------------------------------------------------------- | ------------------------------------ |
| 5     | 1     | No    | Winget          | [Handler.Winget.ps1](../scripts/powershell/handlers/Handler.Winget.ps1)                   | winget パッケージ管理                |
| 5     | 2     | Yes   | WslInstall      | [Handler.WslInstall.ps1](../scripts/powershell/handlers/Handler.WslInstall.ps1)           | WSL コンポーネントのインストール     |
| 6     | 1     | No    | Npm             | [Handler.Npm.ps1](../scripts/powershell/handlers/Handler.Npm.ps1)                         | npm グローバルパッケージ管理         |
| 7     | 1     | No    | Pnpm            | [Handler.Pnpm.ps1](../scripts/powershell/handlers/Handler.Pnpm.ps1)                       | pnpm グローバルパッケージ管理        |
| 8     | 1     | No    | Bun             | [Handler.Bun.ps1](../scripts/powershell/handlers/Handler.Bun.ps1)                         | Bun シンボリックリンク作成           |
| 9     | 1     | No    | OnePasswordCli  | [Handler.OnePasswordCli.ps1](../scripts/powershell/handlers/Handler.OnePasswordCli.ps1)   | 1Password CLI op.exe shim 作成       |
| 10    | 2     | No    | Chezmoi         | [Handler.Chezmoi.ps1](../scripts/powershell/handlers/Handler.Chezmoi.ps1)                 | chezmoi dotfiles 適用                |
| 17    | 2     | No    | NixOSWSL        | [Handler.NixOSWSL.ps1](../scripts/powershell/handlers/Handler.NixOSWSL.ps1)               | NixOS-WSL インストール               |
| 18    | 2     | No    | Docker          | [Handler.Docker.ps1](../scripts/powershell/handlers/Handler.Docker.ps1)                   | Docker Desktop WSL 連携              |
| 20    | 2     | No    | WslConfig       | [Handler.WslConfig.ps1](../scripts/powershell/handlers/Handler.WslConfig.ps1)             | .wslconfig 適用                      |
| 21    | 2     | Yes   | VhdManager      | [Handler.VhdManager.ps1](../scripts/powershell/handlers/Handler.VhdManager.ps1)           | WSL VHD サイズ拡張                   |
| 40    | 2     | No    | VscodeServer    | [Handler.VscodeServer.ps1](../scripts/powershell/handlers/Handler.VscodeServer.ps1)       | VS Code Server キャッシュクリア      |
| 55    | 2     | No    | NixRebuild      | [Handler.NixRebuild.ps1](../scripts/powershell/handlers/Handler.NixRebuild.ps1)           | nixos-rebuild switch の実行          |
| 57    | 2     | No    | Plane           | [Handler.Plane.ps1](../scripts/powershell/handlers/Handler.Plane.ps1)                     | Plane Docker Compose セットアップ    |
| 58    | 2     | No    | PlaneGithubSync | [Handler.PlaneGithubSync.ps1](../scripts/powershell/handlers/Handler.PlaneGithubSync.ps1) | Plane / GitHub Issues 同期タスク登録 |

**重要**: Order は依存関係を優先して設定する。Docker だけで完結するハンドラーは Docker の後、NixOS に依存するハンドラーは NixOSWSL/NixRebuild の後に置く。MLflow は独立した Docker service であり、Nix/Home Manager 管理の native Hermes Agent とは別に扱う。

### ハンドラー実行フロー

```powershell
# 1. ライブラリ読み込み
$libPath = Join-Path $PSScriptRoot "scripts\powershell\lib"
. (Join-Path $libPath "SetupHandler.ps1")

# 2. コンテキスト作成
$context = [SetupContext]::new($PSScriptRoot)

# 3. ハンドラー動的ロード
$handlersPath = Join-Path $PSScriptRoot "scripts\powershell\handlers"
$handlerFiles = Get-ChildItem -LiteralPath $handlersPath -Filter "Handler.*.ps1"

$handlers = @()
foreach ($file in $handlerFiles) {
    . $file.FullName
    $className = $file.BaseName.Replace("Handler.", "") + "Handler"
    $handlers += New-Object $className
}

# 4. Order でソート・実行
$handlers | Sort-Object Order | ForEach-Object {
    if ($_.CanApply($context)) {
        $_.Apply($context)
    }
}
```

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
| `ci-nix.yml`     | hosted Linux/macOS/Windows | Nix lint・format・build・catalog 整合性と OS 別 installer / runtime E2E        |
| `ci-chezmoi.yml` | hosted Windows/Linux       | Windows 設定の Pester、template BOM、font installer、未認証 op の render guard |
| `ci-other.yml`   | hosted Linux/Windows       | Python・MLflow・actionlint、PowerShell lint / Pester、devcontainer E2E         |

通常 CI はこの3本に集約します。`codeql.yml` は独立した Actions セキュリティ検査として維持します。
選別ルールは `.github/actions/detect-ci-changes/action.yml` の Bash に直接定義し、外部 manifest と専用 Python detector は持ちません。
Git の差分を `nix`・`chezmoi`・`other` の3つのフラグに分類し、workflow の `if` で実行条件を定義します。
Nix 設定は Nix、Windows の chezmoi 設定は chezmoi、共通 installer・scripts・Taskfile・Docker・workflow・テストは全分類を選択します。
catalog と共有キー設定は Windows の生成物にも影響するため、Nix と chezmoi を両方選択します。
通常の docs / README / AGENTS はスキップしますが、配布対象の agent 設定などの Markdown はその所属分類で検証します。
分類は排他的ではなく、複数変更の和集合を実行します。言語・OS 別の細かな最適化は行わず、分類内の検証をまとめて実行します。

各検証ジョブの名前・OS runner・実際の runtime assertion を維持します。Changes ジョブは各 workflow に一つだけ置きます。
workflow は常時起動し、対象外の検証ジョブだけを `if` でスキップします。検出失敗はチェック失敗とし、手動実行は全分類を有効にします。
PR は merge-base からの差分を使い、削除・移動元も含めます。NUL 区切りでファイル名を扱い、push のゼロ base SHA では empty tree と比較します。
`ci-nix.yml` の `complete` は必要な build / E2E の success と、対象外ジョブの skipped を確認します。
Linux の nix-unit・custom-package-builds・workspace-cycle は catalog の `check` ジョブに集約し、`linux-build` からの二重ビルド参照をなくします。

WSL job は一時 NixOS-WSL 環境で native Nix/Home Manager switch、既存 `~/.hermes` state の保持、CLI 起動、user service の再起動と active 状態を検証します。
Docker Desktop の実機適用と nix-darwin switch は runner の OS 制約により実行せず、installer 末尾の local acceptance が判定します。
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
