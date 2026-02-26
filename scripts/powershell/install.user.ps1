<#
.SYNOPSIS
    User-scope setup phase (no elevation).

.DESCRIPTION
    Runs only Winget handler in user scope mode.
#>

[CmdletBinding()]
param(
    [string]$DistroName = "NixOS",
    [string]$InstallDir = "$env:USERPROFILE\NixOS",
    [string]$ReleaseTag = "",
    [string]$PostInstallScript = "",
    [hashtable]$Options = @{},
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

foreach ($key in $Options.Keys) {
    $context.Options[$key] = $Options[$key]
}

$context.Options["UserScopeOnly"] = $true
$context.Options["WingetMode"] = "import"
$context.Options["ReleaseTag"] = $ReleaseTag
$context.Options["PostInstallScript"] = $PostInstallScript
$context.Options["SyncMode"] = $SyncMode
$context.Options["SyncBack"] = $SyncBack

$handlersPath = Join-Path $PSScriptRoot "handlers"
$handlers = Get-SetupHandler -HandlersPath $handlersPath
$handlers = Select-SetupHandler -Handlers $handlers
$handlers = @($handlers | Where-Object { $_.Name -eq "Winget" })

if ($CheckOnly) {
    $canApply = $false
    foreach ($handler in $handlers) {
        try {
            if ($handler.CanApply($context)) {
                $canApply = $true
                break
            }
        }
        catch {
            Write-Warning "[$($handler.Name)] CanApply() check failed: $($_.Exception.Message)"
        }
    }
    return $canApply
}

$results = Invoke-SetupHandler -Handlers $handlers -Context $context
Show-SetupSummary -Results $results

$failedCount = @($results | Where-Object { -not $_.Success }).Count
if ($failedCount -gt 0) {
    throw "User phase failed with $failedCount handler failure(s)."
}
