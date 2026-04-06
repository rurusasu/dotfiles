# アーキテクチャ

このリポジトリの全体アーキテクチャと設計について説明します。

## 設計原則

**「Windows と Linux で同じ開発環境を構築する」** を目標に、以下の原則で管理する。

1. **Nix (Home Manager) がパッケージの Single Source of Truth (SSOT)**
   - 全 CLI ツールは `nix/packages/all.nix` に一元定義
   - Linux/macOS: Home Manager が `home.packages` としてインストール
   - Windows: `nix build .#winget-export` で winget/pnpm の JSON を導出
2. **chezmoi が設定ファイルの SSOT**
   - 全 OS 共通の dotfiles をテンプレートで管理
   - OS 固有の差分は `.chezmoiignore.tmpl` とテンプレート分岐で吸収
3. **OS 固有の処理は最小限に分離**
   - NixOS モジュール: システムレベル設定 (nix gc, Docker, WSL 固有)
   - PowerShell ハンドラー: Windows セットアップ自動化

## 全体構造

```
dotfiles/
├── nix/                    # NixOS/Home Manager configuration
│   ├── packages/
│   │   ├── all.nix         # ★ SSOT: 全パッケージ + wingetMap + windowsOnly
│   │   ├── winget.nix      # winget/pnpm JSON 生成 derivation
│   │   └── default.nix     # nix profile 向け package sets
│   ├── home/               # Home Manager 設定
│   │   ├── packages.nix    # all.nix → home.packages
│   │   └── wsl/users.nix   # WSL ユーザー HM 設定
│   ├── flakes/             # Flake inputs/outputs, treefmt
│   ├── hosts/              # Host-specific configs (WSL, Linux)
│   ├── modules/            # Custom NixOS modules (system-level)
│   ├── profiles/           # Reusable config profiles
│   ├── lib/                # Helper functions
│   ├── overlays/           # Nixpkgs overlays
│   └── templates/          # Project templates
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
├── install.ps1             # NixOS WSL installer (auto-elevates to admin)
├── flake.nix               # Nix flake entry point
└── flake.lock
```

## セットアップフロー

```
Windows                              WSL (NixOS)
────────                             ───────────
install.ps1
    │
    ├─► Download NixOS WSL
    │
    ├─► Import to WSL
    │
    └─► scripts/sh/nixos-wsl-postinstall.sh ──► ~/.dotfiles (symlink)
                                                  │
                                                  ▼
                                             nixos-rebuild switch
                                                  │
                                                  ▼
                                             NixOS configured
```

## 役割分担

| 役割                 | ツール       | 説明                                         |
| -------------------- | ------------ | -------------------------------------------- |
| パッケージ定義 (SSOT)| Nix          | `nix/packages/all.nix` に全ツールを一元定義  |
| パッケージ (Linux)   | Home Manager | `home.packages` で宣言的インストール         |
| パッケージ (Windows) | winget/pnpm  | nix から生成した JSON でインストール          |
| ユーザー設定         | chezmoi      | dotfiles (shell, git, terminal, editor)      |
| システム設定         | NixOS        | OS レベルの設定 (nix gc, Docker, WSL)        |
| タスク実行           | Taskfile     | Windows から WSL コマンドを実行              |

## パッケージ管理フロー

```
nix/packages/all.nix (SSOT)
│
├── packages         ─── nix/home/packages.nix ─── Home Manager (Linux/macOS)
│                                                    └── home.packages = [...]
│
├── wingetMap        ─── nix/packages/winget.nix ── nix build .#winget-export
│   (nix→winget対応)     └── windows/winget/packages.json (generated)
│                        └── windows/pnpm/packages.json  (generated)
│
└── windowsOnly      ─── Windows 専用 GUI アプリ (winget/msstore/pnpm)
    (nix対応なし)
```

### ツール追加手順

1. `nix/packages/all.nix` の該当カテゴリにパッケージ追加
2. クロスプラットフォームなら `wingetMap` に nix attr → winget ID の対応を追加
3. `nix build .#winget-export` で winget/pnpm JSON を再生成
4. `nixos-rebuild switch` で Linux 反映、`winget import` で Windows 反映

### Windows 専用アプリの追加

`nix/packages/all.nix` の `windowsOnly` セクションに追加するだけ。

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

| Order | ハンドラー   | ソースファイル                                                                      | 説明                                    |
| ----- | ------------ | ----------------------------------------------------------------------------------- | --------------------------------------- |
| 5     | Winget       | [Handler.Winget.ps1](../scripts/powershell/handlers/Handler.Winget.ps1)             | winget パッケージ管理（JSON定義ベース） |
| 10    | Chezmoi      | [Handler.Chezmoi.ps1](../scripts/powershell/handlers/Handler.Chezmoi.ps1)           | chezmoi dotfiles 適用                   |
| 20    | WslConfig    | [Handler.WslConfig.ps1](../scripts/powershell/handlers/Handler.WslConfig.ps1)       | .wslconfig 適用                         |
| 21    | VhdManager   | [Handler.VhdManager.ps1](../scripts/powershell/handlers/Handler.VhdManager.ps1)     | WSL VHD サイズ拡張                      |
| 30    | Docker       | [Handler.Docker.ps1](../scripts/powershell/handlers/Handler.Docker.ps1)             | Docker Desktop WSL 連携                 |
| 40    | VscodeServer | [Handler.VscodeServer.ps1](../scripts/powershell/handlers/Handler.VscodeServer.ps1) | VS Code Server キャッシュクリア         |
| 50    | NixOSWSL     | [Handler.NixOSWSL.ps1](../scripts/powershell/handlers/Handler.NixOSWSL.ps1)         | NixOS-WSL インストール                  |

**重要**: Order は 5〜10 刻みで設定し、将来の挿入を容易にする

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

### テストピラミッド

```
          /  E2E  \          ← ローカル手動: VM で実際にインストール
         /  Build  \         ← CI: nix build、NixOS config ビルド
        / Integration\       ← CI: nixos-rebuild (dry)、install.cmd
       /  Unit Tests  \      ← CI: Pester、パッケージ整合性
      / Static Analysis\     ← CI: flake check、lint、fmt
```

### CI (GitHub Actions) で実行するテスト

| Workflow | ランナー | テスト内容 |
| -------- | -------- | ---------- |
| `test-nix.yml` | Linux | `nix flake check --no-build` (評価エラー検知)、`nix fmt -- --fail-on-change` (フォーマット)、`nix build --dry-run` (ビルド可能性) |
| `test-powershell.yml` | Windows | PSScriptAnalyzer (lint)、Pester ユニットテスト (ハンドラー) |
| `test-consistency.yml` | Linux | `nix build .#winget-export` と `windows/winget/packages.json` の diff |

### テスト対象の判断基準

| レベル | 対象 | 方法 | 場所 |
| ------ | ---- | ---- | ---- |
| Static Analysis | nix 構文、フォーマット | `nix flake check`、`nix fmt` | CI (Linux) |
| Unit Test | PowerShell ハンドラー | Pester + モック | CI (Windows) |
| Unit Test | パッケージ整合性 | winget-export diff | CI (Linux) |
| Build Test | NixOS config、package sets | `nix build --dry-run` | CI (Linux) |
| E2E | 実際のインストール | 手動実行 | ローカル |

### CI で実行しないもの

- **Vagrant/Ansible による VM テスト**: GitHub Actions 標準ランナーはネスト仮想化非対応。個人リポジトリに有料ランナーは過剰
- **Windows E2E**: UAC、GUI インストーラー等の自動化が困難
- **NixOS VM test (`nixosTest`)**: 将来オプション。systemd サービスのテストが必要になったら追加

### GitHub Actions 無料枠 (public repo)

| ランナー | 無料枠/月 | 消費レート |
| -------- | --------- | ---------- |
| Linux | 2,000 分 | 1x |
| Windows | 2,000 分 | 2x |
| macOS | 2,000 分 | 10x |

---

## 関連ドキュメント

- [パッケージ管理](./nix/package-management.md)
- [chezmoi ドキュメント](./chezmoi/)
- [フォーマッター設定](./formatter/)
- [ハンドラー開発ガイド](./scripts/powershell/handler-development.md)
