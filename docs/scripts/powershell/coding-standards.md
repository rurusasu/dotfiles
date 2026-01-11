# コーディング規約

## 命名規則

### ファイル名

- **ハンドラー**: `Handler.{Name}.ps1` 形式（例: `Handler.Docker.ps1`）
- **テスト**: `{FileName}.Tests.ps1` 形式（例: `Handler.Docker.Tests.ps1`）
- **ライブラリ**: PascalCase + 動詞-名詞（例: `Invoke-ExternalCommand.ps1`）

### クラス名

- **ハンドラー**: `{Name}Handler` 形式（例: `DockerHandler`）
- **コンテキスト**: `{Purpose}Context` 形式（例: `SetupContext`）
- **結果**: `{Purpose}Result` 形式（例: `SetupResult`）

PascalCase を使用します。

### 関数名

動詞-名詞 形式（PowerShell標準）を使用します。

**重要**: 名詞は**単数形**を使用します（PSScriptAnalyzer ルール: PSUseSingularNouns）。

```powershell
# ✅ 正しい
function Get-SetupHandler { }
function Invoke-Wsl { }
function New-HandlerInstance { }
function Test-PathExist { }  # 単数形

# ❌ 誤り
function GetHandlers { }
function wsl { }
function create_handler { }
function Test-PathExists { }  # 複数形はNG
```

### 変数名

- **ローカル変数**: camelCase（例: `$distroName`, `$installDir`）
- **パラメータ**: PascalCase（例: `$DistroName`, `$InstallDir`）
- **定数**: PascalCase（例: `$MinimumCoverage`）

**重要**: PowerShell 自動変数（`$error`, `$PSBoundParameters`, `$_` など）と同じ名前を避けてください（PSScriptAnalyzer ルール: PSAvoidAssignmentToAutomaticVariable）。

```powershell
# ✅ 正しい
param(
    [string]$DistroName,
    [int]$MinimumCoverage = 80,
    [System.Exception]$Exception  # $error ではなく $Exception を使用
)

$handlerName = "Docker"
$isReady = $true

# ❌ 誤り
param(
    [string]$distro_name,
    [int]$minimum_coverage = 80,
    [System.Exception]$error  # 自動変数と競合
)

$handler_name = "Docker"
$is_ready = $true
```

## インデント・スタイル

### インデント

4 スペース（PowerShell標準）を使用します。タブは使用しません。

```powershell
# ✅ 正しい
function Test-Something {
    if ($condition) {
        Write-Host "True"
    }
}

# ❌ 誤り（2スペース）
function Test-Something {
  if ($condition) {
    Write-Host "True"
  }
}
```

### 中括弧

K&R スタイル（開き括弧は同じ行）を使用します。

```powershell
# ✅ 正しい
if ($condition) {
    # 処理
} else {
    # 処理
}

foreach ($item in $items) {
    # 処理
}

# ❌ 誤り（Allman スタイル）
if ($condition)
{
    # 処理
}
else
{
    # 処理
}
```

## エラーハンドリング

### ハンドラーの Apply() メソッド

必ず try-catch でラップし、適切な結果を返します。

```powershell
[SetupResult] Apply([SetupContext]$context) {
    try {
        $this.WriteInfo("処理を開始します")

        # 処理を実行
        $result = Invoke-SomeCommand -ArgumentList "arg"

        $this.WriteSuccess("処理が完了しました")
        return $this.CreateSuccessResult("成功: $result")

    } catch {
        # エラーログ出力
        $this.WriteError("エラー: $($_.Exception.Message)")
        # 失敗結果を返す（例外を再スローしない）
        return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
    }
}
```

**重要**: Apply() メソッドは例外をスローせず、常に SetupResult を返します。

### スクリプトレベル

```powershell
$ErrorActionPreference = "Stop"  # エラーで停止

try {
    # 処理
    $result = Get-Something
    Write-Host "Success: $result"
} catch {
    Write-Error "Failed: $($_.Exception.Message)"
    exit 1
}
```

## ログ出力

### ハンドラー内

基底クラスのヘルパーメソッドを使用します。

```powershell
# 情報ログ（青）
$this.WriteInfo("処理を開始します")

# 成功ログ（緑）
$this.WriteSuccess("処理が完了しました")

# エラーログ（赤）
$this.WriteError("エラーが発生しました")
```

### スクリプトレベル

Write-Host を使用し、色を指定します。

```powershell
Write-Host "Starting process..." -ForegroundColor Cyan
Write-Host "Success!" -ForegroundColor Green
Write-Host "Error occurred" -ForegroundColor Red
Write-Host "Warning: Something might be wrong" -ForegroundColor Yellow
```

## 外部コマンド実行

### ラッパー関数の使用

テスト可能にするため、外部コマンドは必ずラッパー経由で実行します。

```powershell
# ❌ 直接呼び出し（テスト不可）
$output = wsl.exe --list --verbose
$content = Get-Content "file.txt"

# ✅ ラッパー経由（Mock可能）
$output = Invoke-Wsl -ArgumentList "--list", "--verbose"
$content = Invoke-GetContent -Path "file.txt"
```

### 新しいコマンドのラッパー作成

```powershell
# lib/Invoke-ExternalCommand.ps1 に追加
function Invoke-YourCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList
    )

    & your-command.exe @ArgumentList
}
```

## パス操作

### Join-Path の使用

OS依存しないパス結合には Join-Path を使用します。

```powershell
# ✅ 正しい
$path = Join-Path $context.RootPath "subdir\file.txt"
$libPath = Join-Path $PSScriptRoot "lib"

# ❌ 誤り（文字列結合）
$path = "$($context.RootPath)\subdir\file.txt"
$libPath = "$PSScriptRoot\lib"
```

### Test-Path のラッパー使用

```powershell
# ✅ 正しい（Mock可能）
if (Test-PathExist $filePath) {  # 単数形の関数名
    # 処理
}

# ❌ 誤り（Mock不可 / または複数形）
if (Test-Path $filePath) {
    # 処理
}
if (Test-PathExists $filePath) {  # 複数形はNG
    # 処理
}
```

**注意**: ラッパー関数名は `Test-PathExist`（単数形）です。PSScriptAnalyzer の PSUseSingularNouns ルールに準拠しています。

## 配列操作の注意

### 空配列のプロパティアクセス

空配列の Count プロパティにアクセスする場合は `@()` でラップします。

```powershell
# ✅ 正しい（安全）
$handlers = @()
$handlers = @($handlers | Sort-Object Order)
$count = @($handlers).Count  # 0 が返る

# ❌ 誤り（エラーの可能性）
$handlers = $handlers | Sort-Object Order
$count = $handlers.Count  # PropertyNotFoundException の可能性
```

### 配列の初期化

```powershell
# ✅ 正しい
$items = @()

# ❌ 誤り（null の可能性）
$items = $null
```

## コメント

### 関数のドキュメント

```powershell
<#
.SYNOPSIS
    関数の簡潔な説明

.DESCRIPTION
    関数の詳細な説明

.PARAMETER Name
    パラメータの説明

.EXAMPLE
    使用例
#>
function Get-Something {
    param([string]$Name)
    # 処理
}
```

### インラインコメント

複雑なロジックのみにコメントを付けます。自明なコードにはコメント不要です。

```powershell
# ✅ 適切（複雑なロジック）
# ファイル名から Handler. プレフィックスを削除してクラス名を生成
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
$className = $baseName.Replace("Handler.", "") + "Handler"

# ❌ 不要（自明）
# ハンドラー名を設定
$this.Name = "Docker"
```

## 冪等性の保証

### 既に適用済みのチェック

ハンドラーは何度実行しても同じ結果になるべきです。

```powershell
[SetupResult] Apply([SetupContext]$context) {
    try {
        # 既に適用済みかチェック
        if ($this.IsAlreadyApplied($context)) {
            return $this.CreateSuccessResult("既に適用済みです")
        }

        # 処理を実行
        # ...

        return $this.CreateSuccessResult("成功")
    } catch {
        return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
    }
}

hidden [bool] IsAlreadyApplied([SetupContext]$context) {
    # チェックロジック
    return $false
}
```

## テスタビリティ

### すべての外部依存をモック可能にする

```powershell
# ✅ テスト可能
function Do-Something {
    $exists = Invoke-TestPath "file.txt"
    if ($exists) {
        $content = Invoke-GetContent "file.txt"
        return $content
    }
    return $null
}

# テストでモック
Mock Invoke-TestPath { return $true }
Mock Invoke-GetContent { return "mocked content" }

# ❌ テスト不可
function Do-Something {
    if (Test-Path "file.txt") {
        return Get-Content "file.txt"
    }
    return $null
}
```

## SharedData の使用

### ハンドラー間のデータ共有

```powershell
# ハンドラー A（Order 10）が共有データを設定
[SetupResult] Apply([SetupContext]$context) {
    $vhdPath = "C:\path\to.vhdx"
    $context.SharedData["VhdPath"] = $vhdPath
    return $this.CreateSuccessResult("VHD パス: $vhdPath")
}

# ハンドラー B（Order 20）が共有データを使用
[SetupResult] Apply([SetupContext]$context) {
    $vhdPath = $context.SharedData["VhdPath"]
    if ($vhdPath) {
        # VHD パスを使用した処理
    }
    return $this.CreateSuccessResult("成功")
}
```

**命名規則**: SharedData のキーは `{HandlerName}_{PropertyName}` 形式を推奨
