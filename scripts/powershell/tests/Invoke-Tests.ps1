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

.PARAMETER IncludeIntegration
    Integration.Tests.ps1 を実行対象に含めるか

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
    [string[]]$Path,

    [Parameter()]
    [int]$MinimumCoverage = 0,

    [Parameter()]
    [string]$OutputFile,

    [Parameter()]
    [string]$CoverageOutputFile,

    [Parameter()]
    [switch]$ShowCoverage,

    [Parameter()]
    [switch]$IncludeIntegration
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

function ConvertTo-Xml10SafeText {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return ''
    }

    # Pester's JUnit exporter writes failure text directly to XML attributes.
    # Keep diagnostics readable while representing XML 1.0-forbidden controls.
    return [regex]::Replace([string]$Value, '[\x00-\x08\x0B\x0C\x0E-\x1F\uFFFE\uFFFF]', {
            param($match)
            '[U+{0:X4}]' -f [int][char]$match.Value[0]
        })
}

function Write-SafeJUnitReport {
    param(
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)][string]$Path
    )

    $tests = @($Result.Tests | Where-Object ShouldRun)
    $failures = @($tests | Where-Object Result -EQ 'Failed')
    $skipped = @($tests | Where-Object { $_.Result -notin @('Passed', 'Failed') })
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $writer = [System.Xml.XmlWriter]::Create([System.IO.Path]::GetFullPath($Path), $settings)
    try {
        $writer.WriteStartDocument()
        $writer.WriteStartElement('testsuites')
        $writer.WriteAttributeString('name', (ConvertTo-Xml10SafeText $Result.Configuration.TestResult.TestSuiteName.Value))
        $writer.WriteAttributeString('tests', [string]$tests.Count)
        $writer.WriteAttributeString('errors', [string]($Result.FailedContainersCount + $Result.FailedBlocksCount))
        $writer.WriteAttributeString('failures', [string]$failures.Count)
        $writer.WriteAttributeString('disabled', [string]($Result.NotRunCount + $Result.SkippedCount))
        $writer.WriteAttributeString('time', $Result.Duration.TotalSeconds.ToString('0.000', [Globalization.CultureInfo]::InvariantCulture))
        $writer.WriteStartElement('testsuite')
        $writer.WriteAttributeString('name', 'PowerShell')
        $writer.WriteAttributeString('tests', [string]$tests.Count)
        $writer.WriteAttributeString('errors', '0')
        $writer.WriteAttributeString('failures', [string]$failures.Count)
        $writer.WriteAttributeString('skipped', [string]$skipped.Count)
        $writer.WriteAttributeString('time', $Result.Duration.TotalSeconds.ToString('0.000', [Globalization.CultureInfo]::InvariantCulture))

        foreach ($test in $tests) {
            $writer.WriteStartElement('testcase')
            $writer.WriteAttributeString('name', (ConvertTo-Xml10SafeText $test.ExpandedPath))
            $writer.WriteAttributeString('classname', (ConvertTo-Xml10SafeText ($test.Block.Path -join '.')))
            $writer.WriteAttributeString('time', $test.Duration.TotalSeconds.ToString('0.000', [Globalization.CultureInfo]::InvariantCulture))

            if ($test.Result -eq 'Failed') {
                $messages = @($test.ErrorRecord | ForEach-Object {
                        if ($_.DisplayErrorMessage) { $_.DisplayErrorMessage } else { $_.ToString() }
                    })
                $traces = @($test.ErrorRecord | ForEach-Object {
                        if ($_.DisplayStackTrace) { $_.DisplayStackTrace }
                    })
                $writer.WriteStartElement('failure')
                $writer.WriteAttributeString('message', (ConvertTo-Xml10SafeText ($messages -join [Environment]::NewLine)))
                if ($traces.Count -gt 0) {
                    $writer.WriteString((ConvertTo-Xml10SafeText ($traces -join [Environment]::NewLine)))
                }
                $writer.WriteEndElement()
            }
            elseif ($test.Result -notin @('Passed', 'Failed')) {
                $writer.WriteStartElement('skipped')
                $reason = @($test.ErrorRecord | ForEach-Object { if ($_.DisplayErrorMessage) { $_.DisplayErrorMessage } }) -join [Environment]::NewLine
                if ($reason) { $writer.WriteAttributeString('message', (ConvertTo-Xml10SafeText $reason)) }
                $writer.WriteEndElement()
            }

            $writer.WriteEndElement()
        }

        $writer.WriteEndElement()
        $writer.WriteEndElement()
        $writer.WriteEndDocument()
        $writer.Flush()
    }
    finally {
        $writer.Dispose()
    }
}

# Pester v3 / v6 が自動ロードされるのを防ぐ
$currentPester = Get-Module -Name Pester | Select-Object -First 1
if ($currentPester) {
    $currentVersion = $currentPester.Version
    if ($currentVersion -lt [Version]"5.0.0" -or $currentVersion -ge [Version]"6.0.0") {
        Write-Host "Pester v$currentVersion がロードされています。Pester v5 に切り替えます..." -ForegroundColor Yellow
        Remove-Module -Name Pester -Force -ErrorAction SilentlyContinue
    }
}

# Pester v5 モジュールの確認とインストール
$pesterV5 = Get-Module -ListAvailable -Name Pester |
    Where-Object { $_.Version -ge [Version]"5.0.0" -and $_.Version -lt [Version]"6.0.0" } |
    Sort-Object Version -Descending |
    Select-Object -First 1

if (-not $pesterV5) {
    Write-Host "Pester v5 がインストールされていません。自動インストールします..." -ForegroundColor Yellow
    try {
        Install-Module -Name Pester -MinimumVersion 5.0.0 -MaximumVersion 5.999.999 -Scope CurrentUser -Force -SkipPublisherCheck
        $pesterV5 = Get-Module -ListAvailable -Name Pester |
            Where-Object { $_.Version -ge [Version]"5.0.0" -and $_.Version -lt [Version]"6.0.0" } |
            Sort-Object Version -Descending |
            Select-Object -First 1
        if (-not $pesterV5) {
            throw "インストール後もモジュールが見つかりません"
        }
        Write-Host "Pester v$($pesterV5.Version) をインストールしました" -ForegroundColor Green
    }
    catch {
        Write-Error "Pester v5 の自動インストールに失敗しました: $($_.Exception.Message)"
        Write-Error "手動でインストールしてください: Install-Module -Name Pester -MinimumVersion 5.0.0 -MaximumVersion 5.999.999 -Scope CurrentUser -Force"
        exit 1
    }
}

# Pester v5 を強制ロード
Import-Module -Name Pester -RequiredVersion $pesterV5.Version -Force

$loadedVersion = (Get-Module -Name Pester).Version
Write-Host "Pester v$loadedVersion を使用します" -ForegroundColor Cyan
Write-Host ""

# テスト対象ファイルの収集（カバレッジ有効時のみ）
$sourceFiles = @()
if ($coverageRequested) {
    $sourceFiles = @(
        Get-ChildItem -LiteralPath (Join-Path $projectRoot 'lib') -Filter '*.ps1' -File -ErrorAction SilentlyContinue
        Get-ChildItem -LiteralPath (Join-Path $projectRoot 'handlers') -Filter 'Handler.*.ps1' -File -ErrorAction SilentlyContinue
    ) | Select-Object -ExpandProperty FullName

    if ($sourceFiles.Count -eq 0) {
        Write-Warning "カバレッジ対象ファイルが見つかりません。パス: $projectRoot"
    }
}

# テストパスの決定
$excludeIntegration = $false
if (-not $Path) {
    $Path = @($scriptRoot)
    $excludeIntegration = -not $IncludeIntegration
}

# Pester 設定
$pesterConfig = New-PesterConfiguration

# テストパス
$pesterConfig.Run.Path = $Path
if ($excludeIntegration) {
    $pesterConfig.Run.ExcludePath = @("**/Integration.Tests.ps1")
}
$pesterConfig.Run.Exit = $false
$pesterConfig.Run.PassThru = $true

# 出力設定。JUnit XML を生成する CI 実行では ANSI 制御文字を出力しない。
# Pester 5.9 は CIFormat=Auto と JUnitXml を併用すると、色付きのログを XML
# 属性へそのまま書き込み、結果ファイル自体を壊すことがある。
$pesterConfig.Output.Verbosity = if ($OutputFile) { "Normal" } else { "Detailed" }
$pesterConfig.Output.CIFormat = if ($OutputFile) { "None" } else { "Auto" }
$pesterConfig.Output.RenderMode = if ($OutputFile) { "Plaintext" } else { "Auto" }

# カバレッジ設定
if ($coverageRequested) {
    if ($sourceFiles.Count -eq 0) {
        $pesterConfig.CodeCoverage.Enabled = $false
    }
    else {
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
    }
}
else {
    $pesterConfig.CodeCoverage.Enabled = $false
}

# JUnit XML 出力
if ($OutputFile) {
    # Pester 5.9's JUnit exporter can fail on ANSI ESC in failure details. Write
    # the report after the run so invalid XML controls are represented, not lost.
    $pesterConfig.TestResult.Enabled = $false
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
# 呼び出し元の StrictMode をテストスコープへ継承させず、通常の Pester CI と実行条件を揃える
Set-StrictMode -Off
$result = Invoke-Pester -Configuration $pesterConfig

if ($OutputFile -and $result) {
    Write-SafeJUnitReport -Result $result -Path $OutputFile
}

if (-not $result) {
    Write-Host "FAIL: Test runner did not return a result." -ForegroundColor Red
    exit 1
}

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
}
else {
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
    }
    else {
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
if ($totalCount -le 0) {
    Write-Host "FAIL: No tests were discovered" -ForegroundColor Red
    exit 1
}

if ($failedCount -gt 0 -or $result.Result -eq 'Failed' -or
    $result.FailedContainersCount -gt 0 -or $result.FailedBlocksCount -gt 0) {
    Write-Host "FAIL: $failedCount test(s) failed; containers=$($result.FailedContainersCount), blocks=$($result.FailedBlocksCount)" -ForegroundColor Red
    exit 1
}

Write-Host "SUCCESS: All tests passed!" -ForegroundColor Green
exit 0
