<#
.SYNOPSIS
    NixOS-WSL のインストールとセットアップを自動化するスクリプト

.DESCRIPTION
    以下の処理を実行します:
    1. NixOS-WSL のダウンロードとインポート
    2. Post-install セットアップの実行
    3. ハンドラーシステムによる自動設定:
       - WslConfig: .wslconfig の適用と VHD 拡張
       - Docker: Docker Desktop との WSL 連携
       - VscodeServer: VS Code Server のキャッシュ削除と事前インストール
       - Chezmoi: chezmoi による dotfiles 適用
       - Winget: パッケージ管理

.PARAMETER DistroName
    WSL ディストリビューション名（デフォルト: NixOS）

.PARAMETER InstallDir
    WSL インストール先ディレクトリ（デフォルト: $env:USERPROFILE\NixOS）

.PARAMETER ReleaseTag
    NixOS-WSL のリリースタグ（指定しない場合は latest）

.PARAMETER PostInstallScript
    Post-install スクリプトのパス

.PARAMETER Options
    ハンドラーオプションのハッシュテーブル
    例: @{ SkipWslConfigApply = $true; DockerIntegrationRetries = 10 }

.PARAMETER SyncMode
    Post-install スクリプトの --sync-mode オプション（デフォルト: link）

.PARAMETER SyncBack
    Post-install スクリプトの --sync-back オプション（デフォルト: lock）

.PARAMETER SkipWslBaseInstall
    [非推奨] WSL 基盤インストールをスキップ（-Options で指定してください）

.PARAMETER SkipPostInstallSetup
    [非推奨] Post-install セットアップをスキップ（-Options で指定してください）

.PARAMETER SkipSetDefaultDistro
    [非推奨] デフォルトディストリビューション設定をスキップ（-Options で指定してください）

.PARAMETER DockerIntegrationRetries
    [非推奨] Docker Desktop 連携のリトライ回数（-Options で指定してください）

.PARAMETER DockerIntegrationRetryDelaySeconds
    [非推奨] Docker Desktop 連携のリトライ間隔（-Options で指定してください）

.PARAMETER SkipWslConfigApply
    [非推奨] .wslconfig 適用をスキップ（-Options で指定してください）

.PARAMETER SkipVhdExpand
    [非推奨] VHD 拡張をスキップ（-Options で指定してください）

.PARAMETER SkipVscodeServerClean
    [非推奨] VS Code Server キャッシュ削除をスキップ（-Options で指定してください）

.PARAMETER SkipVscodeServerPreinstall
    [非推奨] VS Code Server 事前インストールをスキップ（-Options で指定してください）

.EXAMPLE
    .\install.ps1

.EXAMPLE
    .\install.ps1 -DistroName "MyNixOS" -InstallDir "D:\WSL\MyNixOS"

.EXAMPLE
    .\install.ps1 -Options @{ SkipWslConfigApply = $true; SkipVhdExpand = $true }
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

    # Deprecated parameters (backward compatibility)
    [switch]$SkipWslBaseInstall,
    [switch]$SkipPostInstallSetup,
    [switch]$SkipSetDefaultDistro,
    [int]$DockerIntegrationRetries = -1,
    [int]$DockerIntegrationRetryDelaySeconds = -1,
    [switch]$SkipWslConfigApply,
    [switch]$SkipVhdExpand,
    [switch]$SkipVscodeServerClean,
    [switch]$SkipVscodeServerPreinstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ========================================
# Library Loading
# ========================================
$libPath = Join-Path $PSScriptRoot "scripts\powershell\lib"
. (Join-Path $libPath "SetupHandler.ps1")
. (Join-Path $libPath "Invoke-ExternalCommand.ps1")

# ========================================
# Backward Compatibility Layer
# ========================================
if ($PSBoundParameters.ContainsKey('SkipWslBaseInstall'))
{
    Write-Warning "-SkipWslBaseInstall is deprecated. Use -Options @{ SkipWslBaseInstall = `$true } instead."
    $Options['SkipWslBaseInstall'] = $SkipWslBaseInstall.IsPresent
}
if ($PSBoundParameters.ContainsKey('SkipPostInstallSetup'))
{
    Write-Warning "-SkipPostInstallSetup is deprecated. Use -Options @{ SkipPostInstallSetup = `$true } instead."
    $Options['SkipPostInstallSetup'] = $SkipPostInstallSetup.IsPresent
}
if ($PSBoundParameters.ContainsKey('SkipSetDefaultDistro'))
{
    Write-Warning "-SkipSetDefaultDistro is deprecated. Use -Options @{ SkipSetDefaultDistro = `$true } instead."
    $Options['SkipSetDefaultDistro'] = $SkipSetDefaultDistro.IsPresent
}
if ($PSBoundParameters.ContainsKey('DockerIntegrationRetries') -and $DockerIntegrationRetries -ge 0)
{
    Write-Warning "-DockerIntegrationRetries is deprecated. Use -Options @{ DockerIntegrationRetries = N } instead."
    $Options['DockerIntegrationRetries'] = $DockerIntegrationRetries
}
if ($PSBoundParameters.ContainsKey('DockerIntegrationRetryDelaySeconds') -and $DockerIntegrationRetryDelaySeconds -ge 0)
{
    Write-Warning "-DockerIntegrationRetryDelaySeconds is deprecated. Use -Options @{ DockerIntegrationRetryDelaySeconds = N } instead."
    $Options['DockerIntegrationRetryDelaySeconds'] = $DockerIntegrationRetryDelaySeconds
}
if ($PSBoundParameters.ContainsKey('SkipWslConfigApply'))
{
    Write-Warning "-SkipWslConfigApply is deprecated. Use -Options @{ SkipWslConfigApply = `$true } instead."
    $Options['SkipWslConfigApply'] = $SkipWslConfigApply.IsPresent
}
if ($PSBoundParameters.ContainsKey('SkipVhdExpand'))
{
    Write-Warning "-SkipVhdExpand is deprecated. Use -Options @{ SkipVhdExpand = `$true } instead."
    $Options['SkipVhdExpand'] = $SkipVhdExpand.IsPresent
}
if ($PSBoundParameters.ContainsKey('SkipVscodeServerClean'))
{
    Write-Warning "-SkipVscodeServerClean is deprecated. Use -Options @{ SkipVscodeServerClean = `$true } instead."
    $Options['SkipVscodeServerClean'] = $SkipVscodeServerClean.IsPresent
}
if ($PSBoundParameters.ContainsKey('SkipVscodeServerPreinstall'))
{
    Write-Warning "-SkipVscodeServerPreinstall is deprecated. Use -Options @{ SkipVscodeServerPreinstall = `$true } instead."
    $Options['SkipVscodeServerPreinstall'] = $SkipVscodeServerPreinstall.IsPresent
}

# Set default PostInstallScript if not provided
if (-not $PSBoundParameters.ContainsKey("PostInstallScript"))
{
    $PostInstallScript = Join-Path $PSScriptRoot "scripts\sh\nixos-wsl-postinstall.sh"
}

# ========================================
# Phase 1: Handler System Execution
# ========================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Phase 1: Handler System Execution" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$context = [SetupContext]::new($PSScriptRoot)
$context.DistroName = $DistroName
$context.InstallDir = $InstallDir

# Merge all options into context
foreach ($key in $Options.Keys)
{
    $context.Options[$key] = $Options[$key]
}

# Add additional parameters for NixOSWSL handler
$context.Options['ReleaseTag'] = $ReleaseTag
$context.Options['PostInstallScript'] = $PostInstallScript
$context.Options['SyncMode'] = $SyncMode
$context.Options['SyncBack'] = $SyncBack

# Load and execute handlers
$handlersPath = Join-Path $PSScriptRoot "scripts\powershell\handlers"
$handlers = Get-SetupHandler -HandlersPath $handlersPath
$handlers = Select-SetupHandler -Handlers $handlers
$results = Invoke-SetupHandler -Handlers $handlers -Context $context

# ========================================
# Phase 2: Final Processing
# ========================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Phase 2: Final Processing" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($Options['SkipSetDefaultDistro'] -ne $true)
{
    Write-Host "Setting default distro: $DistroName"
    & wsl --set-default $DistroName
}

$expandDockerVhd = Join-Path $PSScriptRoot "windows\expand-docker-vhd.ps1"
if (Test-Path -LiteralPath $expandDockerVhd)
{
    Write-Host "Expanding Docker Desktop VHDX..."
    & $expandDockerVhd -Force
}

# ========================================
# Phase 3: Summary
# ========================================
Show-SetupSummary -Results $results

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Launch NixOS: wsl -d $DistroName" -ForegroundColor Cyan
Write-Host ""
Write-Host "Press Enter to close..." -ForegroundColor Gray
Read-Host | Out-Null
