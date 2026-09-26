[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ManifestPath,

    [ValidateNotNullOrEmpty()]
    [string[]]$PackageId = @(
        'junegunn.fzf', 'x-motemen.ghq', 'jqlang.jq',
        'JesseDuffield.lazygit', 'LuaLS.lua-language-server'
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/SetupHandler.ps1')
. (Join-Path $PSScriptRoot '../lib/Invoke-ExternalCommand.ps1')
. (Join-Path $PSScriptRoot '../handlers/Handler.Winget.ps1')

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$handler = [WingetHandler]::new()
$originalPath = $env:PATH
$verified = 0
try {
    foreach ($id in @($PackageId | Select-Object -Unique)) {
        $entries = @($manifest.Sources.Packages | Where-Object { $_.PackageIdentifier -eq $id })
        if ($entries.Count -ne 1 -or -not $entries[0].PSObject.Properties['verifyCommand']) {
            throw "Required recovery package is missing or has no verification: $id"
        }
        $entry = $entries[0]
        $pkg = [PSCustomObject]@{
            Id            = $id
            VerifyCommand = $entry.verifyCommand
            PathEntries   = if ($entry.PSObject.Properties['pathEntries']) { @($entry.pathEntries) } else { @() }
        }

        # Exclude WinGet Links and all preinstalled runner tools. Each command
        # must resolve from its own installed package, not an unrelated binary.
        $env:PATH = "$PSHOME;$env:SystemRoot\System32"
        $packageDirectory = $handler.FindPortableCommandDirectory($pkg)
        if (-not $packageDirectory) { throw "Required installed package executable is missing or ambiguous: $id" }
        $handler.EnsureProcessPathEntries($pkg)
        $resolved = Get-Command -Name $entry.verifyCommand.command -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $resolved -or (Split-Path -Parent $resolved.Source) -ne $packageDirectory) {
            throw "Package command did not resolve from its own directory: $id"
        }
        if (-not $handler.TestPackageVerification($pkg.VerifyCommand)) {
            throw "Package command recovery verification failed: $id"
        }
        $verified++
        Write-Host "Recovered and verified $id from $($resolved.Source)"
    }
    if ($verified -eq 0) { throw 'No package command recovery checks ran.' }
    Write-Host "Portable command recovery: $verified package(s) passed without inherited package PATH entries."
}
finally {
    $env:PATH = $originalPath
}
