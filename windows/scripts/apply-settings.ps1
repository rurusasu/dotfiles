# Apply Windows settings from dotfiles
# Run this script as Administrator to create symlinks and install packages

param(
    [string]$DotfilesPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [switch]$SkipWinget,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Check for admin privileges (required for symlinks)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] This script requires Administrator privileges for creating symlinks." -ForegroundColor Red
    Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
    exit 1
}

Write-Host "Applying Windows settings from dotfiles..." -ForegroundColor Cyan
Write-Host "Dotfiles path: $DotfilesPath" -ForegroundColor Gray

# Apply Windows Terminal settings (symlink)
$TerminalSettingsSource = Join-Path $DotfilesPath "windows\terminal\settings.json"
$TerminalSettingsDest = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"

if (Test-Path $TerminalSettingsSource) {
    $destDir = Split-Path -Parent $TerminalSettingsDest
    if (Test-Path $destDir) {
        # Backup existing settings if not a symlink
        if ((Test-Path $TerminalSettingsDest) -and -not (Get-Item $TerminalSettingsDest).Attributes.ToString().Contains("ReparsePoint")) {
            $backupPath = "$TerminalSettingsDest.backup"
            Copy-Item -Path $TerminalSettingsDest -Destination $backupPath -Force
            Write-Host "[INFO] Backed up existing settings to $backupPath" -ForegroundColor Gray
        }

        # Remove existing file/symlink
        if (Test-Path $TerminalSettingsDest) {
            Remove-Item -Path $TerminalSettingsDest -Force
        }

        # Create symlink
        New-Item -ItemType SymbolicLink -Path $TerminalSettingsDest -Target $TerminalSettingsSource | Out-Null
        Write-Host "[OK] Windows Terminal settings linked" -ForegroundColor Green
    } else {
        Write-Host "[SKIP] Windows Terminal not installed" -ForegroundColor Yellow
    }
} else {
    Write-Host "[SKIP] Windows Terminal settings not found in dotfiles" -ForegroundColor Yellow
}

# Install winget packages
if (-not $SkipWinget) {
    $WingetPackagesSource = Join-Path $DotfilesPath "windows\winget\packages.json"

    if (Test-Path $WingetPackagesSource) {
        Write-Host ""
        Write-Host "Installing winget packages (this may take a while)..." -ForegroundColor Gray
        Write-Host "You may need to accept license agreements interactively." -ForegroundColor Yellow

        winget import -i $WingetPackagesSource --accept-package-agreements --accept-source-agreements

        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Winget packages installed" -ForegroundColor Green
        } else {
            Write-Host "[WARN] Some packages may have failed to install" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[SKIP] Winget packages file not found" -ForegroundColor Yellow
    }
} else {
    Write-Host "[SKIP] Winget packages (--SkipWinget specified)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Apply complete!" -ForegroundColor Green
