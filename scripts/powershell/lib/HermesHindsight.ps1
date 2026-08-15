<#!
.SYNOPSIS
    Prepares native Ollama and the Hindsight memory API for Hermes.
#>

$script:HermesHindsightCommandTimeoutSeconds = 1800

function Get-HermesHindsightPositiveInteger {
    param([string]$Name, [int]$DefaultValue)

    $value = [Environment]::GetEnvironmentVariable($Name)
    $parsed = 0
    if ([int]::TryParse($value, [ref]$parsed) -and $parsed -gt 0) { return $parsed }
    return $DefaultValue
}

function Get-HermesHindsightNonNegativeInteger {
    param([string]$Name, [int]$DefaultValue)

    $value = [Environment]::GetEnvironmentVariable($Name)
    $parsed = 0
    if ([int]::TryParse($value, [ref]$parsed) -and $parsed -ge 0) { return $parsed }
    return $DefaultValue
}

function Invoke-HermesHindsightCommand {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][int]$TimeoutSeconds
    )

    $output = @(Invoke-ExternalCommandWithTimeout -Command $Command -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds)
    $exitCode = $global:LASTEXITCODE
    if ($exitCode -ne 0) {
        $message = ($output -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($message)) { $message = "exit code $exitCode" }
        throw [System.InvalidOperationException]::new("$Command failed: $message")
    }
    return $output
}

function Get-HermesHindsightEnvironmentValue {
    param(
        [Parameter(Mandatory)][string]$EnvironmentFile,
        [Parameter(Mandatory)][string]$Key
    )

    $matches = @(
        Get-Content -LiteralPath $EnvironmentFile -ErrorAction Stop |
            Where-Object { $_ -match ("^{0}=(.*)$" -f [regex]::Escape($Key)) } |
            ForEach-Object { $Matches[1] }
    )
    if ($matches.Count -ne 1) {
        throw [System.InvalidOperationException]::new("Hindsight environment value $Key must occur exactly once.")
    }
    if ([string]::IsNullOrWhiteSpace([string]$matches[0])) {
        throw [System.InvalidOperationException]::new("Hindsight environment value $Key must be nonempty.")
    }
    return [string]$matches[0]
}

function Get-HermesHindsightEnvironment {
    param([Parameter(Mandatory)][string]$ComposeFile)

    $environmentFile = Join-Path (Split-Path -Parent $ComposeFile) 'hindsight.env'
    $llmModel = Get-HermesHindsightEnvironmentValue -EnvironmentFile $environmentFile -Key 'HINDSIGHT_API_LLM_MODEL'
    $embeddingModel = Get-HermesHindsightEnvironmentValue -EnvironmentFile $environmentFile -Key 'HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL'
    return [PSCustomObject]@{
        PSTypeName     = 'HermesHindsightEnvironment'
        LlmModel       = $llmModel
        EmbeddingModel = $embeddingModel
    }
}

function Wait-HermesHindsightOllama {
    $attempts = Get-HermesHindsightPositiveInteger -Name 'HINDSIGHT_OLLAMA_READY_ATTEMPTS' -DefaultValue 30
    $delaySeconds = Get-HermesHindsightNonNegativeInteger -Name 'HINDSIGHT_OLLAMA_READY_DELAY_SECONDS' -DefaultValue 2
    $timeoutSeconds = Get-HermesHindsightPositiveInteger -Name 'HINDSIGHT_OLLAMA_PROBE_TIMEOUT_SECONDS' -DefaultValue 2
    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        try {
            $null = Invoke-HermesHindsightCommand -Command 'curl' -Arguments @('--fail', '--silent', '--show-error', '--max-time', "$timeoutSeconds", 'http://127.0.0.1:11434/api/version') -TimeoutSeconds $timeoutSeconds
            return
        }
        catch {
            if ($attempt -eq $attempts) { break }
            Start-Sleep -Seconds $delaySeconds
        }
    }
    throw [System.InvalidOperationException]::new("Ollama API did not become ready after $attempts attempts.")
}

function Initialize-HermesHindsightHost {
    param(
        [Parameter(Mandatory)][string]$ComposeFile,
        [Parameter(Mandatory)][string]$DataDir
    )

    foreach ($command in @('ollama', 'curl')) {
        if ($null -eq (Get-ExternalCommand -Name $command)) {
            throw [System.InvalidOperationException]::new("$command command was not found.")
        }
    }
    Wait-HermesHindsightOllama
    $environment = Get-HermesHindsightEnvironment -ComposeFile $ComposeFile
    foreach ($model in @($environment.LlmModel, $environment.EmbeddingModel)) {
        $null = Invoke-HermesHindsightCommand -Command 'ollama' -Arguments @('pull', $model) -TimeoutSeconds $script:HermesHindsightCommandTimeoutSeconds
    }
    $timeoutSeconds = Get-HermesHindsightPositiveInteger -Name 'HINDSIGHT_OLLAMA_PROBE_TIMEOUT_SECONDS' -DefaultValue 2
    $tags = (Invoke-HermesHindsightCommand -Command 'curl' -Arguments @('--fail', '--silent', '--show-error', '--max-time', "$timeoutSeconds", 'http://127.0.0.1:11434/api/tags') -TimeoutSeconds $timeoutSeconds) -join "`n" | ConvertFrom-Json -ErrorAction Stop
    foreach ($model in @($environment.LlmModel, $environment.EmbeddingModel)) {
        if (@($tags.models | Where-Object { $_.name -eq $model }).Count -ne 1) {
            throw [System.InvalidOperationException]::new("Ollama model is missing after pull: $model")
        }
    }
    $null = New-Item -ItemType Directory -Path (Join-Path $DataDir 'hindsight/pg0') -Force
    $null = New-Item -ItemType Directory -Path (Join-Path $DataDir 'hindsight/cache') -Force
    return $environment
}

function Wait-HermesHindsightApi {
    param([int]$Port = 8888)

    $attempts = Get-HermesHindsightPositiveInteger -Name 'HINDSIGHT_API_READY_ATTEMPTS' -DefaultValue 30
    $delaySeconds = Get-HermesHindsightNonNegativeInteger -Name 'HINDSIGHT_API_READY_DELAY_SECONDS' -DefaultValue 2
    $timeoutSeconds = Get-HermesHindsightPositiveInteger -Name 'HINDSIGHT_API_PROBE_TIMEOUT_SECONDS' -DefaultValue 2
    $url = "http://127.0.0.1:$Port/health"
    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        try {
            $health = (Invoke-HermesHindsightCommand -Command 'curl' -Arguments @('--fail', '--silent', '--show-error', '--max-time', "$timeoutSeconds", $url) -TimeoutSeconds $timeoutSeconds) -join "`n" | ConvertFrom-Json -ErrorAction Stop
            if ($health.status -eq 'healthy' -and $health.database -eq 'connected') { return }
        }
        catch { }
        if ($attempt -lt $attempts) { Start-Sleep -Seconds $delaySeconds }
    }
    throw [System.InvalidOperationException]::new("Hindsight API did not become ready after $attempts attempts.")
}
