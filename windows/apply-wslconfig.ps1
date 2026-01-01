[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$source = Join-Path $PSScriptRoot ".wslconfig"
$dest = Join-Path $env:USERPROFILE ".wslconfig"

if (-not (Test-Path -LiteralPath $source)) {
    throw "Source .wslconfig not found: $source"
}

Copy-Item -LiteralPath $source -Destination $dest -Force
Write-Host "Updated $dest"
Write-Host "Apply changes by running: wsl --shutdown"
