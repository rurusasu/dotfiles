<#
.SYNOPSIS
    Windows platform adapter for the installer phases ordered by Taskfile.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Gui', 'Wsl', 'WslBase')][string]$Phase)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$libPath = Join-Path $PSScriptRoot 'lib'
. (Join-Path $libPath 'WindowsEnvironment.ps1')
Repair-WindowsSetupEnvironment
$repository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$options = @{}
$configuration = $null
if ($env:DOTFILES_INSTALL_CONFIGURATION) {
    $configuration = $env:DOTFILES_INSTALL_CONFIGURATION | ConvertFrom-Json
    foreach ($property in $configuration.Options.PSObject.Properties) { $options[$property.Name] = $property.Value }
}

if ($Phase -eq 'Gui') {
    & (Join-Path $PSScriptRoot 'install.user.ps1') -Options $options
    return
}

. (Join-Path $libPath 'SetupHandler.ps1')
. (Join-Path $libPath 'Invoke-ExternalCommand.ps1')
$context = [SetupContext]::new($repository)
$context.Options = $options
if ($configuration) {
    $context.DistroName = $configuration.DistroName
    if ($configuration.InstallDir) { $context.InstallDir = $configuration.InstallDir }
}

. (Join-Path $PSScriptRoot 'handlers/Handler.WslInstall.ps1')
$foundation = [WslInstallHandler]::new()
if ($Phase -eq 'WslBase') {
    $result = $foundation.Apply($context)
    Show-SetupSummary -Results @($result)
    if (-not $result.Success) { throw $result.Message }
    exit 3010
}

if ($foundation.CanApply($context)) {
    $exitCode = Invoke-WslBaseElevation -ScriptPath $PSCommandPath
    if ($exitCode -eq 3010) {
        if ($configuration -and $configuration.PSObject.Properties['ResultPath']) {
            Set-Content -LiteralPath $configuration.ResultPath -Value 'RestartRequired' -Encoding Ascii
        }
        Write-Host 'WSL foundation enabled. Restart Windows and run install.cmd again.' -ForegroundColor Yellow
        return
    }
    throw "WSL foundation setup failed or was cancelled (exit=$exitCode)."
}

# Registration is per-user. Only the foundation above may run under UAC.
. (Join-Path $PSScriptRoot 'handlers/Handler.NixOSWSL.ps1')
$installer = [NixOSWSLHandler]::new()
if ($installer.DistroExists($context.DistroName)) {
    Invoke-NixosWslSetup -Context $context
    $installer.EnsurePostInstallIntegration($context.DistroName)
}
else {
    # Apply already invokes Invoke-NixosWslSetup; do not rebuild twice on first install.
    $result = $installer.Apply($context)
    Show-SetupSummary -Results @($result)
    if (-not $result.Success) { throw $result.Message }
}
