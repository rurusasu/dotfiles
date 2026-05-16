<#
.SYNOPSIS
    Register a weekly Windows Scheduled Task to compact Docker VHDX

.DESCRIPTION
    Registers a task that runs compact-docker-vhd.ps1 every Sunday at 3:00 AM
    with highest privileges (required for diskpart).

    To unregister: Unregister-ScheduledTask -TaskName "Docker VHDX Compact" -Confirm:$false

.PARAMETER Unregister
    Remove the scheduled task instead of registering it

.EXAMPLE
    .\register-docker-compact-task.ps1
    .\register-docker-compact-task.ps1 -Unregister
#>

[CmdletBinding()]
param(
    [switch]$Unregister
)

$ErrorActionPreference = "Stop"
$taskName = "Docker VHDX Compact"

# Check for admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Administrator privileges required. Relaunching as admin..."
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $MyInvocation.MyCommand.Path)
    if ($Unregister) { $argList += "-Unregister" }
    Start-Process pwsh -Verb RunAs -ArgumentList $argList
    exit 0
}

if ($Unregister) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Scheduled task '$taskName' removed."
    exit 0
}

$scriptPath = Join-Path $PSScriptRoot "compact-docker-vhd.ps1"
if (-not (Test-Path $scriptPath)) {
    Write-Error "compact-docker-vhd.ps1 not found at: $scriptPath"
    exit 1
}

$action = New-ScheduledTaskAction `
    -Execute "pwsh.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Force"

# Run every Sunday at 3:00 AM
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "03:00"

$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable:$false

$principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

$task = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal `
    -Description "Weekly Docker VHDX compaction to reclaim SSD space. Runs compact-docker-vhd.ps1."

Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null
Write-Host "Scheduled task '$taskName' registered."
Write-Host "  Schedule: Every Sunday at 03:00 AM"
Write-Host "  Script:   $scriptPath"
Write-Host ""
Write-Host "To remove: Unregister-ScheduledTask -TaskName '$taskName' -Confirm:`$false"
Write-Host "To run now: Start-ScheduledTask -TaskName '$taskName'"
