<#
.SYNOPSIS
    Orchestrates the Hermes bootstrap container and Compose services.
#>

$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath 'lib\Invoke-ExternalCommand.ps1')
. (Join-Path $libPath 'lib\HermesBootstrap.ps1')

class HermesAgentHandler : SetupHandlerBase {
    [int]$DockerCheckTimeoutSeconds = 15
    [int]$DockerComposeTimeoutSeconds = 180

    HermesAgentHandler() {
        $this.Name = 'HermesAgent'
        $this.Description = 'Hermes Agent Docker container setup'
        $this.Order = 56
        $this.RequiresAdmin = $false
        $this.Phase = 2
    }

    [bool] CanApply([SetupContext]$ctx) {
        if ($this.IsSkipped($ctx)) {
            $this.Log('Hermes Agent setup is disabled by option.', 'Gray')
            return $false
        }

        $composeFile = $this.GetComposeFilePath($ctx)
        if (-not (Test-Path -LiteralPath $composeFile)) {
            $this.Log("Hermes compose file was not found: $composeFile", 'Gray')
            return $false
        }

        if (-not (Get-Command -Name 'docker' -ErrorAction SilentlyContinue)) {
            $this.Log('docker command was not found.', 'Gray')
            return $false
        }

        if (-not (Test-DockerDaemon -TimeoutSeconds $this.DockerCheckTimeoutSeconds)) {
            $this.Log('Docker daemon is not ready; skipping Hermes Agent.', 'Gray')
            return $false
        }

        if (-not (Test-WslAvailable)) {
            $this.Log('WSL is not available; skipping Hermes Agent.', 'Gray')
            return $false
        }

        if (-not $this.TestNixOsReady($ctx.DistroName)) {
            $this.Log("$($ctx.DistroName) is not ready; skipping Hermes Agent.", 'Gray')
            return $false
        }

        if (-not $this.IsTruthy($ctx.GetOption('NixRebuildApplied', $false))) {
            $this.Log('NixOS configuration has not been applied; skipping Hermes Agent.', 'Gray')
            return $false
        }

        return $true
    }

    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            $composeFile = $this.GetComposeFilePath($ctx)
            if (-not (Test-Path -LiteralPath $composeFile)) {
                return $this.CreateFailureResult("Hermes compose file was not found: $composeFile")
            }

            $dataDir = $this.GetDataDir()
            $this.EnsureDirectory($dataDir)
            $this.EnsureDirectory((Join-Path $dataDir '.xurl'))
            $this.EnsureDirectory($this.GetBrowserDataDir())

            $validation = $this.InvokeCompose($composeFile, @('config', '--quiet'))
            if (-not $validation.Success) {
                return $this.CreateFailureResult("Hermes Compose validation failed: $($validation.Message)")
            }

            $build = $this.InvokeCompose($composeFile, @('build', 'hermes', 'hermes-bootstrap'))
            if (-not $build.Success) {
                return $this.CreateFailureResult("Hermes image build failed: $($build.Message)")
            }

            $bootstrap = Invoke-HermesBootstrap -ComposeFile $composeFile -DataDir $dataDir
            if (-not $bootstrap.Success) {
                return $this.CreateFailureResult("Hermes bootstrap failed: $($bootstrap.Message)")
            }

            $start = $this.InvokeCompose($composeFile, @('up', '-d', '--force-recreate'))
            if (-not $start.Success) {
                return $this.CreateFailureResult("Hermes Agent startup failed: $($start.Message)")
            }

            if (-not $this.WaitForApi()) {
                try {
                    $this.InvokeCompose($composeFile, @('ps', '--all')) | Out-Null
                }
                catch {
                    $null = $_
                }
                $attempts = $this.GetPositiveEnvironmentInteger('HERMES_API_READY_ATTEMPTS', 30)
                return $this.CreateFailureResult("Hermes API did not become ready after $attempts attempts.")
            }

            return $this.CreateSuccessResult("Hermes Agent started: http://127.0.0.1:9119 / browser: $($this.GetBrowserViewUrl())")
        }
        catch {
            return $this.CreateFailureResult('Hermes Agent setup failed.')
        }
    }

    hidden [bool] IsSkipped([SetupContext]$ctx) {
        if ($this.IsTruthy($ctx.GetOption('SkipHermesAgent', $false))) {
            return $true
        }

        return -not $this.IsTruthy($ctx.GetOption('HermesAgentEnabled', $true))
    }

    hidden [bool] IsTruthy([object]$value) {
        if ($null -eq $value) { return $false }
        if ($value -is [bool]) { return [bool]$value }

        return ([string]$value).Trim() -in @('1', 'true', 'TRUE', 'True', 'yes', 'YES', 'Yes', 'on', 'ON', 'On')
    }

    hidden [string] GetComposeFilePath([SetupContext]$ctx) {
        return Join-Path $ctx.DotfilesPath 'docker\hermes-agent\compose.yml'
    }

    hidden [bool] TestNixOsReady([string]$distroName) {
        if ([string]::IsNullOrWhiteSpace($distroName)) { return $false }

        try {
            Invoke-Wsl -TimeoutSeconds (Get-WslCheckTimeoutSecond) -Arguments @(
                '-d', $distroName, '-u', 'root', '--', 'true'
            ) | Out-Null
            return $LASTEXITCODE -eq 0
        }
        catch {
            return $false
        }
    }

    hidden [string] GetDataDir() {
        if (-not [string]::IsNullOrWhiteSpace($env:HERMES_DATA_DIR)) {
            return $env:HERMES_DATA_DIR
        }

        return Join-Path $this.GetHomeDir() '.hermes'
    }

    hidden [string] GetBrowserDataDir() {
        if (-not [string]::IsNullOrWhiteSpace($env:HERMES_BROWSER_DATA_DIR)) {
            return $env:HERMES_BROWSER_DATA_DIR
        }

        return Join-Path (Join-Path $this.GetHomeDir() '.hermes') '.browser'
    }

    hidden [string] GetBrowserViewUrl() {
        $port = if ([string]::IsNullOrWhiteSpace($env:HERMES_BROWSER_VIEW_PORT)) {
            '6080'
        }
        else {
            $env:HERMES_BROWSER_VIEW_PORT
        }
        return "http://127.0.0.1:$port"
    }

    hidden [string] GetApiHealthUrl() {
        $port = if ([string]::IsNullOrWhiteSpace($env:HERMES_API_PORT)) {
            '8642'
        }
        else {
            $env:HERMES_API_PORT
        }
        return "http://127.0.0.1:$port/health"
    }

    hidden [int] GetPositiveEnvironmentInteger([string]$name, [int]$defaultValue) {
        $rawValue = [Environment]::GetEnvironmentVariable($name)
        $parsedValue = 0
        if ([int]::TryParse($rawValue, [ref]$parsedValue) -and $parsedValue -gt 0) {
            return $parsedValue
        }
        return $defaultValue
    }

    hidden [int] GetNonNegativeEnvironmentInteger([string]$name, [int]$defaultValue) {
        $rawValue = [Environment]::GetEnvironmentVariable($name)
        $parsedValue = 0
        if ([int]::TryParse($rawValue, [ref]$parsedValue) -and $parsedValue -ge 0) {
            return $parsedValue
        }
        return $defaultValue
    }

    hidden [bool] WaitForApi() {
        $attempts = $this.GetPositiveEnvironmentInteger('HERMES_API_READY_ATTEMPTS', 30)
        $delaySeconds = $this.GetNonNegativeEnvironmentInteger('HERMES_API_READY_DELAY_SECONDS', 2)
        $timeoutSeconds = $this.GetPositiveEnvironmentInteger('HERMES_API_PROBE_TIMEOUT_SECONDS', 2)
        $healthUrl = $this.GetApiHealthUrl()

        for ($attempt = 1; $attempt -le $attempts; $attempt++) {
            try {
                $response = Invoke-WebRequest -Uri $healthUrl -Method Get -UseBasicParsing `
                    -TimeoutSec $timeoutSeconds -ErrorAction Stop
                if ($null -ne $response -and [int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 300) {
                    return $true
                }
            }
            catch {
                $null = $_
            }

            if ($attempt -lt $attempts) {
                Start-Sleep -Seconds $delaySeconds
            }
        }

        return $false
    }

    hidden [string] GetHomeDir() {
        if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) { return $env:USERPROFILE }
        if (-not [string]::IsNullOrWhiteSpace($env:HOME)) { return $env:HOME }
        return [Environment]::GetFolderPath('UserProfile')
    }

    hidden [void] EnsureDirectory([string]$path) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    hidden [pscustomobject] InvokeCompose([string]$composeFile, [string[]]$command) {
        $arguments = @('compose', '-f', $composeFile) + $command
        $output = @(Invoke-Docker -Arguments $arguments -TimeoutSeconds $this.DockerComposeTimeoutSeconds)
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) {
            return [PSCustomObject]@{ Success = $true; Message = '' }
        }

        $message = (($output -join "`n").Trim())
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = "exit code $exitCode"
        }
        elseif ($message.Length -gt 4096) {
            $message = "$($message.Substring(0, 4096))..."
        }
        return [PSCustomObject]@{ Success = $false; Message = $message }
    }
}
