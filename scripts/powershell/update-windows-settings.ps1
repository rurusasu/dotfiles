# Apply Windows settings from dotfiles
# Automatically elevates to Administrator if needed

[CmdletBinding()]
param(
    [string]$DotfilesPath = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))),
    [switch]$SkipWinget,
    [string]$WslDistro = "NixOS",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Auto-elevate to Administrator if needed
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "管理者権限が必要です。UAC プロンプトを表示します..." -ForegroundColor Yellow
    $scriptPath = $PSCommandPath
    $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptPath`"")
    foreach ($key in $PSBoundParameters.Keys) {
        $value = $PSBoundParameters[$key]
        if ($value -is [switch]) {
            if ($value) { $arguments += "-$key" }
        } else {
            $arguments += "-$key"
            $arguments += "`"$value`""
        }
    }
    Start-Process pwsh -ArgumentList $arguments -Verb RunAs
    exit 0
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
    } else {
        Write-Host "[SKIP] Windows Terminal settings not found in WSL" -ForegroundColor Yellow
        Write-Host "[HINT] Run 'sudo nixos-rebuild switch' in WSL first to generate settings" -ForegroundColor Yellow
    }
} else {
    Write-Host "[SKIP] Windows Terminal not installed" -ForegroundColor Yellow
}

# WezTerm settings (Nix-generated from WSL)
$WeztermConfigDir = "$env:USERPROFILE\.config\wezterm"
$WeztermConfigDest = "$WeztermConfigDir\wezterm.lua"

# Create config directory if it doesn't exist
if (-not (Test-Path $WeztermConfigDir)) {
    New-Item -ItemType Directory -Path $WeztermConfigDir -Force | Out-Null
}

# Read WezTerm config from WSL
$weztermContent = wsl -d $WslDistro -- bash -c "cat /home/$WslUser/.config/wezterm/wezterm.lua" 2>$null

if ($LASTEXITCODE -eq 0 -and $weztermContent) {
    # Backup existing config if not already backed up
    if ((Test-Path $WeztermConfigDest) -and -not (Test-Path "$WeztermConfigDest.backup")) {
        Copy-Item -Path $WeztermConfigDest -Destination "$WeztermConfigDest.backup" -Force
        Write-Host "[INFO] Backed up existing WezTerm config to $WeztermConfigDest.backup" -ForegroundColor Gray
    }

    # Write the config
    $weztermContent | Out-File -FilePath $WeztermConfigDest -Encoding utf8 -Force
    Write-Host "[OK] WezTerm settings applied" -ForegroundColor Green
} else {
    Write-Host "[SKIP] WezTerm settings not found in WSL" -ForegroundColor Yellow
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
