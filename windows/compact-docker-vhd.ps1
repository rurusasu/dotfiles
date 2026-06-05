<#
.SYNOPSIS
    Compact Docker Desktop VHDX to reclaim SSD space

.DESCRIPTION
    Docker Desktop on WSL2 never shrinks its VHDX automatically.
    This script prunes unused Docker objects, stops Docker, shuts down WSL,
    compacts the VHDX via diskpart, and restarts Docker Desktop.

    Requires administrator privileges (diskpart needs elevation).

.PARAMETER SkipPrune
    Skip docker system prune before compaction

.PARAMETER SkipRestart
    Do not restart Docker Desktop after compaction

.PARAMETER ThresholdGB
    Only compact if physical VHDX file size exceeds this value (default: 50)

.PARAMETER Force
    Skip confirmation prompt

.EXAMPLE
    .\compact-docker-vhd.ps1
    .\compact-docker-vhd.ps1 -Force -SkipPrune
    .\compact-docker-vhd.ps1 -ThresholdGB 30
#>

[CmdletBinding()]
param(
    [switch]$SkipPrune,
    [switch]$SkipRestart,
    [int]$ThresholdGB = 50,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Check for admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Administrator privileges required. Relaunching as admin..."
    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $MyInvocation.MyCommand.Path)
    if ($SkipPrune) { $args += "-SkipPrune" }
    if ($SkipRestart) { $args += "-SkipRestart" }
    if ($Force) { $args += "-Force" }
    $args += "-ThresholdGB", $ThresholdGB
    Start-Process pwsh -Verb RunAs -ArgumentList $args
    exit 0
}

# Find Docker VHDX
$vhdxPath = Join-Path $env:LOCALAPPDATA "Docker\wsl\disk\docker_data.vhdx"
if (-not (Test-Path $vhdxPath)) {
    $vhdxPath = Join-Path $env:LOCALAPPDATA "Docker\wsl\data\ext4.vhdx"
}
if (-not (Test-Path $vhdxPath)) {
    Write-Warning "Docker VHDX not found. Is Docker Desktop installed?"
    exit 0
}

$physicalSizeGB = [math]::Round((Get-Item $vhdxPath).Length / 1GB, 2)
Write-Host "Docker VHDX: $vhdxPath"
Write-Host "Physical size: ${physicalSizeGB}GB"

if ($physicalSizeGB -lt $ThresholdGB) {
    Write-Host "Physical size ${physicalSizeGB}GB is below threshold ${ThresholdGB}GB. No compaction needed."
    exit 0
}

if (-not $Force) {
    $confirm = Read-Host "Compact Docker VHDX (${physicalSizeGB}GB)? Docker Desktop will be stopped temporarily. (y/N)"
    if ($confirm -notmatch '^[Yy]') {
        Write-Host "Cancelled."
        exit 0
    }
}

# Step 1: prune inside Docker while it's still running
if (-not $SkipPrune) {
    $dockerRunning = $null
    try {
        $dockerRunning = & docker info --format "{{.ServerVersion}}" 2>$null
    }
    catch {}

    if ($dockerRunning) {
        Write-Host "`nStep 1/4: Pruning unused Docker objects..."
        & docker system prune -a --force
        Write-Host "Prune complete."
    }
    else {
        Write-Host "`nStep 1/4: Docker not running, skipping prune."
    }
}
else {
    Write-Host "`nStep 1/4: Skipping prune (-SkipPrune)."
}

# Step 2: stop Docker Desktop
Write-Host "`nStep 2/4: Stopping Docker Desktop..."
$dockerProcesses = @(
    "Docker Desktop",
    "com.docker.backend",
    "com.docker.build",
    "com.docker.dev-envs",
    "com.docker.extensions",
    "com.docker.proxy",
    "com.docker.service"
)
foreach ($proc in $dockerProcesses) {
    Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 3
foreach ($proc in $dockerProcesses) {
    if (Get-Process -Name $proc -ErrorAction SilentlyContinue) {
        Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
    }
}
Start-Sleep -Seconds 2

# Step 3: shutdown WSL
Write-Host "`nStep 3/4: Shutting down WSL..."
& wsl --shutdown
Start-Sleep -Seconds 3

# Step 4: compact via diskpart
Write-Host "`nStep 4/4: Compacting VHDX..."
$diskpartScript = @"
select vdisk file="$vhdxPath"
compact vdisk
exit
"@
$tempFile = [System.IO.Path]::GetTempFileName() + ".txt"
Set-Content -Path $tempFile -Value $diskpartScript -Encoding ASCII
try {
    $result = & diskpart /s $tempFile 2>&1
    Write-Host $result
}
finally {
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
}

$newSizeGB = [math]::Round((Get-Item $vhdxPath).Length / 1GB, 2)
$savedGB = [math]::Round($physicalSizeGB - $newSizeGB, 2)
Write-Host "`nBefore: ${physicalSizeGB}GB  →  After: ${newSizeGB}GB  (saved: ${savedGB}GB)"

# Restart Docker Desktop
if (-not $SkipRestart) {
    Write-Host "`nRestarting Docker Desktop..."
    $dockerExe = Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe"
    if (Test-Path $dockerExe) {
        Start-Process -FilePath $dockerExe
        Write-Host "Docker Desktop started."
    }
    else {
        Write-Host "Docker Desktop executable not found. Please start manually."
    }
}
else {
    Write-Host "`nDocker Desktop not restarted (-SkipRestart). Start it manually when ready."
}

Write-Host "`nDone."
