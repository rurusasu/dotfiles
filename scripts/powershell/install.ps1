<#
.SYNOPSIS
    Install Windows GUI applications and configure NixOS-WSL.
.DESCRIPTION
    Taskfile owns the GUI -> NixOS-WSL sequence. UserPhaseOnly runs GUI setup alone.
#>
[CmdletBinding()]
param(
    [hashtable]$Options = @{},
    [string]$DistroName = 'NixOS',
    [string]$InstallDir = '',
    [string]$ReleaseTag = '',
    [ValidateSet('link', 'repo', 'nix', 'none')]
    [string]$SyncMode = 'link',
    [ValidateSet('repo', 'lock', 'none')]
    [string]$SyncBack = 'lock',
    [switch]$ForcePostInstall,
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

$restartRequired = $false
if ($UserPhaseOnly) {
    Write-Host "Windows GUI Application Setup" -ForegroundColor Cyan
    & $userScriptPath -Options $Options
    Write-Host "User Phase Complete!" -ForegroundColor Green
}
else {
    foreach ($name in 'ReleaseTag', 'SyncMode', 'SyncBack', 'ForcePostInstall') {
        if ($PSBoundParameters.ContainsKey($name)) {
            $Options[$name] = Get-Variable -Name $name -ValueOnly
            if ($name -eq 'ForcePostInstall') { $Options[$name] = [bool]$ForcePostInstall }
        }
    }
    . (Join-Path $libPath 'Invoke-ExternalCommand.ps1')
    . (Join-Path $libPath 'Invoke-WindowsInstallTask.ps1')
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
    $restartRequired = Invoke-WindowsInstallTask -Repository $repoRoot -Configuration @{
        DistroName = $DistroName; InstallDir = $InstallDir; Options = $Options
    }
    if (-not $restartRequired) { Write-Host "Setup Complete!" -ForegroundColor Green }
}
if (-not $NoPause) {
    Write-Host "Press Enter to close..." -ForegroundColor Gray
    Read-Host | Out-Null
}
if ($restartRequired) { exit 3010 }
