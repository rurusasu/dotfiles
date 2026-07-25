<#
.SYNOPSIS
    Runs Hermes X API MCP lifecycle commands through native Windows Docker.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('auth', 'restart', 'up')]
    [string]$Action,
    [string]$ComposeFile = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/Invoke-ExternalCommand.ps1')
. (Join-Path $PSScriptRoot 'lib/HermesXApi.ps1')

function Get-HermesXApiComposeFile {
    [CmdletBinding()]
    param([string]$ComposeFile = '')

    if (-not [string]::IsNullOrWhiteSpace($ComposeFile)) {
        return [System.IO.Path]::GetFullPath($ComposeFile)
    }
    if (-not [string]::IsNullOrWhiteSpace($env:HERMES_COMPOSE_FILE)) {
        return [System.IO.Path]::GetFullPath($env:HERMES_COMPOSE_FILE)
    }

    $repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    return [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot 'docker/hermes-agent/compose.yml'))
}

function Get-HermesXApiDataDir {
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace($env:HERMES_DATA_DIR)) {
        return [System.IO.Path]::GetFullPath($env:HERMES_DATA_DIR)
    }
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        return [System.IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.hermes'))
    }
    if (-not [string]::IsNullOrWhiteSpace($env:HOME)) {
        return [System.IO.Path]::GetFullPath((Join-Path $env:HOME '.hermes'))
    }

    $userProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    if ([string]::IsNullOrWhiteSpace($userProfile)) {
        throw [System.InvalidOperationException]::new('Unable to resolve the current user profile.')
    }
    return [System.IO.Path]::GetFullPath((Join-Path $userProfile '.hermes'))
}

function Initialize-HermesXApiRuntimeHome {
    [CmdletBinding()]
    param()

    $dataDir = Get-HermesXApiDataDir
    foreach ($directory in @($dataDir, (Join-Path $dataDir '.xurl'))) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }
}

function Invoke-HermesXApiDocker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $global:LASTEXITCODE = 0
    Invoke-Docker -Arguments $Arguments | Out-Host
    return $global:LASTEXITCODE
}

try {
    $resolvedComposeFile = Get-HermesXApiComposeFile -ComposeFile $ComposeFile
    Initialize-HermesXApiRuntimeHome

    $exitCode = Invoke-HermesXApiCredentialScope -Action {
        switch ($Action) {
            'auth' {
                Invoke-HermesXApiDocker -Arguments @(
                    'compose', '-f', $resolvedComposeFile,
                    'run', '--rm', '--no-deps', '--entrypoint', '/bin/sh', 'xapi-mcp',
                    '-lc', 'CLIENT_ID="$X_API_CLIENT_ID" CLIENT_SECRET="$X_API_CLIENT_SECRET" node_modules/.bin/xurl auth oauth2 --headless'
                )
            }
            'restart' {
                Invoke-HermesXApiDocker -Arguments @(
                    'compose', '-f', $resolvedComposeFile,
                    'up', '-d', '--force-recreate', 'xapi-mcp'
                )
            }
            'up' {
                Invoke-HermesXApiDocker -Arguments @(
                    'compose', '-f', $resolvedComposeFile,
                    'up', '-d', '--force-recreate'
                )
            }
        }
    }
    exit $exitCode
}
catch {
    [Console]::Error.WriteLine('Hermes X API lifecycle command failed.')
    exit 1
}
