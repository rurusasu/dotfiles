[CmdletBinding()]
param(
    [ValidateSet('up', 'verify')]
    [string]$Action = 'up',
    [string]$ComposeFile = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ComposeFile)) {
    $ComposeFile = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path 'docker/hindsight/compose.yml'
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

& docker compose -f $ComposeFile config --quiet
if ($LASTEXITCODE -ne 0) { throw 'Hindsight Compose validation failed.' }

if ($Action -eq 'up') {
    $environmentFile = Join-Path (Split-Path -Parent $ComposeFile) 'hindsight.env'
    $llmModel = (Select-String -LiteralPath $environmentFile -Pattern '^HINDSIGHT_API_LLM_MODEL=(.+)$').Matches.Groups[1].Value
    $embeddingModel = (Select-String -LiteralPath $environmentFile -Pattern '^HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL=(.+)$').Matches.Groups[1].Value
    & ollama pull $llmModel
    if ($LASTEXITCODE -ne 0) { throw "Ollama model pull failed: $llmModel" }
    & ollama pull $embeddingModel
    if ($LASTEXITCODE -ne 0) { throw "Ollama model pull failed: $embeddingModel" }

    $dataDir = if ($env:HINDSIGHT_DATA_DIR) { $env:HINDSIGHT_DATA_DIR } else { Join-Path $env:USERPROFILE '.local/share/hindsight' }
    New-Item -ItemType Directory -Path (Join-Path $dataDir 'pg0'), (Join-Path $dataDir 'cache') -Force | Out-Null
    & docker compose -f $ComposeFile up -d hindsight
    if ($LASTEXITCODE -ne 0) { throw 'Hindsight startup failed.' }
}

Wait-HindsightApi
Write-Host 'Hindsight is healthy and database-connected.' -ForegroundColor Green
