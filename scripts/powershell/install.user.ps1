<#
.SYNOPSIS
    Install the selected Windows GUI applications through WinGet only.
#>
[CmdletBinding()]
param(
    [hashtable]$Options = @{},
    [switch]$CheckOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$libPath = Join-Path $PSScriptRoot "lib"
. (Join-Path $libPath "WindowsEnvironment.ps1")
Repair-WindowsSetupEnvironment
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
. (Join-Path $libPath "SetupHandler.ps1")
. (Join-Path $libPath "Invoke-ExternalCommand.ps1")
Update-ProcessEnvironmentPath -ReportStatus -ProcessOnly

$context = [SetupContext]::new($repoRoot)
foreach ($key in $Options.Keys) {
    $context.Options[$key] = $Options[$key]
}
$context.Options["WingetMode"] = "import"
$context.Options["SkipRetiredPackageCleanup"] = $true

# Do not discover or load CLI/bootstrap/WSL handlers, even when those tools
# already exist on PATH. Their standalone implementations are not this profile.
. (Join-Path $PSScriptRoot "handlers/Handler.Winget.ps1")
$handler = [WingetHandler]::new()
$available = $handler.CanApply($context)
if ($CheckOnly) {
    return [bool]$available
}
if (-not $available) {
    throw "WinGet is not available. Update App Installer from Microsoft Store."
}

$results = @($handler.Apply($context))
Show-SetupSummary -Results $results
$failedCount = @($results | Where-Object { -not $_.Success }).Count
if ($failedCount -gt 0) {
    throw "GUI setup failed with $failedCount handler failure(s)."
}
