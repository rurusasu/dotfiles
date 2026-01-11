# アーキテクチャ

## ハンドラーシステムの設計

### 基底クラス: SetupHandlerBase

**場所**: [lib/SetupHandler.ps1:114-180](../../../scripts/powershell/lib/SetupHandler.ps1#L114-L180)

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

**場所**: [lib/SetupHandler.ps1:25-83](../../../scripts/powershell/lib/SetupHandler.ps1#L25-L83)

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

### 実行結果: SetupResult

**場所**: [lib/SetupHandler.ps1:88-109](../../../scripts/powershell/lib/SetupHandler.ps1#L88-L109)

```powershell
class SetupResult {
    [string]$HandlerName
    [bool]$Success
    [string]$Message
    [System.Exception]$Error
}
```

## ハンドラー実行フロー

### 1. ライブラリ読み込み

```powershell
$libPath = Join-Path $PSScriptRoot "scripts\powershell\lib"
. (Join-Path $libPath "SetupHandler.ps1")
. (Join-Path $libPath "Invoke-ExternalCommand.ps1")
```

### 2. コンテキスト作成

```powershell
$context = [SetupContext]::new($PSScriptRoot)
$context.DistroName = $DistroName
$context.InstallDir = $InstallDir
```

### 3. ハンドラー動的ロード

```powershell
$handlersPath = Join-Path $PSScriptRoot "scripts\powershell\handlers"
$handlerFiles = Get-ChildItem -LiteralPath $handlersPath -Filter "Handler.*.ps1"

$handlers = @()
foreach ($file in $handlerFiles) {
    . $file.FullName  # スクリプトを読み込む（クラス定義が登録される）
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $className = $baseName.Replace("Handler.", "") + "Handler"
    $handlerInstance = New-Object $className  # クラスをインスタンス化
    $handlers += $handlerInstance
}
```

**重要**: ファイル名は `Handler.{Name}.ps1` パターンに一致する必要があります

### 4. Order プロパティでソート

```powershell
$handlers = $handlers | Sort-Object Order
```

### 5. 実行

```powershell
$results = @()
foreach ($handler in $handlers) {
    if (-not $handler.CanApply($context)) {
        Write-Host "[SKIP] $($handler.Name)" -ForegroundColor Yellow
        continue
    }

    Write-Host "[RUN] $($handler.Name) - $($handler.Description)" -ForegroundColor Cyan
    $result = $handler.Apply($context)
    $results += $result
}
```

### 6. 結果サマリー

```powershell
foreach ($result in $results) {
    if ($result.Success) {
        Write-Host "[OK] $($result.HandlerName): $($result.Message)" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $($result.HandlerName): $($result.Message)" -ForegroundColor Red
    }
}
```

## ハンドラー実行順序

| Order | ハンドラー | ソースファイル | 説明 |
|-------|-----------|--------------|------|
| 5 | Winget | [Handler.Winget.ps1](../../../scripts/powershell/handlers/Handler.Winget.ps1) | winget パッケージ管理（JSON定義ベース） |
| 10 | Chezmoi | [Handler.Chezmoi.ps1](../../../scripts/powershell/handlers/Handler.Chezmoi.ps1) | chezmoi dotfiles 適用 |
| 20 | WslConfig | [Handler.WslConfig.ps1](../../../scripts/powershell/handlers/Handler.WslConfig.ps1) | .wslconfig 適用、VHD 拡張、ファイルシステムリサイズ |
| 30 | Docker | [Handler.Docker.ps1](../../../scripts/powershell/handlers/Handler.Docker.ps1) | Docker Desktop WSL 連携、docker-desktop distro 作成 |
| 40 | VscodeServer | [Handler.VscodeServer.ps1](../../../scripts/powershell/handlers/Handler.VscodeServer.ps1) | VS Code Server キャッシュクリア、事前インストール |
| 50 | NixOSWSL | [Handler.NixOSWSL.ps1](../../../scripts/powershell/handlers/Handler.NixOSWSL.ps1) | NixOS-WSL のダウンロードとインストール、Post-install セットアップ |

**重要**: Order は 5〜10 刻みで設定し、将来の挿入を容易にする

## 外部コマンドラッパー

### 目的

テストでモック可能にするため、すべての外部コマンドをラップ関数経由で実行します。

### 実装場所

[lib/Invoke-ExternalCommand.ps1](../../../scripts/powershell/lib/Invoke-ExternalCommand.ps1)

### ラッパー関数一覧

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

# diskpart コマンド
function Invoke-Diskpart {
    param([string]$Command)
    $Command | diskpart
}

# ファイル操作
function Invoke-TestPath { param([string]$Path); Test-Path $Path }
function Invoke-GetContent { param([string]$Path); Get-Content $Path }
function Invoke-SetContent { param([string]$Path, [string[]]$Value); Set-Content $Path $Value }
function Invoke-GetChildItem { param([string]$Path, [string]$Filter); Get-ChildItem $Path -Filter $Filter }
function Invoke-CopyItem { param([string]$Source, [string]$Destination); Copy-Item $Source $Destination }
function Invoke-StartProcess { param([string]$FilePath, [string[]]$ArgumentList); Start-Process $FilePath -ArgumentList $ArgumentList -Wait }
```

### 使用方法

```powershell
# ❌ 直接呼び出し（テスト不可）
$output = wsl.exe --list --verbose

# ✅ ラッパー使用（Mock可能）
$output = Invoke-Wsl -ArgumentList "--list", "--verbose"
```

### テストでのモック

```powershell
Mock Invoke-Wsl { return "Mocked output" }
Should -Invoke Invoke-Wsl -Times 1 -Exactly
```
