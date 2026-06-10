#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-NormalizedPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    return [System.IO.Path]::GetFullPath($Path.Trim()).TrimEnd("\")
}

function Get-OpenClawConfigPath {
    if (-not [string]::IsNullOrWhiteSpace($env:OPENCLAW_CONFIG)) {
        return $env:OPENCLAW_CONFIG
    }

    if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        throw "USERPROFILE is required to resolve OpenClaw config path."
    }

    return Join-Path (Join-Path $env:USERPROFILE ".openclaw") "openclaw.json"
}

function Set-JsonProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [AllowNull()]
        [object]$Value
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($property) {
        $property.Value = $Value
        return
    }

    Add-Member -InputObject $Object -MemberType NoteProperty -Name $Name -Value $Value
}

function Get-JsonObjectProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($property -and $property.Value -and $property.Value -is [pscustomobject]) {
        return $property.Value
    }

    $value = [pscustomobject]@{}
    Set-JsonProperty -Object $Object -Name $Name -Value $value
    return $value
}

function Read-OpenClawConfig {
    param([string]$ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        return [pscustomobject]@{}
    }

    $content = Get-Content -LiteralPath $ConfigPath -Raw
    if ([string]::IsNullOrWhiteSpace($content)) {
        return [pscustomobject]@{}
    }

    $config = $content | ConvertFrom-Json
    if (-not $config) {
        return [pscustomobject]@{}
    }
    if ($config -is [array] -or $config -isnot [pscustomobject]) {
        throw "OpenClaw config root must be a JSON object: $ConfigPath"
    }

    return $config
}

function Write-OpenClawConfig {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config,
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    $directory = Split-Path -Parent $ConfigPath
    if ($directory -and -not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $json = $Config | ConvertTo-Json -Depth 20
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($ConfigPath, "$json`r`n", $utf8NoBom)
}

function Invoke-GatewayRestartCommand {
    param([string]$Command)

    if ([string]::IsNullOrWhiteSpace($Command)) {
        throw "OpenClaw gateway restart command is required."
    }

    $global:LASTEXITCODE = 0
    $output = & $Command 2>&1
    $success = $?
    $exitCode = if ($null -eq $global:LASTEXITCODE) { 0 } else { $global:LASTEXITCODE }

    if (-not $success -or $exitCode -ne 0) {
        $joinedOutput = ($output | Out-String).Trim()
        if ($joinedOutput) {
            throw "OpenClaw gateway restart failed (exit=$exitCode): $joinedOutput"
        }
        throw "OpenClaw gateway restart failed (exit=$exitCode)."
    }

    if ($output) {
        $output | Write-Host
    }
}

function Get-OpenClawGatewayCommandPath {
    if (-not [string]::IsNullOrWhiteSpace($env:OPENCLAW_GATEWAY_COMMAND)) {
        return $env:OPENCLAW_GATEWAY_COMMAND
    }

    if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        throw "USERPROFILE is required to resolve OpenClaw gateway command path."
    }

    return Join-Path (Join-Path $env:USERPROFILE ".openclaw") "gateway.cmd"
}

function Get-OpenClawGatewayProcesses {
    Get-CimInstance Win32_Process | Where-Object {
        if ($_.ProcessId -eq $PID) {
            return $false
        }

        $commandLine = [string]$_.CommandLine
        if ([string]::IsNullOrWhiteSpace($commandLine)) {
            return $false
        }

        $runsGatewayCommand = $commandLine -match '(?i)(^|[\\/])gateway\.cmd("|\s|$)'
        $runsOpenClawGateway = $commandLine -match '(?i)(^|\s)"?[^"]*[\\/]node_modules[\\/]openclaw[\\/](dist[\\/]index\.js|openclaw\.mjs)"?\s+gateway(\s|$)'
        return $runsGatewayCommand -or $runsOpenClawGateway
    }
}

function Stop-OpenClawGatewayProcesses {
    $gatewayProcesses = @(Get-OpenClawGatewayProcesses)

    foreach ($gatewayProcess in $gatewayProcesses) {
        try {
            Stop-Process -Id $gatewayProcess.ProcessId -Force -ErrorAction Stop
            Write-Host "Stopped OpenClaw gateway process: $($gatewayProcess.ProcessId)"
        }
        catch {
            Write-Warning "Failed to stop OpenClaw gateway process $($gatewayProcess.ProcessId): $($_.Exception.Message)"
        }
    }
}

function Start-OpenClawGatewayProcess {
    $gatewayCommand = Get-OpenClawGatewayCommandPath
    if (-not (Test-Path -LiteralPath $gatewayCommand -PathType Leaf)) {
        throw "OpenClaw gateway command was not found: $gatewayCommand"
    }

    Start-Process -FilePath $gatewayCommand -WindowStyle Hidden | Out-Null
    Write-Host "OpenClaw gateway restart requested: $gatewayCommand"
}

function Restart-OpenClawGateway {
    if (-not [string]::IsNullOrWhiteSpace($env:OPENCLAW_GATEWAY_RESTART_COMMAND)) {
        Invoke-GatewayRestartCommand -Command $env:OPENCLAW_GATEWAY_RESTART_COMMAND
        Write-Host "OpenClaw gateway restart command completed: $env:OPENCLAW_GATEWAY_RESTART_COMMAND"
        return
    }

    Stop-OpenClawGatewayProcesses
    Start-OpenClawGatewayProcess
}

$lifelogRoot = Get-NormalizedPath $env:LIFELOG_ROOT
if (-not $lifelogRoot) {
    throw "LIFELOG_ROOT is required. Set it to the explicit lifelog repository root before running chezmoi apply."
}

$agentsPath = Join-Path $lifelogRoot "AGENTS.md"
if (-not (Test-Path -LiteralPath $agentsPath -PathType Leaf)) {
    throw "LIFELOG_ROOT does not look like lifelog root; AGENTS.md was not found: $agentsPath"
}

$configPath = Get-OpenClawConfigPath
$config = Read-OpenClawConfig -ConfigPath $configPath
$agents = Get-JsonObjectProperty -Object $config -Name "agents"
$defaults = Get-JsonObjectProperty -Object $agents -Name "defaults"
Set-JsonProperty -Object $defaults -Name "workspace" -Value $lifelogRoot
Write-OpenClawConfig -Config $config -ConfigPath $configPath

Write-Host "OpenClaw agents.defaults.workspace: $lifelogRoot"
Restart-OpenClawGateway
