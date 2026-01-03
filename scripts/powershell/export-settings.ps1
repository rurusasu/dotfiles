# Export Windows settings to dotfiles
# Run this script to update dotfiles with current Windows settings

param(
    [string]$DotfilesPath = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
)

$ErrorActionPreference = "Stop"

Write-Host "Exporting Windows settings to dotfiles..." -ForegroundColor Cyan
Write-Host "Dotfiles path: $DotfilesPath" -ForegroundColor Gray

# Note: Windows Terminal settings are now managed in Nix
# Edit nix/profiles/home/programs/terminals/windows-terminal/default.nix instead
Write-Host "[INFO] Windows Terminal settings are managed in Nix" -ForegroundColor Gray
Write-Host "       Edit: nix/profiles/home/programs/terminals/windows-terminal/default.nix" -ForegroundColor Gray

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
