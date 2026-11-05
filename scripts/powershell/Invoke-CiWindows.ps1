# Prepare an immutable Windows installation plan and exercise its native adapters.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Prepare', 'Apply', 'Configure', 'Restart', 'Verify')][string]$Phase,
    [Parameter(Mandatory)][string]$ArtifactDirectory,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$TestedSha,
    [ValidateSet('5.1', '7')][string]$PowerShellVersion = '7'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$artifact = [IO.Path]::GetFullPath($ArtifactDirectory)
$archivePath = Join-Path $artifact 'source.zip'
$manifestPath = Join-Path $artifact 'packages.json'
$provenancePath = Join-Path $artifact 'windows-provenance.json'
$source = Join-Path $artifact 'source'

if ($Phase -eq 'Prepare') {
    New-Item -ItemType Directory -Path $artifact -Force | Out-Null
    if (Test-Path -LiteralPath $source) { throw 'Prepare Windows artifacts in a fresh directory.' }
    $head = @(& git -C $repository rev-parse HEAD)
    if ($LASTEXITCODE -ne 0 -or ($head -join '').Trim() -cne $TestedSha) {
        throw 'Windows artifact source does not match the tested SHA.'
    }
    & git -C $repository archive --format=zip --output=$archivePath $TestedSha
    if ($LASTEXITCODE -ne 0) { throw 'Could not archive the tested Windows source.' }
    Expand-Archive -LiteralPath $archivePath -DestinationPath $source -Force
    Copy-Item -LiteralPath (Join-Path $source 'windows/winget/packages.json') -Destination $manifestPath
    $provenance = [ordered]@{
        schemaVersion = 1
        target = 'windows'
        testedSha = $TestedSha
        packagesSha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        sourceSnapshotSha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    [IO.File]::WriteAllText($provenancePath, ($provenance | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    # The transferred payload is the archive plus plan, never this mutable extraction.
    Remove-Item -LiteralPath $source -Recurse -Force
    return
}

$provenance = Get-Content -LiteralPath $provenancePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($provenance.schemaVersion -ne 1 -or $provenance.target -cne 'windows' -or $provenance.testedSha -cne $TestedSha) {
    throw 'Windows artifact provenance does not match this target and tested SHA.'
}
foreach ($entry in @(
        @{ Path = $archivePath; Digest = $provenance.sourceSnapshotSha256 },
        @{ Path = $manifestPath; Digest = $provenance.packagesSha256 }
    )) {
    if ($entry.Digest -cnotmatch '^[0-9a-f]{64}$' -or
        (Get-FileHash -LiteralPath $entry.Path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $entry.Digest) {
        throw "Windows artifact digest mismatch: $($entry.Path)"
    }
}
if ($Phase -eq 'Apply') {
    if (Test-Path -LiteralPath $source) { throw 'Import Windows artifacts into a fresh directory.' }
    Expand-Archive -LiteralPath $archivePath -DestinationPath $source -Force
}
$sourceManifest = Join-Path $source 'windows/winget/packages.json'
if ((Get-FileHash -LiteralPath $sourceManifest -Algorithm SHA256).Hash.ToLowerInvariant() -cne $provenance.packagesSha256) {
    throw 'The extracted Windows installer does not consume the prepared package plan.'
}
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Windows artifact consumers require a native Windows runner.'
}
. (Join-Path $source 'scripts/powershell/lib/Invoke-ExternalCommand.ps1')
Update-ProcessEnvironmentPath

switch ($Phase) {
    'Apply' {
        # Always supervise from 5.1: updating PowerShell 7 can terminate its process.
        $previousWorkspace = $env:GITHUB_WORKSPACE
        $previousRuntime = $env:DOTFILES_E2E_POWERSHELL_VERSION
        try {
            $env:GITHUB_WORKSPACE = $source
            $env:DOTFILES_E2E_POWERSHELL_VERSION = $PowerShellVersion
            Invoke-NativeCommand -Command 'powershell.exe' -Arguments @(
                '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                (Join-Path $PSScriptRoot 'Invoke-CiWindowsInstall.ps1')
            ) | Out-Host
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        }
        finally {
            $env:GITHUB_WORKSPACE = $previousWorkspace
            $env:DOTFILES_E2E_POWERSHELL_VERSION = $previousRuntime
        }
    }
    'Configure' {
        # Task prepares the production NixOS distro before this phase: the real
        # chezmoi WSL keybinding hook deliberately requires it.
        $previousForce = $env:DOTFILES_FORCE_WINDOWS_POWERSHELL
        if ($PowerShellVersion -eq '5.1') { $env:DOTFILES_FORCE_WINDOWS_POWERSHELL = '1' }
        else { Remove-Item Env:\DOTFILES_FORCE_WINDOWS_POWERSHELL -ErrorAction SilentlyContinue }
        Push-Location -LiteralPath $source
        try {
            Invoke-NativeCommand -Command 'cmd.exe' -Arguments @('/d', '/c', 'install.cmd -Phase Chezmoi') | Out-Host
            if ($LASTEXITCODE -ne 0) { throw "Windows settings activation failed (exit=$LASTEXITCODE)." }
        }
        finally {
            Pop-Location
            $env:DOTFILES_FORCE_WINDOWS_POWERSHELL = $previousForce
        }
    }
    'Restart' {
        # GitHub-hosted workers cannot reboot their controlling host and resume
        # this job. Exercise a fresh native shell/session after the WSL cold boot.
        $sessionScript = Join-Path $artifact 'fresh-session.ps1'
        $sessionBody = @'
param([string]$ManagedProfile, [string]$Marker, [int]$ExpectedMajor, [int]$ParentProcessId, [switch]$LoadCompatibilityProfile)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($PID -eq $ParentProcessId -or $PSVersionTable.PSVersion.Major -ne $ExpectedMajor) {
    throw 'Windows restart did not create the requested fresh runtime.'
}
if ($LoadCompatibilityProfile) { . $ManagedProfile }
foreach ($name in @('dotf', 'ls', 'll', 'codex')) {
    if (-not (Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)) {
        throw "Managed PowerShell profile function is missing: $name"
    }
}
if ((Get-Alias grep).Definition -cne 'rg.exe' -or (Get-Alias find).Definition -cne 'fd.exe') {
    throw 'The managed PowerShell aliases were not activated.'
}
[IO.File]::WriteAllText($Marker, ($PSVersionTable.PSVersion.Major.ToString() + ':' + $PID), [Text.UTF8Encoding]::new($false))
'@
        [IO.File]::WriteAllText($sessionScript, $sessionBody, [Text.UTF8Encoding]::new($true))
        # The installed profile belongs to PowerShell 7. Test its normal startup
        # in both installer matrices, then PS5.1 syntax compatibility separately.
        Invoke-NativeCommand -Command 'pwsh.exe' -Arguments @(
            '-NoLogo', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $sessionScript,
            '-ManagedProfile', (Join-Path $env:USERPROFILE 'Documents/PowerShell/Microsoft.PowerShell_profile.ps1'),
            '-Marker', (Join-Path $artifact 'profile-session.txt'), '-ExpectedMajor', 7, '-ParentProcessId', $PID
        ) | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Fresh Windows session failed (exit=$LASTEXITCODE)." }
        if ($PowerShellVersion -eq '5.1') {
            Invoke-NativeCommand -Command 'powershell.exe' -Arguments @(
                '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $sessionScript,
                '-ManagedProfile', (Join-Path $env:USERPROFILE 'Documents/PowerShell/Microsoft.PowerShell_profile.ps1'),
                '-Marker', (Join-Path $artifact 'compatibility-session.txt'), '-ExpectedMajor', 5,
                '-ParentProcessId', $PID, '-LoadCompatibilityProfile'
            ) | Out-Host
            if ($LASTEXITCODE -ne 0) { throw "Windows PowerShell compatibility session failed (exit=$LASTEXITCODE)." }
        }
    }
    'Verify' {
        $major = if ($PowerShellVersion -eq '5.1') { 5 } else { 7 }
        if ($PSVersionTable.PSVersion.Major -ne $major) { throw 'Run Windows verification with the selected PowerShell runtime.' }
        $session = (Get-Content -LiteralPath (Join-Path $artifact 'profile-session.txt') -Raw).Trim()
        if ($session -notmatch '^7:[0-9]+$') { throw 'The fresh Windows profile session was not verified.' }
        if ($PowerShellVersion -eq '5.1' -and
            (Get-Content -LiteralPath (Join-Path $artifact 'compatibility-session.txt') -Raw).Trim() -notmatch '^5:[0-9]+$') {
            throw 'The Windows PowerShell compatibility session was not verified.'
        }
        Update-ProcessEnvironmentPath
        foreach ($command in @('task.exe', 'chezmoi.exe', 'spf.exe', 'rg.exe', 'fd.exe', 'lazygit.exe', 'starship.exe')) {
            Invoke-NativeCommand -Command $command -Arguments @('--version') | Out-Host
            if ($LASTEXITCODE -ne 0) { throw "Installed Windows command failed: $command" }
        }
        foreach ($relative in @(
                'Documents/PowerShell/Microsoft.PowerShell_profile.ps1',
                'AppData/Local/superfile/config.toml', '.config/git/config',
                'AppData/Local/Microsoft/Windows Terminal/Fragments/dotfiles/catppuccin-mocha.json'
            )) {
            if (-not (Test-Path -LiteralPath (Join-Path $env:USERPROFILE $relative) -PathType Leaf)) {
                throw "Windows settings are missing after activation: $relative"
            }
        }
        $managedProfile = Join-Path $env:USERPROFILE 'Documents/PowerShell/Microsoft.PowerShell_profile.ps1'
        $expectedProfile = Join-Path $source 'chezmoi/Documents/PowerShell/Microsoft.PowerShell_profile.ps1'
        if ((Get-FileHash -LiteralPath $managedProfile).Hash -cne (Get-FileHash -LiteralPath $expectedProfile).Hash) {
            throw 'The activated PowerShell profile differs from the prepared source.'
        }
        $fontDirectory = Join-Path $env:LOCALAPPDATA 'Microsoft/Windows/Fonts/UDEV Gothic NF'
        if (@(Get-ChildItem -LiteralPath $fontDirectory -Recurse -Filter '*.ttf' -File).Count -eq 0) {
            throw 'The native Windows font installation did not produce any fonts.'
        }
        $master = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($package in $master.Sources.Packages) {
            Invoke-NativeCommand -Command 'winget' -Arguments @(
                'list', '--id', $package.PackageIdentifier, '--exact', '--accept-source-agreements', '--disable-interactivity'
            ) | Out-Host
            if ($LASTEXITCODE -ne 0) { throw "Windows package is not installed: $($package.PackageIdentifier)" }
        }
        # The upstream WinGet/Store catalog is external. Record actual resolved
        # versions without claiming that the source plan pins those binaries.
        Invoke-NativeCommand -Command 'winget' -Arguments @(
            'export', '--output', (Join-Path $artifact 'installed-packages.json'), '--include-versions', '--accept-source-agreements'
        ) | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'Could not record the resolved Windows package inventory.' }
    }
}
