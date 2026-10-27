<# Run one Windows operation, or import the master and continue through Task. #>
[CmdletBinding()]
param(
    [ValidateSet('Winget', 'Wsl', 'Chezmoi')][string]$Phase = 'Winget',
    [string]$DistroName = 'NixOS',
    [string]$InstallDir = '',
    [string]$ReleaseTag = '',
    [ValidateSet('link', 'repo', 'nix', 'none')][string]$SyncMode = 'link',
    [ValidateSet('repo', 'lock', 'none')][string]$SyncBack = 'lock',
    [switch]$ForcePostInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot 'lib/Invoke-ExternalCommand.ps1')
$repository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path

if ($Phase -eq 'Chezmoi') {
    $source = Join-Path $repository 'chezmoi'
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw "chezmoi source is missing: $source" }
    $runtime = Join-Path $env:LOCALAPPDATA 'chezmoi'
    New-Item -ItemType Directory -Path $runtime -Force | Out-Null
    Invoke-NativeCommand -Command 'chezmoi' -Arguments @(
        '--persistent-state', (Join-Path $runtime 'chezmoistate.boltdb'), '--cache', (Join-Path $runtime 'cache'),
        '--no-tty', '--no-pager', 'init', '--apply', '--force', '--source', $source, '-v'
    )
    if ($LASTEXITCODE -ne 0) { throw "chezmoi init --apply failed (exit=$LASTEXITCODE)." }
    return
}

$settings = @{
    DistroName = $DistroName; InstallDir = $(if ($InstallDir) { $InstallDir } else { Join-Path $env:USERPROFILE 'NixOS' }); ReleaseTag = $ReleaseTag
    SyncMode = $SyncMode; SyncBack = $SyncBack; ForcePostInstall = [bool]$ForcePostInstall
}
if ($env:DOTFILES_INSTALL_CONFIGURATION) {
    $inherited = $env:DOTFILES_INSTALL_CONFIGURATION | ConvertFrom-Json
    foreach ($property in $inherited.PSObject.Properties) {
        if ($settings.ContainsKey($property.Name) -and -not $PSBoundParameters.ContainsKey($property.Name)) {
            $settings[$property.Name] = $property.Value
        }
    }
}

if ($Phase -eq 'Wsl') {
    if (-not (Test-WslAvailable)) {
        $systemDirectory = if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { 'Sysnative' } else { 'System32' }
        $wsl = Join-Path (Join-Path $env:SystemRoot $systemDirectory) 'wsl.exe'
        [ValidateRange(0, 2147483)][int]$timeoutSeconds = Get-PackageInstallTimeoutSecond
        $process = Start-Process -FilePath $wsl -ArgumentList @('--install', '--no-distribution') -Verb RunAs -WindowStyle Hidden -PassThru
        try {
            if ($timeoutSeconds -gt 0) {
                if (-not $process.WaitForExit($timeoutSeconds * 1000)) {
                    throw 'Timed out waiting for WSL installation; the Windows operation may still be running.'
                }
            }
            else { [void]$process.WaitForExit() }
            if ($process.ExitCode -notin @(0, 3010, 1641)) { throw "WSL installation failed (exit=$($process.ExitCode))." }
        }
        finally { $process.Dispose() }
        Write-Host 'Restart Windows, then run install.cmd again.' -ForegroundColor Yellow
        exit 3010
    }
    . (Join-Path $PSScriptRoot 'lib/Invoke-NixosWslSetup.ps1')
    Install-NixosWsl -DistroName $settings.DistroName -InstallDir $settings.InstallDir -ReleaseTag $settings.ReleaseTag
    Invoke-NixosWslSetup -Repository $repository -DistroName $settings.DistroName -SyncMode $settings.SyncMode -SyncBack $settings.SyncBack -ForcePostInstall:([bool]$settings.ForcePostInstall)
    return
}

Update-ProcessEnvironmentPath
Import-WindowsPackage -ManifestPath (Join-Path $repository 'windows/winget/packages.json')
if ($PSBoundParameters.ContainsKey('Phase')) { return }
$task = Get-Command task -CommandType Application -ErrorAction Stop | Select-Object -First 1
$previousConfiguration = $env:DOTFILES_INSTALL_CONFIGURATION
$previousShell = $env:DOTFILES_INSTALL_POWERSHELL
try {
    $env:DOTFILES_INSTALL_CONFIGURATION = $settings | ConvertTo-Json -Compress
    $env:DOTFILES_INSTALL_POWERSHELL = (Get-Process -Id $PID).Path.Replace('\', '/')
    Invoke-NativeCommand -Command $task.Source -Arguments @('--dir', $repository, '--exit-code', 'install', 'INSTALL_STAGE=apply') | Out-Host
    if ($LASTEXITCODE -in @(3010, 194)) { exit 3010 }
    exit $LASTEXITCODE
}
finally {
    $env:DOTFILES_INSTALL_CONFIGURATION = $previousConfiguration
    $env:DOTFILES_INSTALL_POWERSHELL = $previousShell
}
