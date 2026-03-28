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
    Order = 50 (管理者権限が必要なため後半で実行)
#>

# 依存ファイルの読み込み
# 注: SetupHandler.ps1 は install.ps1 またはテストフレームワークによって事前にロードされている前提
# クラスキャッシュ問題を防ぐため、ここでは読み込まない
$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class NixOSWSLHandler : SetupHandlerBase {
    NixOSWSLHandler() {
        $this.Name = "NixOSWSL"
        $this.Description = "NixOS-WSL のダウンロードとインストール"
        $this.Order = 50
        # WSL ディストリビューション登録は per-user 操作であり Windows admin 権限は不要。
        # AzureAD アカウントでは UAC 昇格すると別の HKCU が使われるため、
        # 管理者フェーズで実行すると登録が正規ユーザーの WSL に反映されない。
        $this.RequiresAdmin = $false
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
        # WSL が動作するか確認
        if (-not $this.TestWslExecutable()) {
            $this.LogWarning("WSL が正常に動作しません")
            $this.Log("修正方法: wsl --install を実行するか、Windows Update を確認してください", "Yellow")
            return $false
        }

        # ディストリビューションがすでに存在する場合
        if ($this.DistroExists($ctx.DistroName)) {
            $this.Log("ディストリビューション '$($ctx.DistroName)' はすでに存在します", "Gray")
            return $false
        }

        return $true
    }

    <#
    .SYNOPSIS
        WSL が実際に動作するか確認する
    .DESCRIPTION
        wsl --status を実行して、WSL が有効化されているか確認。
        管理者昇格プロセスでは WSL 出力に null バイトが含まれるため除去してから確認する。
    #>
    hidden [bool] TestWslExecutable() {
        try {
            # wsl --version はディストリビューション未登録でも exit 0 を返す最も確実な確認方法
            # 管理者昇格プロセスでも動作する
            Invoke-Wsl -Arguments @("--version") 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                return $true
            }
            # --version に対応していない古い WSL では --status を試す
            $output = Invoke-Wsl -Arguments @("--status") 2>&1
            # WSL の出力は null バイトを含む場合があるため除去してからパターンを確認する
            $cleanOutput = ($output | ForEach-Object {
                ($_ -replace "`0", '' -replace [char]0xFEFF, '').Trim()
            }) -join " "
            if ($cleanOutput -match 'Default|既定|Version|バージョン|Kernel|カーネル') {
                return $true
            }
            return ($LASTEXITCODE -eq 0)
        } catch {
            return $false
        }
    }

    <#
    .SYNOPSIS
        NixOS-WSL をインストールする
    #>
    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            # WSL 基盤の有効化
            $this.EnsureWslReady($ctx)

            # VHD が既に存在する場合は再インポート（ダウンロード不要）
            $vhdPath = Join-Path $ctx.InstallDir "ext4.vhdx"
            if (Test-Path -LiteralPath $vhdPath) {
                $this.Log("既存の VHD を検出しました。wsl --import-in-place で再登録します...")
                $this.ReimportExistingVhd($ctx)
            } else {
                # 通常インストール: GitHub からダウンロードしてインポート
                $releaseTag = $ctx.GetOption("ReleaseTag", "")
                $release = $this.GetRelease($releaseTag)
                $asset = $this.SelectAsset($release)
                $archivePath = $this.DownloadAsset($asset)
                $this.InstallDistro($ctx, $asset, $archivePath)
            }

            # Post-install セットアップ
            $this.ExecutePostInstall($ctx)

            # whoami shim の作成
            $this.EnsureWhoamiShim($ctx.DistroName)

            # 書き込み可能チェック
            $this.EnsureWslWritable($ctx.DistroName)

            # Docker グループへのユーザー追加
            # DockerHandler は NixOS インストール前（Phase 2a, Order=18）に実行されるため、
            # 初回インストール時には NixOS が存在せず Docker 連携をスキップする。
            # ここで docker グループ設定を行うことで初回インストール後も docker コマンドが使用可能になる。
            $this.EnsureDockerGroup($ctx.DistroName)

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
        WSL が有効化されているか確認し、必要に応じてインストール
    #>
    hidden [void] EnsureWslReady([SetupContext]$ctx) {
        $skipWslBaseInstall = $ctx.GetOption("SkipWslBaseInstall", $false)

        $this.Log("WSL の状態を確認しています...")
        $statusOutput = Invoke-Wsl --status 2>&1
        if ($LASTEXITCODE -eq 0) {
            return
        }

        if ($statusOutput -match "Unrecognized option" -or $statusOutput -match "invalid command line option") {
            Invoke-Wsl -l -q 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                return
            }
        }

        if ($skipWslBaseInstall) {
            throw "WSL が有効化されていません。SkipWslBaseInstall を外すか、手動で有効化してください。"
        }

        $this.Log("WSL 基盤をインストールします (再起動が必要になる場合があります)...")
        Invoke-Wsl --install --no-distribution
        throw "WSL の有効化を完了するため、Windows を再起動してから再度このスクリプトを実行してください。"
    }

    <#
    .SYNOPSIS
        WSL のバージョン番号を取得
    #>
    hidden [version] GetWslVersion() {
        $output = Invoke-Wsl --version 2>&1
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
        $help = Invoke-Wsl --help 2>&1
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
        return Invoke-RestMethodSafe -Uri $uri -Headers @{ "User-Agent" = "nixos-wsl-installer" }
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
        Invoke-WebRequestSafe -Uri $asset.browser_download_url -OutFile $destination
        return $destination
    }

    # ========================================
    # WSL Readiness
    # ========================================

    <#
    .SYNOPSIS
        WSL サービスが操作可能になるまで待機する
    .DESCRIPTION
        wsl --status が成功するまでリトライする。
        WslConfig ハンドラーによる terminate 直後に import を実行すると
        WSL サービスが過渡状態のため失敗することがある。
    #>
    hidden [void] WaitForWslReady() { $this.WaitForWslReady(10, 2) }
    hidden [void] WaitForWslReady([int]$maxAttempts, [int]$intervalSeconds) {
        for ($i = 1; $i -le $maxAttempts; $i++) {
            try {
                Invoke-Wsl --status 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    return
                }
            } catch {
                # WSL が過渡状態の場合、例外を無視してリトライする
                $null = $_.Exception
            }
            if ($i -lt $maxAttempts) {
                $this.Log("WSL の準備を待機しています... ($i/$maxAttempts)")
                Start-SleepSafe -Seconds $intervalSeconds
            }
        }
        $this.LogWarning("WSL の準備完了を確認できませんでした。インポートを試行します。")
    }

    # ========================================
    # Distro Installation
    # ========================================

    <#
    .SYNOPSIS
        WSL ディストリビューションが存在するか確認
    .DESCRIPTION
        wsl --list --quiet の出力は null バイトを含む場合があるため除去してから比較する。
    #>
    hidden [bool] DistroExists([string]$name) {
        $list = Invoke-Wsl --list --quiet 2>$null | ForEach-Object {
            ($_ -replace "`0", '' -replace [char]0xFEFF, '').Trim()
        } | Where-Object { $_ }
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
        if ((Get-ChildItemSafe -Path $path -Force | Measure-Object).Count -gt 0) {
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
        既存の VHD を wsl --import-in-place で再登録する
    .DESCRIPTION
        VHD ファイルが InstallDir に存在するが WSL に未登録の場合（再インストール・登録消失）に使用する。
        ダウンロードが不要なため高速に復元できる。
    #>
    hidden [void] ReimportExistingVhd([SetupContext]$ctx) {
        $this.WaitForWslReady()
        $vhdPath = Join-Path $ctx.InstallDir "ext4.vhdx"

        # まず --import-in-place を試みる（WSL 2.4.4+ の新形式 VHD 用、コピー不要で高速）
        $this.Log("wsl --import-in-place $($ctx.DistroName) $($ctx.InstallDir)")
        Invoke-Wsl --import-in-place $ctx.DistroName $ctx.InstallDir
        if ($LASTEXITCODE -eq 0) {
            $this.Log("VHD からの再登録が完了しました", "Green")
            return
        }

        # フォールバック: VHD を一時的にリネームして --import --vhd
        # --import --vhd は InstallDir に新たな ext4.vhdx を作成するため、
        # 既存ファイルとの競合を避けるために元の VHD を .bak にリネームする。
        $this.LogWarning("--import-in-place に失敗しました。VHD をリネームして --import --vhd を試みます。")
        $vhdBak = $vhdPath + ".bak"
        try {
            Rename-Item -LiteralPath $vhdPath -NewName ([System.IO.Path]::GetFileName($vhdBak)) -Force
            Invoke-Wsl --import --vhd $ctx.DistroName $ctx.InstallDir $vhdBak
            if ($LASTEXITCODE -eq 0) {
                Remove-Item -LiteralPath $vhdBak -Force -ErrorAction SilentlyContinue
                $this.Log("VHD からの再登録が完了しました (--import --vhd)", "Green")
                return
            }
            # --import --vhd も失敗した場合は元の VHD を復元
            if (Test-Path -LiteralPath $vhdBak) {
                Rename-Item -LiteralPath $vhdBak -NewName "ext4.vhdx" -Force -ErrorAction SilentlyContinue
            }
        } catch {
            if (Test-Path -LiteralPath $vhdBak) {
                Rename-Item -LiteralPath $vhdBak -NewName "ext4.vhdx" -Force -ErrorAction SilentlyContinue
            }
            throw
        }

        throw "VHD からの再登録に失敗しました。VHD が別プロセスに使用されている可能性があります。再起動後に再試行してください。(exit code: $LASTEXITCODE)"
    }

    <#
    .SYNOPSIS
        wsl --import でディストリビューションをインポート
    #>
    hidden [void] ImportDistro([string]$name, [string]$dir, [string]$archive) {
        $this.Log("WSL ディストリビューションをインポートします: $name -> $dir")
        $this.WaitForWslReady()
        $this.EnsureInstallDir($dir)
        Invoke-Wsl --import $name $dir $archive --version 2
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
        $this.WaitForWslReady()
        $wslArgs = @("--install", "--from-file", $archive, "--name", $name)
        if ($location) {
            $this.EnsureInstallDir($location)
            $wslArgs += @("--location", $location)
        }
        Invoke-Wsl @wslArgs
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
        $wslPath = Invoke-Wsl -Arguments @("wslpath", "-a", $resolved) 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($wslPath)) {
            $drive = [IO.Path]::GetPathRoot($resolved).TrimEnd(":\")
            $rest = $resolved.Substring(2) -replace "\\", "/"
            $fallback = "/mnt/$($drive.ToLower())$rest"
            $wslPath = $fallback
        }

        $syncMode = $ctx.GetOption("SyncMode", "link")
        $syncBack = $ctx.GetOption("SyncBack", "lock")
        $cmd = "bash `"$wslPath`" --force --sync-mode $syncMode --sync-back $syncBack"
        Invoke-Wsl -d $ctx.DistroName -u root -- sh -lc $cmd
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
        Invoke-Wsl -d $distroName -u root -- sh -lc $cmd
    }

    <#
    .SYNOPSIS
        WSL ファイルシステムが書き込み可能か確認
    #>
    hidden [void] EnsureWslWritable([string]$distroName) {
        $this.Log("WSL 書き込み可能チェック...")
        $writableCheck = "touch /tmp/.wsl-write-test 2>/dev/null && rm -f /tmp/.wsl-write-test"
        Invoke-Wsl -d $distroName -u root -- sh -lc $writableCheck
        if ($LASTEXITCODE -ne 0) {
            $this.LogWarning("WSL が読み取り専用です。VHD 拡張は WslConfig ハンドラーで処理されます。")
        }
    }

    <#
    .SYNOPSIS
        Docker グループにデフォルトユーザーを追加する
    .DESCRIPTION
        DockerHandler は NixOS インストール前に実行されるため、初回インストール時は
        NixOS が存在せず Docker 連携をスキップする。
        NixOS インストール直後にここで docker グループ設定を行う。
    #>
    hidden [void] EnsureDockerGroup([string]$distroName) {
        $this.Log("Docker グループにユーザーを追加します...")
        $user = Invoke-Wsl "-d" $distroName "--" "sh" "-lc" "whoami" | Select-Object -First 1
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($user)) {
            $user = "nixos"
        }
        $user = $user.Trim()
        $cmd = "( groupadd docker 2>/dev/null || true ) && usermod -aG docker $user"
        Invoke-Wsl "-d" $distroName "-u" "root" "--" "sh" "-lc" $cmd
        if ($LASTEXITCODE -eq 0) {
            $this.Log("docker グループに '$user' を追加しました", "Green")
        } else {
            $this.LogWarning("docker グループへのユーザー追加に失敗しました (exit code: $LASTEXITCODE)")
        }
    }
}
