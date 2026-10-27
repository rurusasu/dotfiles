#Requires -Version 5.1
[CmdletBinding()]
param([string[]]$Path = @($PSScriptRoot))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'support/Resolve-TestModule.ps1')
$pesterModule = Resolve-TestModule -Name Pester
if (Get-Module -Name Pester) { Remove-Module -Name Pester -Force -ErrorAction Stop }
Import-Module -Name $pesterModule.Path -Force -ErrorAction Stop

$config = New-PesterConfiguration
$config.Run.Path = $Path
$config.Run.Exit = $false
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'
$config.CodeCoverage.Enabled = $false
Set-StrictMode -Off
$result = Invoke-Pester -Configuration $config
if (-not $result -or $result.TotalCount -le 0) {
    Write-Host 'FAIL: No tests were discovered.' -ForegroundColor Red
    exit 1
}
if ($result.FailedCount -gt 0 -or $result.Result -eq 'Failed' -or
    $result.FailedContainersCount -gt 0 -or $result.FailedBlocksCount -gt 0) { exit 1 }
exit 0
