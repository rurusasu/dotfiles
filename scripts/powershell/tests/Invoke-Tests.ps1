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

# Pester モジュールの確認とインストール
if (-not (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge [Version]"5.0.0" })) {
    Write-Host "Installing Pester 5.x..." -ForegroundColor Yellow
    Install-Module -Name Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force -SkipPublisherCheck
}

Import-Module Pester -MinimumVersion 5.0.0

# テスト対象ファイルの収集
$sourceFiles = @(
    "$projectRoot/lib/SetupHandler.ps1",
    "$projectRoot/lib/Invoke-ExternalCommand.ps1",
    "$projectRoot/handlers/Handler.WslConfig.ps1",
    "$projectRoot/handlers/Handler.Docker.ps1",
    "$projectRoot/handlers/Handler.VscodeServer.ps1",
    "$projectRoot/handlers/Handler.Chezmoi.ps1"
) | Where-Object { Test-Path $_ }

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
if ($sourceFiles.Count -gt 0) {
    $pesterConfig.CodeCoverage.Enabled = $true
    $pesterConfig.CodeCoverage.Path = $sourceFiles
    $pesterConfig.CodeCoverage.CoveragePercentTarget = $MinimumCoverage
    $pesterConfig.CodeCoverage.OutputFormat = "CoverageGutters"
    # 外部コマンド直接呼び出しはカバレッジから除外
    $pesterConfig.CodeCoverage.ExcludeTests = $true

    if ($CoverageOutputFile) {
        $pesterConfig.CodeCoverage.OutputPath = $CoverageOutputFile
        $pesterConfig.CodeCoverage.OutputFormat = "CoverageGutters"
    }
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
