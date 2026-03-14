<#
.SYNOPSIS
    Admin/non-winget setup phase.

.DESCRIPTION
    Runs all handlers except Winget.
    -CheckOnly returns true when any admin-required handler can apply.
#>

[CmdletBinding()]
param(
    [string]$DistroName = "NixOS",
    [string]$InstallDir = "$env:USERPROFILE\NixOS",
    [string]$ReleaseTag = "",
    [string]$PostInstallScript = "",
    [hashtable]$Options = @{},
    [string]$OptionsJson = "",
    [ValidateSet("link", "repo", "nix", "none")]
    [string]$SyncMode = "link",
    [ValidateSet("repo", "lock", "none")]
    [string]$SyncBack = "lock",
    [switch]$CheckOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

function Test-IsAdminCurrent {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Merge-Options {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [hashtable]$BaseOptions,
        [string]$JsonOptions
    )

    $merged = @{}
    if ($null -ne $BaseOptions) {
        foreach ($key in $BaseOptions.Keys) {
            $merged[$key] = $BaseOptions[$key]
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($JsonOptions)) {
        $parsed = ConvertFrom-Json -InputObject $JsonOptions
        if ($null -ne $parsed) {
            foreach ($prop in $parsed.PSObject.Properties) {
                $merged[$prop.Name] = $prop.Value
            }
        }
    }

    return $merged
}

$effectiveOptions = Merge-Options -BaseOptions $Options -JsonOptions $OptionsJson

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$libPath = Join-Path $PSScriptRoot "lib"
. (Join-Path $libPath "SetupHandler.ps1")
. (Join-Path $libPath "Invoke-ExternalCommand.ps1")

if (-not $PSBoundParameters.ContainsKey("PostInstallScript")) {
    $PostInstallScript = Join-Path $repoRoot "scripts\sh\nixos-wsl-postinstall.sh"
}

$context = [SetupContext]::new($repoRoot)
$context.DistroName = $DistroName
$context.InstallDir = $InstallDir

foreach ($key in $effectiveOptions.Keys) {
    $context.Options[$key] = $effectiveOptions[$key]
}

$context.Options["ReleaseTag"] = $ReleaseTag
$context.Options["PostInstallScript"] = $PostInstallScript
$context.Options["SyncMode"] = $SyncMode
$context.Options["SyncBack"] = $SyncBack

$handlersPath = Join-Path $PSScriptRoot "handlers"
$handlers = Get-SetupHandler -HandlersPath $handlersPath
$handlers = Select-SetupHandler -Handlers $handlers
$handlers = @($handlers | Where-Object { $_.Name -notin @("Winget", "OpenClaw") })

$adminApplicableCount = 0
foreach ($handler in $handlers) {
    if (-not $handler.RequiresAdmin) {
        continue
    }

    try {
        if ($handler.CanApply($context)) {
            $adminApplicableCount++
        }
    }
    catch {
        Write-Warning "[$($handler.Name)] CanApply() check failed: $($_.Exception.Message)"
    }
}

if ($CheckOnly) {
    return ($adminApplicableCount -gt 0)
}

$results = Invoke-SetupHandler -Handlers $handlers -Context $context

if ($adminApplicableCount -gt 0 -and (Test-IsAdminCurrent)) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Phase 2: Final Processing" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    if ($effectiveOptions["SkipSetDefaultDistro"] -ne $true) {
        Write-Host "Setting default distro: $DistroName"
        & wsl --set-default $DistroName
    }

    $expandDockerVhd = Join-Path $repoRoot "windows\expand-docker-vhd.ps1"
    if (Test-Path -LiteralPath $expandDockerVhd) {
        Write-Host "Expanding Docker Desktop VHDX..."
        & $expandDockerVhd -Force
    }
}

Show-SetupSummary -Results $results

$failedCount = @($results | Where-Object { -not $_.Success }).Count
if ($failedCount -gt 0) {
    throw "Admin phase failed with $failedCount handler failure(s)."
}
