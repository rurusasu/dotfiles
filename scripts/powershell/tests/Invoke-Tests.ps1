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
    .\Invoke-Tests.ps1 -Path .\Install.Tests.ps1
    特定のテストファイルのみ実行
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$Path,

    [Parameter()]
    [ValidateRange(0, 100)]
    [int]$MinimumCoverage = 0,

    [Parameter()]
    [string]$CoverageOutputFile,

    [Parameter()]
    [switch]$ShowCoverage
)

$ErrorActionPreference = "Stop"
if ($PSScriptRoot) {
    $scriptRoot = $PSScriptRoot
}
else {
    $scriptRoot = (Get-Location).ProviderPath
}
$projectRoot = Split-Path -Parent $scriptRoot
$coverageRequested = ($MinimumCoverage -gt 0) -or $ShowCoverage -or (-not [string]::IsNullOrWhiteSpace($CoverageOutputFile))

# インストール済みの互換性のある安定版を使い、不足時は準備不足として失敗する。
. (Join-Path $scriptRoot 'support/Resolve-TestModule.ps1')
$pesterModule = Resolve-TestModule -Name Pester

if (Get-Module -Name Pester) {
    Remove-Module -Name Pester -Force -ErrorAction Stop
}
Import-Module -Name $pesterModule.Path -Force -ErrorAction Stop

$loadedVersion = (Get-Module -Name Pester).Version
Write-Host "Pester v$loadedVersion を使用します" -ForegroundColor Cyan

# テスト対象ファイルの収集（カバレッジ有効時のみ）
$sourceFiles = @()
if ($coverageRequested) {
    $sourceFiles = @(@(
        Get-ChildItem -LiteralPath (Join-Path $projectRoot 'lib') -Filter '*.ps1' -File -ErrorAction SilentlyContinue
        Get-ChildItem -LiteralPath $projectRoot -Filter 'install.ps1' -File
    ) | Select-Object -ExpandProperty FullName)

    if ($sourceFiles.Count -eq 0) {
        throw "Coverage was requested, but no runtime PowerShell source files were found: $projectRoot"
    }
}

# テストパスの決定
if (-not $Path) {
    $Path = @($scriptRoot)
}

# Pester 設定
$pesterConfig = New-PesterConfiguration

# テストパス
$pesterConfig.Run.Path = $Path
$pesterConfig.Run.Exit = $false
$pesterConfig.Run.PassThru = $true

# 出力設定
$pesterConfig.Output.Verbosity = "Detailed"

# カバレッジ設定
if ($coverageRequested) {
    $pesterConfig.CodeCoverage.Enabled = $true
    $pesterConfig.CodeCoverage.Path = $sourceFiles
    $pesterConfig.CodeCoverage.CoveragePercentTarget = $MinimumCoverage
    $pesterConfig.CodeCoverage.OutputFormat = "Cobertura"
    $pesterConfig.CodeCoverage.ExcludeTests = $true
    $pesterConfig.CodeCoverage.UseBreakpoints = $false

    if ($CoverageOutputFile) {
        $pesterConfig.CodeCoverage.OutputPath = $CoverageOutputFile
    }
}
else {
    $pesterConfig.CodeCoverage.Enabled = $false
}

# テスト実行
# 呼び出し元の StrictMode をテストスコープへ継承させず、通常の Pester CI と実行条件を揃える
Set-StrictMode -Off
$result = Invoke-Pester -Configuration $pesterConfig

if (-not $result) {
    Write-Host "FAIL: Test runner did not return a result." -ForegroundColor Red
    exit 1
}

if ($coverageRequested) {
    if ($null -eq $result.CodeCoverage -or $null -eq $result.CodeCoverage.CoveragePercent) {
        Write-Host 'FAIL: Coverage was requested, but no coverage measurement was returned.' -ForegroundColor Red
        exit 1
    }
    $coverage = $result.CodeCoverage.CoveragePercent

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
if ($result.TotalCount -le 0) {
    Write-Host "FAIL: No tests were discovered" -ForegroundColor Red
    exit 1
}

if ($result.FailedCount -gt 0 -or $result.Result -eq 'Failed' -or
    $result.FailedContainersCount -gt 0 -or $result.FailedBlocksCount -gt 0) {
    exit 1
}

exit 0
