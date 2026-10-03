[CmdletBinding()]
param(
    [ValidateSet('up', 'verify')]
    [string]$Action = 'up',
    [string]$ComposeFile = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ComposeFile)) {
    $ComposeFile = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path 'docker/local-ai-services/compose.yml'
}

function Invoke-HindsightCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFailure,
        [switch]$CaptureOutput
    )

    if ($CaptureOutput) {
        $output = @(& $Command @Arguments)
    }
    else {
        & $Command @Arguments | Out-Host
        $output = @()
    }
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "$Command failed with exit code $exitCode."
    }
    return [PSCustomObject]@{ ExitCode = $exitCode; Output = $output }
}

function Wait-HindsightApi {
    $attempts = if ($env:HINDSIGHT_API_READY_ATTEMPTS) { [int]$env:HINDSIGHT_API_READY_ATTEMPTS } else { 150 }
    $delaySeconds = if ($env:HINDSIGHT_API_READY_DELAY_SECONDS) { [int]$env:HINDSIGHT_API_READY_DELAY_SECONDS } else { 2 }
    $port = if ($env:HINDSIGHT_API_PORT) { [int]$env:HINDSIGHT_API_PORT } else { 8888 }

    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        try {
            $health = Invoke-RestMethod -Uri "http://127.0.0.1:$port/health" -TimeoutSec 2
            if ($health.status -eq 'healthy' -and $health.database -eq 'connected') { return }
        }
        catch {
            if ($attempt -eq $attempts) { break }
        }
        if ($attempt -lt $attempts) { Start-Sleep -Seconds $delaySeconds }
    }
    throw "Hindsight API did not become ready after $attempts attempts."
}

function Invoke-HindsightMain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('up', 'verify')][string]$RequestedAction,
        [Parameter(Mandatory)][string]$RequestedComposeFile
    )

    $null = Invoke-HindsightCommand -Command 'docker' -Arguments @('compose', '-f', $RequestedComposeFile, 'config', '--quiet')

    if ($RequestedAction -eq 'up') {
        $environmentFile = if ($env:HINDSIGHT_ENV_FILE) {
            $env:HINDSIGHT_ENV_FILE
        }
        else {
            $candidate = Join-Path (Split-Path -Parent $RequestedComposeFile) 'hindsight.env'
            if (Test-Path -LiteralPath $candidate) { $candidate } else { Join-Path $PSScriptRoot '../../docker/hindsight/hindsight.env' }
        }
        $llmModel = (Select-String -LiteralPath $environmentFile -Pattern '^HINDSIGHT_OLLAMA_LLM_MODEL=(.+)$').Matches.Groups[1].Value
        $embeddingModel = (Select-String -LiteralPath $environmentFile -Pattern '^HINDSIGHT_OLLAMA_EMBEDDING_MODEL=(.+)$').Matches.Groups[1].Value
        $dataDir = if ($env:HINDSIGHT_DATA_DIR) { $env:HINDSIGHT_DATA_DIR } else { Join-Path $env:USERPROFILE '.local/share/hindsight' }
        $null = Invoke-HindsightCommand -Command 'ollama' -Arguments @('pull', $llmModel)
        $null = Invoke-HindsightCommand -Command 'ollama' -Arguments @('pull', $embeddingModel)
        $null = Invoke-HindsightCommand -Command 'docker' -Arguments @('compose', '-f', $RequestedComposeFile, 'pull', 'hindsight')
        New-Item -ItemType Directory -Path (Join-Path $dataDir 'pg0'), (Join-Path $dataDir 'cache') -Force | Out-Null
        try {
            $null = Invoke-HindsightCommand -Command 'docker' -Arguments @('compose', '-f', $RequestedComposeFile, 'up', '-d', '--force-recreate', '--remove-orphans', 'hindsight')
            Wait-HindsightApi
        }
        catch {
            $startupError = $_
            $stopResult = Invoke-HindsightCommand -Command 'docker' -Arguments @(
                'compose', '-f', $RequestedComposeFile, 'stop', 'hindsight'
            ) -AllowFailure
            if ($stopResult.ExitCode -ne 0) {
                throw "$($startupError.Exception.Message) Also failed to stop Hindsight."
            }
            throw $startupError
        }

        Write-Host 'Hindsight is healthy and database-connected.' -ForegroundColor Green
        return
    }

    Wait-HindsightApi
    Write-Host 'Hindsight is healthy and database-connected.' -ForegroundColor Green
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-HindsightMain -RequestedAction $Action -RequestedComposeFile $ComposeFile
}
