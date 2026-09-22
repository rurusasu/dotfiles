<#
.SYNOPSIS
    winget パッケージ管理ハンドラー

.DESCRIPTION
    - winget import: パッケージリストからインストール
    - winget export: インストール済みパッケージをエクスポート

.NOTES
    Order = 5 (最初に実行、他のハンドラーの前提)
    Mode オプションで動作を切り替え:
    - "import" (デフォルト): パッケージをインストール
    - "export": パッケージリストをエクスポート
#>

# 依存ファイルの読み込み
# 注: SetupHandler.ps1 は install.ps1 またはテストフレームワークによって事前にロードされている前提
# クラスキャッシュ問題を防ぐため、ここでは読み込まない
$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class WingetHandler : SetupHandlerBase {
    hidden [bool]$LastInstallTimedOut
    hidden [bool]$LastInstallSucceeded
    hidden [int]$LastInstallExitCode

    WingetHandler() {
        $this.Name = "Winget"
        $this.Description = "winget パッケージ管理"
        $this.Order = 5
        $this.RequiresAdmin = $false
        $this.Phase = 1
    }

    <#
    .SYNOPSIS
        実行可否を判定する
    .DESCRIPTION
        以下の条件をチェック:
        - winget コマンドが利用可能か
        - パッケージリストファイルが存在するか（import モード時）
    #>
    [bool] CanApply([SetupContext]$ctx) {
        # winget の確認
        $wingetCmd = Get-ExternalCommand -Name "winget"
        if (-not $wingetCmd) {
            $this.LogWarning("winget が見つかりません")
            return $false
        }

        # winget が実際に動作するか確認
        if (-not $this.TestWingetExecutable()) {
            $this.LogWarning("winget が正常に動作しません（App Installer の再インストールが必要な可能性があります）")
            $this.Log("修正方法: Microsoft Store から App Installer を更新してください", "Yellow")
            return $false
        }

        $mode = $ctx.GetOption("WingetMode", "import")

        if ($mode -eq "import") {
            # import モード: パッケージリストの存在確認
            $packagesPath = $this.GetPackagesPath($ctx)
            if (-not (Test-PathExist -Path $packagesPath)) {
                $this.LogWarning("パッケージリストが見つかりません: $packagesPath")
                return $false
            }
        }

        return $true
    }

    <#
    .SYNOPSIS
        winget が実際に動作するか確認する
    .DESCRIPTION
        winget --version を実行して、動作確認を行う
    #>
    hidden [bool] TestWingetExecutable() {
        try {
            $output = Invoke-Winget -Arguments @("--version")
            # exit code 0 かつ出力に version 形式があるか確認
            if ($LASTEXITCODE -eq 0 -and $output -match 'v?\d+\.\d+') {
                return $true
            }
            return $false
        }
        catch {
            $this.LogWarning("winget 動作確認中に例外が発生しました: $($_.Exception.Message)")
            return $false
        }
    }

    <#
    .SYNOPSIS
        winget 操作を実行する
    #>
    [SetupResult] Apply([SetupContext]$ctx) {
        $mode = $ctx.GetOption("WingetMode", "import")

        $result = $null
        switch ($mode) {
            "import" { $result = $this.ImportPackages($ctx) }
            "export" { $result = $this.ExportPackages($ctx) }
            default {
                $result = $this.CreateFailureResult("不明なモード: $mode (import または export を指定してください)")
            }
        }
        return $result
    }

    <#
    .SYNOPSIS
        パッケージをインストールする（インストール済みはスキップ）
    #>
    hidden [SetupResult] ImportPackages([SetupContext]$ctx) {
        try {
            $packagesPath = $this.GetPackagesPath($ctx)
            $this.Log("winget パッケージをインストールしています...")
            $this.Log("ソース: $packagesPath")

            # packages.json を読み込んで各パッケージを取得
            $packagesJson = Get-JsonContent -Path $packagesPath
            $packages = @()
            if ($packagesJson.Sources) {
                foreach ($source in $packagesJson.Sources) {
                    $sourceName = $null
                    if ($source.PSObject.Properties.Name -contains "SourceDetails") {
                        $sourceName = $source.SourceDetails.Name
                    }
                    if ($source.Packages) {
                        foreach ($pkg in $source.Packages) {
                            if ($pkg.PackageIdentifier) {
                                $version = $null
                                if ($pkg.PSObject.Properties.Name -contains "Version") {
                                    $version = $pkg.Version
                                }
                                $verifyCommand = $null
                                if ($pkg.PSObject.Properties.Name -contains "verifyCommand") {
                                    $verifyCommand = $pkg.verifyCommand
                                }
                                $installArgs = @()
                                if ($pkg.PSObject.Properties.Name -contains "installArgs") {
                                    $installArgs = @($pkg.installArgs)
                                }
                                $installTimeoutSeconds = $null
                                if ($pkg.PSObject.Properties.Name -contains "installTimeoutSeconds") {
                                    $installTimeoutSeconds = $pkg.installTimeoutSeconds
                                }
                                $directInstaller = $null
                                if ($pkg.PSObject.Properties.Name -contains "directInstaller") {
                                    $directInstaller = $pkg.directInstaller
                                }
                                $ciSkipInstall = $false
                                if ($pkg.PSObject.Properties.Name -contains "ciSkipInstall") {
                                    $ciSkipInstall = [bool]$pkg.ciSkipInstall
                                }
                                $portableLink = $null
                                if ($pkg.PSObject.Properties.Name -contains "portableLink") {
                                    $portableLink = $pkg.portableLink
                                }
                                $pathEntries = @()
                                if ($pkg.PSObject.Properties.Name -contains "pathEntries") {
                                    $pathEntries = @($pkg.pathEntries)
                                }
                                $skipInstall = $false
                                if ($pkg.PSObject.Properties.Name -contains "skipInstall") {
                                    $skipInstall = [bool]$pkg.skipInstall
                                }
                                $skipReason = $null
                                if ($pkg.PSObject.Properties.Name -contains "skipReason") {
                                    $skipReason = [string]$pkg.skipReason
                                }
                                $installFeature = $null
                                if ($pkg.PSObject.Properties.Name -contains "installFeature") {
                                    $installFeature = [string]$pkg.installFeature
                                }
                                $requiresAdmin = $false
                                if ($pkg.PSObject.Properties.Name -contains "requiresAdmin") {
                                    $requiresAdmin = [bool]$pkg.requiresAdmin
                                }
                                $packages += [PSCustomObject]@{
                                    Id                    = $pkg.PackageIdentifier
                                    Version               = $version
                                    SourceName            = $sourceName
                                    VerifyCommand         = $verifyCommand
                                    InstallArgs           = $installArgs
                                    InstallTimeoutSeconds = $installTimeoutSeconds
                                    DirectInstaller       = $directInstaller
                                    CiSkipInstall         = $ciSkipInstall
                                    PortableLink          = $portableLink
                                    PathEntries           = $pathEntries
                                    SkipInstall           = $skipInstall
                                    SkipReason            = $skipReason
                                    InstallFeature        = $installFeature
                                    RequiresAdmin         = $requiresAdmin
                                }
                            }
                        }
                    }
                }
            }

            if ($ctx.GetOption("WingetVerifyCommandOnly", $false)) {
                $ciSkipped = @($packages | Where-Object { $_.CiSkipInstall }).Count
                $packages = @($packages | Where-Object { $null -ne $_.VerifyCommand -and -not $_.CiSkipInstall })
                $ciSkipMessage = if ($ciSkipped -gt 0) { ", $ciSkipped 個 CI 対象外" } else { "" }
                $this.Log("CI 検証モード: verifyCommand 付きパッケージのみ対象にします ($($packages.Count) 個$ciSkipMessage)", "Gray")
            }

            $packages = @($packages | Where-Object {
                    [string]::IsNullOrWhiteSpace($_.InstallFeature) -or
                    [bool]$ctx.GetOption($_.InstallFeature, $false)
                })

            $adminPhase = [bool]$ctx.GetOption("WingetAdminPhase", $false)
            $deferredAdminPackages = @($packages | Where-Object { $_.RequiresAdmin })
            if ($adminPhase) {
                $packages = @($packages | Where-Object { $_.RequiresAdmin })
            }
            else {
                $packages = @($packages | Where-Object { -not $_.RequiresAdmin })
                foreach ($pkg in $deferredAdminPackages) {
                    $this.Log("管理者フェーズに委譲: $($pkg.Id)", "Yellow")
                }
            }

            if ($packages.Count -eq 0 -and $deferredAdminPackages.Count -gt 0 -and -not $adminPhase) {
                return $this.CreateSuccessResult("$($deferredAdminPackages.Count) 個を管理者フェーズに委譲")
            }

            if ($packages.Count -eq 0) {
                $this.Log("インストールするパッケージがありません", "Gray")
                return $this.CreateSuccessResult("パッケージリストが空です")
            }

            # インストール済みパッケージを一括取得（winget list を1回だけ実行）
            # 正規表現で検出できないパッケージ（ARP エントリ等）は個別チェックにフォールバック
            $installedIds = $this.GetInstalledPackageIds()

            # 通常実行ではインストール済みも含めて winget install を流し、
            # winget 側の install-or-upgrade 動作で latest を選ばせる。
            $verifyCommandOnly = $ctx.GetOption("WingetVerifyCommandOnly", $false)
            $toInstall = @()
            $skipped = 0
            $verified = 0
            $verifyFailed = 0
            $deferred = 0
            foreach ($pkg in $packages) {
                $isInstalled = $pkg.Id -in $installedIds
                if (-not $isInstalled) {
                    $isInstalled = $this.IsPackageInstalled($pkg.Id, $pkg.SourceName)
                }

                $directInstallerCurrent = $pkg.DirectInstaller -and $this.TestDirectInstallerCurrent($pkg)
                $verificationPassed = $false
                if ($pkg.VerifyCommand -and $this.ShouldDeferWslVerificationToAdminInstall($pkg, $ctx)) {
                    $this.LogWarning("Microsoft.WSL の検証は Phase 2b の管理者 WSL インストールに委譲します")
                    $deferred++
                    continue
                }

                if ($pkg.VerifyCommand -and ($isInstalled -or $directInstallerCurrent)) {
                    Update-ProcessEnvironmentPath
                    # Existing portable packages need their command shim before
                    # verification. Missing package directories are expected
                    # before the first install, so keep this lookup quiet.
                    $this.EnsurePortableLinkQuiet($pkg)
                    if ($verifyCommandOnly) {
                        $this.EnsurePathEntries($pkg)
                    }
                    else {
                        $this.EnsurePathEntriesQuiet($pkg)
                    }
                    $verificationPassed = if ($verifyCommandOnly) {
                        $this.TestPackageVerification($pkg.VerifyCommand)
                    }
                    else {
                        $this.TestPackageVerificationQuiet($pkg.VerifyCommand)
                    }
                    if ($verificationPassed) {
                        if ($verifyCommandOnly) {
                            $verified++
                            $this.Log("スキップ (検証済み): $($pkg.Id)", "Gray")
                            continue
                        }
                    }
                }

                if ($directInstallerCurrent -and $verificationPassed) {
                    $verified++
                    $this.Log("スキップ (直接インストーラーで検証済み): $($pkg.Id)", "Gray")
                    continue
                }

                if ($pkg.SkipInstall) {
                    if ($verificationPassed) {
                        $this.Log("スキップ (検証済み/手動対象): $($pkg.Id)", "Gray")
                        continue
                    }

                    $this.LogSkippedInstall($pkg)
                    $skipped++
                    continue
                }

                if ($isInstalled) {
                    if ($pkg.VerifyCommand -and $verificationPassed) {
                        $toInstall += $this.NewInstallCandidate($pkg, $false)
                    }
                    elseif ($pkg.VerifyCommand) {
                        if (-not [string]::IsNullOrWhiteSpace($this.GetRecoveryStrategy($pkg.VerifyCommand))) {
                            if ($this.RecoverPackageVerification($pkg)) {
                                $verified++
                            }
                            else {
                                $this.LogWarning("✗ $($pkg.Id) はインストール済みですが検証に失敗しました")
                                $verifyFailed++
                            }
                            continue
                        }

                        if ($this.ShouldReinstallOnVerifyFailure($pkg.VerifyCommand)) {
                            $this.LogWarning("インストール済みですが検証に失敗しました。再インストールします: $($pkg.Id)")
                            $toInstall += $this.NewInstallCandidate($pkg, $true)
                        }
                        else {
                            $this.LogWarning("✗ $($pkg.Id) はインストール済みですが検証に失敗しました")
                            $verifyFailed++
                        }
                    }
                    else {
                        $toInstall += $this.NewInstallCandidate($pkg, $false)
                    }
                }
                else {
                    $toInstall += $this.NewInstallCandidate($pkg, $false)
                }
            }

            if ($toInstall.Count -eq 0) {
                $this.EnsureCargoPath()
                $parts = @()
                if ($verified -gt 0) { $parts += "$verified 個検証済み" }
                if ($verifyFailed -gt 0) { $parts += "$verifyFailed 個検証失敗" }
                if ($deferred -gt 0) { $parts += "$deferred 個管理者フェーズ待ち" }
                $parts += "$skipped 個スキップ"
                if ($verifyFailed -gt 0) {
                    return $this.CreateFailureResult($parts -join ", ")
                }

                $this.Log("すべてのパッケージがインストール済みで、検証対象も正常です", "Green")
                return $this.CreateSuccessResult($parts -join ", ")
            }

            # 対象パッケージをインストール/更新
            $succeeded = 0
            $unchanged = 0
            $failed = 0

            foreach ($pkg in $toInstall) {
                $this.Log("インストール/更新中: $($pkg.Id)")
                $installArgs = $this.NewWingetInstallArguments($pkg, [bool]$pkg.Force)

                $installOutput = $this.InvokePackageInstall($pkg, $installArgs)
                $alreadyInstalledInstallFailure = (-not $pkg.DirectInstaller) -and $this.IsAlreadyInstalledInstallFailure($installOutput)
                foreach ($line in $installOutput) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                        $this.Log("  $line", "Gray")
                    }
                }

                if ($this.LastInstallTimedOut) {
                    if ($this.LastInstallSucceeded) {
                        Update-ProcessEnvironmentPath
                        $this.EnsurePortableLinkQuiet($pkg)
                        $this.EnsurePathEntriesQuiet($pkg)
                        $succeeded++
                        $this.Log("✓ $($pkg.Id) (direct fallback 成功、WinGet タイムアウトのため実行検証をスキップ)", "Yellow")
                    }
                    else {
                        $failed++
                        $this.LogWarning("✗ $($pkg.Id) のインストールがタイムアウトしたため、実行検証をスキップしました")
                    }
                    continue
                }

                if ($this.LastInstallExitCode -ne 0) {
                    if ($alreadyInstalledInstallFailure) {
                        if (-not $pkg.VerifyCommand) {
                            $unchanged++
                            $this.Log("変更なし: $($pkg.Id) (winget install は no-op でした)", "Gray")
                            continue
                        }

                        Update-ProcessEnvironmentPath
                        $this.EnsurePortableLinkQuiet($pkg)
                        $this.EnsurePathEntriesQuiet($pkg)
                        if ($this.TestPackageVerification($pkg.VerifyCommand)) {
                            $verified++
                            $this.Log("検証済み: $($pkg.Id) (winget install は no-op でした)", "Green")
                            continue
                        }

                        if ($this.RecoverPackageVerification($pkg)) {
                            $verified++
                            continue
                        }

                        $verifyFailed++
                        $this.LogWarning("✗ $($pkg.Id) は既にインストールされていますが検証に失敗しました")
                        continue
                    }

                    $failed++
                    $this.LogWarning("✗ $($pkg.Id) のインストールに失敗しました")
                    continue
                }

                Update-ProcessEnvironmentPath

                $this.EnsurePortableLink($pkg)
                $this.EnsurePathEntries($pkg)

                if ($pkg.VerifyCommand -and $this.TestPackageVerification($pkg.VerifyCommand)) {
                    $succeeded++
                    $this.Log("✓ $($pkg.Id)", "Green")
                }
                elseif ($pkg.VerifyCommand) {
                    if ($this.RecoverPackageVerification($pkg)) {
                        $verified++
                    }
                    else {
                        $verifyFailed++
                        $this.LogWarning("✗ $($pkg.Id) のインストールは成功しましたが検証に失敗しました")
                    }
                }
                else {
                    $succeeded++
                    $this.Log("✓ $($pkg.Id)", "Green")
                }
            }

            # Rustup インストール後: ~/.cargo/bin を PATH に追加
            $this.EnsureCargoPath()

            $parts = @()
            if ($succeeded -gt 0) { $parts += "$succeeded 個インストール" }
            if ($unchanged -gt 0) { $parts += "$unchanged 個変更なし" }
            if ($verifyFailed -gt 0) { $parts += "$verifyFailed 個検証失敗" }
            if ($failed -gt 0) { $parts += "$failed 個失敗" }
            if ($verified -gt 0) { $parts += "$verified 個検証済み" }
            if ($deferred -gt 0) { $parts += "$deferred 個管理者フェーズ待ち" }
            $parts += "$skipped 個スキップ"
            $message = $parts -join ", "
            if ($failed -gt 0 -or $verifyFailed -gt 0) {
                return $this.CreateFailureResult($message)
            }
            return $this.CreateSuccessResult($message)
        }
        catch {
            $this.LogWarning("winget パッケージインストール中に予期しないエラーが発生しました: $($_.Exception.Message)")
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }

    hidden [bool] IsAlreadyInstalledInstallFailure([object[]]$installOutput) {
        $text = ($installOutput | ForEach-Object { [string]$_ }) -join "`n"
        return $text -match '0x80073cfb' -or
        $text -match 'No applicable update found' -or
        $text -match 'No available upgrade found' -or
        $text -match 'No newer package versions are available' -or
        $text -match 'already installed' -or
        $text -match '既にインストールされています' -or
        $text -match '利用可能なアップグレードが見つかりませんでした' -or
        $text -match '新しいパッケージ バージョンはありません' -or
        $text -match 'バージョン番号を特定できません' -or
        $text -match '別のバージョンが既にインストールされています'
    }

    hidden [void] LogSkippedInstall([object]$pkg) {
        $reason = ""
        if ($pkg.PSObject.Properties.Name -contains "SkipReason" -and -not [string]::IsNullOrWhiteSpace($pkg.SkipReason)) {
            $reason = " - $($pkg.SkipReason)"
        }
        $this.Log("スキップ (手動対象): $($pkg.Id)$reason", "Yellow")
    }

    hidden [object] NewInstallCandidate([object]$pkg, [bool]$force) {
        return [PSCustomObject]@{
            Id                    = $pkg.Id
            Version               = $pkg.Version
            SourceName            = $pkg.SourceName
            VerifyCommand         = $pkg.VerifyCommand
            InstallArgs           = $pkg.InstallArgs
            InstallTimeoutSeconds = $pkg.InstallTimeoutSeconds
            DirectInstaller       = $pkg.DirectInstaller
            CiSkipInstall         = $pkg.CiSkipInstall
            PortableLink           = $pkg.PortableLink
            PathEntries            = $pkg.PathEntries
            Force                 = $force
        }
    }

    hidden [bool] ShouldDeferWslVerificationToAdminInstall([object]$pkg, [SetupContext]$ctx) {
        if ($null -eq $pkg -or $pkg.Id -ne "Microsoft.WSL") {
            return $false
        }
        if ($ctx.GetOption("WingetVerifyCommandOnly", $false)) {
            return $false
        }
        if ($ctx.GetOption("UserPhaseOnly", $false)) {
            return $false
        }
        if ($ctx.GetOption("SkipWslInstall", $false)) {
            return $false
        }
        return $true
    }

    hidden [object[]] NewWingetInstallArguments([object]$pkg, [bool]$force) {
        $installArgs = @(
            "install", "-e", "--id", $pkg.Id,
            "--silent",
            "--accept-package-agreements",
            "--accept-source-agreements",
            "--disable-interactivity"
        )
        if ($pkg.SourceName -eq "msstore") {
            $installArgs += "--source"
            $installArgs += "msstore"
        }
        elseif ($pkg.SourceName -eq "winget") {
            # Avoid winget probing the Microsoft Store for every package. The
            # fallback source lookup can hang on unavailable Store endpoints
            # and makes a successful package install look like a verification
            # failure after the command timeout.
            $installArgs += "--source"
            $installArgs += "winget"
        }
        if ($pkg.InstallArgs) {
            $installArgs += @($pkg.InstallArgs)
        }
        if ($force) {
            $installArgs += "--force"
        }
        return $installArgs
    }

    hidden [object[]] InvokePackageInstall([object]$pkg, [object[]]$installArgs) {
        $this.LastInstallTimedOut = $false
        $this.LastInstallSucceeded = $false
        $this.LastInstallExitCode = 1

        if ($pkg.DirectInstaller) {
            $wingetOutput = @($this.InvokeWingetInstall($pkg, $installArgs))
            $wingetExitCode = $this.LastInstallExitCode
            $this.LastInstallTimedOut = $this.TestInstallTimedOut($wingetOutput)
            if ($wingetExitCode -eq 0) {
                $this.LastInstallSucceeded = $true
                $this.LastInstallExitCode = 0
                return $wingetOutput
            }

            $this.Log("winget が $($pkg.Id) を完了できなかったため、公式 archive fallback を実行します", "Gray")
            $directOutput = @($this.InvokeDirectInstaller($pkg))
            $directExitCode = $LASTEXITCODE
            $this.LastInstallExitCode = $directExitCode
            if ($directExitCode -eq 0) {
                $this.LastInstallSucceeded = $true
                # Do not replay a transient WinGet timeout after the fallback
                # succeeded. The user should see the effective result only.
                return $directOutput
            }
            return @($wingetOutput + $directOutput)
        }

        $output = @($this.InvokeWingetInstall($pkg, $installArgs))
        $this.LastInstallTimedOut = $this.TestInstallTimedOut($output)
        $this.LastInstallSucceeded = $this.LastInstallExitCode -eq 0
        return $output
    }

    hidden [object[]] InvokeWingetInstall([object]$pkg, [object[]]$installArgs) {
        $installTimeoutSeconds = $this.GetInstallTimeoutSeconds($pkg)
        if ($installTimeoutSeconds -gt 0) {
            $output = @(Invoke-Winget -Arguments $installArgs -TimeoutSeconds $installTimeoutSeconds)
            $this.LastInstallExitCode = [int]$LASTEXITCODE
            return $output
        }
        $output = @(Invoke-Winget -Arguments $installArgs)
        $this.LastInstallExitCode = [int]$LASTEXITCODE
        return $output
    }

    hidden [object[]] InvokeDirectInstaller([object]$pkg) {
        $type = $this.GetDirectInstallerType($pkg.DirectInstaller)
        if ($type -ne "archive" -and $type -ne "file") {
            $global:LASTEXITCODE = 1
            return @("Unsupported directInstaller type for $($pkg.Id): $type")
        }

        $url = $this.GetDirectInstallerString($pkg.DirectInstaller, "url")
        $sha256 = $this.GetDirectInstallerString($pkg.DirectInstaller, "sha256")
        $destination = $this.ResolveDirectInstallerPath(
            $this.GetDirectInstallerString($pkg.DirectInstaller, "destination")
        )
        $executable = $this.GetDirectInstallerString($pkg.DirectInstaller, "executable")
        $timeoutSeconds = $this.GetDirectInstallerTimeoutSeconds($pkg.DirectInstaller)

        if ([string]::IsNullOrWhiteSpace($url) -or
            [string]::IsNullOrWhiteSpace($sha256) -or
            [string]::IsNullOrWhiteSpace($destination) -or
            [string]::IsNullOrWhiteSpace($executable)) {
            $global:LASTEXITCODE = 1
            return @("directInstaller metadata is incomplete for $($pkg.Id)")
        }

        $archivePath = Join-Path $env:TEMP ("dotfiles-$([guid]::NewGuid().ToString('N')).zip")
        $stagingPath = Join-Path $env:TEMP ("dotfiles-$([guid]::NewGuid().ToString('N'))")
        $destinationExisted = Test-Path -LiteralPath $destination
        $destinationBackedUp = $false
        $backupPath = $null
        try {
            $this.Log("公式 archive をダウンロードしています: $($pkg.Id)", "Gray")
            Invoke-WebRequest -Uri $url -OutFile $archivePath -UseBasicParsing -TimeoutSec $timeoutSeconds
            $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
            if ($actualHash -ne $sha256.ToUpperInvariant()) {
                $global:LASTEXITCODE = 1
                return @("directInstaller hash mismatch for $($pkg.Id): expected $sha256, got $actualHash")
            }

            if ($type -eq "file") {
                New-Item -ItemType Directory -Path $destination -Force | Out-Null
                $targetPath = Join-Path $destination $executable
                $targetParent = Split-Path -Parent $targetPath
                if ($targetParent) {
                    New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
                }
                Copy-Item -LiteralPath $archivePath -Destination $targetPath -Force
                $markerPath = Join-Path $destination ".dotfiles-direct-installer.sha256"
                Set-Content -LiteralPath $markerPath -Value $sha256.ToUpperInvariant() -Encoding ASCII
                $global:LASTEXITCODE = 0
                return @("公式 file を配置しました: $targetPath")
            }

            New-Item -ItemType Directory -Path $stagingPath -Force | Out-Null
            Expand-Archive -LiteralPath $archivePath -DestinationPath $stagingPath -Force
            $stagedExecutablePath = Join-Path $stagingPath $executable
            if (-not (Test-Path -LiteralPath $stagedExecutablePath -PathType Leaf)) {
                throw "directInstaller archive does not contain the expected executable for $($pkg.Id): $executable"
            }

            if ($destinationExisted) {
                $destinationParent = Split-Path -Parent $destination
                $destinationName = Split-Path -Leaf $destination
                $backupName = "$destinationName.dotfiles-backup-$([guid]::NewGuid().ToString('N'))"
                $backupPath = if ($destinationParent) {
                    Join-Path $destinationParent $backupName
                }
                else {
                    $backupName
                }
                Move-Item -LiteralPath $destination -Destination $backupPath -Force -ErrorAction Stop
                $destinationBackedUp = $true
            }

            New-Item -ItemType Directory -Path $destination -Force | Out-Null
            Copy-Item -Path (Join-Path $stagingPath "*") -Destination $destination -Recurse -Force
            $targetPath = Join-Path $destination $executable
            if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
                throw "directInstaller staged copy is missing the expected executable for $($pkg.Id): $targetPath"
            }
            $markerPath = Join-Path $destination ".dotfiles-direct-installer.sha256"
            Set-Content -LiteralPath $markerPath -Value $sha256.ToUpperInvariant() -Encoding ASCII
            if ($destinationBackedUp) {
                Remove-Item -LiteralPath $backupPath -Recurse -Force -ErrorAction Stop
                $destinationBackedUp = $false
            }
            $global:LASTEXITCODE = 0
            return @("公式 archive を展開しました: $destination")
        }
        catch {
            $rollbackError = $null
            try {
                if ($destinationBackedUp -or -not $destinationExisted) {
                    if (Test-Path -LiteralPath $destination) {
                        Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction Stop
                    }
                }
                if ($destinationBackedUp) {
                    Move-Item -LiteralPath $backupPath -Destination $destination -Force -ErrorAction Stop
                    $destinationBackedUp = $false
                }
            }
            catch {
                $rollbackError = $_.Exception.Message
            }

            $global:LASTEXITCODE = 1
            $message = $_.Exception.Message
            if ($rollbackError) {
                $message += "; directInstaller rollback failed: $rollbackError"
            }
            return @($message)
        }
        finally {
            Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    hidden [bool] TestInstallTimedOut([object[]]$installOutput) {
        if ($LASTEXITCODE -eq 124) {
            return $true
        }

        $text = ($installOutput | ForEach-Object { [string]$_ }) -join "`n"
        return $text -match 'タイムアウトしました|timed out'
    }

    hidden [bool] TestDirectInstallerCurrent([object]$pkg) {
        if ($null -eq $pkg -or $null -eq $pkg.DirectInstaller) {
            return $false
        }
        $destination = $this.ResolveDirectInstallerPath(
            $this.GetDirectInstallerString($pkg.DirectInstaller, "destination")
        )
        $executable = $this.GetDirectInstallerString($pkg.DirectInstaller, "executable")
        if ([string]::IsNullOrWhiteSpace($destination) -or [string]::IsNullOrWhiteSpace($executable)) {
            return $false
        }
        if (-not (Test-Path -LiteralPath (Join-Path $destination $executable) -PathType Leaf)) {
            return $false
        }

        $expectedHash = $this.GetDirectInstallerString($pkg.DirectInstaller, "sha256")
        if ([string]::IsNullOrWhiteSpace($expectedHash)) {
            return $false
        }
        $markerPath = Join-Path $destination ".dotfiles-direct-installer.sha256"
        if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
            return $false
        }
        try {
            $actualMarker = (Get-Content -LiteralPath $markerPath -Raw -ErrorAction Stop).Trim()
            return $actualMarker -eq $expectedHash.ToUpperInvariant()
        }
        catch {
            return $false
        }
    }

    hidden [string] GetDirectInstallerType([object]$directInstaller) {
        if ($directInstaller -is [hashtable] -and $directInstaller.ContainsKey("type")) {
            return [string]$directInstaller["type"]
        }
        if ($directInstaller -and ($directInstaller.PSObject.Properties.Name -contains "type")) {
            return [string]$directInstaller.type
        }
        return ""
    }

    hidden [string] GetDirectInstallerString([object]$directInstaller, [string]$name) {
        if ($directInstaller -is [hashtable] -and $directInstaller.ContainsKey($name)) {
            return [string]$directInstaller[$name]
        }
        if ($directInstaller -and ($directInstaller.PSObject.Properties.Name -contains $name)) {
            return [string]$directInstaller.$name
        }
        return ""
    }

    hidden [string] ResolveDirectInstallerPath([string]$path) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            return ""
        }
        return [Environment]::ExpandEnvironmentVariables($path)
    }

    hidden [int] GetDirectInstallerTimeoutSeconds([object]$directInstaller) {
        $timeoutSeconds = 900
        if ($directInstaller -is [hashtable] -and $directInstaller.ContainsKey("timeoutSeconds")) {
            $timeoutSeconds = [int]$directInstaller["timeoutSeconds"]
        }
        elseif ($directInstaller -and ($directInstaller.PSObject.Properties.Name -contains "timeoutSeconds")) {
            $timeoutSeconds = [int]$directInstaller.timeoutSeconds
        }

        if ($timeoutSeconds -le 0) {
            return 900
        }
        return $timeoutSeconds
    }

    hidden [int] GetInstallTimeoutSeconds([object]$pkg) {
        # A process-wide install override must be able to shorten or disable
        # the generated default for every package. Explicit per-package
        # values remain the fallback when no override is present.
        $hasEnvironmentOverride =
            -not [string]::IsNullOrWhiteSpace($env:DOTFILES_INSTALL_TIMEOUT_SECONDS) -or
            -not [string]::IsNullOrWhiteSpace($env:DOTFILES_WINGET_COMMAND_TIMEOUT_SECONDS)
        if ($hasEnvironmentOverride) {
            return Get-PackageInstallTimeoutSecond -LegacyEnvironmentVariable "DOTFILES_WINGET_COMMAND_TIMEOUT_SECONDS"
        }

        if ($null -eq $pkg -or -not ($pkg.PSObject.Properties.Name -contains "InstallTimeoutSeconds")) {
            return Get-PackageInstallTimeoutSecond -LegacyEnvironmentVariable "DOTFILES_WINGET_COMMAND_TIMEOUT_SECONDS"
        }
        $rawTimeout = $pkg.InstallTimeoutSeconds
        if ($null -eq $rawTimeout) {
            return Get-PackageInstallTimeoutSecond -LegacyEnvironmentVariable "DOTFILES_WINGET_COMMAND_TIMEOUT_SECONDS"
        }
        $timeoutSeconds = 0
        if ([int]::TryParse([string]$rawTimeout, [ref]$timeoutSeconds) -and $timeoutSeconds -gt 0) {
            return $timeoutSeconds
        }
        return Get-PackageInstallTimeoutSecond -LegacyEnvironmentVariable "DOTFILES_WINGET_COMMAND_TIMEOUT_SECONDS"
    }

    hidden [bool] RecoverPackageVerification([object]$pkg) {
        $strategy = $this.GetRecoveryStrategy($pkg.VerifyCommand)
        if ([string]::IsNullOrWhiteSpace($strategy)) {
            return $false
        }

        switch ($strategy) {
            "wingetRepair" {
                return $this.RepairPackageAndVerify($pkg)
            }
            "wingetRepairThenReinstall" {
                if ($this.RepairPackageAndVerify($pkg)) {
                    return $true
                }

                $this.LogWarning("winget repair 後も検証に失敗したため再インストールします: $($pkg.Id)")
                if (-not $this.ReinstallPackageAndVerify($pkg)) {
                    return $false
                }

                return $true
            }
            default {
                $this.LogWarning("未知の recoveryStrategy です: $strategy ($($pkg.Id))")
                return $false
            }
        }
        return $false
    }

    hidden [bool] RepairPackageAndVerify([object]$pkg) {
        $this.LogWarning("検証に失敗したため winget repair を実行します: $($pkg.Id)")
        $repairArgs = @(
            "repair", "-e", "--id", $pkg.Id,
            "--silent",
            "--accept-package-agreements",
            "--accept-source-agreements",
            "--disable-interactivity",
            "--force"
        )
        if ($pkg.SourceName -eq "winget") {
            $repairArgs += "--source"
            $repairArgs += "winget"
        }

        $repairOutput = @(Invoke-Winget -Arguments $repairArgs)
        foreach ($line in $repairOutput) {
            if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                $this.Log("  $line", "Gray")
            }
        }

        if ($LASTEXITCODE -ne 0) {
            $this.LogWarning("winget repair が失敗しました: $($pkg.Id)")
        }

        Update-ProcessEnvironmentPath
        if ($this.TestPackageVerification($pkg.VerifyCommand)) {
            $this.Log("✓ $($pkg.Id) (repair 後に検証済み)", "Green")
            return $true
        }

        $this.LogWarning("winget repair 後も検証に失敗しました: $($pkg.Id)")
        return $false
    }

    hidden [bool] ReinstallPackageAndVerify([object]$pkg) {
        $uninstallArgs = @(
            "uninstall", "-e", "--id", $pkg.Id,
            "--silent",
            "--accept-source-agreements",
            "--disable-interactivity",
            "--force"
        )
        if ($pkg.SourceName -eq "winget") {
            $uninstallArgs += "--source"
            $uninstallArgs += "winget"
        }

        $uninstallOutput = @(Invoke-Winget -Arguments $uninstallArgs)
        foreach ($line in $uninstallOutput) {
            if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                $this.Log("  $line", "Gray")
            }
        }
        if ($LASTEXITCODE -ne 0) {
            $this.LogWarning("winget uninstall が失敗しました: $($pkg.Id)")
            return $false
        }

        $installArgs = $this.NewWingetInstallArguments($pkg, $true)
        $installOutput = $this.InvokeWingetInstall($pkg, $installArgs)
        foreach ($line in $installOutput) {
            if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                $this.Log("  $line", "Gray")
            }
        }
        if ($LASTEXITCODE -ne 0) {
            $this.LogWarning("winget install が失敗しました: $($pkg.Id)")
            return $false
        }

        Update-ProcessEnvironmentPath
        if ($this.TestPackageVerification($pkg.VerifyCommand)) {
            $this.Log("✓ $($pkg.Id) (reinstall 後に検証済み)", "Green")
            return $true
        }

        $this.LogWarning("winget reinstall 後も検証に失敗しました: $($pkg.Id)")
        return $false
    }

    <#
    .SYNOPSIS
        インストール済みパッケージの ID リストを一括取得する
    .DESCRIPTION
        winget list を1回実行し、全インストール済みパッケージ ID を返す。
        パッケージごとに winget を呼ぶより大幅に高速。
    #>
    hidden [string[]] GetInstalledPackageIds() {
        try {
            # Restrict the bulk query to the community source. Without an
            # explicit source winget may probe Microsoft Store and block on a
            # network timeout before the package loop even starts.
            $output = Invoke-Winget -Arguments @("list", "--source", "winget", "--disable-interactivity")
            if ($LASTEXITCODE -ne 0) { return @() }
            # winget list の固定幅カラムは CJK 文字や省略記号で列位置がずれるため、
            # パッケージ ID のフォーマット (Publisher.Package) を正規表現で直接抽出する。
            # winget の公式 ID は必ず "組織名.パッケージ名" の形式。
            $ids = @()
            $headerPassed = $false
            foreach ($line in $output) {
                if ($line -match '^-{2,}') { $headerPassed = $true; continue }
                if (-not $headerPassed) { continue }
                # Publisher.Package 形式の ID を抽出 (例: Git.Git, Microsoft.VCRedist.2015+.x64)
                if ($line -match '(\S+\.\S+)') {
                    $candidate = $Matches[1]
                    # ARP エントリ (ARP\Machine\...) や URL は除外
                    if ($candidate -notmatch '^ARP\\' -and $candidate -notmatch '://') {
                        $ids += $candidate
                    }
                }
            }
            return $ids
        }
        catch {
            $this.LogWarning("インストール済みパッケージ一覧の取得に失敗しました: $($_.Exception.Message)")
            return @()
        }
    }

    <#
    .SYNOPSIS
        指定されたパッケージがインストール済みかどうかを確認する
    .DESCRIPTION
        個別チェック用。一括チェックには GetInstalledPackageIds を使用。
    #>
    hidden [bool] IsPackageInstalled([string]$packageId, [string]$sourceName) {
        try {
            $arguments = @("list", "--id", $packageId, "--exact", "--disable-interactivity")
            if ($sourceName -eq "msstore" -or $sourceName -eq "winget") {
                $arguments += @("--source", $sourceName)
            }
            Invoke-Winget -Arguments $arguments | Out-Null
            return $LASTEXITCODE -eq 0
        }
        catch {
            $this.LogWarning("パッケージ確認中にエラーが発生しました ($packageId): $($_.Exception.Message)")
            return $false
        }
    }

    hidden [bool] TestPackageVerification([object]$verifyCmd) {
        return $this.TestPackageVerificationInternal($verifyCmd, $false)
    }

    hidden [bool] TestPackageVerificationQuiet([object]$verifyCmd) {
        return $this.TestPackageVerificationInternal($verifyCmd, $true)
    }

    hidden [bool] TestPackageVerificationInternal([object]$verifyCmd, [bool]$quiet) {
        if (-not ($verifyCmd.PSObject.Properties.Name -contains "command")) {
            if (-not $quiet) {
                $this.LogWarning("verifyCommand に 'command' フィールドがありません")
            }
            return $false
        }
        try {
            $command = $verifyCmd.command
            $arguments = if ($verifyCmd.PSObject.Properties.Name -contains "args") { @($verifyCmd.args) } else { @() }
            $type = if ($verifyCmd.PSObject.Properties.Name -contains "type") { [string]$verifyCmd.type } else { "command" }

            if ($type -eq "commandExists") {
                return $null -ne (Get-ExternalCommand -Name $command)
            }

            if ($type -eq "appxPackage") {
                if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
                    $this.Log("検証コマンド実行エラー: Get-AppxPackage が利用できません", "Yellow")
                    return $false
                }

                $appxPackage = Get-AppxPackage -Name $command -ErrorAction SilentlyContinue
                return $null -ne $appxPackage
            }

            if ($type -eq "appxLaunchTarget") {
                return $this.TestAppxLaunchTarget($command, $arguments)
            }

            $timeoutSeconds = $this.GetVerifyTimeoutSeconds($verifyCmd)
            $output = @(Invoke-VerifyCommand -Command $command -Arguments $arguments -TimeoutSeconds $timeoutSeconds)
            if ($LASTEXITCODE -eq 0) {
                return $true
            }

            $displayCommand = "$command $($arguments -join ' ')".Trim()
            if (-not $quiet) {
                $this.Log("検証コマンド失敗 (exit code: $LASTEXITCODE): $displayCommand", "Yellow")
                foreach ($line in $output) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                        $this.Log("  $line", "Gray")
                    }
                }
            }
            return $LASTEXITCODE -eq 0
        }
        catch {
            if (-not $quiet) {
                $this.Log("検証コマンド実行エラー: $($_.Exception.Message)", "Yellow")
            }
            return $false
        }
    }

    hidden [bool] TestAppxLaunchTarget([string]$packageName, [object[]]$arguments) {
        if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
            $this.Log("検証コマンド実行エラー: Get-AppxPackage が利用できません", "Yellow")
            return $false
        }

        if ($arguments.Count -lt 1 -or [string]::IsNullOrWhiteSpace([string]$arguments[0])) {
            $this.LogWarning("appxLaunchTarget 検証には AppUserModelID を args[0] に指定してください")
            return $false
        }

        $appUserModelId = [string]$arguments[0]
        $appxPackage = Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $appxPackage) {
            return $false
        }

        $packageFamilyName = [string]$appxPackage.PackageFamilyName
        if ([string]::IsNullOrWhiteSpace($packageFamilyName)) {
            $this.LogWarning("AppX PackageFamilyName が取得できません: $packageName")
            return $false
        }

        $expectedPrefix = "$packageFamilyName!"
        if (-not $appUserModelId.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            $this.LogWarning("AppUserModelID が PackageFamilyName と一致しません: $appUserModelId")
            return $false
        }

        $applicationId = $appUserModelId.Substring($expectedPrefix.Length)
        if ([string]::IsNullOrWhiteSpace($applicationId)) {
            $this.LogWarning("AppUserModelID に Application ID が含まれていません: $appUserModelId")
            return $false
        }

        $installLocation = [string]$appxPackage.InstallLocation
        if ([string]::IsNullOrWhiteSpace($installLocation)) {
            $this.LogWarning("AppX InstallLocation が取得できません: $packageName")
            return $false
        }

        $manifestPath = Join-Path $installLocation "AppxManifest.xml"
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            $this.LogWarning("AppX manifest が見つかりません: $manifestPath")
            return $false
        }

        try {
            [xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw
            $match = Select-Xml -Xml $manifest -XPath "//*[local-name()='Application' and @Id='$applicationId']" |
                Select-Object -First 1
            return $null -ne $match
        }
        catch {
            $this.LogWarning("AppX manifest の読み込みに失敗しました: $($_.Exception.Message)")
            return $false
        }
    }

    hidden [bool] ShouldReinstallOnVerifyFailure([object]$verifyCmd) {
        if ($verifyCmd -is [hashtable] -and $verifyCmd.ContainsKey("reinstallOnVerifyFailure")) {
            return [bool]$verifyCmd["reinstallOnVerifyFailure"]
        }
        if ($verifyCmd -and ($verifyCmd.PSObject.Properties.Name -contains "reinstallOnVerifyFailure")) {
            return [bool]$verifyCmd.reinstallOnVerifyFailure
        }
        return $true
    }

    hidden [string] GetRecoveryStrategy([object]$verifyCmd) {
        if ($verifyCmd -is [hashtable] -and $verifyCmd.ContainsKey("recoveryStrategy")) {
            return [string]$verifyCmd["recoveryStrategy"]
        }
        if ($verifyCmd -and ($verifyCmd.PSObject.Properties.Name -contains "recoveryStrategy")) {
            return [string]$verifyCmd.recoveryStrategy
        }
        return ""
    }

    hidden [int] GetVerifyTimeoutSeconds([object]$verifyCmd) {
        $timeoutSeconds = 15
        if ($verifyCmd -is [hashtable] -and $verifyCmd.ContainsKey("timeoutSeconds")) {
            $timeoutSeconds = [int]$verifyCmd["timeoutSeconds"]
        }
        elseif ($verifyCmd -and ($verifyCmd.PSObject.Properties.Name -contains "timeoutSeconds")) {
            $timeoutSeconds = [int]$verifyCmd.timeoutSeconds
        }

        if ($timeoutSeconds -le 0) {
            return 15
        }
        return $timeoutSeconds
    }

    hidden [void] EnsurePortableLink([object]$pkg) {
        $this.EnsurePortableLinkInternal($pkg, $false)
    }

    hidden [void] EnsurePortableLinkQuiet([object]$pkg) {
        $this.EnsurePortableLinkInternal($pkg, $true)
    }

    hidden [void] EnsurePortableLinkInternal([object]$pkg, [bool]$quiet) {
        if (-not $pkg.PortableLink) { return }

        $linkName = $null
        if ($pkg.PortableLink.PSObject.Properties.Name -contains "linkName") {
            $linkName = [string]$pkg.PortableLink.linkName
        }
        $targetPattern = $null
        if ($pkg.PortableLink.PSObject.Properties.Name -contains "targetPattern") {
            $targetPattern = [string]$pkg.PortableLink.targetPattern
        }
        if (-not $linkName -or -not $targetPattern) {
            $this.LogWarning("portableLink に linkName または targetPattern がありません: $($pkg.Id)")
            return
        }

        $packagesBase = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
        $packageDir = Get-ChildItem -Path $packagesBase -Directory -Filter "$($pkg.Id)_*" -ErrorAction SilentlyContinue |
            Select-Object -First 1
        $target = $null
        if ($packageDir) {
            $target = Get-ChildItem -Path $packageDir.FullName -File -Filter $targetPattern -Recurse -ErrorAction SilentlyContinue |
                Select-Object -First 1
        }
        elseif ($pkg.DirectInstaller) {
            $directDestination = $this.ResolveDirectInstallerPath(
                $this.GetDirectInstallerString($pkg.DirectInstaller, "destination")
            )
            $directExecutable = $this.GetDirectInstallerString($pkg.DirectInstaller, "executable")
            if ($directDestination -and $directExecutable) {
                $directTargetPath = Join-Path $directDestination $directExecutable
                if (Test-Path -LiteralPath $directTargetPath -PathType Leaf) {
                    $target = Get-Item -LiteralPath $directTargetPath
                }
            }
        }

        if (-not $target) {
            if (-not $quiet) {
                $this.LogWarning("portableLink の対象パッケージが見つかりません: $($pkg.Id)")
            }
            return
        }

        if (-not $packageDir -and $target.Name -notlike $targetPattern) {
            if (-not $quiet) {
                $this.LogWarning("portableLink の対象 exe が見つかりません: $($pkg.Id) ($targetPattern)")
            }
            return
        }

        $linksPath = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"
        if (-not (Test-Path -LiteralPath $linksPath)) {
            New-Item -ItemType Directory -Path $linksPath -Force | Out-Null
        }

        $linkPath = Join-Path $linksPath $linkName
        $linkIsCurrent = $this.IsPortableLinkCurrent($linkPath, $target.FullName)
        $copyIsCurrent = $this.IsPortableCopyCurrent($linkPath, $target.FullName)
        if (-not $linkIsCurrent -and -not $copyIsCurrent) {
            try {
                $this.CreatePortableLink($linkPath, $target.FullName)
            }
            catch {
                # Windows PowerShell user sessions cannot create symlinks unless
                # Developer Mode or elevation is enabled. A copied portable exe
                # still gives the user-scoped package a working command; the
                # next Apply refreshes it after a winget upgrade.
                $this.LogWarning("シンボリックリンクを作成できないため portableLink をコピーで作成します: $linkName")
                if (Test-Path -LiteralPath $linkPath) {
                    Remove-Item -LiteralPath $linkPath -Force -ErrorAction Stop
                }
                Copy-Item -LiteralPath $target.FullName -Destination $linkPath -Force -ErrorAction Stop
                $this.Log("portableLink をコピーで作成しました", "Green")
            }
        }

        $userPath = Get-UserEnvironmentPath
        $pathItems = if ($userPath) { @($userPath -split ";" | Where-Object { $_ }) } else { @() }
        if ($pathItems -notcontains $linksPath) {
            Set-UserEnvironmentPath -Path (($pathItems + @($linksPath)) -join ";")
        }
        if (($env:PATH -split ";") -notcontains $linksPath) {
            $env:PATH = "$env:PATH;$linksPath"
        }
    }

    hidden [void] EnsurePathEntries([object]$pkg) {
        $this.EnsurePathEntriesInternal($pkg, $false)
    }

    hidden [void] EnsurePathEntriesQuiet([object]$pkg) {
        $this.EnsurePathEntriesInternal($pkg, $true)
    }

    hidden [void] EnsurePathEntriesInternal([object]$pkg, [bool]$quiet) {
        if (-not $pkg.PathEntries) { return }

        $resolvedEntries = [System.Collections.Generic.List[string]]::new()
        $missingEntries = [System.Collections.Generic.List[string]]::new()
        foreach ($rawEntry in @($pkg.PathEntries)) {
            if ([string]::IsNullOrWhiteSpace([string]$rawEntry)) { continue }

            $expanded = [Environment]::ExpandEnvironmentVariables([string]$rawEntry)
            $resolvedMatches = @(Get-Item -Path $expanded -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer })
            if ($resolvedMatches.Count -eq 0 -and (Test-Path -LiteralPath $expanded -PathType Container)) {
                $resolvedMatches = @(Get-Item -LiteralPath $expanded -ErrorAction SilentlyContinue)
            }

            if ($resolvedMatches.Count -eq 0) {
                $missingEntries.Add([string]$rawEntry)
                continue
            }

            foreach ($match in $resolvedMatches) {
                if (-not [string]::IsNullOrWhiteSpace($match.FullName)) {
                    $resolvedEntries.Add($match.FullName)
                }
            }
        }

        if ($resolvedEntries.Count -eq 0) {
            if ($missingEntries.Count -gt 0 -and -not $quiet) {
                $this.LogWarning("pathEntries の候補ディレクトリが見つかりません: $($pkg.Id) ($($missingEntries -join ', '))")
            }
            return
        }

        $userPath = Get-UserEnvironmentPath
        $userPathItems = if ($userPath) { @($userPath -split ";" | Where-Object { $_ }) } else { @() }
        $processPathItems = if ($env:PATH) { @($env:PATH -split ";" | Where-Object { $_ }) } else { @() }

        $newUserPathItems = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $userPathItems) { $newUserPathItems.Add($item) }

        $updatedUserPath = $false
        foreach ($entry in $resolvedEntries) {
            if ($userPathItems -notcontains $entry) {
                $newUserPathItems.Add($entry)
                $updatedUserPath = $true
            }
            if ($processPathItems -notcontains $entry) {
                $env:PATH = if ($env:PATH) { "$env:PATH;$entry" } else { $entry }
                $processPathItems += $entry
            }
        }

        if ($updatedUserPath) {
            Set-UserEnvironmentPath -Path ($newUserPathItems -join ";")
            $this.Log("USER PATH にパッケージ PATH を追加しました: $($resolvedEntries -join ', ')", "Green")
        }
    }

    <#
    .SYNOPSIS
        インストール済みパッケージをエクスポートする (winget export)
    #>
    hidden [SetupResult] ExportPackages([SetupContext]$ctx) {
        try {
            $packagesPath = $this.GetPackagesPath($ctx)
            $this.Log("winget パッケージをエクスポートしています...")
            $this.Log("出力先: $packagesPath")

            # 出力ディレクトリが存在しない場合は作成
            $parentDir = Split-Path -Parent $packagesPath
            if (-not (Test-PathExist -Path $parentDir)) {
                New-DirectorySafe -Path $parentDir | Out-Null
            }

            Invoke-Winget -Arguments @(
                "export",
                "-o", $packagesPath
            ) | Out-Null

            if ($LASTEXITCODE -eq 0) {
                $this.Log("winget export 完了", "Green")
                $this.Log("git でコミットするのを忘れずに", "Gray")
                return $this.CreateSuccessResult("パッケージリストをエクスポートしました: $packagesPath")
            }
            else {
                # 一部エクスポートできないパッケージがあっても続行
                $this.LogWarning("一部のパッケージがエクスポートできなかった可能性があります（正常な動作です）")
                return $this.CreateSuccessResult("パッケージリストをエクスポートしました（一部除外）: $packagesPath")
            }
        }
        catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }

    <#
    .SYNOPSIS
        ~/.cargo/bin を User PATH に追加する
    .DESCRIPTION
        Rustup (Rustlang.Rustup) インストール後、cargo 等のコマンドを
        ターミナルから直接実行できるようにするため、~/.cargo/bin を
        永続的に User 環境変数 PATH に追加する。
    #>
    hidden [void] EnsureCargoPath() {
        $cargoBinPath = "$env:USERPROFILE\.cargo\bin"

        if (-not (Test-Path $cargoBinPath)) {
            return
        }

        $userPath = Get-UserEnvironmentPath
        $pathItems = if ($userPath) { $userPath -split ";" } else { @() }

        if ($pathItems -contains $cargoBinPath) {
            $this.Log(".cargo\bin は既に PATH に含まれています", "Gray")
            return
        }

        $newPath = ($pathItems + @($cargoBinPath) | Where-Object { $_ }) -join ";"
        Set-UserEnvironmentPath -Path $newPath
        $env:PATH = "$env:PATH;$cargoBinPath"
        $this.Log(".cargo\bin を USER PATH に追加しました: $cargoBinPath", "Green")
    }

    <#
    .SYNOPSIS
        パッケージリストファイルのパスを取得する
    #>
    hidden [string] GetPackagesPath([SetupContext]$ctx) {
        return Join-Path $ctx.DotfilesPath "windows\winget\packages.json"
    }
}
