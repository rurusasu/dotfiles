<#!
.SYNOPSIS
    Runs the complete Hermes Hindsight live acceptance lifecycle on Windows.
#>

[CmdletBinding()]
param(
    [string]$ComposeFile = '',
    [string]$DataDir = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/Invoke-ExternalCommand.ps1')
. (Join-Path $PSScriptRoot 'lib/HermesHindsight.ps1')

function Get-HermesHindsightVerifyPath {
    [CmdletBinding()]
    param(
        [string]$ComposeFile = '',
        [string]$DataDir = ''
    )

    $repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $resolvedComposeFile = if (-not [string]::IsNullOrWhiteSpace($ComposeFile)) {
        [System.IO.Path]::GetFullPath($ComposeFile)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:HERMES_COMPOSE_FILE)) {
        [System.IO.Path]::GetFullPath($env:HERMES_COMPOSE_FILE)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot 'docker/hermes-agent/compose.yml'))
    }

    $resolvedDataDir = if (-not [string]::IsNullOrWhiteSpace($DataDir)) {
        [System.IO.Path]::GetFullPath($DataDir)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:HERMES_DATA_DIR)) {
        [System.IO.Path]::GetFullPath($env:HERMES_DATA_DIR)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        [System.IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.hermes'))
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:HOME)) {
        [System.IO.Path]::GetFullPath((Join-Path $env:HOME '.hermes'))
    }
    else {
        throw [System.InvalidOperationException]::new('Unable to resolve the Hermes data directory.')
    }

    return [PSCustomObject]@{
        ComposeFile = $resolvedComposeFile
        DataDir     = $resolvedDataDir
    }
}

function Invoke-HermesHindsightVerifyDocker {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Arguments)

    $global:LASTEXITCODE = 0
    $output = @(Invoke-Docker -Arguments $Arguments)
    $exitCode = $global:LASTEXITCODE
    if ($exitCode -ne 0) {
        throw [System.InvalidOperationException]::new(
            "Docker command failed with exit code $exitCode`: docker $($Arguments -join ' ')"
        )
    }
    return $output
}

function Invoke-HermesHindsightVerify {
    [CmdletBinding()]
    param(
        [string]$ComposeFile = '',
        [string]$DataDir = ''
    )

    $paths = Get-HermesHindsightVerifyPath -ComposeFile $ComposeFile -DataDir $DataDir
    if (-not (Test-Path -LiteralPath $paths.ComposeFile -PathType Leaf)) {
        throw [System.IO.FileNotFoundException]::new('Hermes Compose file was not found.')
    }

    $compose = @('compose', '-f', $paths.ComposeFile)
    $apiUrl = 'http://hindsight:8888'
    $ollamaUrl = 'http://host.docker.internal:11434'
    $stateFile = '/opt/data/hindsight/acceptance-state.json'
    $evidenceFile = '/opt/data/hindsight/acceptance.json'
    $profiles = 'default,rick,hoffman,risarisa,nancy,kuroda,shiraishi'

    $null = Invoke-HermesHindsightVerifyDocker -Arguments ($compose + @('config', '--quiet'))

    $null = Initialize-HermesHindsightHost `
        -ComposeFile $paths.ComposeFile `
        -DataDir $paths.DataDir

    $null = Invoke-HermesHindsightVerifyDocker -Arguments ($compose + @('up', '-d', 'hindsight'))
    Wait-HermesHindsightApi

    $null = Invoke-HermesHindsightVerifyDocker -Arguments ($compose + @(
            'exec', '-T', 'hermes',
            'hermes-hindsight-acceptance', 'probe',
            '--api-url', $apiUrl,
            '--ollama-url', $ollamaUrl,
            '--strict-probes', '20',
            '--timeout', '300',
            '--evidence', $evidenceFile
        ))

    $null = Invoke-HermesHindsightVerifyDocker -Arguments ($compose + @(
            'exec', '-T', 'hermes',
            'hermes-hindsight-acceptance', 'seed',
            '--api-url', $apiUrl,
            '--profiles', $profiles,
            '--timeout', '300',
            '--state', $stateFile
        ))

    $null = Invoke-HermesHindsightVerifyDocker -Arguments ($compose + @('restart', 'hindsight'))
    Wait-HermesHindsightApi

    $null = Invoke-HermesHindsightVerifyDocker -Arguments ($compose + @(
            'exec', '-T', 'hermes',
            'hermes-hindsight-acceptance', 'verify',
            '--api-url', $apiUrl,
            '--timeout', '300',
            '--state', $stateFile,
            '--evidence', $evidenceFile
        ))

    $hindsightStopped = $false
    try {
        $null = Invoke-HermesHindsightVerifyDocker -Arguments ($compose + @('stop', 'hindsight'))
        $hindsightStopped = $true

        $null = Invoke-HermesHindsightVerifyDocker -Arguments ($compose + @(
                'exec', '-T', 'hermes',
                'hermes-hindsight-acceptance', 'degraded',
                '--api-url', $apiUrl,
                '--timeout', '5',
                '--state', $stateFile,
                '--evidence', $evidenceFile
            ))

        $aliveOutput = @(Invoke-HermesHindsightVerifyDocker -Arguments ($compose + @(
                    'exec', '-T', 'hermes',
                    'hermes', 'chat', '--quiet', '-q',
                    'Reply with exactly HERMES_ALIVE and nothing else.'
                )))
        $nonEmptyLines = @(
            $aliveOutput |
                ForEach-Object { [string]$_ } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
        $finalResponse = if ($nonEmptyLines.Count -gt 0) {
            $nonEmptyLines[-1]
        }
        else {
            ''
        }
        if ($finalResponse -cne 'HERMES_ALIVE') {
            throw [System.InvalidOperationException]::new(
                "Hermes degraded one-shot must end with exact HERMES_ALIVE; got: $finalResponse"
            )
        }

        $hermesPort = if ([string]::IsNullOrWhiteSpace($env:HERMES_API_PORT)) {
            8642
        }
        else {
            $parsedPort = 0
            if (-not [int]::TryParse($env:HERMES_API_PORT, [ref]$parsedPort) -or
                $parsedPort -lt 1 -or $parsedPort -gt 65535) {
                throw [System.InvalidOperationException]::new(
                    'HERMES_API_PORT must be a positive integer between 1 and 65535.'
                )
            }
            $parsedPort
        }
        $null = Invoke-HermesHindsightCommand `
            -Command 'curl' `
            -Arguments @(
            '--fail', '--silent', '--show-error', '--max-time', '5',
            "http://127.0.0.1:$hermesPort/health"
        ) `
            -TimeoutSeconds 5

        $null = Invoke-HermesHindsightVerifyDocker -Arguments ($compose + @('start', 'hindsight'))
        Wait-HermesHindsightApi
        $hindsightStopped = $false
    }
    finally {
        if ($hindsightStopped) {
            try {
                $null = Invoke-HermesHindsightVerifyDocker -Arguments ($compose + @('start', 'hindsight'))
                Wait-HermesHindsightApi
            }
            catch {
                Write-Warning "Hindsight restart failed during failure recovery: $($_.Exception.Message)"
            }
        }
    }

    $null = Invoke-HermesHindsightVerifyDocker -Arguments ($compose + @(
            'exec', '-T', 'hermes',
            'hermes-hindsight-acceptance', 'recovery',
            '--api-url', $apiUrl,
            '--timeout', '300',
            '--state', $stateFile,
            '--evidence', $evidenceFile
        ))

    $null = Invoke-HermesHindsightVerifyDocker -Arguments ($compose + @(
            'exec', '-T', 'hermes',
            'hermes-hindsight-acceptance', 'cleanup',
            '--api-url', $apiUrl,
            '--state', $stateFile,
            '--evidence', $evidenceFile
        ))
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-HermesHindsightVerify -ComposeFile $ComposeFile -DataDir $DataDir
        exit 0
    }
    catch {
        [Console]::Error.WriteLine($_.Exception.Message)
        exit 1
    }
}
