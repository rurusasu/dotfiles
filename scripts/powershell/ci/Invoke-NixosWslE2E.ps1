<#
.SYNOPSIS
    Run an isolated NixOS-WSL install and nixos-rebuild switch E2E check.

.DESCRIPTION
    This script is intended for a self-hosted Windows GitHub Actions runner with
    WSL2 enabled. It creates a temporary NixOS-WSL distro, runs the repository
    post-install flow, verifies that nixos-rebuild switch removed the first-run
    welcome banner, and unregisters the temporary distro unless -KeepDistro is set.
#>

[CmdletBinding()]
param(
    [string]$DistroName = "",
    [string]$InstallDir = "",
    [string]$ReleaseTag = "",
    [int]$PostInstallTimeoutSeconds = 5400,
    [switch]$KeepDistro
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$libPath = Join-Path $repoRoot "scripts\powershell\lib"

. (Join-Path $libPath "WindowsEnvironment.ps1")
Repair-WindowsSetupEnvironment
. (Join-Path $libPath "SetupHandler.ps1")
. (Join-Path $libPath "Invoke-ExternalCommand.ps1")
. (Join-Path $repoRoot "scripts\powershell\handlers\Handler.NixOSWSL.ps1")

if ([string]::IsNullOrWhiteSpace($DistroName)) {
    $suffix = if ($env:GITHUB_RUN_ID) {
        "$($env:GITHUB_RUN_ID)-$($env:GITHUB_RUN_ATTEMPT)"
    }
    else {
        [guid]::NewGuid().ToString("N")
    }
    $DistroName = "NixOS-CI-$suffix"
}

if ($DistroName -notmatch '^[A-Za-z0-9_.-]+$') {
    throw "DistroName contains unsupported characters: $DistroName"
}

$tempRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { $env:TEMP }
if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    $InstallDir = Join-Path $tempRoot $DistroName
}

function Write-CiSection {
    param([Parameter(Mandatory)][string]$Title)

    if ($env:GITHUB_ACTIONS -eq "true") {
        Write-Host "::group::$Title"
    }
    else {
        Write-Host ""
        Write-Host "=== $Title ===" -ForegroundColor Cyan
    }
}

function Complete-CiSection {
    if ($env:GITHUB_ACTIONS -eq "true") {
        Write-Host "::endgroup::"
    }
}

function Test-PathUnderRoot {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Roots
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    foreach ($root in $Roots) {
        if ([string]::IsNullOrWhiteSpace($root)) {
            continue
        }
        $fullRoot = [System.IO.Path]::GetFullPath($root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        $rootWithSeparator = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
        if ($fullPath.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
            $fullPath.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Remove-InstallDirectory {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $allowedRoots = @($env:RUNNER_TEMP, $env:TEMP) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if (-not (Test-PathUnderRoot -Path $Path -Roots $allowedRoots)) {
        throw "Refusing to remove InstallDir outside runner temp directories: $Path"
    }

    Remove-Item -LiteralPath $Path -Recurse -Force
}

function Invoke-WslChecked {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [int]$TimeoutSeconds = 600,
        [switch]$AllowFailure
    )

    $output = @(Invoke-Wsl -TimeoutSeconds $TimeoutSeconds -Arguments $Arguments 2>&1)
    $exitCode = $LASTEXITCODE

    foreach ($line in $output) {
        if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
            Write-Host "  $line"
        }
    }

    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "wsl $($Arguments -join ' ') failed with exit code $exitCode"
    }

    return [PSCustomObject]@{
        ExitCode = $exitCode
        Output   = @($output)
    }
}

function Remove-TemporaryDistro {
    param([Parameter(Mandatory)][string]$Name)

    Invoke-WslChecked -Arguments @("--terminate", $Name) -TimeoutSeconds 60 -AllowFailure | Out-Null
    Invoke-WslChecked -Arguments @("--unregister", $Name) -TimeoutSeconds 300 -AllowFailure | Out-Null
}

$installFullPath = [System.IO.Path]::GetFullPath($InstallDir)
if (-not (Test-PathUnderRoot -Path $installFullPath -Roots @($tempRoot))) {
    throw "InstallDir must be under RUNNER_TEMP or TEMP for safe cleanup: $installFullPath"
}

$createdDistro = $false

try {
    Write-CiSection "Preflight"
    try {
        Write-Host "Repository: $repoRoot"
        Write-Host "Distro:     $DistroName"
        Write-Host "InstallDir: $installFullPath"
        Invoke-WslChecked -Arguments @("--version") -TimeoutSeconds 60 | Out-Null
        Invoke-WslChecked -Arguments @("--status") -TimeoutSeconds 60 -AllowFailure | Out-Null
    }
    finally {
        Complete-CiSection
    }

    Write-CiSection "Clean Previous Temporary State"
    try {
        Remove-TemporaryDistro -Name $DistroName
        Remove-InstallDirectory -Path $installFullPath
    }
    finally {
        Complete-CiSection
    }

    Write-CiSection "Install NixOS-WSL"
    try {
        $context = [SetupContext]::new($repoRoot)
        $context.DistroName = $DistroName
        $context.InstallDir = $installFullPath
        $context.Options["ReleaseTag"] = $ReleaseTag
        $context.Options["PostInstallScript"] = Join-Path $repoRoot "scripts\sh\nixos-wsl-postinstall.sh"
        $context.Options["PostInstallTimeoutSeconds"] = $PostInstallTimeoutSeconds
        $context.Options["SyncMode"] = "repo"
        $context.Options["SyncBack"] = "none"

        $handler = [NixOSWSLHandler]::new()
        $createdDistro = $true
        $result = $handler.Apply($context)
        if (-not $result.Success) {
            throw "NixOS-WSL install failed: $($result.Message)"
        }
    }
    finally {
        Complete-CiSection
    }

    Write-CiSection "Verify nixos-rebuild switch"
    try {
        Invoke-WslChecked -Arguments @("--terminate", $DistroName) -TimeoutSeconds 60 -AllowFailure | Out-Null

        $welcomeCheck = Invoke-WslChecked -Arguments @(
            "-d", $DistroName, "--",
            "bash", "-lc", "true"
        ) -TimeoutSeconds 300
        $welcomeText = $welcomeCheck.Output -join [Environment]::NewLine
        if ($welcomeText -match "Welcome to your new NixOS-WSL system") {
            throw "NixOS-WSL first-run welcome is still displayed; nixos-rebuild switch did not fully apply."
        }

        Invoke-WslChecked -Arguments @(
            "-d", $DistroName, "-u", "root", "--",
            "bash", "-lc",
            "test -f /home/nixos/.dotfiles/flake.nix && test -e /run/current-system/sw/bin/nixos-rebuild"
        ) -TimeoutSeconds 300 | Out-Null

        Invoke-WslChecked -Arguments @(
            "-d", $DistroName, "-u", "root", "--",
            "bash", "-lc",
            "nixos-rebuild list-generations | tail -n +2 && readlink -f /run/current-system"
        ) -TimeoutSeconds 300 | Out-Null

        Invoke-WslChecked -Arguments @(
            "-d", $DistroName, "-u", "nixos", "--",
            "bash", "-lc",
            "command -v zsh && command -v chezmoi && command -v task && command -v git"
        ) -TimeoutSeconds 300 | Out-Null
    }
    finally {
        Complete-CiSection
    }
}
finally {
    if ($createdDistro -and -not $KeepDistro) {
        Write-CiSection "Cleanup"
        try {
            Remove-TemporaryDistro -Name $DistroName
            Remove-InstallDirectory -Path $installFullPath
        }
        finally {
            Complete-CiSection
        }
    }
    elseif ($KeepDistro) {
        Write-Host "Keeping temporary distro for debugging: $DistroName"
        Write-Host "InstallDir: $installFullPath"
    }
}
