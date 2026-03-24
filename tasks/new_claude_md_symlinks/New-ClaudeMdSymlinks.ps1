<#
.SYNOPSIS
    Creates CLAUDE.md symlinks pointing to AGENTS.md in all directories.

.DESCRIPTION
    Finds all AGENTS.md files in the repository and creates corresponding
    CLAUDE.md symlinks. Skips directories where CLAUDE.md already exists
    as a regular file (e.g., chezmoi/dot_claude/CLAUDE.md).

.PARAMETER DryRun
    Shows what would be done without actually creating symlinks.

.EXAMPLE
    .\New-ClaudeMdSymlinks.ps1
    .\New-ClaudeMdSymlinks.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Get repository root
$repoRoot = git rev-parse --show-toplevel 2>$null
if (-not $repoRoot) {
    $repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}

Write-Host "Repository root: $repoRoot" -ForegroundColor Cyan

# Find all AGENTS.md files
$agentsFiles = Get-ChildItem -Path $repoRoot -Filter "AGENTS.md" -Recurse -File

$created = 0
$skipped = 0
$errors = 0

foreach ($agentsFile in $agentsFiles) {
    $dir = $agentsFile.DirectoryName
    $claudeMd = Join-Path $dir "CLAUDE.md"

    # Check if CLAUDE.md already exists
    if (Test-Path $claudeMd) {
        $item = Get-Item $claudeMd -Force
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            # It's a symlink, remove and recreate
            if (-not $DryRun) {
                Remove-Item $claudeMd -Force
            }
            Write-Host "  Replacing existing symlink: $claudeMd" -ForegroundColor Yellow
        }
        else {
            # It's a regular file, skip
            Write-Host "  Skipping (regular file exists): $claudeMd" -ForegroundColor DarkGray
            $skipped++
            continue
        }
    }

    # Create symlink
    $relativePath = "AGENTS.md"
    if ($DryRun) {
        Write-Host "  Would create: $claudeMd -> $relativePath" -ForegroundColor Green
        $created++
    }
    else {
        try {
            New-Item -ItemType SymbolicLink -Path $claudeMd -Target $relativePath -Force | Out-Null
            Write-Host "  Created: $claudeMd -> $relativePath" -ForegroundColor Green
            $created++
        }
        catch {
            Write-Host "  Failed: $claudeMd - $($_.Exception.Message)" -ForegroundColor Red
            $errors++
        }
    }
}

Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Created: $created"
Write-Host "  Skipped: $skipped"
Write-Host "  Errors:  $errors"

if ($errors -gt 0 -and -not $DryRun) {
    Write-Host ""
    Write-Host "Some symlinks failed to create. Try one of:" -ForegroundColor Yellow
    Write-Host "  1. Enable Developer Mode in Windows Settings" -ForegroundColor Yellow
    Write-Host "  2. Run this script as Administrator" -ForegroundColor Yellow
    exit 1
}
