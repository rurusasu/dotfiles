<#
.SYNOPSIS
    Helper functions for NixOS-WSL installation

.DESCRIPTION
    Extracted from install.ps1 to improve modularity and testability.
    Provides functions for:
    - Admin privilege management
    - WSL installation and verification
    - NixOS-WSL release download
    - Distro installation (import/from-file)
    - Post-install setup
#>

<#
.SYNOPSIS
    Ensure script is running with administrator privileges

.DESCRIPTION
    Checks if the current process has admin rights.
    If not, re-launches the script with UAC elevation.

.EXAMPLE
    Assert-Admin
#>
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

<#
.SYNOPSIS
    Ensure WSL is installed and ready to use

.DESCRIPTION
    Checks WSL status and installs if necessary.
    May require system restart.

.PARAMETER SkipWslBaseInstall
    If true, skip WSL installation and throw error if not available

.EXAMPLE
    Ensure-WslReady
#>
function Ensure-WslReady
{
    param([switch]$SkipWslBaseInstall)

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

<#
.SYNOPSIS
    Get WSL version number

.OUTPUTS
    System.Version or $null if version cannot be determined

.EXAMPLE
    $ver = Get-WslVersion
    if ($ver -ge [version]"2.4.4.0") { ... }
#>
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

<#
.SYNOPSIS
    Check if WSL supports --install --from-file command

.DESCRIPTION
    Requires WSL 2.4.4+

.OUTPUTS
    Boolean indicating support

.EXAMPLE
    if (Supports-FromFileInstall) { ... }
#>
function Supports-FromFileInstall
{
    $ver = Get-WslVersion
    if ($ver -and $ver -ge [version]"2.4.4.0")
    {
        return $true
    }
    # Fallback: detect help text
    $help = & wsl --help 2>&1
    return ($help -match "--install --from-file")
}

<#
.SYNOPSIS
    Fetch a NixOS-WSL release from GitHub

.PARAMETER Tag
    Release tag name (empty for latest)

.OUTPUTS
    GitHub release object

.EXAMPLE
    $release = Get-Release -Tag "v24.5.1"
    $release = Get-Release  # Latest
#>
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

<#
.SYNOPSIS
    Select the appropriate installer asset from a release

.PARAMETER Release
    GitHub release object

.OUTPUTS
    Asset object

.EXAMPLE
    $asset = Select-Asset -Release $release
#>
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

<#
.SYNOPSIS
    Download an asset from GitHub

.PARAMETER Asset
    Asset object with download URL

.OUTPUTS
    Path to downloaded file in %TEMP%

.EXAMPLE
    $path = Download-Asset -Asset $asset
#>
function Download-Asset
{
    param($Asset)
    $destination = Join-Path $env:TEMP $Asset.name
    Write-Host "最新のアーカイブをダウンロードします: $($Asset.name)"
    Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $destination -UseBasicParsing
    return $destination
}

<#
.SYNOPSIS
    Ensure installation directory exists and is empty

.PARAMETER Path
    Directory path to validate/create

.EXAMPLE
    Ensure-InstallDir -Path "C:\WSL\NixOS"
#>
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

<#
.SYNOPSIS
    Check if a WSL distro is already registered

.PARAMETER Name
    Distro name

.OUTPUTS
    Boolean

.EXAMPLE
    if (Distro-Exists -Name "NixOS") { ... }
#>
function Distro-Exists
{
    param([string]$Name)
    $list = & wsl --list --quiet | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    return $list -contains $Name
}

<#
.SYNOPSIS
    Import a WSL distro using wsl --import

.PARAMETER Name
    Distro name

.PARAMETER Dir
    Installation directory

.PARAMETER Archive
    Path to .tar.gz archive

.EXAMPLE
    Import-Distro -Name "NixOS" -Dir "C:\WSL\NixOS" -Archive "nixos.tar.gz"
#>
function Import-Distro
{
    param([string]$Name, [string]$Dir, [string]$Archive)
    Write-Host "WSL ディストリビューションをインポートします: $Name -> $Dir"
    Ensure-InstallDir -Path $Dir
    & wsl --import $Name $Dir $Archive --version 2
}

<#
.SYNOPSIS
    Install a WSL distro using wsl --install --from-file (WSL 2.4.4+)

.PARAMETER Name
    Distro name

.PARAMETER Archive
    Path to .wsl file

.PARAMETER Location
    Optional installation directory

.EXAMPLE
    Install-FromFile -Name "NixOS" -Archive "nixos.wsl" -Location "C:\WSL\NixOS"
#>
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

<#
.SYNOPSIS
    Execute post-install setup script in WSL

.PARAMETER Name
    Distro name

.PARAMETER ScriptPath
    Path to post-install script

.PARAMETER SyncMode
    Chezmoi sync mode (default: link)

.PARAMETER SyncBack
    Chezmoi sync back mode (default: lock)

.PARAMETER SkipPostInstallSetup
    Skip execution

.EXAMPLE
    Invoke-PostInstallSetup -Name "NixOS" -ScriptPath ".\postinstall.sh"
#>
function Invoke-PostInstallSetup
{
    param(
        [string]$Name,
        [string]$ScriptPath,
        [string]$SyncMode = "link",
        [string]$SyncBack = "lock",
        [switch]$SkipPostInstallSetup
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

<#
.SYNOPSIS
    Create whoami symlinks in WSL

.PARAMETER Name
    Distro name

.EXAMPLE
    Ensure-WhoamiShim -Name "NixOS"
#>
function Ensure-WhoamiShim
{
    param([string]$Name)
    $cmd = "if [ -x /run/current-system/sw/bin/whoami ]; then " +
    "ln -sf /run/current-system/sw/bin/whoami /bin/whoami; " +
    "ln -sf /run/current-system/sw/bin/whoami /usr/bin/whoami; fi"
    & wsl -d $Name -u root -- sh -lc $cmd
}

<#
.SYNOPSIS
    Verify WSL filesystem is writable

.PARAMETER Name
    Distro name

.EXAMPLE
    Ensure-WslWritable -Name "NixOS"
#>
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
