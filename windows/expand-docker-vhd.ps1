<#
.SYNOPSIS
    Expand Docker Desktop VHDX to the size specified in docker-vhd-size.conf

.DESCRIPTION
    Docker Desktop on WSL2 uses a VHDX file for storage. This script expands
    the VHDX to the target size if it's currently smaller.

.PARAMETER TargetSizeGB
    Target size in GB. If not specified, reads from docker-vhd-size.conf

.PARAMETER Force
    Skip confirmation prompt

.EXAMPLE
    .\expand-docker-vhd.ps1
    .\expand-docker-vhd.ps1 -TargetSizeGB 128
    .\expand-docker-vhd.ps1 -Force
#>

[CmdletBinding()]
param(
    [int]$TargetSizeGB = 0,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Read target size from config if not specified
if ($TargetSizeGB -eq 0) {
    $configPath = Join-Path $PSScriptRoot "docker-vhd-size.conf"
    if (Test-Path $configPath) {
        $content = Get-Content $configPath | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\d+' }
        if ($content) {
            $TargetSizeGB = [int]($content | Select-Object -First 1)
        }
    }
    if ($TargetSizeGB -eq 0) {
        $TargetSizeGB = 64
        Write-Host "Using default size: ${TargetSizeGB}GB"
    }
}

# Find Docker VHDX
$vhdxPath = Join-Path $env:LOCALAPPDATA "Docker\wsl\disk\docker_data.vhdx"
if (-not (Test-Path $vhdxPath)) {
    # Try alternative location
    $vhdxPath = Join-Path $env:LOCALAPPDATA "Docker\wsl\data\ext4.vhdx"
}

if (-not (Test-Path $vhdxPath)) {
    Write-Warning "Docker VHDX not found. Is Docker Desktop installed?"
    exit 0
}

# Get current size
$currentSizeGB = [math]::Round((Get-Item $vhdxPath).Length / 1GB, 2)
$targetSizeMB = $TargetSizeGB * 1024

Write-Host "Docker VHDX: $vhdxPath"
Write-Host "Current size: ${currentSizeGB}GB"
Write-Host "Target size: ${TargetSizeGB}GB"

if ($currentSizeGB -ge $TargetSizeGB) {
    Write-Host "VHDX is already at or above target size. No expansion needed."
    exit 0
}

if (-not $Force) {
    $confirm = Read-Host "Expand Docker VHDX to ${TargetSizeGB}GB? This requires stopping Docker Desktop. (y/N)"
    if ($confirm -notmatch '^[Yy]') {
        Write-Host "Cancelled."
        exit 0
    }
}

# Stop Docker Desktop
Write-Host "Stopping Docker Desktop..."
$dockerProcesses = @("Docker Desktop", "com.docker.backend", "com.docker.service")
foreach ($proc in $dockerProcesses) {
    Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 3

# Shutdown WSL
Write-Host "Shutting down WSL..."
& wsl --shutdown
Start-Sleep -Seconds 3

# Expand VHDX using diskpart
Write-Host "Expanding VHDX to ${TargetSizeGB}GB..."
$diskpartScript = @"
select vdisk file="$vhdxPath"
expand vdisk maximum=$targetSizeMB
exit
"@

$tempFile = New-TemporaryFile
Set-Content -Path $tempFile -Value $diskpartScript -Encoding ASCII

try {
    $result = & diskpart /s $tempFile.FullName 2>&1
    Write-Host $result
} finally {
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
}

# Verify new size
$newSizeGB = [math]::Round((Get-Item $vhdxPath).Length / 1GB, 2)
Write-Host "New VHDX size: ${newSizeGB}GB"

if ($newSizeGB -ge $TargetSizeGB) {
    Write-Host "VHDX expansion successful!"
    Write-Host ""
    Write-Host "Note: The ext4 filesystem inside will auto-expand when Docker starts."
    Write-Host "Start Docker Desktop to complete the process."
} else {
    Write-Warning "VHDX expansion may not have completed successfully."
}
