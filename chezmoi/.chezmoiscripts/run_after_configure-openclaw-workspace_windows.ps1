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
