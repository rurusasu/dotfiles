# Export Windows settings to dotfiles
# Run this script to update dotfiles with current Windows settings

param(
    [string]$DotfilesPath = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
)

$ErrorActionPreference = "Stop"

Write-Host "Exporting Windows settings to dotfiles..." -ForegroundColor Cyan
Write-Host "Dotfiles path: $DotfilesPath" -ForegroundColor Gray

# Note: Windows Terminal and WezTerm settings are managed by chezmoi
Write-Host "[INFO] Windows Terminal/WezTerm settings are managed by chezmoi" -ForegroundColor Gray
Write-Host "       Source: chezmoi/AppData/Local/Packages/.../LocalState/settings.json" -ForegroundColor Gray
Write-Host "       Source: chezmoi/dot_config/wezterm/wezterm.lua" -ForegroundColor Gray

# Export winget packages
$WingetPackagesDest = Join-Path $DotfilesPath "windows\winget\packages.json"

Write-Host "Exporting winget packages (this may take a while)..." -ForegroundColor Gray
winget export -o $WingetPackagesDest 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Winget packages exported" -ForegroundColor Green
} else {
    Write-Host "[WARN] Some packages could not be exported (this is normal)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Export complete!" -ForegroundColor Green
Write-Host "Don't forget to commit the changes to git." -ForegroundColor Gray
