[CmdletBinding()]
param(
    [string]$DistroName = "NixOS",
    [string]$InstallDir = "$env:USERPROFILE\\NixOS",
    [string]$ReleaseTag = "",
    [switch]$SkipWslBaseInstall,
    [switch]$SkipChannelUpdate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Admin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        throw "PowerShell を管理者として実行してください。"
    }
}

function Ensure-WslReady {
    Write-Host "WSL の状態を確認しています..."
    $statusOutput = & wsl --status 2>&1
    if ($LASTEXITCODE -eq 0) {
        return
    }
    if ($statusOutput -match "Unrecognized option" -or $statusOutput -match "invalid command line option") {
        & wsl -l -q 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            return
        }
    }
    if ($SkipWslBaseInstall) {
        throw "WSL が有効化されていません。SkipWslBaseInstall を外すか、手動で有効化してください。"
    }
    Write-Host "WSL 基盤をインストールします (再起動が必要になる場合があります)..."
    & wsl --install --no-distribution
    Write-Warning "WSL の有効化を完了するため、Windows を再起動してから再度このスクリプトを実行してください。"
    exit 0
}

function Get-WslVersion {
    $output = & wsl --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        return $null
    }
    if ($output -match "WSL version:\\s*([0-9\\.]+)") {
        try { return [version]$Matches[1] } catch { return $null }
    }
    return $null
}

function Supports-FromFileInstall {
    $ver = Get-WslVersion
    if ($ver -and $ver -ge [version]"2.4.4.0") {
        return $true
    }
    # fallback: detect help text just in case parsing failed
    $help = & wsl --help 2>&1
    return ($help -match "--install --from-file")
}

function Get-Release {
    param([string]$Tag)
    $base = "https://api.github.com/repos/nix-community/NixOS-WSL/releases"
    $uri = if ([string]::IsNullOrWhiteSpace($Tag)) { "$base/latest" } else { "$base/tags/$Tag" }
    return Invoke-RestMethod -Uri $uri -Headers @{ "User-Agent" = "nixos-wsl-installer" }
}

function Select-Asset {
    param($Release)
    $priority = @("nixos.wsl", "nixos-wsl.tar.gz", "nixos-wsl-legacy.tar.gz")
    foreach ($name in $priority) {
        $asset = $Release.assets | Where-Object { $_.name -eq $name } | Select-Object -First 1
        if ($asset) {
            return $asset
        }
    }
    throw "Release $($Release.tag_name) に利用可能なアーカイブが見つかりません。"
}

function Download-Asset {
    param($Asset)
    $destination = Join-Path $env:TEMP $Asset.name
    Write-Host "最新のアーカイブをダウンロードします: $($Asset.name)"
    Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $destination -UseBasicParsing
    return $destination
}

function Ensure-InstallDir {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
        return
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "指定したインストール先 $Path はディレクトリではありません。"
    }
    if ((Get-ChildItem -LiteralPath $Path -Force | Measure-Object).Count -gt 0) {
        throw "インストール先 $Path が空ではありません。空のディレクトリを指定するか、既存の内容を移動してください。"
    }
}

function Distro-Exists {
    param([string]$Name)
    $list = & wsl --list --quiet | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    return $list -contains $Name
}

function Import-Distro {
    param([string]$Name, [string]$Dir, [string]$Archive)
    Write-Host "WSL ディストリビューションをインポートします: $Name -> $Dir"
    Ensure-InstallDir -Path $Dir
    & wsl --import $Name $Dir $Archive --version 2
}

function Install-FromFile {
    param(
        [string]$Name,
        [string]$Archive,
        [string]$Location
    )
    Write-Host "WSL 2.4.4+ の手順で登録します: wsl --install --from-file ..."
    $args = @("--install", "--from-file", $Archive, "--name", $Name)
    if ($Location) {
        Ensure-InstallDir -Path $Location
        $args += @("--location", $Location)
    }
    & wsl @args
}

function Run-PostInstall {
    param([string]$Name)
    Write-Host "NixOS 内でチャンネル更新と再構成を実行します..."
    & wsl -d $Name -u root -- sh -lc "nix-channel --update && nixos-rebuild switch"
}

Assert-Admin
Ensure-WslReady

$release = Get-Release -Tag $ReleaseTag
$asset = Select-Asset -Release $release
$archivePath = Download-Asset -Asset $asset

$supportsFromFile = Supports-FromFileInstall -and $asset.name -like "*.wsl"

if (Distro-Exists -Name $DistroName) {
    Write-Warning "WSL ディストリビューション '$DistroName' はすでに登録されています。インポートをスキップします。"
} else {
    if ($supportsFromFile) {
        try {
            $location = if ($PSBoundParameters.ContainsKey("InstallDir")) { $InstallDir } else { $null }
            Install-FromFile -Name $DistroName -Archive $archivePath -Location $location
        } catch {
            Write-Warning "wsl --install --from-file に失敗しました。古い WSL 手順 (--import) で再試行します。`n$($_.Exception.Message)"
            Import-Distro -Name $DistroName -Dir $InstallDir -Archive $archivePath
        }
    } else {
        Import-Distro -Name $DistroName -Dir $InstallDir -Archive $archivePath
    }
}

if ($SkipChannelUpdate) {
    Write-Host "チャンネル更新をスキップしました。"
} else {
    Run-PostInstall -Name $DistroName
}

Write-Host "完了しました。NixOS を起動するには: wsl -d $DistroName"
