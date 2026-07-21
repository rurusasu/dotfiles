<#
.SYNOPSIS
    Runs the focused Hermes bootstrap through native Windows Docker Desktop.
#>

[CmdletBinding()]
param(
    [string]$ComposeFile = '',
    [string]$DataDir = '',
    [string]$BrowserDataDir = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/Invoke-ExternalCommand.ps1')
. (Join-Path $PSScriptRoot 'lib/HermesBootstrap.ps1')

function New-HermesBootstrapEntrypointResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$ExitCode,
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message
    )

    return [PSCustomObject]@{
        ExitCode = $ExitCode
        Message  = $Message
    }
}

function Get-HermesBootstrapEntrypointPath {
    [CmdletBinding()]
    param(
        [string]$ComposeFile = '',
        [string]$DataDir = '',
        [string]$BrowserDataDir = ''
    )

    $repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $resolvedComposeFile = if ([string]::IsNullOrWhiteSpace($ComposeFile)) {
        Join-Path $repositoryRoot 'docker/hermes-agent/compose.yml'
    }
    else {
        [System.IO.Path]::GetFullPath($ComposeFile)
    }

    $profileRoot = if (-not [string]::IsNullOrWhiteSpace($DataDir)) {
        $DataDir
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:HERMES_DATA_DIR)) {
        $env:HERMES_DATA_DIR
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        Join-Path $env:USERPROFILE '.hermes'
    }
    else {
        $userProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
        if ([string]::IsNullOrWhiteSpace($userProfile)) {
            throw [System.InvalidOperationException]::new('Unable to resolve the current user profile.')
        }
        Join-Path $userProfile '.hermes'
    }
    $resolvedDataDir = [System.IO.Path]::GetFullPath($profileRoot)

    $browserRoot = if (-not [string]::IsNullOrWhiteSpace($BrowserDataDir)) {
        $BrowserDataDir
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:HERMES_BROWSER_DATA_DIR)) {
        $env:HERMES_BROWSER_DATA_DIR
    }
    else {
        Join-Path $resolvedDataDir '.browser'
    }

    return [PSCustomObject]@{
        ComposeFile    = [System.IO.Path]::GetFullPath($resolvedComposeFile)
        DataDir        = $resolvedDataDir
        BrowserDataDir = [System.IO.Path]::GetFullPath($browserRoot)
    }
}

function Get-HermesBootstrapEntrypointExitCode {
    [CmdletBinding()]
    param()

    if ($global:LASTEXITCODE -gt 0) {
        return $global:LASTEXITCODE
    }
    return 1
}

function Invoke-HermesBootstrapDockerPhase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [Parameter(Mandatory)]
        [string]$FailureMessage
    )

    try {
        $global:LASTEXITCODE = 0
        $null = @(Invoke-Docker -Arguments $Arguments 2>$null)
        if ($global:LASTEXITCODE -eq 0) {
            return New-HermesBootstrapEntrypointResult -ExitCode 0 -Message ''
        }
        return New-HermesBootstrapEntrypointResult -ExitCode $global:LASTEXITCODE -Message $FailureMessage
    }
    catch {
        return New-HermesBootstrapEntrypointResult -ExitCode 1 -Message $FailureMessage
    }
}

function Invoke-HermesBootstrapEntrypoint {
    [CmdletBinding()]
    param(
        [string]$ComposeFile = '',
        [string]$DataDir = '',
        [string]$BrowserDataDir = ''
    )

    try {
        $paths = Get-HermesBootstrapEntrypointPath `
            -ComposeFile $ComposeFile `
            -DataDir $DataDir `
            -BrowserDataDir $BrowserDataDir

        if (-not (Test-Path -LiteralPath $paths.ComposeFile -PathType Leaf)) {
            return New-HermesBootstrapEntrypointResult -ExitCode 2 -Message 'Hermes Compose file was not found.'
        }

        foreach ($commandName in @('docker', 'op')) {
            if (-not (Get-Command -Name $commandName -CommandType Application -ErrorAction SilentlyContinue)) {
                return New-HermesBootstrapEntrypointResult `
                    -ExitCode 127 `
                    -Message "Required command is unavailable: $commandName."
            }
        }

        $docker = Invoke-HermesBootstrapDockerPhase `
            -Arguments @('info') `
            -FailureMessage 'Docker Desktop is not ready.'
        if ($docker.ExitCode -ne 0) { return $docker }

        $compose = Invoke-HermesBootstrapDockerPhase `
            -Arguments @('compose', 'version') `
            -FailureMessage 'Docker Compose is unavailable.'
        if ($compose.ExitCode -ne 0) { return $compose }

        foreach ($directory in @($paths.DataDir, (Join-Path $paths.DataDir '.xurl'), $paths.BrowserDataDir)) {
            $null = New-Item -ItemType Directory -Path $directory -Force
        }

        $config = Invoke-HermesBootstrapDockerPhase `
            -Arguments @('compose', '-f', $paths.ComposeFile, 'config', '--quiet') `
            -FailureMessage 'Hermes Compose validation failed.'
        if ($config.ExitCode -ne 0) { return $config }

        $build = Invoke-HermesBootstrapDockerPhase `
            -Arguments @('compose', '-f', $paths.ComposeFile, 'build', 'hermes', 'hermes-bootstrap') `
            -FailureMessage 'Hermes image build failed.'
        if ($build.ExitCode -ne 0) { return $build }

        try {
            $global:LASTEXITCODE = 0
            $bootstrap = Invoke-HermesBootstrap -ComposeFile $paths.ComposeFile -DataDir $paths.DataDir
        }
        catch {
            return New-HermesBootstrapEntrypointResult -ExitCode 1 -Message 'Hermes bootstrap failed.'
        }
        if (-not $bootstrap.Success) {
            $message = if ([string]::IsNullOrWhiteSpace([string]$bootstrap.Message)) {
                'Hermes bootstrap failed.'
            }
            else {
                [string]$bootstrap.Message
            }
            return New-HermesBootstrapEntrypointResult `
                -ExitCode (Get-HermesBootstrapEntrypointExitCode) `
                -Message $message
        }

        $startup = Invoke-HermesBootstrapDockerPhase `
            -Arguments @('compose', '-f', $paths.ComposeFile, 'up', '-d', '--force-recreate') `
            -FailureMessage 'Hermes Compose startup failed.'
        if ($startup.ExitCode -ne 0) { return $startup }

        return New-HermesBootstrapEntrypointResult -ExitCode 0 -Message 'Hermes bootstrap completed.'
    }
    catch {
        return New-HermesBootstrapEntrypointResult -ExitCode 1 -Message 'Hermes bootstrap entrypoint failed.'
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $entrypointResult = Invoke-HermesBootstrapEntrypoint `
        -ComposeFile $ComposeFile `
        -DataDir $DataDir `
        -BrowserDataDir $BrowserDataDir
    if ($entrypointResult.ExitCode -eq 0) {
        [Console]::Out.WriteLine($entrypointResult.Message)
    }
    else {
        [Console]::Error.WriteLine($entrypointResult.Message)
    }
    exit $entrypointResult.ExitCode
}
