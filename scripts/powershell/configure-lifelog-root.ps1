#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [string]$ExpectedRemoteRegex = 'github\.com[:/]rurusasu/lifelog(?:\.git)?$',

    [string]$GitCommand = "git",

    [string]$ChezmoiCommand = "chezmoi",

    [string]$ChezmoiSource = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "chezmoi"),

    [ValidateSet("User", "Process")]
    [string]$EnvironmentTarget = "User",

    [switch]$SkipChezmoiApply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-NormalizedPath {
    param([string]$InputPath)

    if ([string]::IsNullOrWhiteSpace($InputPath)) {
        throw "Path is required."
    }

    return [System.IO.Path]::GetFullPath($InputPath.Trim()).TrimEnd("\")
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    $output = & $Command @Arguments 2>&1
    $exitCode = if ($null -eq $global:LASTEXITCODE) { 0 } else { $global:LASTEXITCODE }
    if ($exitCode -ne 0) {
        $joinedOutput = ($output | Out-String).Trim()
        if ($joinedOutput) {
            throw "$Description failed (exit=$exitCode): $joinedOutput"
        }
        throw "$Description failed (exit=$exitCode)."
    }

    return @($output)
}

function Assert-LifelogRoot {
    param([string]$Root)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "Lifelog root does not exist: $Root"
    }

    $agentsPath = Join-Path $Root "AGENTS.md"
    if (-not (Test-Path -LiteralPath $agentsPath -PathType Leaf)) {
        throw "AGENTS.md was not found under the explicit lifelog root: $agentsPath"
    }

    $gitTopLevel = @(
        Invoke-CheckedCommand `
            -Command $GitCommand `
            -Arguments @("-C", $Root, "rev-parse", "--show-toplevel") `
            -Description "git rev-parse --show-toplevel"
    )[0]
    $normalizedTopLevel = Get-NormalizedPath ([string]$gitTopLevel)
    if (-not [string]::Equals($normalizedTopLevel, $Root, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Explicit path is not the git top-level. Expected $Root but git returned $normalizedTopLevel."
    }

    $gitDir = @(
        Invoke-CheckedCommand `
            -Command $GitCommand `
            -Arguments @("-C", $Root, "rev-parse", "--git-dir") `
            -Description "git rev-parse --git-dir"
    )[0]
    if ([string]::IsNullOrWhiteSpace([string]$gitDir)) {
        throw "Git directory could not be resolved for explicit lifelog root: $Root"
    }

    $origin = @(
        Invoke-CheckedCommand `
            -Command $GitCommand `
            -Arguments @("-C", $Root, "remote", "get-url", "origin") `
            -Description "git remote get-url origin"
    )[0]
    if ([string]::IsNullOrWhiteSpace([string]$origin) -or ([string]$origin) -notmatch $ExpectedRemoteRegex) {
        throw "Explicit path is not the expected lifelog repository. Origin was: $origin"
    }
}

function Set-LifelogRootEnvironment {
    param(
        [string]$Root,
        [string]$Target
    )

    [System.Environment]::SetEnvironmentVariable("LIFELOG_ROOT", $Root, $Target)
    $env:LIFELOG_ROOT = $Root
}

function Invoke-ChezmoiRefresh {
    param([string]$Root)

    if ($SkipChezmoiApply) {
        Write-Host "Skipping chezmoi init/apply. LIFELOG_ROOT is set for $EnvironmentTarget."
        return
    }

    if (-not (Test-Path -LiteralPath $ChezmoiSource -PathType Container)) {
        throw "Chezmoi source directory does not exist: $ChezmoiSource"
    }

    $oldSetupRoot = $env:OPENCLAW_LIFELOG_ROOT_FOR_INIT
    try {
        $env:OPENCLAW_LIFELOG_ROOT_FOR_INIT = $Root

        Invoke-CheckedCommand `
            -Command $ChezmoiCommand `
            -Arguments @("init", "--source", $ChezmoiSource) `
            -Description "chezmoi init" | Out-Null

        Invoke-CheckedCommand `
            -Command $ChezmoiCommand `
            -Arguments @("apply", "--source", $ChezmoiSource, "--force") `
            -Description "chezmoi apply" | Out-Null
    }
    finally {
        if ($null -eq $oldSetupRoot) {
            Remove-Item Env:\OPENCLAW_LIFELOG_ROOT_FOR_INIT -ErrorAction SilentlyContinue
        }
        else {
            $env:OPENCLAW_LIFELOG_ROOT_FOR_INIT = $oldSetupRoot
        }
    }

    Write-Host "chezmoi init/apply completed with LIFELOG_ROOT: $Root"
}

$lifelogRoot = Get-NormalizedPath $Path
Assert-LifelogRoot -Root $lifelogRoot
Set-LifelogRootEnvironment -Root $lifelogRoot -Target $EnvironmentTarget
Invoke-ChezmoiRefresh -Root $lifelogRoot
Write-Host "LIFELOG_ROOT: $lifelogRoot"
