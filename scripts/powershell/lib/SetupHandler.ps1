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

    # 実行フェーズ (1 = User Scope, 2 = Admin/後半)
    # Phase 1: winget, npm, pnpm
    # Phase 2: chezmoi, nix-rebuild, wsl-config, docker, vscode-server, nixos-wsl, vhd-manager
    [int]$Phase = 2

    # 成功していなければ実行してはいけないハンドラー名
    [string[]]$DependsOn = @()

    # ログバッファリング（CanApply 中はバッファリングし、判定後に表示）
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
        WinGet\Links 配下の shim が現行 exe を指しているか判定する
    .DESCRIPTION
        Links\<name>.exe はシンボリックリンクだけを有効な portable link とみなす。
        ハードリンク/コピーは winget upgrade 後に旧バージョンの実体を保持し得るため、
        常に陳腐化として扱い、次回 Apply でシンボリックリンクへ置き換える。
        ダングリング（ターゲット消失）や未作成も最新ではないとみなす。
    .PARAMETER linkPath
        Links 配下の shim パス
    .PARAMETER targetExe
        現在インストールされている実行ファイルのパス
    .OUTPUTS
        shim が現行 exe と一致していれば $true
    #>
    [bool] IsPortableLinkCurrent([string]$linkPath, [string]$targetExe) {
        if (-not (Test-Path -LiteralPath $linkPath)) { return $false }

        $link = Get-Item -LiteralPath $linkPath -Force
        if ($link.LinkType -eq "SymbolicLink") {
            return (@($link.Target)[0]) -eq $targetExe
        }

        return $false
    }

    <#
    .SYNOPSIS
        portable package のコピー shim が現行 exe と同一内容か判定する
    .DESCRIPTION
        Windows PowerShell の非昇格ユーザーセッションではシンボリックリンクを
        作成できないことがあるため、portable exe のコピーを代替 shim として使う。
        サイズだけでは同一バージョンを保証できないので SHA-256 を比較する。
    #>
    [bool] IsPortableCopyCurrent([string]$linkPath, [string]$targetExe) {
        if (-not (Test-Path -LiteralPath $linkPath -PathType Leaf) -or
            -not (Test-Path -LiteralPath $targetExe -PathType Leaf)) {
            return $false
        }

        try {
            $link = Get-Item -LiteralPath $linkPath -Force
            if ($link.LinkType -eq "SymbolicLink") { return $false }

            $linkHash = (Get-FileHash -LiteralPath $linkPath -Algorithm SHA256).Hash
            $targetHash = (Get-FileHash -LiteralPath $targetExe -Algorithm SHA256).Hash
            return $linkHash -eq $targetHash
        }
        catch {
            return $false
        }
    }

    <#
    .SYNOPSIS
        WinGet\Links 配下にシンボリックリンク shim を作成する
    .DESCRIPTION
        既存 shim は一時シンボリックリンクの作成成功後に置き換える。
        ハードリンク/コピーは winget upgrade に追従しないため使用しない。
    .PARAMETER linkPath
        作成する shim パス
    .PARAMETER targetExe
        リンク先の実行ファイル
    #>
    [void] CreatePortableLink([string]$linkPath, [string]$targetExe) {
        if (-not (Test-Path -LiteralPath $linkPath)) {
            $this.Log("シンボリックリンクを作成しています: $linkPath -> $targetExe")
            New-Item -ItemType SymbolicLink -Path $linkPath -Target $targetExe -Force -ErrorAction Stop | Out-Null
            $this.Log("シンボリックリンクを作成しました", "Green")
            return
        }

        $parentDir = Split-Path -Parent $linkPath
        $linkName = Split-Path -Leaf $linkPath
        $suffix = [System.Guid]::NewGuid().ToString("N")
        $tempLinkPath = Join-Path $parentDir ".$linkName.$suffix.tmp"
        $backupPath = Join-Path $parentDir ".$linkName.$suffix.backup"
        $oldMoved = $false

        try {
            $this.Log("シンボリックリンクを作成しています: $linkPath -> $targetExe")
            New-Item -ItemType SymbolicLink -Path $tempLinkPath -Target $targetExe -Force -ErrorAction Stop | Out-Null
            Move-Item -LiteralPath $linkPath -Destination $backupPath -Force -ErrorAction Stop
            $oldMoved = $true
            Move-Item -LiteralPath $tempLinkPath -Destination $linkPath -Force -ErrorAction Stop
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
            $this.Log("シンボリックリンクを作成しました", "Green")
        }
        catch {
            if ($oldMoved -and -not (Test-Path -LiteralPath $linkPath) -and (Test-Path -LiteralPath $backupPath)) {
                Move-Item -LiteralPath $backupPath -Destination $linkPath -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path -LiteralPath $tempLinkPath) {
                Remove-Item -LiteralPath $tempLinkPath -Force -ErrorAction SilentlyContinue
            }
            throw
        }
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

}

# ========================================
<#
.SYNOPSIS
    Display a summary of handler execution results

.PARAMETER Results
    Array of SetupResult instances

.EXAMPLE
    Show-SetupSummary -Results $results
#>
function Show-SetupSummary {
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
    if ($null -eq $Results) {
        Write-Host "No handlers were executed" -ForegroundColor Gray
        return
    }

    # Ensure Results is an array
    $resultsArray = @($Results)
    $totalCount = $resultsArray.Count

    if ($totalCount -eq 0) {
        Write-Host "No handlers were executed" -ForegroundColor Gray
        return
    }

    $successCount = @($resultsArray | Where-Object { $_.Success }).Count
    $failureCount = @($resultsArray | Where-Object { -not $_.Success }).Count

    Write-Host ""
    Write-Host "Total: $totalCount | Success: $successCount | Failure: $failureCount" -ForegroundColor $(if ($failureCount -eq 0) {
            "Green"
        }
        else {
            "Yellow"
        })
    Write-Host ""

    foreach ($result in $resultsArray) {
        $color = if ($result.Success) {
            "Green"
        }
        else {
            "Red"
        }
        $status = if ($result.Success) {
            "✓"
        }
        else {
            "✗"
        }
        Write-Host "  [$status] $($result.HandlerName): $($result.Message)" -ForegroundColor $color
    }

    Write-Host ""
}
