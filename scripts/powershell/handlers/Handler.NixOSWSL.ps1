<#
.SYNOPSIS
    NixOS-WSL のダウンロードとインストールを管理するハンドラー

.DESCRIPTION
    - 管理者権限チェック
    - WSL 基盤の有効化
    - NixOS-WSL のダウンロード
    - ディストリビューションのインポート/インストール
    - Post-install セットアップの実行

.NOTES
    Order = 5 (最初に実行され、他の WSL 依存ハンドラーより前に完了する)
#>

# 依存ファイルの読み込み
$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\SetupHandler.ps1")
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class NixOSWSLHandler : SetupHandlerBase {
    NixOSWSLHandler() {
        $this.Name = "NixOSWSL"
        $this.Description = "NixOS-WSL のダウンロードとインストール"
        $this.Order = 50
        $this.RequiresAdmin = $true
    }

    <#
    .SYNOPSIS
        実行可否を判定する
    .DESCRIPTION
        以下の条件をチェック:
        - NixOS ディストリビューションがまだ存在しないか
        - または強制再インストールが指定されているか
    #>
    [bool] CanApply([SetupContext]$ctx) {
        # ディストリビューションがすでに存在する場合
        if ($this.DistroExists($ctx.DistroName)) {
            $this.Log("ディストリビューション '$($ctx.DistroName)' はすでに存在します", "Gray")
            return $false
        }

        return $true
    }

    <#
    .SYNOPSIS
        NixOS-WSL をインストールする
    #>
    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            # 管理者権限チェック
            $this.AssertAdmin()

            # WSL 基盤の有効化
            $this.EnsureWslReady($ctx)

            # NixOS-WSL のダウンロード
            $releaseTag = $ctx.GetOption("ReleaseTag", "")
            $release = $this.GetRelease($releaseTag)
            $asset = $this.SelectAsset($release)
            $archivePath = $this.DownloadAsset($asset)

            # インストール
            $this.InstallDistro($ctx, $asset, $archivePath)

            # Post-install セットアップ
            $this.ExecutePostInstall($ctx)

            # whoami shim の作成
            $this.EnsureWhoamiShim($ctx.DistroName)

            # 書き込み可能チェック
            $this.EnsureWslWritable($ctx.DistroName)

            return $this.CreateSuccessResult("NixOS-WSL のインストールが完了しました")
        } catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }

    # ========================================
    # Admin & System Checks
    # ========================================

    <#
    .SYNOPSIS
        管理者権限をチェック
    #>
    hidden [void] AssertAdmin() {
        $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
            throw "このハンドラーは管理者権限が必要です"
        }
    }

    <#
    .SYNOPSIS
        WSL が有効化されているか確認し、必要に応じてインストール
    #>
    hidden [void] EnsureWslReady([SetupContext]$ctx) {
        $skipWslBaseInstall = $ctx.GetOption("SkipWslBaseInstall", $false)

        $this.Log("WSL の状態を確認しています...")
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

        if ($skipWslBaseInstall) {
            throw "WSL が有効化されていません。SkipWslBaseInstall を外すか、手動で有効化してください。"
        }

        $this.Log("WSL 基盤をインストールします (再起動が必要になる場合があります)...")
        & wsl --install --no-distribution
        throw "WSL の有効化を完了するため、Windows を再起動してから再度このスクリプトを実行してください。"
    }

    <#
    .SYNOPSIS
        WSL のバージョン番号を取得
    #>
    hidden [version] GetWslVersion() {
        $output = & wsl --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            return $null
        }
        if ($output -match "WSL version:\\s*([0-9\\.]+)") {
            try {
                return [version]$Matches[1]
            } catch {
                return $null
            }
        }
        return $null
    }

    <#
    .SYNOPSIS
        WSL が --install --from-file をサポートしているか確認
    #>
    hidden [bool] SupportsFromFileInstall() {
        $ver = $this.GetWslVersion()
        if ($ver -and $ver -ge [version]"2.4.4.0") {
            return $true
        }
        # Fallback: ヘルプテキストを確認
        $help = & wsl --help 2>&1
        return ($help -match "--install --from-file")
    }

    # ========================================
    # NixOS-WSL Download
    # ========================================

    <#
    .SYNOPSIS
        GitHub から NixOS-WSL リリースを取得
    #>
    hidden [object] GetRelease([string]$tag) {
        $this.Log("NixOS-WSL リリースを取得しています...")
        $base = "https://api.github.com/repos/nix-community/NixOS-WSL/releases"
        $uri = if ([string]::IsNullOrWhiteSpace($tag)) {
            "$base/latest"
        } else {
            "$base/tags/$tag"
        }
        return Invoke-RestMethod -Uri $uri -Headers @{ "User-Agent" = "nixos-wsl-installer" }
    }

    <#
    .SYNOPSIS
        リリースから適切なアセットを選択
    #>
    hidden [object] SelectAsset([object]$release) {
        $priority = @("nixos.wsl", "nixos-wsl.tar.gz", "nixos-wsl-legacy.tar.gz")
        foreach ($name in $priority) {
            $asset = $release.assets | Where-Object { $_.name -eq $name } | Select-Object -First 1
            if ($asset) {
                $this.Log("アセットを選択: $name")
                return $asset
            }
        }
        throw "Release $($release.tag_name) に利用可能なアーカイブが見つかりません。"
    }

    <#
    .SYNOPSIS
        アセットをダウンロード
    #>
    hidden [string] DownloadAsset([object]$asset) {
        $destination = Join-Path $env:TEMP $asset.name
        $this.Log("アーカイブをダウンロードします: $($asset.name)")
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $destination -UseBasicParsing
        return $destination
    }

    # ========================================
    # Distro Installation
    # ========================================

    <#
    .SYNOPSIS
        WSL ディストリビューションが存在するか確認
    #>
    hidden [bool] DistroExists([string]$name) {
        $list = & wsl --list --quiet | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        return $list -contains $name
    }

    <#
    .SYNOPSIS
        インストールディレクトリを確保
    #>
    hidden [void] EnsureInstallDir([string]$path) {
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -ItemType Directory -Path $path | Out-Null
            return
        }
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            throw "指定したインストール先 $path はディレクトリではありません。"
        }
        if ((Get-ChildItem -LiteralPath $path -Force | Measure-Object).Count -gt 0) {
            throw "インストール先 $path が空ではありません。空のディレクトリを指定するか、既存の内容を移動してください。"
        }
    }

    <#
    .SYNOPSIS
        ディストリビューションをインストール
    #>
    hidden [void] InstallDistro([SetupContext]$ctx, [object]$asset, [string]$archivePath) {
        $supportsFromFile = $this.SupportsFromFileInstall() -and ($asset.name -like "*.wsl")

        if ($supportsFromFile) {
            try {
                $this.InstallFromFile($ctx.DistroName, $archivePath, $ctx.InstallDir)
            } catch {
                $this.LogWarning("wsl --install --from-file に失敗しました。wsl --import にフォールバックします。")
                $this.LogWarning($_.Exception.Message)
                $this.ImportDistro($ctx.DistroName, $ctx.InstallDir, $archivePath)
            }
        } else {
            $this.ImportDistro($ctx.DistroName, $ctx.InstallDir, $archivePath)
        }
    }

    <#
    .SYNOPSIS
        wsl --import でディストリビューションをインポート
    #>
    hidden [void] ImportDistro([string]$name, [string]$dir, [string]$archive) {
        $this.Log("WSL ディストリビューションをインポートします: $name -> $dir")
        $this.EnsureInstallDir($dir)
        & wsl --import $name $dir $archive --version 2
        if ($LASTEXITCODE -ne 0) {
            throw "wsl --import が失敗しました (exit code: $LASTEXITCODE)"
        }
    }

    <#
    .SYNOPSIS
        wsl --install --from-file でディストリビューションをインストール
    #>
    hidden [void] InstallFromFile([string]$name, [string]$archive, [string]$location) {
        $this.Log("WSL 2.4.4+ の手順で登録します: wsl --install --from-file")
        $args = @("--install", "--from-file", $archive, "--name", $name)
        if ($location) {
            $this.EnsureInstallDir($location)
            $args += @("--location", $location)
        }
        & wsl @args
        if ($LASTEXITCODE -ne 0) {
            throw "wsl --install --from-file が失敗しました (exit code: $LASTEXITCODE)"
        }
    }

    # ========================================
    # Post-Install Setup
    # ========================================

    <#
    .SYNOPSIS
        Post-install スクリプトを実行
    #>
    hidden [void] ExecutePostInstall([SetupContext]$ctx) {
        $skipPostInstall = $ctx.GetOption("SkipPostInstallSetup", $false)
        if ($skipPostInstall) {
            $this.Log("Post-install セットアップをスキップしました。", "Gray")
            return
        }

        $scriptPath = $ctx.GetOption("PostInstallScript", "")
        if ([string]::IsNullOrWhiteSpace($scriptPath)) {
            # デフォルトパスを設定
            $scriptPath = Join-Path $ctx.DotfilesPath "scripts\sh\nixos-wsl-postinstall.sh"
        }

        if (-not (Test-Path -LiteralPath $scriptPath)) {
            $this.LogWarning("Post-install スクリプトが見つかりません: $scriptPath")
            return
        }

        $this.Log("Post-install セットアップを実行します...")
        $resolved = (Resolve-Path -LiteralPath $scriptPath).Path
        $wslPath = & wsl wslpath -a $resolved 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($wslPath)) {
            $drive = [IO.Path]::GetPathRoot($resolved).TrimEnd(":\")
            $rest = $resolved.Substring(2) -replace "\\", "/"
            $fallback = "/mnt/$($drive.ToLower())$rest"
            $wslPath = $fallback
        }

        $syncMode = $ctx.GetOption("SyncMode", "link")
        $syncBack = $ctx.GetOption("SyncBack", "lock")
        $cmd = "bash `"$wslPath`" --force --sync-mode $syncMode --sync-back $syncBack"
        & wsl -d $ctx.DistroName -u root -- sh -lc $cmd
        if ($LASTEXITCODE -ne 0) {
            $this.LogWarning("Post-install スクリプトが非ゼロで終了しました (exit code: $LASTEXITCODE)")
        }
    }

    <#
    .SYNOPSIS
        whoami シムリンクを作成
    #>
    hidden [void] EnsureWhoamiShim([string]$distroName) {
        $this.Log("whoami シムリンクを作成します...")
        $cmd = "if [ -x /run/current-system/sw/bin/whoami ]; then " +
               "ln -sf /run/current-system/sw/bin/whoami /bin/whoami; " +
               "ln -sf /run/current-system/sw/bin/whoami /usr/bin/whoami; fi"
        & wsl -d $distroName -u root -- sh -lc $cmd
    }

    <#
    .SYNOPSIS
        WSL ファイルシステムが書き込み可能か確認
    #>
    hidden [void] EnsureWslWritable([string]$distroName) {
        $this.Log("WSL 書き込み可能チェック...")
        $writableCheck = "touch /tmp/.wsl-write-test 2>/dev/null && rm -f /tmp/.wsl-write-test"
        & wsl -d $distroName -u root -- sh -lc $writableCheck
        if ($LASTEXITCODE -ne 0) {
            $this.LogWarning("WSL が読み取り専用です。VHD 拡張は WslConfig ハンドラーで処理されます。")
        }
    }
}
