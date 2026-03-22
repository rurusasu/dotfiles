<#
.SYNOPSIS
    Dotfiles setup orchestrator.

.DESCRIPTION
    Runs setup in two phases:
    1. User phase (no elevation): install.user.ps1
    2. Admin phase (elevate only when required): install.admin.ps1

#>

[CmdletBinding()]
param(
    [string]$DistroName = "NixOS",
    [string]$InstallDir = "$env:USERPROFILE\NixOS",
    [string]$ReleaseTag = "",
    [string]$PostInstallScript = "",
    [hashtable]$Options = @{},
    [ValidateSet("link", "repo", "nix", "none")]
    [string]$SyncMode = "link",
    [ValidateSet("repo", "lock", "none")]
    [string]$SyncBack = "lock",
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

function Test-IsAdminCurrent {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Get-PhaseParameters {
    [CmdletBinding()]
    param()

    return @{
        DistroName       = $DistroName
        InstallDir       = $InstallDir
        ReleaseTag       = $ReleaseTag
        PostInstallScript = $PostInstallScript
        Options          = $Options
        SyncMode         = $SyncMode
        SyncBack         = $SyncBack
    }
}

$userScriptPath = Join-Path $PSScriptRoot "install.user.ps1"
$adminScriptPath = Join-Path $PSScriptRoot "install.admin.ps1"

if (-not (Test-Path -LiteralPath $userScriptPath)) {
    throw "User phase script not found: $userScriptPath"
}
if (-not (Test-Path -LiteralPath $adminScriptPath)) {
    throw "Admin phase script not found: $adminScriptPath"
}

$phaseParams = Get-PhaseParameters

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Phase 1: User Scope Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

& $userScriptPath @phaseParams


Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Phase 2: Admin Setup Check" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$adminRequired = [bool](& $adminScriptPath @phaseParams -CheckOnly)

if ($adminRequired) {
    Write-Host "Admin-required tasks detected." -ForegroundColor Yellow

    if (Test-IsAdminCurrent) {
        Write-Host "Already running as administrator. Executing admin phase in-process." -ForegroundColor Cyan
        & $adminScriptPath @phaseParams
    }
    else {
        Write-Host "Starting admin phase with UAC prompt..." -ForegroundColor Yellow

        $shell = if (Get-Command pwsh -ErrorAction SilentlyContinue) {
            "pwsh"
        }
        else {
            "powershell.exe"
        }

        $optionsJson = if ($null -eq $Options -or $Options.Count -eq 0) {
            "{}"
        }
        else {
            ConvertTo-Json -InputObject $Options -Depth 10 -Compress
        }

        $argList = @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $adminScriptPath,
            "-DistroName",
            $DistroName,
            "-InstallDir",
            $InstallDir,
            "-OptionsJson",
            $optionsJson,
            "-SyncMode",
            $SyncMode,
            "-SyncBack",
            $SyncBack
        )

        if (-not [string]::IsNullOrWhiteSpace($ReleaseTag)) {
            $argList += "-ReleaseTag"
            $argList += $ReleaseTag
        }
        if (-not [string]::IsNullOrWhiteSpace($PostInstallScript)) {
            $argList += "-PostInstallScript"
            $argList += $PostInstallScript
        }

        # 管理者昇格プロセスの出力をログファイルに記録し、終了後に表示
        # $env:TEMP はユーザーごとに異なるため、リポジトリルートの一時ファイルを使用
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
        $logFile = Join-Path $repoRoot ".admin-phase.log"
        if (Test-Path $logFile) { Remove-Item $logFile -Force }

        # admin スクリプトにログファイルパスを渡す
        $argList += "-LogFile"
        $argList += $logFile

        $proc = Start-Process -FilePath $shell -ArgumentList $argList -Verb RunAs -Wait -PassThru

        # ログファイルの内容を元のコンソールに表示
        if (Test-Path $logFile) {
            Write-Host ""
            Get-Content $logFile | ForEach-Object { Write-Host $_ }
        }

        if ($null -ne $proc -and $proc.ExitCode -ne 0) {
            throw "Admin phase failed with exit code $($proc.ExitCode)."
        }
    }
}
else {
    Write-Host "No admin-required tasks detected. Running admin phase without elevation." -ForegroundColor Green
    & $adminScriptPath @phaseParams
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Launch NixOS: wsl -d $DistroName" -ForegroundColor Cyan
Write-Host ""
if (-not $NoPause) {
    Write-Host "Press Enter to close..." -ForegroundColor Gray
    Read-Host | Out-Null
}
