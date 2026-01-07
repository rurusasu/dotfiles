[CmdletBinding()]
param(
    [string]$DistroName = "NixOS",
    [string]$InstallDir = "$env:USERPROFILE\\NixOS",
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

if (-not $PSBoundParameters.ContainsKey("PostInstallScript")) {
    $PostInstallScript = Join-Path $PSScriptRoot "scripts\sh\nixos-wsl-postinstall.sh"
}

function Assert-Admin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        Write-Host "管理者権限が必要です。UAC プロンプトを表示します..." -ForegroundColor Yellow
        $scriptPath = $PSCommandPath
        $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptPath`"")
        foreach ($key in $PSBoundParameters.Keys) {
            $value = $PSBoundParameters[$key]
            if ($value -is [switch]) {
                if ($value) { $arguments += "-$key" }
            } else {
                $arguments += "-$key"
                $arguments += "`"$value`""
            }
        }
        Start-Process pwsh -ArgumentList $arguments -Verb RunAs
        exit 0
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

function Invoke-PostInstallSetup {
    param(
        [string]$Name,
        [string]$ScriptPath
    )
    if ($SkipPostInstallSetup) {
        Write-Host "Post-install セットアップをスキップしました。"
        return
    }
    if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
        return
    }
    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        Write-Warning "Post-install スクリプトが見つかりません: $ScriptPath"
        return
    }
    $resolved = (Resolve-Path -LiteralPath $ScriptPath).Path
    $wslPath = & wsl wslpath -a $resolved 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($wslPath)) {
        $drive = [IO.Path]::GetPathRoot($resolved).TrimEnd(":\")
        $rest = $resolved.Substring(2) -replace "\\", "/"
        $fallback = "/mnt/$($drive.ToLower())$rest"
        $wslPath = $fallback
    }
    Write-Host "Post-install セットアップを実行します..."
    $cmd = "bash `"$wslPath`" --force --sync-mode $SyncMode --sync-back $SyncBack"
    & wsl -d $Name -u root -- sh -lc $cmd
}

function Ensure-WhoamiShim {
    param([string]$Name)
    $cmd = "if [ -x /run/current-system/sw/bin/whoami ]; then " +
           "ln -sf /run/current-system/sw/bin/whoami /bin/whoami; " +
           "ln -sf /run/current-system/sw/bin/whoami /usr/bin/whoami; fi"
    & wsl -d $Name -u root -- sh -lc $cmd
}

function Test-DockerDesktopProxy {
    param([string]$Name)
    $existsCmd = "[ -x /mnt/wsl/docker-desktop/docker-desktop-user-distro ]"
    & wsl -d $Name -u root -- sh -lc $existsCmd
    if ($LASTEXITCODE -ne 0) {
        return $false
    }
    $proxyCmd = "timeout 3 /mnt/wsl/docker-desktop/docker-desktop-user-distro proxy --distro-name nixos --docker-desktop-root /mnt/wsl/docker-desktop 'C:\Program Files\Docker\Docker\resources'"
    & wsl -d $Name -u root -- sh -lc $proxyCmd
    if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 124) {
        return $true
    }
    return $false
}

function Ensure-DockerDesktopIntegration {
    param(
        [string]$Name,
        [int]$Retries,
        [int]$DelaySeconds
    )
    if ($Retries -le 0) {
        return
    }
    $writableCheck = "touch /tmp/.wsl-write-test 2>/dev/null && rm -f /tmp/.wsl-write-test"
    & wsl -d $Name -u root -- sh -lc $writableCheck
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "WSL が書き込み不可のため、Docker Desktop 連携のリトライをスキップします。"
        return
    }
    $freeCheck = 'df -Pk / | awk ''NR==2 {print $4}'''
    $freeBlocks = & wsl -d $Name -u root -- sh -lc $freeCheck
    $freeBlocks = ($freeBlocks | Select-Object -First 1).Trim()
    $freeValue = 0
    if ($freeBlocks -and [int]::TryParse($freeBlocks, [ref]$freeValue) -and $freeValue -lt 10240) {
        Write-Warning "WSL の空き容量が不足しているため、Docker Desktop 連携のリトライをスキップします。"
        return
    }
    Ensure-DockerDesktopDistros
    Ensure-DockerGroup -Name $Name
    Start-DockerDesktopIfNeeded
    if (-not (Test-DockerDesktopHealth)) {
        Write-Warning "Docker Desktop 側の WSL ディストリビューションが壊れている可能性がありますが、連携の確認は続行します。"
    }
    $restarted = $false
    for ($i = 1; $i -le $Retries; $i++) {
        Write-Host "Docker Desktop 連携の確認を試行します ($i/$Retries)..."
        Start-DockerDesktopIfNeeded
        if (Test-DockerDesktopProxy -Name $Name) {
            Write-Host "Docker Desktop 連携の確認に成功しました。"
            return
        }
        Write-Warning "Docker Desktop 連携の確認に失敗しました。WSL を再起動して再試行します。"
        if (-not $restarted) {
            Restart-DockerDesktop
            $restarted = $true
        }
        & wsl --shutdown
        Start-Sleep -Seconds $DelaySeconds
    }
    Write-Warning "Docker Desktop 連携の確認に $Retries 回失敗しました。"
}

function Start-DockerDesktopIfNeeded {
    $running = Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue
    if (-not $running) {
        $running = Get-Process -Name "com.docker.backend" -ErrorAction SilentlyContinue
    }
    if ($running) {
        return
    }
    $dockerExe = Join-Path $env:ProgramFiles "Docker\\Docker\\Docker Desktop.exe"
    if (-not (Test-Path -LiteralPath $dockerExe)) {
        return
    }
    Write-Host "Docker Desktop を起動します..."
    Start-Process -FilePath $dockerExe | Out-Null
    Start-Sleep -Seconds 5
}

function Restart-DockerDesktop {
    $running = Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue
    $backend = Get-Process -Name "com.docker.backend" -ErrorAction SilentlyContinue
    if (-not $running -and -not $backend) {
        return
    }
    Write-Host "Docker Desktop を再起動します..."
    Stop-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue
    Stop-Process -Name "com.docker.backend" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
    Start-DockerDesktopIfNeeded
    Start-Sleep -Seconds 10
}

function Test-DockerDesktopHealth {
    $check = & wsl -d docker-desktop -u root -- sh -lc "test -f /opt/docker-desktop/componentsVersion.json"
    return ($LASTEXITCODE -eq 0)
}

function Ensure-DockerDesktopDistros {
    $dockerExe = Join-Path $env:ProgramFiles "Docker\\Docker\\Docker Desktop.exe"
    if (-not (Test-Path -LiteralPath $dockerExe)) {
        return
    }
    $list = & wsl -l -q 2>$null
    $names = @()
    if ($list) {
        $names = $list | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }
    if ($names -contains "docker-desktop" -and $names -contains "docker-desktop-data") {
        return
    }
    $resourceRoot = Join-Path $env:ProgramFiles "Docker\\Docker\\resources\\wsl"
    $vhdTemplate = Join-Path $resourceRoot "ext4.vhdx"
    $dataTar = Join-Path $resourceRoot "wsl-data.tar"
    if (-not (Test-Path -LiteralPath $vhdTemplate) -or -not (Test-Path -LiteralPath $dataTar)) {
        Write-Warning "Docker Desktop の WSL リソースが見つからないため、ディストリビューションの作成をスキップします。"
        return
    }
    $root = Join-Path $env:LOCALAPPDATA "Docker\\wsl"
    $distroDir = Join-Path $root "distro"
    $dataDir = Join-Path $root "data"
    New-Item -ItemType Directory -Path $distroDir,$dataDir -Force | Out-Null
    $distroVhd = Join-Path $distroDir "ext4.vhdx"
    Copy-Item -LiteralPath $vhdTemplate -Destination $distroVhd -Force
    Write-Host "docker-desktop ディストリビューションを登録します..."
    & wsl --import-in-place docker-desktop $distroVhd
    Write-Host "docker-desktop-data ディストリビューションを登録します..."
    & wsl --import docker-desktop-data $dataDir $dataTar --version 2
}

function Get-WslDefaultUser {
    param([string]$Name)
    $user = & wsl -d $Name -- sh -lc "whoami"
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($user)) {
        return "nixos"
    }
    return $user.Trim()
}

function Ensure-DockerGroup {
    param([string]$Name)
    $user = Get-WslDefaultUser -Name $Name
    & wsl -d $Name -u root -- sh -lc "( groupadd docker || true ) && usermod -aG docker $user"
}

function Cleanup-VscodeServer {
    param([string]$Name)
    $user = Get-WslDefaultUser -Name $Name
    $userHome = "/home/$user"
    $cleanup = @(
        "rm -rf $userHome/.vscode-server $userHome/.vscode-server-insiders",
        "rm -rf $userHome/.vscode-remote-containers $userHome/.vscode-remote-wsl",
        "rm -rf /root/.vscode-server /root/.vscode-server-insiders",
        "rm -rf /root/.vscode-remote-containers /root/.vscode-remote-wsl"
    ) -join " && "
    & wsl -d $Name -u root -- sh -lc $cleanup
}

function Find-VscodeProductJson {
    param([string[]]$Roots, [string]$Pattern)
    $candidates = @()
    foreach ($root in $Roots) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        if (Test-Path -LiteralPath $root) {
            $candidates += Get-ChildItem -LiteralPath $root -Recurse -Filter product.json -ErrorAction SilentlyContinue
        }
    }
    if ($Pattern) {
        $candidates += Get-ChildItem -Path $Pattern -ErrorAction SilentlyContinue
    }
    $candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Get-VscodeProductInfo {
    param([string[]]$Roots, [string]$Pattern)
    $productFile = Find-VscodeProductJson -Roots $Roots -Pattern $Pattern
    if (-not $productFile) {
        return $null
    }
    try {
        return (Get-Content -Raw -LiteralPath $productFile.FullName | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Install-VscodeServer {
    param(
        [string]$Name,
        [string]$Channel,
        [string]$Commit,
        [string]$User
    )
    if (-not $Commit) {
        return
    }
    $serverRoot = if ($Channel -eq "insider") { "/home/$User/.vscode-server-insiders" } else { "/home/$User/.vscode-server" }
    $serverDir = "$serverRoot/bin/$Commit"
    $url = "https://update.code.visualstudio.com/commit:$Commit/server-linux-x64/$Channel"
    $safeUser = $User.Replace("'", "''")
    $safeRoot = $serverRoot.Replace("'", "''")
    $safeDir = $serverDir.Replace("'", "''")
    $safeUrl = $url.Replace("'", "''")
    $chownOwner = "${safeUser}:" + '$groupName'
    $cmd = "set -e; " +
        "userName='$safeUser'; " +
        "groupName=`$(id -gn `"$safeUser`" 2>/dev/null || echo `"$safeUser`"); " +
        "serverRoot='$safeRoot'; " +
        "serverDir='$safeDir'; " +
        "url='$safeUrl'; " +
        "mkdir -p `"$safeDir`"; " +
        "if [ ! -f `"$safeDir/.nixos-patched`" ]; then curl -fsSL `"$safeUrl`" | tar -xz -C `"$safeDir`" --strip-components=1; fi; " +
        "if [ -x `"$safeDir/bin/code-server-insiders`" ] && [ ! -e `"$safeDir/bin/code-server`" ]; then ln -s code-server-insiders `"$safeDir/bin/code-server`"; fi; " +
        "chown -R `"$chownOwner`" `"$safeRoot`""
    & wsl -d $Name -u root -- sh -lc $cmd
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

function Apply-WslConfig {
    if ($SkipWslConfigApply) {
        Write-Host ".wslconfig の適用をスキップしました。"
        return
    }
    $source = Join-Path $PSScriptRoot "windows\\.wslconfig"
    if (-not (Test-Path -LiteralPath $source)) {
        Write-Warning ".wslconfig が見つかりません: $source"
        return
    }
    $dest = Join-Path $env:USERPROFILE ".wslconfig"
    Copy-Item -LiteralPath $source -Destination $dest -Force
    Write-Host ".wslconfig を更新しました。反映のため WSL を再起動します。"
    & wsl --shutdown
}

function Get-WslDistroBasePath {
    param([string]$Name)
    $root = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"
    $keys = Get-ChildItem -Path $root -ErrorAction SilentlyContinue
    foreach ($k in $keys) {
        $props = Get-ItemProperty -Path $k.PSPath
        if ($props.DistributionName -and $props.DistributionName -ieq $Name) {
            return $props.BasePath
        }
    }
    return $null
}

function Parse-SizeToMB {
    param([string]$Value)
    if (-not $Value) { return $null }
    $v = $Value.Trim()
    if ($v -match '^(\\d+)(GB|MB)$') {
        $num = [int]$Matches[1]
        $unit = $Matches[2]
        if ($unit -eq "GB") { return $num * 1024 }
        return $num
    }
    return $null
}

function Ensure-VhdExpanded {
    param([string]$Name)
    if ($SkipVhdExpand) {
        Write-Host "VHDX 拡張をスキップしました。"
        return
    }
    $base = Get-WslDistroBasePath -Name $Name
    if (-not $base) {
        Write-Warning "WSL ディストリの BasePath を取得できませんでした: $Name"
        return
    }
    $vhdx = Join-Path $base "ext4.vhdx"
    if (-not (Test-Path -LiteralPath $vhdx)) {
        Write-Warning "VHDX が見つかりません: $vhdx"
        return
    }
    $wslConfig = Join-Path $PSScriptRoot "windows\\.wslconfig"
    if (-not (Test-Path -LiteralPath $wslConfig)) {
        $wslConfig = Join-Path $env:USERPROFILE ".wslconfig"
    }
    $targetMB = $null
    if (Test-Path -LiteralPath $wslConfig) {
        $content = Get-Content -Raw -Path $wslConfig
        $match = [regex]::Match($content, 'defaultVhdSize\s*=\s*(\d+)\s*(GB|MB)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            $raw = "$($match.Groups[1].Value)$($match.Groups[2].Value.ToUpper())"
            $targetMB = Parse-SizeToMB -Value $raw
        }
    }
    if (-not $targetMB) {
        $targetMB = 32768
        Write-Warning "defaultVhdSize を読み取れないため、${targetMB}MB で VHDX を拡張します。"
    }
    Write-Host "VHDX を ${targetMB}MB へ拡張します: $vhdx"
    & wsl --shutdown
    $diskpart = @"
select vdisk file="$vhdx"
expand vdisk maximum=$targetMB
exit
"@
    $tmp = New-TemporaryFile
    Set-Content -Path $tmp -Value $diskpart -Encoding ASCII
    & diskpart /s $tmp | Out-Null
    Remove-Item -LiteralPath $tmp -Force
}

function Resize-WslFilesystem {
    param([string]$Name)
    $findRoot = 'lsblk -f | awk ''\$2=="ext4" && \$7=="/" {print "/dev/"\$1; exit}'''
    $dev = & wsl -d $Name -u root -- sh -lc $findRoot
    $dev = $dev | Select-Object -First 1
    if ($dev) { $dev = $dev.Trim() } else { $dev = "" }
    if (-not $dev) {
        $findFallback = 'lsblk -f | awk ''\$2=="ext4" && \$7=="/mnt/wslg/distro" {print "/dev/"\$1; exit}'''
        $dev = & wsl -d $Name -u root -- sh -lc $findFallback
        $dev = $dev | Select-Object -First 1
        if ($dev) { $dev = $dev.Trim() } else { $dev = "" }
    }
    if ($dev) {
        Write-Host "ファイルシステムを拡張します: $dev"
        & wsl -d $Name -u root -- sh -lc "resize2fs $dev"
    } else {
        Write-Warning "拡張対象のデバイスを特定できませんでした。"
    }
}

function Ensure-WslWritable {
    param([string]$Name)
    $writableCheck = "touch /tmp/.wsl-write-test 2>/dev/null && rm -f /tmp/.wsl-write-test"
    & wsl -d $Name -u root -- sh -lc $writableCheck
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "WSL が読み取り専用のため、VHDX 拡張を試みます。"
        Ensure-VhdExpanded -Name $Name
        & wsl -d $Name -u root -- sh -lc $writableCheck
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "WSL がまだ読み取り専用です。ファイルシステム拡張を試みます。"
            Resize-WslFilesystem -Name $Name
        }
    }
}
Invoke-PostInstallSetup -Name $DistroName -ScriptPath $PostInstallScript
Apply-WslConfig
Ensure-WslWritable -Name $DistroName
Ensure-WhoamiShim -Name $DistroName
Ensure-DockerDesktopIntegration -Name $DistroName -Retries $DockerIntegrationRetries -DelaySeconds $DockerIntegrationRetryDelaySeconds
if (-not $SkipVscodeServerClean) {
    Write-Host "VS Code Server キャッシュを削除します..."
    Cleanup-VscodeServer -Name $DistroName
    Write-Host "VS Code Server キャッシュを削除しました。"
}
if (-not $SkipVscodeServerPreinstall) {
    $user = Get-WslDefaultUser -Name $DistroName
    $insidersRoots = @(
        (Join-Path $env:LOCALAPPDATA "Programs\\Microsoft VS Code Insiders")
    )
    $stableRoots = @(
        (Join-Path $env:LOCALAPPDATA "Programs\\Microsoft VS Code")
    )
    $insidersPattern = "C:\\Users\\*\\AppData\\Local\\Programs\\Microsoft VS Code Insiders\\*\\resources\\app\\product.json"
    $stablePattern = "C:\\Users\\*\\AppData\\Local\\Programs\\Microsoft VS Code\\*\\resources\\app\\product.json"
    $insidersProduct = Get-VscodeProductInfo -Roots $insidersRoots -Pattern $insidersPattern
    $stableProduct = Get-VscodeProductInfo -Roots $stableRoots -Pattern $stablePattern
    $didPreinstall = $false
    if ($insidersProduct -and $insidersProduct.commit) {
        Write-Host "VS Code Server (Insiders) を事前インストールします..."
        Install-VscodeServer -Name $DistroName -Channel "insider" -Commit $insidersProduct.commit -User $user
        $didPreinstall = $true
    }
    if ($stableProduct -and $stableProduct.commit) {
        Write-Host "VS Code Server (Stable) を事前インストールします..."
        Install-VscodeServer -Name $DistroName -Channel "stable" -Commit $stableProduct.commit -User $user
        $didPreinstall = $true
    }
    if (-not $didPreinstall) {
        Write-Warning "VS Code の product.json が見つからないため、事前インストールをスキップします。"
    }
}

if (-not $SkipSetDefaultDistro) {
    Write-Host "WSL の既定ディストリビューションを設定します: $DistroName"
    & wsl --set-default $DistroName
}

# Windows Terminal / WezTerm 設定を適用
Write-Host "Windows Terminal / WezTerm 設定を適用しています..."
$updateScript = Join-Path $PSScriptRoot "scripts\powershell\update-windows-settings.ps1"
if (Test-Path -LiteralPath $updateScript) {
    & $updateScript -WslDistro $DistroName -SkipWinget
    Write-Host "Windows 設定を適用しました。"
} else {
    Write-Warning "update-windows-settings.ps1 が見つかりません: $updateScript"
}

# Docker Desktop VHDX 拡張
$expandDockerVhd = Join-Path $PSScriptRoot "windows\expand-docker-vhd.ps1"
if (Test-Path -LiteralPath $expandDockerVhd) {
    Write-Host "Docker Desktop VHDX サイズを確認しています..."
    & $expandDockerVhd -Force
}

Write-Host "完了しました。NixOS を起動するには: wsl -d $DistroName"

