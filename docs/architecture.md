# アーキテクチャ

このリポジトリの全体アーキテクチャと設計について説明します。

## 全体構造

```
dotfiles/
├── chezmoi/                # User dotfiles (shell/git/terminal/VS Code/LLM)
├── nix/                    # NixOS/Home Manager configuration
│   ├── flakes/             # Flake inputs/outputs, treefmt
│   ├── hosts/              # Host-specific configs (WSL)
│   ├── profiles/           # Reusable config profiles
│   ├── modules/            # Custom NixOS modules
│   ├── lib/                # Helper functions
│   ├── overlays/           # Nixpkgs overlays
│   ├── packages/           # Package sets for nix profile
│   └── templates/          # Project templates
├── scripts/                # All scripts
│   ├── sh/                 # Shell scripts (Linux/WSL)
│   └── powershell/         # PowerShell scripts (Windows)
├── windows/                # Windows-side config files
│   ├── winget/             # Package management
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

| 役割                 | ツール     | 説明                                    |
| -------------------- | ---------- | --------------------------------------- |
| システム設定         | NixOS      | OS レベルの設定、パッケージ             |
| ユーザー設定         | chezmoi    | dotfiles (shell, git, terminal, editor) |
| パッケージ (Linux)   | Nix Flakes | 宣言的パッケージ管理                    |
| パッケージ (Windows) | winget     | JSON 定義ベースのパッケージ管理         |
| タスク実行           | Taskfile   | Windows から WSL コマンドを実行         |

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

## 関連ドキュメント

- [chezmoi ドキュメント](./chezmoi/)
- [フォーマッター設定](./formatter/)
- [ハンドラー開発ガイド](./scripts/powershell/handler-development.md)
