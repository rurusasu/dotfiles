#Requires -Version 5.0

<#
.SYNOPSIS
    PowerShell テストランナー

.DESCRIPTION
    Pester を使用してすべてのテストを実行し、カバレッジレポートを生成する

.PARAMETER Path
    テストファイルまたはディレクトリへのパス。指定しない場合は tests/ 全体を実行

.PARAMETER MinimumCoverage
    最小カバレッジパーセンテージ。この値を下回ると失敗

.PARAMETER OutputFile
    JUnit XML レポートの出力パス

.PARAMETER CoverageOutputFile
    Cobertura カバレッジレポートの出力パス

.PARAMETER ShowCoverage
    詳細なカバレッジレポートを表示するか

.EXAMPLE
    .\Invoke-Tests.ps1
    全テストを実行

.EXAMPLE
    .\Invoke-Tests.ps1 -MinimumCoverage 90
    90% 以上のカバレッジを要求

.EXAMPLE
    .\Invoke-Tests.ps1 -Path .\tests\handlers\Handler.Chezmoi.Tests.ps1
    特定のテストファイルのみ実行
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Path,

    [Parameter()]
    [int]$MinimumCoverage = 80,

    [Parameter()]
    [string]$OutputFile,

    [Parameter()]
    [string]$CoverageOutputFile,

    [Parameter()]
    [switch]$ShowCoverage
)

$ErrorActionPreference = "Stop"
$scriptRoot = $PSScriptRoot
$projectRoot = Split-Path -Parent $scriptRoot

# Pester v3 が自動ロードされるのを防ぐ
if (Get-Module -Name Pester) {
    $currentVersion = (Get-Module -Name Pester).Version
    if ($currentVersion -lt [Version]"5.0.0") {
        Write-Host "Pester v$currentVersion がロードされています。v5 に切り替えます..." -ForegroundColor Yellow
        Remove-Module -Name Pester -Force -ErrorAction SilentlyContinue
    }
}

# Pester モジュールの確認とインストール
$pesterV5 = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge [Version]"5.0.0" } | Select-Object -First 1

if (-not $pesterV5) {
    Write-Host "Pester v5 がインストールされていません。インストールを開始します..." -ForegroundColor Yellow
    try {
        Install-Module -Name Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber
        Write-Host "Pester v5 のインストールに成功しました" -ForegroundColor Green
    } catch {
        Write-Error "Pester v5 のインストールに失敗しました: $($_.Exception.Message)"
        exit 1
    }
}

# Pester v5 を強制ロード
Import-Module -Name Pester -MinimumVersion 5.0.0 -Force

$loadedVersion = (Get-Module -Name Pester).Version
Write-Host "Pester v$loadedVersion を使用します" -ForegroundColor Cyan
Write-Host ""

# テスト対象ファイルの収集（カバレッジ有効時のみ）
$sourceFiles = @()
if ($MinimumCoverage -gt 0) {
    $sourceFiles = @(
        "$projectRoot\lib\SetupHandler.ps1",
        "$projectRoot\lib\Invoke-ExternalCommand.ps1",
        "$projectRoot\handlers\Handler.WslConfig.ps1",
        "$projectRoot\handlers\Handler.Docker.ps1",
        "$projectRoot\handlers\Handler.VscodeServer.ps1",
        "$projectRoot\handlers\Handler.Chezmoi.ps1",
        "$projectRoot\handlers\Handler.Winget.ps1"
    ) | Where-Object { Test-Path $_ }

    if ($sourceFiles.Count -eq 0) {
        Write-Warning "カバレッジ対象ファイルが見つかりません。パス: $projectRoot"
    }
}

# テストパスの決定
if (-not $Path) {
    $Path = $scriptRoot
}

# Pester 設定
$pesterConfig = New-PesterConfiguration

# テストパス
$pesterConfig.Run.Path = $Path
$pesterConfig.Run.Exit = $false
$pesterConfig.Run.PassThru = $true

# 出力設定
$pesterConfig.Output.Verbosity = "Detailed"
$pesterConfig.Output.CIFormat = "Auto"

# カバレッジ設定
if ($sourceFiles.Count -gt 0 -and $MinimumCoverage -gt 0) {
    $pesterConfig.CodeCoverage.Enabled = $true
    $pesterConfig.CodeCoverage.Path = $sourceFiles
    $pesterConfig.CodeCoverage.CoveragePercentTarget = $MinimumCoverage
    $pesterConfig.CodeCoverage.OutputFormat = "CoverageGutters"
    # 外部コマンド直接呼び出しはカバレッジから除外
    $pesterConfig.CodeCoverage.ExcludeTests = $true
    # カバレッジでモックを使用可能にする（ブレークポイント方式を無効化）
    $pesterConfig.CodeCoverage.UseBreakpoints = $false

    if ($CoverageOutputFile) {
        $pesterConfig.CodeCoverage.OutputPath = $CoverageOutputFile
        $pesterConfig.CodeCoverage.OutputFormat = "CoverageGutters"
    }
} else {
    $pesterConfig.CodeCoverage.Enabled = $false
}

# JUnit XML 出力
if ($OutputFile) {
    $pesterConfig.TestResult.Enabled = $true
    $pesterConfig.TestResult.OutputPath = $OutputFile
    $pesterConfig.TestResult.OutputFormat = "JUnitXml"
}

Write-Host ""
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "  PowerShell Test Runner (Pester)" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Test Path: $Path" -ForegroundColor White
Write-Host "Source Files: $($sourceFiles.Count)" -ForegroundColor White
Write-Host "Minimum Coverage: $MinimumCoverage%" -ForegroundColor White
Write-Host ""

# テスト実行
$result = Invoke-Pester -Configuration $pesterConfig

Write-Host ""
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "  Test Results Summary" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

# 結果表示
$passedCount = $result.PassedCount
$failedCount = $result.FailedCount
$skippedCount = $result.SkippedCount
$totalCount = $result.TotalCount

Write-Host "Tests: " -NoNewline
Write-Host "$passedCount passed" -ForegroundColor Green -NoNewline
Write-Host ", " -NoNewline

if ($failedCount -gt 0) {
    Write-Host "$failedCount failed" -ForegroundColor Red -NoNewline
} else {
    Write-Host "$failedCount failed" -ForegroundColor Gray -NoNewline
}

Write-Host ", " -NoNewline
Write-Host "$skippedCount skipped" -ForegroundColor Yellow -NoNewline
Write-Host " / $totalCount total" -ForegroundColor White
Write-Host ""

# カバレッジ表示
if ($result.CodeCoverage -and $result.CodeCoverage.CoveragePercent) {
    $coverage = [math]::Round($result.CodeCoverage.CoveragePercent, 2)
    $coveredCommands = $result.CodeCoverage.CommandsExecutedCount
    $totalCommands = $result.CodeCoverage.CommandsAnalyzedCount
    $missedCommands = $result.CodeCoverage.CommandsMissedCount

    Write-Host "Coverage: " -NoNewline

    if ($coverage -ge $MinimumCoverage) {
        Write-Host "$coverage%" -ForegroundColor Green -NoNewline
    } else {
        Write-Host "$coverage%" -ForegroundColor Red -NoNewline
    }

    Write-Host " ($coveredCommands / $totalCommands commands, $missedCommands missed)" -ForegroundColor White
    Write-Host ""

    # 詳細カバレッジ
    if ($ShowCoverage -and $result.CodeCoverage.CommandsMissed) {
        Write-Host "Uncovered Commands:" -ForegroundColor Yellow
        $result.CodeCoverage.CommandsMissed |
            Group-Object File |
            ForEach-Object {
                Write-Host "  $($_.Name):" -ForegroundColor White
                $_.Group | ForEach-Object {
                    Write-Host "    Line $($_.Line): $($_.Command)" -ForegroundColor Gray
                }
            }
        Write-Host ""
    }

    # カバレッジしきい値チェック
    if ($coverage -lt $MinimumCoverage) {
        Write-Host "FAIL: Coverage ($coverage%) is below minimum ($MinimumCoverage%)" -ForegroundColor Red
        exit 1
    }
}

# 失敗チェック
if ($failedCount -gt 0) {
    Write-Host "FAIL: $failedCount test(s) failed" -ForegroundColor Red
    exit 1
}

Write-Host "SUCCESS: All tests passed!" -ForegroundColor Green
exit 0
