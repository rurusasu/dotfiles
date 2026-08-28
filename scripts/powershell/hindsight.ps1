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

function Test-HindsightDataDirectoryHasContent {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    $ignored = @(
        [System.IO.Path]::GetFullPath((Join-Path $Path 'pg0')),
        [System.IO.Path]::GetFullPath((Join-Path $Path 'cache'))
    )
    foreach ($entry in Get-ChildItem -LiteralPath $Path -Force -Recurse) {
        if ([System.IO.Path]::GetFullPath($entry.FullName) -notin $ignored) { return $true }
    }
    return $false
}

function Test-HindsightLegacyMemoryContent {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Path)

    $hasMemory = $false
    foreach ($component in @('pg0', 'cache')) {
        $componentPath = Join-Path $Path $component
        if (-not (Test-Path -LiteralPath $componentPath)) { continue }
        $componentItem = Get-Item -LiteralPath $componentPath -Force
        if (-not $componentItem.PSIsContainer -or ($componentItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            throw "Legacy Hindsight component is not a regular directory: $componentPath"
        }
        if ($null -ne (Get-ChildItem -LiteralPath $componentPath -Force -Recurse | Select-Object -First 1)) {
            $hasMemory = $true
        }
    }
    return $hasMemory
}

function Get-HindsightLegacyContainerState {
    [CmdletBinding()]
    param()

    $inspect = Invoke-HindsightCommand -Command 'docker' -Arguments @(
        'container', 'inspect', '--format', '{{.State.Running}}', 'hermes-hindsight'
    ) -AllowFailure -CaptureOutput
    if ($inspect.ExitCode -ne 0) {
        return [PSCustomObject]@{ Exists = $false; Running = $false }
    }
    $running = (($inspect.Output -join '').Trim().ToLowerInvariant() -eq 'true')
    return [PSCustomObject]@{ Exists = $true; Running = $running }
}

function Move-HindsightLegacyData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DataDir,
        [switch]$ValidateOnly
    )

    $hermesDataDir = if ($env:HERMES_DATA_DIR) { $env:HERMES_DATA_DIR } else { Join-Path $env:USERPROFILE '.hermes' }
    $legacyDir = [System.IO.Path]::GetFullPath((Join-Path $hermesDataDir 'hindsight'))
    $DataDir = [System.IO.Path]::GetFullPath($DataDir)
    if ($legacyDir -eq $DataDir -or -not (Test-Path -LiteralPath $legacyDir)) { return }

    $legacyItem = Get-Item -LiteralPath $legacyDir -Force
    if (-not $legacyItem.PSIsContainer -or ($legacyItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        throw "Legacy Hindsight data path is not a regular directory: $legacyDir"
    }
    if (-not (Test-HindsightLegacyMemoryContent -Path $legacyDir)) { return }

    $marker = Join-Path $DataDir '.legacy-migration-source'
    if ((Test-Path -LiteralPath $marker -PathType Leaf) -and
        -not ((Get-Item -LiteralPath $marker -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and
        (Get-Content -LiteralPath $marker -Raw).Trim() -eq $legacyDir) {
        return
    }
    if (Test-Path -LiteralPath $DataDir) {
        $dataItem = Get-Item -LiteralPath $DataDir -Force
        if (-not $dataItem.PSIsContainer -or ($dataItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            throw "Hindsight data path is not a regular directory: $DataDir"
        }
        if (Test-HindsightDataDirectoryHasContent -Path $DataDir) {
            throw "Legacy and independent Hindsight data directories both contain data; migrate them manually: $legacyDir -> $DataDir"
        }
    }
    if ($ValidateOnly) { return }

    $legacyState = Get-HindsightLegacyContainerState
    $legacyContainerWasRunning = $legacyState.Running
    try {
        $parent = Split-Path -Parent $DataDir
        $null = New-Item -ItemType Directory -Path $parent -Force
        $staging = "$DataDir.migrate.$PID"
        if (Test-Path -LiteralPath $staging) { throw "Hindsight migration staging path already exists: $staging" }
        $null = New-Item -ItemType Directory -Path $staging

        if ($legacyContainerWasRunning) {
            $null = Invoke-HindsightCommand -Command 'docker' -Arguments @('stop', 'hermes-hindsight')
        }

        try {
            foreach ($component in @('pg0', 'cache')) {
                $source = Join-Path $legacyDir $component
                $destination = Join-Path $staging $component
                if (Test-Path -LiteralPath $source -PathType Container) {
                    Copy-Item -LiteralPath $source -Destination $destination -Recurse
                }
                else {
                    $null = New-Item -ItemType Directory -Path $destination
                }
            }
            $markerPath = Join-Path $staging '.legacy-migration-source'
            $utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
            [System.IO.File]::WriteAllText($markerPath, ($legacyDir + [Environment]::NewLine), $utf8NoBom)
        }
        catch {
            throw "Unable to copy legacy Hindsight data; the original remains at $legacyDir"
        }

        if (Test-Path -LiteralPath $DataDir -PathType Container) {
            foreach ($component in @('pg0', 'cache')) {
                $componentPath = Join-Path $DataDir $component
                if (Test-Path -LiteralPath $componentPath -PathType Container) {
                    [System.IO.Directory]::Delete($componentPath, $false)
                }
            }
            [System.IO.Directory]::Delete($DataDir, $false)
        }
        Move-Item -LiteralPath $staging -Destination $DataDir

    }
    catch {
        $migrationError = $_
        if ($legacyContainerWasRunning) {
            try {
                $null = Invoke-HindsightCommand -Command 'docker' -Arguments @('start', 'hermes-hindsight')
            }
            catch {
                throw "$($migrationError.Exception.Message) Also failed to restart hermes-hindsight: $($_.Exception.Message)"
            }
        }
        throw $migrationError
    }
    Write-Host "Migrated legacy Hindsight data to $DataDir; the source was preserved at $legacyDir."
    return $legacyContainerWasRunning
}

function Move-HindsightMigratedDataForRetry {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DataDir)

    $hermesDataDir = if ($env:HERMES_DATA_DIR) { $env:HERMES_DATA_DIR } else { Join-Path $env:USERPROFILE '.hermes' }
    $legacyDir = [System.IO.Path]::GetFullPath((Join-Path $hermesDataDir 'hindsight'))
    $DataDir = [System.IO.Path]::GetFullPath($DataDir)
    if (-not (Test-Path -LiteralPath $DataDir)) { return }

    $dataItem = Get-Item -LiteralPath $DataDir -Force
    if (-not $dataItem.PSIsContainer -or ($dataItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        throw "Hindsight data path is not a regular directory: $DataDir"
    }
    $marker = Join-Path $DataDir '.legacy-migration-source'
    if (-not (Test-Path -LiteralPath $marker -PathType Leaf) -or
        ((Get-Item -LiteralPath $marker -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) -or
        (Get-Content -LiteralPath $marker -Raw).Trim() -ne $legacyDir) {
        return
    }

    $timestamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    $quarantine = "$DataDir.failed-cutover.$timestamp.$PID"
    if (Test-Path -LiteralPath $quarantine) {
        throw "Hindsight failed-cutover quarantine path already exists: $quarantine"
    }
    Move-Item -LiteralPath $DataDir -Destination $quarantine
    Write-Warning "Quarantined failed independent Hindsight data at $quarantine before restoring the legacy service."
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
        $environmentFile = Join-Path (Split-Path -Parent $RequestedComposeFile) 'hindsight.env'
        $llmModel = (Select-String -LiteralPath $environmentFile -Pattern '^HINDSIGHT_OLLAMA_LLM_MODEL=(.+)$').Matches.Groups[1].Value
        $embeddingModel = (Select-String -LiteralPath $environmentFile -Pattern '^HINDSIGHT_OLLAMA_EMBEDDING_MODEL=(.+)$').Matches.Groups[1].Value
        $dataDir = if ($env:HINDSIGHT_DATA_DIR) { $env:HINDSIGHT_DATA_DIR } else { Join-Path $env:USERPROFILE '.local/share/hindsight' }
        Move-HindsightLegacyData -DataDir $dataDir -ValidateOnly
        $null = Invoke-HindsightCommand -Command 'ollama' -Arguments @('pull', $llmModel)
        $null = Invoke-HindsightCommand -Command 'ollama' -Arguments @('pull', $embeddingModel)
        $null = Invoke-HindsightCommand -Command 'docker' -Arguments @('compose', '-f', $RequestedComposeFile, 'pull', 'hindsight')
        New-Item -ItemType Directory -Path (Join-Path $dataDir 'pg0'), (Join-Path $dataDir 'cache') -Force | Out-Null
        $migrationStoppedRunningLegacy = [bool](Move-HindsightLegacyData -DataDir $dataDir)

        $legacyState = Get-HindsightLegacyContainerState
        $legacyContainerWasRunning = $migrationStoppedRunningLegacy -or $legacyState.Running
        try {
            if ($legacyState.Running) {
                $null = Invoke-HindsightCommand -Command 'docker' -Arguments @('stop', 'hermes-hindsight')
            }
            $null = Invoke-HindsightCommand -Command 'docker' -Arguments @('compose', '-f', $RequestedComposeFile, 'up', '-d', '--force-recreate', '--remove-orphans', 'hindsight')
            Wait-HindsightApi
        }
        catch {
            $replacementError = $_
            $stopResult = Invoke-HindsightCommand -Command 'docker' -Arguments @(
                'compose', '-f', $RequestedComposeFile, 'stop', 'hindsight'
            ) -AllowFailure
            if ($legacyContainerWasRunning) {
                if ($stopResult.ExitCode -ne 0) {
                    throw "$($replacementError.Exception.Message) Also failed to stop independent Hindsight; hermes-hindsight was not restarted to avoid concurrent writers."
                }
                try {
                    Move-HindsightMigratedDataForRetry -DataDir $dataDir
                    $null = Invoke-HindsightCommand -Command 'docker' -Arguments @('start', 'hermes-hindsight')
                }
                catch {
                    throw "$($replacementError.Exception.Message) Also failed to quarantine failed data or restart hermes-hindsight: $($_.Exception.Message)"
                }
            }
            throw $replacementError
        }
        if ($legacyState.Exists) {
            $null = Invoke-HindsightCommand -Command 'docker' -Arguments @('rm', 'hermes-hindsight')
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
