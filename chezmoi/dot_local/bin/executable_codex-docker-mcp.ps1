<#
.SYNOPSIS
    Starts Docker Desktop if needed, then runs docker for Codex MCP servers.

.DESCRIPTION
    Codex MCP stdio servers use stdout for JSON-RPC. This wrapper writes its
    own status messages to stderr only, waits for the Docker daemon, then
    replaces the current action with the requested docker command.
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$DockerArgs
)

$ErrorActionPreference = "Stop"

function Write-McpLog {
    param([Parameter(Mandatory)][string]$Message)
    [Console]::Error.WriteLine("[codex-docker-mcp] $Message")
}

function Test-DockerReady {
    $null = & docker info 2>$null
    return $LASTEXITCODE -eq 0
}

function Get-DockerDesktopPath {
    $candidates = @()

    if ($env:ProgramFiles) {
        $candidates += Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe"
    }
    if (${env:ProgramFiles(x86)}) {
        $candidates += Join-Path ${env:ProgramFiles(x86)} "Docker\Docker\Docker Desktop.exe"
    }
    if ($env:LOCALAPPDATA) {
        $candidates += Join-Path $env:LOCALAPPDATA "Docker\Docker Desktop.exe"
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $null
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-McpLog "docker command was not found on PATH."
    exit 127
}

if ($DockerArgs.Count -eq 0) {
    Write-McpLog "No docker arguments were supplied."
    exit 64
}

if (-not (Test-DockerReady)) {
    $dockerDesktop = Get-DockerDesktopPath
    if ($dockerDesktop) {
        Write-McpLog "Docker daemon is not ready. Starting Docker Desktop."
        Start-Process -FilePath $dockerDesktop -WindowStyle Hidden | Out-Null
    }
    else {
        Write-McpLog "Docker daemon is not ready and Docker Desktop was not found."
    }

    $deadline = (Get-Date).AddSeconds(150)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        if (Test-DockerReady) {
            break
        }
    }
}

if (-not (Test-DockerReady)) {
    Write-McpLog "Docker daemon did not become ready before timeout."
    exit 1
}

& docker @DockerArgs
exit $LASTEXITCODE
