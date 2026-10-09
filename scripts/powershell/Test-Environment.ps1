<#
.SYNOPSIS
    Verifies the Windows dotfiles environment after installation.

.DESCRIPTION
    Checks the commands managed by the Windows bootstrap and exercises Docker,
    Docker Compose, chezmoi, and WSL. Use -Runtime to run a disposable
    hello-world container as the final runtime acceptance check.
#>

[CmdletBinding()]
param(
    [switch]$Docker,
    [switch]$Runtime,
    [string]$DistroName = ''
)

. (Join-Path $PSScriptRoot "lib\Invoke-ExternalCommand.ps1")

function Assert-DotfilesAcceptanceExitCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Label
    )

    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE"
    }
}

function Test-DotfilesEnvironment {
    [CmdletBinding()]
    param(
        [switch]$Docker,
        [switch]$Runtime,
        [string]$DistroName = ''
    )

    $dockerEnabled = $Docker -or $Runtime

    $requiredCommands = @(
        "winget",
        "git",
        "gh",
        "chezmoi",
        "rg",
        "fd",
        "jq",
        "nvim",
        "node",
        "uv",
        "go",
        "rustup",
        "wsl"
    )
    if ($dockerEnabled) {
        $requiredCommands += "docker"
    }

    foreach ($name in $requiredCommands) {
        if (-not (Get-Command -Name $name -ErrorAction SilentlyContinue)) {
            throw "Missing command: $name"
        }
    }

    if ($dockerEnabled) {
        Invoke-Docker -Arguments @("info") | Out-Null
        Assert-DotfilesAcceptanceExitCode -Label "docker info"

        Invoke-Docker -Arguments @("compose", "version") | Out-Null
        Assert-DotfilesAcceptanceExitCode -Label "docker compose version"
    }

    Invoke-Chezmoi -Arguments @("apply", "--dry-run") | Out-Null
    Assert-DotfilesAcceptanceExitCode -Label "chezmoi apply --dry-run"

    Invoke-Wsl -Arguments @("--status") | Out-Null
    Assert-DotfilesAcceptanceExitCode -Label "wsl --status"

    if (-not [string]::IsNullOrWhiteSpace($DistroName)) {
        # Prevent a deferred/skipped NixOS rebuild from reporting setup success.
        # WSL selects the distro's configured Linux user, not a Windows user.
        Invoke-Wsl -TimeoutSeconds 60 -Arguments @(
            '-d', $DistroName, '--', 'bash', '-lc',
            'export XDG_RUNTIME_DIR=/run/user/$(id -u); export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus; test -e /etc/NIXOS && command -v hermes >/dev/null && systemctl --user is-active --quiet hermes-agent.service'
        ) | Out-Null
        Assert-DotfilesAcceptanceExitCode -Label "NixOS WSL native Hermes acceptance ($DistroName)"
    }

    if ($Runtime) {
        Invoke-Docker -Arguments @("run", "--rm", "hello-world") | Out-Null
        Assert-DotfilesAcceptanceExitCode -Label "docker run --rm hello-world"
    }

    return [pscustomobject]@{
        HandlerName = "EnvironmentAcceptance"
        Success     = $true
        Message     = "Windows environment acceptance passed"
        Error       = $null
    }
}

if ($MyInvocation.InvocationName -ne ".") {
    Test-DotfilesEnvironment -Docker:$Docker -Runtime:$Runtime -DistroName $DistroName
}
