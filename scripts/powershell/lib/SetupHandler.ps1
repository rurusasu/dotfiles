<#
.SYNOPSIS
    セットアップハンドラーの基底クラスとコンテキスト定義

.DESCRIPTION
    各ハンドラーはこのクラスを継承し、CanApply() と Apply() を実装する。
    Order プロパティで実行順序を制御する。

.NOTES
    Order の目安:
      10-30  : WSL 環境に依存する処理（WslConfig, Docker, VscodeServer）
      100+   : WSL に依存しない処理（Chezmoi）

    小さい値が先に実行される。同じ Order の場合、ファイル名順。

.EXAMPLE
    class MyHandler : SetupHandlerBase {
        MyHandler() {
            $this.Name = "MyHandler"
            $this.Description = "My custom handler"
            $this.Order = 50
        }

        [bool] CanApply([SetupContext]$ctx) {
            return $true
        }

        [SetupResult] Apply([SetupContext]$ctx) {
            # 処理を実行
            return $this.CreateResult($true, "完了しました")
        }
    }
#>

# ========================================
# Prevent Multiple Class Definitions
# ========================================
# PowerShell classes are cached per session. When the same class is dot-sourced
# multiple times, it creates type conflicts ("Cannot convert SetupContext to SetupContext").
# This file should only be loaded once per session. Handler files should NOT dot-source
# this file; they rely on it being pre-loaded by install.ps1 or the test framework.

<#
.SYNOPSIS
    セットアップ実行時の共有コンテキスト

.DESCRIPTION
    全ハンドラーで共有される状態を保持する。
    パス情報、オプション、ディストリビューション名などを含む。
#>
class SetupContext {
    # dotfiles リポジトリのルートパス
    [string]$DotfilesPath

    # WSL ディストリビューション名
    [string]$DistroName = "NixOS"

    # WSL インストール先ディレクトリ
    [string]$InstallDir

    # 各ハンドラーのスキップフラグ等を格納
    [hashtable]$Options = @{}

    <#
    .SYNOPSIS
        SetupContext のコンストラクタ
    .PARAMETER dotfilesPath
        dotfiles リポジトリのルートパス
    #>
    SetupContext([string]$dotfilesPath) {
        $this.DotfilesPath = $dotfilesPath
        $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { '~' }
        $this.InstallDir = Join-Path $homeDir "NixOS"
    }

    <#
    .SYNOPSIS
        オプション値を取得する
    .PARAMETER key
        オプションのキー名
    .PARAMETER default
        キーが存在しない場合のデフォルト値
    #>
    [object] GetOption([string]$key, [object]$default) {
        if ($this.Options.ContainsKey($key)) {
            return $this.Options[$key]
        }
        return $default
    }
}

<#
.SYNOPSIS
    ハンドラー実行結果を表すクラス

.DESCRIPTION
    各ハンドラーの Apply() メソッドが返す結果オブジェクト。
    成功/失敗、メッセージ、エラー情報を保持する。
#>
class SetupResult {
    # ハンドラー名
    [string]$HandlerName

    # 実行が成功したかどうか
    [bool]$Success

    # 結果メッセージ
    [string]$Message

    # エラーが発生した場合の例外オブジェクト
    [System.Exception]$Error

    <#
    .SYNOPSIS
        SetupResult のコンストラクタ
    #>
    SetupResult() {
        $this.Success = $false
        $this.Message = ""
    }

    <#
    .SYNOPSIS
        成功結果を作成するファクトリメソッド
    .PARAMETER handlerName
        ハンドラー名
    .PARAMETER message
        成功メッセージ
    #>
    static [SetupResult] CreateSuccess([string]$handlerName, [string]$message) {
        $result = [SetupResult]::new()
        $result.HandlerName = $handlerName
        $result.Success = $true
        $result.Message = $message
        return $result
    }

    <#
    .SYNOPSIS
        失敗結果を作成するファクトリメソッド
    .PARAMETER handlerName
        ハンドラー名
    .PARAMETER message
        エラーメッセージ
    .PARAMETER exception
        例外オブジェクト（オプション）
    #>
    static [SetupResult] CreateFailure([string]$handlerName, [string]$message, [System.Exception]$exception) {
        $result = [SetupResult]::new()
        $result.HandlerName = $handlerName
        $result.Success = $false
        $result.Message = $message
        $result.Error = $exception
        return $result
    }

    static [SetupResult] CreateFailure([string]$handlerName, [string]$message) {
        return [SetupResult]::CreateFailure($handlerName, $message, $null)
    }
}

<#
.SYNOPSIS
    セットアップハンドラーの基底クラス

.DESCRIPTION
    各ハンドラーはこのクラスを継承し、CanApply() と Apply() を実装する必要がある。
    CanApply() で実行可否を判定し、Apply() で実際の処理を行う。

.NOTES
    Order プロパティについて:
    - 小さい値が先に実行される
    - WSL 依存処理は 10-50 の範囲を推奨
    - WSL 非依存処理は 100 以上を推奨
    - 同じ Order の場合はファイル名のアルファベット順

    実装時の注意:
    - CanApply() は副作用を持たないこと
    - Apply() は冪等性を保つこと（何度実行しても同じ結果）
    - エラー発生時は SetupResult.CreateFailure() を返すこと
#>
class SetupHandlerBase {
    # ハンドラーの識別名
    [string]$Name

    # ハンドラーの説明（ログ表示用）
    [string]$Description

    # 実行順序（小さい値が先に実行される）
    # 目安: 10-30=WSL依存, 100+=WSL非依存
    [int]$Order = 100

    # 管理者権限が必要かどうか
    [bool]$RequiresAdmin = $false

    # オプショナルサービスの同意設定（設定されている場合、一括同意プロンプトの対象になる）
    # ConsentKey: chezmoi.toml の [data] セクションに保存するキー名 (例: "openclaw_enabled")
    # ConsentLabel: 一括同意プロンプトに表示する説明文
    [string]$ConsentKey = ""
    [string]$ConsentLabel = ""

    # ログバッファリング（CanApply 中はバッファリングし、スキップ時は破棄）
    hidden [bool]$_bufferLogs = $false
    hidden [System.Collections.ArrayList]$_logBuffer = [System.Collections.ArrayList]::new()

    <#
    .SYNOPSIS
        実行可否を判定する（派生クラスでオーバーライド必須）
    .DESCRIPTION
        このメソッドは副作用を持たず、実行可能かどうかのみを判定する。
        前提条件（ファイル存在、コマンド存在等）をチェックする。
    .PARAMETER ctx
        セットアップコンテキスト
    .OUTPUTS
        実行可能な場合は $true、そうでない場合は $false
    #>
    [bool] CanApply([SetupContext]$ctx) {
        throw [System.NotImplementedException]::new(
            "CanApply() must be implemented by derived class: $($this.GetType().Name)"
        )
    }

    <#
    .SYNOPSIS
        セットアップ処理を実行する（派生クラスでオーバーライド必須）
    .DESCRIPTION
        実際のセットアップ処理を行う。冪等性を保つよう実装すること。
    .PARAMETER ctx
        セットアップコンテキスト
    .OUTPUTS
        SetupResult オブジェクト
    #>
    [SetupResult] Apply([SetupContext]$ctx) {
        throw [System.NotImplementedException]::new(
            "Apply() must be implemented by derived class: $($this.GetType().Name)"
        )
    }

    <#
    .SYNOPSIS
        成功結果を作成するヘルパーメソッド
    .PARAMETER message
        成功メッセージ
    #>
    [SetupResult] CreateSuccessResult([string]$message) {
        return [SetupResult]::CreateSuccess($this.Name, $message)
    }

    <#
    .SYNOPSIS
        失敗結果を作成するヘルパーメソッド
    .PARAMETER message
        エラーメッセージ
    .PARAMETER exception
        例外オブジェクト（オプション）
    #>
    [SetupResult] CreateFailureResult([string]$message, [System.Exception]$exception) {
        return [SetupResult]::CreateFailure($this.Name, $message, $exception)
    }

    [SetupResult] CreateFailureResult([string]$message) {
        return [SetupResult]::CreateFailure($this.Name, $message, $null)
    }

    <#
    .SYNOPSIS
        ログメッセージを出力するヘルパーメソッド
    .PARAMETER message
        出力するメッセージ
    .PARAMETER color
        文字色（デフォルト: Cyan）
    #>
    [void] Log([string]$message, [string]$color) {
        if ($this._bufferLogs) {
            $this._logBuffer.Add(@{ Message = $message; Color = $color }) | Out-Null
            return
        }
        Write-Host "[$($this.Name)] $message" -ForegroundColor $color
    }

    [void] Log([string]$message) {
        $this.Log($message, "Cyan")
    }

    <#
    .SYNOPSIS
        警告メッセージを出力するヘルパーメソッド
    .PARAMETER message
        出力するメッセージ
    #>
    [void] LogWarning([string]$message) {
        if ($this._bufferLogs) {
            $this._logBuffer.Add(@{ Message = $message; Color = "Yellow" }) | Out-Null
            return
        }
        Write-Host "[$($this.Name)] $message" -ForegroundColor Yellow
    }

    <#
    .SYNOPSIS
        エラーメッセージを出力するヘルパーメソッド
    .PARAMETER message
        出力するメッセージ
    #>
    [void] LogError([string]$message) {
        if ($this._bufferLogs) {
            $this._logBuffer.Add(@{ Message = $message; Color = "Red" }) | Out-Null
            return
        }
        Write-Host "[$($this.Name)] $message" -ForegroundColor Red
    }

    # バッファされたログを出力する
    hidden [void] FlushLogBuffer() {
        foreach ($entry in $this._logBuffer) {
            Write-Host "[$($this.Name)] $($entry.Message)" -ForegroundColor $entry.Color
        }
        $this._logBuffer.Clear()
    }

    # バッファを破棄する
    hidden [void] ClearLogBuffer() {
        $this._logBuffer.Clear()
    }

    # このハンドラーが同意プロンプト対象かどうか
    [bool] NeedsConsent() {
        return -not [string]::IsNullOrEmpty($this.ConsentKey)
    }

    # chezmoi.toml から同意フラグを読み取る ($true / $false / $null)
    [object] ReadConsentFlag() {
        if (-not $this.NeedsConsent()) { return $null }
        $tomlPath = $this.GetChezmoiTomlPath()
        if (-not (Test-Path $tomlPath)) { return $null }
        $content = Get-Content $tomlPath -Raw -ErrorAction SilentlyContinue
        if (-not $content) { return $null }
        if ($content -match "$([regex]::Escape($this.ConsentKey))\s*=\s*(true|false)") {
            return ($Matches[1] -eq 'true')
        }
        return $null
    }

    # chezmoi.toml に同意フラグを永続化する
    [void] WriteConsentFlag([bool]$enabled) {
        if (-not $this.NeedsConsent()) { return }
        $tomlPath = $this.GetChezmoiTomlPath()
        $value = if ($enabled) { "true" } else { "false" }
        $nl = [Environment]::NewLine

        $dir = Split-Path $tomlPath
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        if (-not (Test-Path $tomlPath)) {
            [System.IO.File]::WriteAllText($tomlPath, "[data]${nl}$($this.ConsentKey) = ${value}${nl}")
            return
        }

        $content = Get-Content $tomlPath -Raw
        if ($content -match "$([regex]::Escape($this.ConsentKey))\s*=") {
            $content = $content -replace "($([regex]::Escape($this.ConsentKey))\s*=\s*)\w+", "`${1}${value}"
        } elseif ($content -match '\[data\]') {
            $content = $content -replace '(\[data\]\s*\r?\n)', "`$1$($this.ConsentKey) = ${value}${nl}"
        } else {
            $content = "${content}${nl}[data]${nl}$($this.ConsentKey) = ${value}${nl}"
        }
        [System.IO.File]::WriteAllText($tomlPath, $content)
    }

    hidden [string] GetChezmoiTomlPath() {
        $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
        return Join-Path $homeDir ".config\chezmoi\chezmoi.toml"
    }
}

<#
.SYNOPSIS
    オプショナルサービスの一括同意プロンプトを表示する
.DESCRIPTION
    ConsentKey が設定されていて、chezmoi.toml にフラグが未設定のハンドラーを
    一覧表示し、ユーザーに一括で選択させる。結果は chezmoi.toml に永続化する。
    非対話環境ではスキップする。
.PARAMETER Handlers
    全ハンドラーの配列
#>
function Invoke-ConsentPrompt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Handlers
    )

    # 同意が必要なハンドラーを抽出（ConsentKey があり、フラグ未設定）
    $pending = @($Handlers | Where-Object {
        $_.NeedsConsent() -and ($null -eq $_.ReadConsentFlag())
    })

    if ($pending.Count -eq 0) { return }

    # 非対話環境ではスキップ
    if (-not (Test-InteractiveEnvironment)) { return }

    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Yellow
    Write-Host "  追加セットアップ (Docker コンテナ)" -ForegroundColor Yellow
    Write-Host "  ========================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  以下のサービスをこの PC にセットアップできます。" -ForegroundColor White
    Write-Host "  Docker コンテナとしてビルド・起動されます。" -ForegroundColor Gray
    Write-Host ""
    for ($i = 0; $i -lt $pending.Count; $i++) {
        Write-Host "  [$($i + 1)] $($pending[$i].ConsentLabel)" -ForegroundColor Cyan
    }
    Write-Host ""
    $answer = Read-Host "  セットアップする番号を入力 (例: 1,2 / all / none) [none]"

    if ([string]::IsNullOrWhiteSpace($answer)) { $answer = "none" }

    $selectedIndices = @()
    if ($answer -ieq "all") {
        $selectedIndices = 0..($pending.Count - 1)
    } elseif ($answer -ine "none") {
        $selectedIndices = @($answer -split '[,\s]+' | ForEach-Object {
            $num = 0
            if ([int]::TryParse($_.Trim(), [ref]$num) -and $num -ge 1 -and $num -le $pending.Count) {
                $num - 1
            }
        })
    }

    # 選択結果を永続化
    for ($i = 0; $i -lt $pending.Count; $i++) {
        $enabled = $i -in $selectedIndices
        $pending[$i].WriteConsentFlag($enabled)
        $status = if ($enabled) { "有効" } else { "スキップ" }
        $color = if ($enabled) { "Green" } else { "Gray" }
        Write-Host "  $($pending[$i].Name): $status" -ForegroundColor $color
    }
    Write-Host ""
}

# ========================================
# Handler Orchestration Functions
# ========================================

<#
.SYNOPSIS
    Load all handler instances from a directory

.PARAMETER HandlersPath
    Path to the handlers directory containing Handler.*.ps1 files

.OUTPUTS
    Array of handler instances

.EXAMPLE
    $handlers = Get-SetupHandler -HandlersPath ".\handlers"
#>
function Get-SetupHandler
{
    param(
        [Parameter(Mandatory)]
        [string]$HandlersPath
    )

    $handlers = @()
    $handlerFiles = Get-ChildItem -Path $HandlersPath -Filter "Handler.*.ps1" -ErrorAction SilentlyContinue

    if ($handlerFiles.Count -eq 0)
    {
        Write-Warning "No handler files found in: $HandlersPath"
        return $handlers
    }

    foreach ($file in $handlerFiles)
    {
        try
        {
            # Dot-source the handler file
            . $file.FullName

            # Extract class name (Handler.Chezmoi.ps1 → ChezmoiHandler)
            $handlerName = $file.BaseName -replace '^Handler\.', ''
            $className = "${handlerName}Handler"

            # Instantiate the handler
            $instance = New-Object $className
            $handlers += $instance

            Write-Verbose "Loaded handler: $($instance.Name) (Order: $($instance.Order))"
        } catch
        {
            Write-Warning "Failed to load handler: $($file.Name) - $($_.Exception.Message)"
        }
    }

    Write-Verbose "Loaded $($handlers.Count) handler(s)"
    return $handlers
}

<#
.SYNOPSIS
    Sort handlers by their execution order

.PARAMETER Handlers
    Array of handler instances to sort

.OUTPUTS
    Sorted array of handlers (by Order property, ascending)

.EXAMPLE
    $sorted = Select-SetupHandler -Handlers $handlers
#>
function Select-SetupHandler
{
    param(
        [Parameter(Mandatory)]
        [array]$Handlers
    )

    # Sort-Object は PS5.1 で安定ソートが保証されないためインデックスを仸る
    $indexed = for ($i = 0; $i -lt $Handlers.Count; $i++)
    {
        [PSCustomObject]@{ Idx = $i; Item = $Handlers[$i] }
    }
    return ($indexed | Sort-Object -Property @{ Expression = { $_.Item.Order } }, @{ Expression = { $_.Idx } }) |
        ForEach-Object { $_.Item }
}

<#
.SYNOPSIS
    Execute handlers in sequence

.PARAMETER Handlers
    Array of handler instances to execute

.PARAMETER Context
    SetupContext instance with configuration and state

.PARAMETER SkipHandlers
    Array of handler names to skip

.OUTPUTS
    Array of SetupResult instances

.EXAMPLE
    $results = Invoke-SetupHandler -Handlers $handlers -Context $context
#>
function Invoke-SetupHandler
{
    param(
        [Parameter(Mandatory)]
        [array]$Handlers,
        [Parameter(Mandatory)]
        [SetupContext]$Context,
        [string[]]$SkipHandlers = @()
    )

    $results = @()

    if ($Handlers.Count -eq 0)
    {
        Write-Warning "No handlers to execute"
        return $results
    }

    foreach ($handler in $Handlers)
    {
        # Skip if in skip list
        if ($handler.Name -in $SkipHandlers)
        {
            Write-Host "[$($handler.Name)] Skipped (user request)" -ForegroundColor Gray
            continue
        }

        # Check if handler can apply (buffer logs during check)
        $canApply = $false
        $handler._bufferLogs = $true
        try
        {
            $canApply = $handler.CanApply($Context)
        } catch
        {
            $handler._bufferLogs = $false
            $handler.ClearLogBuffer()
            Write-Warning "[$($handler.Name)] CanApply() check failed: $($_.Exception.Message)"
            continue
        }
        $handler._bufferLogs = $false

        if (-not $canApply)
        {
            $handler.ClearLogBuffer()
            continue
        }

        # Execute handler
        Write-Host ""
        Write-Host "[$($handler.Name)] $($handler.Description)" -ForegroundColor Cyan
        $handler.FlushLogBuffer()

        try
        {
            $result = $handler.Apply($Context)
            $results += $result

            if ($result.Success)
            {
                # Summary で表示するため OK ログは省略
            } else
            {
                Write-Host "[$($handler.Name)] FAIL $($result.Message)" -ForegroundColor Red
                if ($result.Error)
                {
                    Write-Host "[$($handler.Name)] Error: $($result.Error.Message)" -ForegroundColor Red
                }
            }
        } catch
        {
            $exception = $_.Exception
            $result = [SetupResult]::CreateFailure($handler.Name, "Unhandled exception", $exception)
            $results += $result
            Write-Host "[$($handler.Name)] FAIL Exception: $($exception.Message)" -ForegroundColor Red
        }
    }

    return $results
}

<#
.SYNOPSIS
    Display a summary of handler execution results

.PARAMETER Results
    Array of SetupResult instances

.EXAMPLE
    Show-SetupSummary -Results $results
#>
function Show-SetupSummary
{
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        $Results
    )

    Write-Host ""
    Write-Host "========================================" -ForegroundColor White
    Write-Host "Setup Summary" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor White

    # Handle null, empty, or non-array results
    if ($null -eq $Results)
    {
        Write-Host "No handlers were executed" -ForegroundColor Gray
        return
    }

    # Ensure Results is an array
    $resultsArray = @($Results)
    $totalCount = $resultsArray.Count

    if ($totalCount -eq 0)
    {
        Write-Host "No handlers were executed" -ForegroundColor Gray
        return
    }

    $successCount = @($resultsArray | Where-Object { $_.Success }).Count
    $failureCount = @($resultsArray | Where-Object { -not $_.Success }).Count

    Write-Host ""
    Write-Host "Total: $totalCount | Success: $successCount | Failure: $failureCount" -ForegroundColor $(if ($failureCount -eq 0)
        { "Green"
        } else
        { "Yellow"
        })
    Write-Host ""

    foreach ($result in $resultsArray)
    {
        $color = if ($result.Success)
        { "Green"
        } else
        { "Red"
        }
        $status = if ($result.Success)
        { "✓"
        } else
        { "✗"
        }
        Write-Host "  [$status] $($result.HandlerName): $($result.Message)" -ForegroundColor $color
    }

    Write-Host ""
}
