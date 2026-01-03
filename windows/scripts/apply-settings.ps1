# Apply Windows settings from dotfiles
# Run this script as Administrator to create symlinks and install packages

param(
    [string]$DotfilesPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [switch]$SkipWinget,
    [string]$WslDistro = "NixOS",
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

# Get WSL user for Nix-generated settings
$WslUser = wsl -d $WslDistro -- whoami 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Could not get WSL user from $WslDistro" -ForegroundColor Red
    Write-Host "[HINT] Make sure WSL distro '$WslDistro' is running" -ForegroundColor Yellow
    exit 1
}
$WslUser = $WslUser.Trim()

# Windows Terminal settings (Nix-generated from WSL)
# Note: Home Manager creates symlinks, so we need to resolve and copy the actual file
$TerminalSettingsDest = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"

Write-Host "[INFO] Using Nix-generated settings from WSL" -ForegroundColor Gray

$destDir = Split-Path -Parent $TerminalSettingsDest
if (Test-Path $destDir) {
    # Read the actual content from WSL (resolves symlinks)
    $settingsContent = wsl -d $WslDistro -- bash -c "cat /home/$WslUser/.config/windows-terminal/settings.json" 2>$null

    if ($LASTEXITCODE -eq 0 -and $settingsContent) {
        # Backup existing settings if not already backed up
        if ((Test-Path $TerminalSettingsDest) -and -not (Test-Path "$TerminalSettingsDest.backup")) {
            Copy-Item -Path $TerminalSettingsDest -Destination "$TerminalSettingsDest.backup" -Force
            Write-Host "[INFO] Backed up existing settings to $TerminalSettingsDest.backup" -ForegroundColor Gray
        }

        # Write the settings directly (copy approach since symlinks don't work with WSL symlinks)
        $settingsContent | Out-File -FilePath $TerminalSettingsDest -Encoding utf8 -Force
        Write-Host "[OK] Windows Terminal settings applied" -ForegroundColor Green
        Write-Host "     Note: Settings are copied, run this script again after nixos-rebuild to update" -ForegroundColor Gray
    } else {
        Write-Host "[SKIP] Windows Terminal settings not found in WSL" -ForegroundColor Yellow
        Write-Host "[HINT] Run 'sudo nixos-rebuild switch' in WSL first to generate settings" -ForegroundColor Yellow
    }
} else {
    Write-Host "[SKIP] Windows Terminal not installed" -ForegroundColor Yellow
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
