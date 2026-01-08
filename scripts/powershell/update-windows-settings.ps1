# Apply Windows settings from dotfiles
# Terminal settings are managed by chezmoi; this script handles winget only

[CmdletBinding()]
param(
    [string]$DotfilesPath = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))),
    [switch]$SkipWinget,
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
Write-Host "[INFO] Windows Terminal/WezTerm settings are managed by chezmoi" -ForegroundColor Gray
Write-Host "[INFO] Run: chezmoi apply" -ForegroundColor Gray

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
