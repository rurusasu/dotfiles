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

.PARAMETER DistroName
    WSL ディストリビューション名（デフォルト: NixOS）

.PARAMETER InstallDir
    WSL インストール先ディレクトリ（デフォルト: $env:USERPROFILE\NixOS）

.PARAMETER ReleaseTag
    NixOS-WSL のリリースタグ（指定しない場合は latest）

.PARAMETER SkipWslBaseInstall
    WSL 基盤インストールをスキップ

.PARAMETER PostInstallScript
    Post-install スクリプトのパス

.PARAMETER SkipPostInstallSetup
    Post-install セットアップをスキップ

.PARAMETER SkipSetDefaultDistro
    デフォルトディストリビューション設定をスキップ

.PARAMETER DockerIntegrationRetries
    Docker Desktop 連携のリトライ回数（デフォルト: 5）

.PARAMETER DockerIntegrationRetryDelaySeconds
    Docker Desktop 連携のリトライ間隔（秒）（デフォルト: 5）

.PARAMETER SkipWslConfigApply
    .wslconfig 適用をスキップ

.PARAMETER SkipVhdExpand
    VHD 拡張をスキップ

.PARAMETER SkipVscodeServerClean
    VS Code Server キャッシュ削除をスキップ

.PARAMETER SkipVscodeServerPreinstall
    VS Code Server 事前インストールをスキップ

.PARAMETER SyncMode
    Post-install スクリプトの --sync-mode オプション（デフォルト: link）

.PARAMETER SyncBack
    Post-install スクリプトの --sync-back オプション（デフォルト: lock）

.EXAMPLE
    .\install.ps1

.EXAMPLE
    .\install.ps1 -DistroName "MyNixOS" -InstallDir "D:\WSL\MyNixOS"

.EXAMPLE
    .\install.ps1 -SkipWslConfigApply -SkipVhdExpand
#>

[CmdletBinding()]
param(
    [string]$DistroName = "NixOS",
    [string]$InstallDir = "$env:USERPROFILE\NixOS",
    [string]$ReleaseTag = "",
    [switch]$SkipWslBaseInstall,
    [string]$PostInstallScript = "",
    [switch]$SkipPostInstallSetup,
    [switch]$SkipSetDefaultDistro,
    [int]$DockerIntegrationRetries = 5,
    [int]$DockerIntegrationRetryDelaySeconds = 5,
    [switch]$SkipWslConfigApply,
    [switch]$SkipVhdExpand,
    [switch]$SkipVscodeServerClean,
    [switch]$SkipVscodeServerPreinstall,
    [ValidateSet("link", "repo", "nix", "none")]
    [string]$SyncMode = "link",
    [ValidateSet("repo", "lock", "none")]
    [string]$SyncBack = "lock"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $PSBoundParameters.ContainsKey("PostInstallScript"))
{
    $PostInstallScript = Join-Path $PSScriptRoot "scripts\sh\nixos-wsl-postinstall.sh"
}

function Assert-Admin
{
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator))
    {
        Write-Host "管理者権限が必要です。UAC プロンプトを表示します..." -ForegroundColor Yellow
        $scriptPath = $PSCommandPath
        $arguments = @("-NoProfile", "-NoExit", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptPath`"")
        foreach ($key in $PSBoundParameters.Keys)
        {
            $value = $PSBoundParameters[$key]
            if ($value -is [switch])
            {
                if ($value)
                { $arguments += "-$key"
                }
            } else
            {
                $arguments += "-$key"
                $arguments += "`"$value`""
            }
        }
        Start-Process pwsh -ArgumentList $arguments -Verb RunAs
        exit 0
    }
}

function Ensure-WslReady
{
    Write-Host "WSL の状態を確認しています..."
    $statusOutput = & wsl --status 2>&1
    if ($LASTEXITCODE -eq 0)
    {
        return
    }
    if ($statusOutput -match "Unrecognized option" -or $statusOutput -match "invalid command line option")
    {
        & wsl -l -q 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0)
        {
            return
        }
    }
    if ($SkipWslBaseInstall)
    {
        throw "WSL が有効化されていません。SkipWslBaseInstall を外すか、手動で有効化してください。"
    }
    Write-Host "WSL 基盤をインストールします (再起動が必要になる場合があります)..."
    & wsl --install --no-distribution
    Write-Warning "WSL の有効化を完了するため、Windows を再起動してから再度このスクリプトを実行してください。"
    exit 0
}

function Get-WslVersion
{
    $output = & wsl --version 2>&1
    if ($LASTEXITCODE -ne 0)
    {
        return $null
    }
    if ($output -match "WSL version:\\s*([0-9\\.]+)")
    {
        try
        { return [version]$Matches[1]
        } catch
        { return $null
        }
    }
    return $null
}

function Supports-FromFileInstall
{
    $ver = Get-WslVersion
    if ($ver -and $ver -ge [version]"2.4.4.0")
    {
        return $true
    }
    # fallback: detect help text just in case parsing failed
    $help = & wsl --help 2>&1
    return ($help -match "--install --from-file")
}

function Get-Release
{
    param([string]$Tag)
    $base = "https://api.github.com/repos/nix-community/NixOS-WSL/releases"
    $uri = if ([string]::IsNullOrWhiteSpace($Tag))
    { "$base/latest"
    } else
    { "$base/tags/$Tag"
    }
    return Invoke-RestMethod -Uri $uri -Headers @{ "User-Agent" = "nixos-wsl-installer" }
}

function Select-Asset
{
    param($Release)
    $priority = @("nixos.wsl", "nixos-wsl.tar.gz", "nixos-wsl-legacy.tar.gz")
    foreach ($name in $priority)
    {
        $asset = $Release.assets | Where-Object { $_.name -eq $name } | Select-Object -First 1
        if ($asset)
        {
            return $asset
        }
    }
    throw "Release $($Release.tag_name) に利用可能なアーカイブが見つかりません。"
}

function Download-Asset
{
    param($Asset)
    $destination = Join-Path $env:TEMP $Asset.name
    Write-Host "最新のアーカイブをダウンロードします: $($Asset.name)"
    Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $destination -UseBasicParsing
    return $destination
}

function Ensure-InstallDir
{
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path))
    {
        New-Item -ItemType Directory -Path $Path | Out-Null
        return
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Container))
    {
        throw "指定したインストール先 $Path はディレクトリではありません。"
    }
    if ((Get-ChildItem -LiteralPath $Path -Force | Measure-Object).Count -gt 0)
    {
        throw "インストール先 $Path が空ではありません。空のディレクトリを指定するか、既存の内容を移動してください。"
    }
}

function Distro-Exists
{
    param([string]$Name)
    $list = & wsl --list --quiet | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    return $list -contains $Name
}

function Import-Distro
{
    param([string]$Name, [string]$Dir, [string]$Archive)
    Write-Host "WSL ディストリビューションをインポートします: $Name -> $Dir"
    Ensure-InstallDir -Path $Dir
    & wsl --import $Name $Dir $Archive --version 2
}

function Install-FromFile
{
    param(
        [string]$Name,
        [string]$Archive,
        [string]$Location
    )
    Write-Host "WSL 2.4.4+ の手順で登録します: wsl --install --from-file ..."
    $args = @("--install", "--from-file", $Archive, "--name", $Name)
    if ($Location)
    {
        Ensure-InstallDir -Path $Location
        $args += @("--location", $Location)
    }
    & wsl @args
}

function Invoke-PostInstallSetup
{
    param(
        [string]$Name,
        [string]$ScriptPath
    )
    if ($SkipPostInstallSetup)
    {
        Write-Host "Post-install セットアップをスキップしました。"
        return
    }
    if ([string]::IsNullOrWhiteSpace($ScriptPath))
    {
        return
    }
    if (-not (Test-Path -LiteralPath $ScriptPath))
    {
        Write-Warning "Post-install スクリプトが見つかりません: $ScriptPath"
        return
    }
    $resolved = (Resolve-Path -LiteralPath $ScriptPath).Path
    $wslPath = & wsl wslpath -a $resolved 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($wslPath))
    {
        $drive = [IO.Path]::GetPathRoot($resolved).TrimEnd(":\")
        $rest = $resolved.Substring(2) -replace "\\", "/"
        $fallback = "/mnt/$($drive.ToLower())$rest"
        $wslPath = $fallback
    }
    Write-Host "Post-install セットアップを実行します..."
    $cmd = "bash `"$wslPath`" --force --sync-mode $SyncMode --sync-back $SyncBack"
    & wsl -d $Name -u root -- sh -lc $cmd
}

function Ensure-WhoamiShim
{
    param([string]$Name)
    $cmd = "if [ -x /run/current-system/sw/bin/whoami ]; then " +
    "ln -sf /run/current-system/sw/bin/whoami /bin/whoami; " +
    "ln -sf /run/current-system/sw/bin/whoami /usr/bin/whoami; fi"
    & wsl -d $Name -u root -- sh -lc $cmd
}


Assert-Admin
Ensure-WslReady

$release = Get-Release -Tag $ReleaseTag
$asset = Select-Asset -Release $release
$archivePath = Download-Asset -Asset $asset

$supportsFromFile = Supports-FromFileInstall -and $asset.name -like "*.wsl"

if (Distro-Exists -Name $DistroName)
{
    Write-Warning "WSL ディストリビューション '$DistroName' はすでに登録されています。インポートをスキップします。"
} else
{
    if ($supportsFromFile)
    {
        try
        {
            $location = if ($PSBoundParameters.ContainsKey("InstallDir"))
            { $InstallDir
            } else
            { $null
            }
            Install-FromFile -Name $DistroName -Archive $archivePath -Location $location
        } catch
        {
            Write-Warning "wsl --install --from-file に失敗しました。古い WSL 手順 (--import) で再試行します。`n$($_.Exception.Message)"
            Import-Distro -Name $DistroName -Dir $InstallDir -Archive $archivePath
        }
    } else
    {
        Import-Distro -Name $DistroName -Dir $InstallDir -Archive $archivePath
    }
}

function Ensure-WslWritable
{
    param([string]$Name)
    $writableCheck = "touch /tmp/.wsl-write-test 2>/dev/null && rm -f /tmp/.wsl-write-test"
    & wsl -d $Name -u root -- sh -lc $writableCheck
    if ($LASTEXITCODE -ne 0)
    {
        Write-Warning "WSL が読み取り専用です。VHD 拡張は WslConfig ハンドラーで処理されます。"
    }
}
# Post-install セットアップの実行
Invoke-PostInstallSetup -Name $DistroName -ScriptPath $PostInstallScript

# WSL の書き込み可能状態を確保
Ensure-WslWritable -Name $DistroName

# whoami シムのセットアップ
Ensure-WhoamiShim -Name $DistroName

# ========================================
# ハンドラーシステムによる自動設定
# ========================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ハンドラーシステムによる自動設定を開始" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ハンドラーシステムのロード
$libPath = Join-Path $PSScriptRoot "scripts\powershell\lib"
. (Join-Path $libPath "SetupHandler.ps1")
. (Join-Path $libPath "Invoke-ExternalCommand.ps1")

# セットアップコンテキストの作成
$context = [SetupContext]::new($PSScriptRoot)
$context.DistroName = $DistroName
$context.InstallDir = $InstallDir

# オプションの設定
$context.Options["SkipWslConfigApply"] = $SkipWslConfigApply.IsPresent
$context.Options["SkipVhdExpand"] = $SkipVhdExpand.IsPresent
$context.Options["SkipVscodeServerClean"] = $SkipVscodeServerClean.IsPresent
$context.Options["SkipVscodeServerPreinstall"] = $SkipVscodeServerPreinstall.IsPresent
$context.Options["DockerIntegrationRetries"] = $DockerIntegrationRetries
$context.Options["DockerIntegrationRetryDelaySeconds"] = $DockerIntegrationRetryDelaySeconds

# ハンドラーの読み込み
$handlersPath = Join-Path $PSScriptRoot "scripts\powershell\handlers"
$handlerFiles = Get-ChildItem -LiteralPath $handlersPath -Filter "Handler.*.ps1" -ErrorAction SilentlyContinue

$handlers = @()
foreach ($file in $handlerFiles) {
    try {
        . $file.FullName

        # クラス名を推測（例: Handler.WslConfig.ps1 -> WslConfigHandler）
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $className = $baseName.Replace("Handler.", "") + "Handler"

        # ハンドラーインスタンスの作成
        $handlerInstance = New-Object $className
        $handlers += $handlerInstance

        Write-Host "[Load] $($handlerInstance.Name) (Order: $($handlerInstance.Order))" -ForegroundColor Gray
    } catch {
        Write-Warning "ハンドラーの読み込みに失敗しました: $($file.Name) - $($_.Exception.Message)"
    }
}

# 実行順序でソート
$handlers = $handlers | Sort-Object Order

# ハンドラーの実行
$results = @()
foreach ($handler in $handlers) {
    Write-Host ""
    Write-Host "[$($handler.Name)] $($handler.Description)" -ForegroundColor Cyan

    # 実行可否の判定
    if (-not $handler.CanApply($context)) {
        Write-Host "[$($handler.Name)] スキップします" -ForegroundColor Gray
        continue
    }

    # 実行
    try {
        $result = $handler.Apply($context)
        $results += $result

        if ($result.Success) {
            Write-Host "[$($handler.Name)] ✓ $($result.Message)" -ForegroundColor Green
        } else {
            Write-Host "[$($handler.Name)] ✗ $($result.Message)" -ForegroundColor Red
            if ($result.Error) {
                Write-Host "[$($handler.Name)] エラー詳細: $($result.Error.Message)" -ForegroundColor Red
            }
        }
    } catch {
        $result = [SetupResult]::CreateFailure($handler.Name, $_.Exception.Message, $_.Exception)
        $results += $result
        Write-Host "[$($handler.Name)] ✗ 例外が発生しました: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ========================================
# 最終処理
# ========================================

if (-not $SkipSetDefaultDistro) {
    Write-Host ""
    Write-Host "WSL の既定ディストリビューションを設定します: $DistroName" -ForegroundColor Cyan
    & wsl --set-default $DistroName
}

# Docker Desktop VHDX 拡張
$expandDockerVhd = Join-Path $PSScriptRoot "windows\expand-docker-vhd.ps1"
if (Test-Path -LiteralPath $expandDockerVhd) {
    Write-Host ""
    Write-Host "Docker Desktop VHDX サイズを確認しています..." -ForegroundColor Cyan
    & $expandDockerVhd -Force
}

# ========================================
# 結果サマリー
# ========================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "セットアップ完了" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# 成功・失敗の集計
$successCount = ($results | Where-Object { $_.Success }).Count
$failureCount = ($results | Where-Object { -not $_.Success }).Count

Write-Host "実行結果: $successCount 件成功, $failureCount 件失敗" -ForegroundColor $(if ($failureCount -eq 0) { "Green" } else { "Yellow" })
Write-Host ""

if ($failureCount -gt 0) {
    Write-Host "失敗したハンドラー:" -ForegroundColor Yellow
    foreach ($result in $results | Where-Object { -not $_.Success }) {
        Write-Host "  - $($result.HandlerName): $($result.Message)" -ForegroundColor Yellow
    }
    Write-Host ""
}

Write-Host "NixOS を起動するには: wsl -d $DistroName" -ForegroundColor Cyan
Write-Host ""
Write-Host "Enter を押すとこのウィンドウを閉じます..." -ForegroundColor Gray
Read-Host | Out-Null
