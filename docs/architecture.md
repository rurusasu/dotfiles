# アーキテクチャ

このリポジトリの全体アーキテクチャと設計について説明します。

## 設計原則

**「OS ごとに 1 コマンドで同じ開発環境へ収束する」** を目標に、以下の原則で管理する。

1. **Nix catalog がパッケージ provider の Single Source of Truth (SSOT)**
   - 全ツールと OS ごとの provider は `nix/packages/sets.nix` に一元定義
   - Unix 系 CLI は Home Manager、macOS cask は nix-homebrew、Linux system package は NixOS/System Manager が消費
   - Windows は `nix build .#winget-export` で winget/npm/pnpm JSON を導出
2. **chezmoi が設定ファイルの SSOT**
   - 全 OS 共通の dotfiles をテンプレートで管理
   - OS 固有の差分は `.chezmoiignore.tmpl` とテンプレート分岐で吸収
3. **システム収束は OS に適した宣言レイヤーへ分離**
   - Windows: PowerShell handlers + winget
   - macOS: nix-darwin + nix-homebrew
   - Ubuntu/Debian: System Manager
   - NixOS/WSL: NixOS module
4. **Full support は runtime acceptance までを契約に含める**
   - 必須 CLI、chezmoi drift、Docker、Compose 全サービス、hello-world を確認
   - installer は同じコマンドを安全に再実行できる

## 全体構造

```
dotfiles/
├── nix/                    # Cross-platform declarative configuration
│   ├── packages/
│   │   ├── sets.nix        # ★ SSOT: package + provider catalog
│   │   └── winget.nix      # winget/npm/pnpm JSON 生成 derivation
│   ├── darwin/             # nix-darwin + nix-homebrew
│   ├── system-manager/     # Ubuntu/Debian services and users
│   ├── home/               # Shared Home Manager configuration
│   ├── flakes/             # Flake inputs/outputs, treefmt
│   ├── hosts/              # NixOS hosts (native Linux, WSL)
│   ├── modules/            # Custom NixOS modules (system-level)
│   └── tests/              # NixOS VM acceptance
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
├── install.cmd             # Windows one-command entrypoint
├── install.sh              # macOS/Linux one-command dispatcher
├── flake.nix               # Nix flake entry point
└── flake.lock
```

## セットアップフロー

| Platform      | Entrypoint                                | System layer                             | User layer             | Runtime        |
| ------------- | ----------------------------------------- | ---------------------------------------- | ---------------------- | -------------- |
| Windows       | `install.cmd`                             | PowerShell handlers, winget, NixOS-WSL   | Home Manager + chezmoi | Docker Desktop |
| macOS ARM64   | `./install.sh`                            | nix-darwin + nix-homebrew                | Home Manager + chezmoi | Docker Desktop |
| Ubuntu/Debian | `./install.sh`                            | System Manager                           | Home Manager + chezmoi | rootful Docker |
| NixOS         | `./install.sh`                            | NixOS generation + host hardware profile | Home Manager + chezmoi | rootful Docker |
| Other Linux   | `DOTFILES_ALLOW_USER_ONLY=1 ./install.sh` | none                                     | Home Manager only      | not managed    |

Full support の共通フローは `preflight → Nix/bootstrap → system switch → Home Manager → chezmoi → Compose → runtime acceptance` です。失敗時はその phase で停止し、同じ入口を再実行します。

## 役割分担

| 役割                    | ツール                  | 説明                                                           |
| ----------------------- | ----------------------- | -------------------------------------------------------------- |
| Provider 定義 (SSOT)    | Nix catalog             | package、winget、npm、Darwin cask、Linux module を一元定義     |
| Unix ユーザーパッケージ | Home Manager            | macOS、NixOS、Ubuntu、Debian で共通の `home.packages`          |
| Windows パッケージ      | winget/npm/pnpm         | catalog から生成した JSON を handlers が適用                   |
| macOS システム          | nix-darwin/nix-homebrew | Homebrew、Docker Desktop、Home Manager を 1 generation で適用  |
| Ubuntu/Debian システム  | System Manager          | user identity、Nix、Docker service/socket、Home Manager を適用 |
| NixOS システム          | NixOS module            | native/WSL host、Docker、Home Manager を generation に統合     |
| ユーザー設定            | chezmoi                 | shell、Git、terminal、editor の OS 差分をテンプレート化        |
| 受入検証                | platform verifier       | runtime acceptance と drift を検出                             |

## Hermes Bootstrap Ownership

Hermes uses one containerized bootstrap across supported operating systems. The
runtime mount is `/opt/data`, not a Git checkout. The root and named profile
homes are applied from source repositories, while live secrets, memories,
sessions, logs, and browser state remain local runtime data.

| Owner                 | Source                                                                                  | Responsibility                                                                              |
| --------------------- | --------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Dotfiles              | [rurusasu/dotfiles](https://github.com/rurusasu/dotfiles)                               | Compose wiring, manifest, host adapters, operator Taskfile and documentation                |
| Root distribution     | [rurusasu/hermes-home](https://github.com/rurusasu/hermes-home)                         | `root-distribution.yaml` and root declarative config, policy, cron, scripts, and MCP blocks |
| Rick distribution     | [rurusasu/hermes-profile-rick](https://github.com/rurusasu/hermes-profile-rick)         | Official `distribution.yaml` and Rick declarative content                                   |
| Hoffman distribution  | [rurusasu/hermes-profile-hoffman](https://github.com/rurusasu/hermes-profile-hoffman)   | Official `distribution.yaml` and Hoffman declarative content                                |
| Risarisa distribution | [rurusasu/hermes-profile-risarisa](https://github.com/rurusasu/hermes-profile-risarisa) | Official `distribution.yaml` and Risarisa declarative content                               |
| Shared data           | [rurusasu/lifelog](https://github.com/rurusasu/lifelog)                                 | The one locked read-write checkout at `/opt/data/shared/lifelog`                            |

`/opt/data/core/lifelog` is only a compatibility symlink to
`../shared/lifelog`; profile homes are never Git repositories. The default
profile owns shared-lifelog synchronization through the common bootstrap
command.

## パッケージ管理フロー

```
nix/packages/sets.nix (SSOT)
├── Home Manager ───────── macOS / NixOS / Ubuntu / Debian CLI
├── darwinCasks ────────── nix-homebrew casks
├── linuxSystemModules ─── NixOS / System Manager packages and services
├── wingetMap + npmMap ─── generated Windows manifests
├── supportReport ──────── per-OS provider/unsupported evidence
└── providerErrors ─────── CI failure when coverage is missing
```

### ツール追加手順

1. `nix/packages/sets.nix` の `catalog` にエントリを追加:
   ```nix
   mypackage = { pkg = pkgs.mypackage; winget = "Publisher.Package"; category = "dev"; };
   ```
   Set `winget = null` if there is no Windows equivalent.
2. `nix build .#winget-export` で winget/npm/pnpm JSON を再生成
3. `nixos-rebuild switch` で Linux 反映、`winget import` で Windows 反映

### Windows 専用アプリの追加

`nix/packages/sets.nix` の `windowsOnly` セクションに追加するだけ。

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

| Order | Phase | Admin | ハンドラー      | ソースファイル                                                                            | 説明                                     |
| ----- | ----- | ----- | --------------- | ----------------------------------------------------------------------------------------- | ---------------------------------------- |
| 5     | 1     | No    | Winget          | [Handler.Winget.ps1](../scripts/powershell/handlers/Handler.Winget.ps1)                   | winget パッケージ管理                    |
| 5     | 2     | Yes   | WslInstall      | [Handler.WslInstall.ps1](../scripts/powershell/handlers/Handler.WslInstall.ps1)           | WSL コンポーネントのインストール         |
| 6     | 1     | No    | Codex           | [Handler.Codex.ps1](../scripts/powershell/handlers/Handler.Codex.ps1)                     | Codex CLI リンクと MCP PATH 設定         |
| 6     | 1     | No    | Npm             | [Handler.Npm.ps1](../scripts/powershell/handlers/Handler.Npm.ps1)                         | npm グローバルパッケージ管理             |
| 7     | 1     | No    | ClaudeCode      | [Handler.ClaudeCode.ps1](../scripts/powershell/handlers/Handler.ClaudeCode.ps1)           | Claude Code スタンドアロンインストール   |
| 7     | 1     | No    | Pnpm            | [Handler.Pnpm.ps1](../scripts/powershell/handlers/Handler.Pnpm.ps1)                       | pnpm グローバルパッケージ管理            |
| 8     | 1     | No    | Bun             | [Handler.Bun.ps1](../scripts/powershell/handlers/Handler.Bun.ps1)                         | Bun シンボリックリンク作成               |
| 9     | 1     | No    | OnePasswordCli  | [Handler.OnePasswordCli.ps1](../scripts/powershell/handlers/Handler.OnePasswordCli.ps1)   | 1Password CLI op.exe shim 作成           |
| 10    | 2     | No    | Chezmoi         | [Handler.Chezmoi.ps1](../scripts/powershell/handlers/Handler.Chezmoi.ps1)                 | chezmoi dotfiles 適用                    |
| 18    | 2     | No    | Docker          | [Handler.Docker.ps1](../scripts/powershell/handlers/Handler.Docker.ps1)                   | Docker Desktop WSL 連携                  |
| 20    | 2     | No    | WslConfig       | [Handler.WslConfig.ps1](../scripts/powershell/handlers/Handler.WslConfig.ps1)             | .wslconfig 適用                          |
| 21    | 2     | Yes   | VhdManager      | [Handler.VhdManager.ps1](../scripts/powershell/handlers/Handler.VhdManager.ps1)           | WSL VHD サイズ拡張                       |
| 40    | 2     | No    | VscodeServer    | [Handler.VscodeServer.ps1](../scripts/powershell/handlers/Handler.VscodeServer.ps1)       | VS Code Server キャッシュクリア          |
| 50    | 2     | No    | NixOSWSL        | [Handler.NixOSWSL.ps1](../scripts/powershell/handlers/Handler.NixOSWSL.ps1)               | NixOS-WSL インストール                   |
| 55    | 2     | No    | NixRebuild      | [Handler.NixRebuild.ps1](../scripts/powershell/handlers/Handler.NixRebuild.ps1)           | nixos-rebuild switch の実行              |
| 56    | 2     | No    | HermesAgent     | [Handler.HermesAgent.ps1](../scripts/powershell/handlers/Handler.HermesAgent.ps1)         | Hermes Agent Docker コンテナセットアップ |
| 57    | 2     | No    | Plane           | [Handler.Plane.ps1](../scripts/powershell/handlers/Handler.Plane.ps1)                     | Plane Docker Compose セットアップ        |
| 58    | 2     | No    | PlaneGithubSync | [Handler.PlaneGithubSync.ps1](../scripts/powershell/handlers/Handler.PlaneGithubSync.ps1) | Plane / GitHub Issues 同期タスク登録     |

**重要**: Order は依存関係を優先して設定する。Docker だけで完結するハンドラーは Docker の後、NixOS に依存するローカルコンテナ系ハンドラーは NixOSWSL/NixRebuild の後に置く。

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

| Workflow                      | Runner                     | Guarantee                                                                  |
| ----------------------------- | -------------------------- | -------------------------------------------------------------------------- |
| `ci-nix.yml`                  | hosted Linux               | Statix、treefmt、flake evaluation、package smoke                           |
| `ci-consistency.yml`          | hosted Linux               | catalog から生成した winget/npm/pnpm JSON の一致                           |
| `ci-powershell.yml`           | hosted Windows             | handlers、entrypoint、Windows acceptance の Pester                         |
| `ci-bootstrap-build.yml`      | hosted Linux/macOS         | nix-darwin、System Manager、NixOS、Home Manager、support report の実 build |
| `ci-bootstrap-e2e-linux.yml`  | hosted Linux               | Ubuntu/Debian/NixOS installer 2 周、Compose、Docker runtime                |
| `ci-bootstrap-e2e-hosted.yml` | hosted Windows/macOS/Linux | Pester/Bats、nix-darwin build、`Protected Bootstrap E2E` aggregate         |

Windows/macOS は標準 hosted runner で installer の分岐、順序、失敗伝播、冪等性と宣言 output を検証します。Docker Desktop、WSL2、nix-darwin switch の実機適用は nested virtualization と OS 制約のため CI では実行せず、one-command installer 末尾の local acceptance が判定します。

Ubuntu、Debian、NixOS の hosted Linux job は 1 周目で clean bootstrap、2 周目で idempotency を検証し、各周回の後に runtime acceptance を実行します。pull request では hosted contract、declarative build、Linux runtime E2E の全checkが成功し、approval待ちやqueued jobがないことをmerge条件にします。

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
