<#
.SYNOPSIS
    Install Windows GUI applications only.
.DESCRIPTION
    Uses the existing PowerShell runtime and WinGet. Does not install CLI tools,
    deploy dotfiles, provision WSL, or execute administrator setup phases.
#>
[CmdletBinding()]
param(
    [hashtable]$Options = @{},
    [switch]$UserPhaseOnly,
    [switch]$WingetVerifyCommandOnly,
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$libPath = Join-Path $PSScriptRoot "lib"
. (Join-Path $libPath "WindowsEnvironment.ps1")
Repair-WindowsSetupEnvironment

$userScriptPath = Join-Path $PSScriptRoot "install.user.ps1"
if (-not (Test-Path -LiteralPath $userScriptPath -PathType Leaf)) {
    throw "GUI setup script not found: $userScriptPath"
}
if ($WingetVerifyCommandOnly) {
    $Options["WingetVerifyCommandOnly"] = $true
}

Write-Host "Windows GUI Application Setup" -ForegroundColor Cyan
& $userScriptPath -Options $Options

if ($UserPhaseOnly) {
    Write-Host "User Phase Complete!" -ForegroundColor Green
}
else {
    Write-Host "Setup Complete!" -ForegroundColor Green
}
if (-not $NoPause) {
    Write-Host "Press Enter to close..." -ForegroundColor Gray
    Read-Host | Out-Null
}
