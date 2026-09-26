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

            $this.RemoveRetiredPackages((Split-Path -Parent $packagesPath)) | Out-Null

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
                $packages = @($packages | Where-Object {
                        $null -ne $_.VerifyCommand -and
                        -not $_.CiSkipInstall -and
                        -not $_.SkipInstall
                    })
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
            # 表示名やバージョンに含まれるドットを ID と誤認しないよう、manifest ID と照合する。
            $wingetPackageIds = @($packages | Where-Object { $_.SourceName -eq "winget" } | ForEach-Object { [string]$_.Id })
            $installedIds = $this.GetInstalledPackageIds($wingetPackageIds)

            # 通常実行ではインストール済みも含めて winget install を流し、
            # winget 側の install-or-upgrade 動作で latest を選ばせる。
            $verifyCommandOnly = $ctx.GetOption("WingetVerifyCommandOnly", $false)
            if ($verifyCommandOnly) {
                $inventoryIds = @($packages | ForEach-Object { [string]$_.Id } | Sort-Object -Unique)
                $this.Log("CI_VERIFICATION_INVENTORY: $($inventoryIds -join '|')", "Gray")
            }
            $toInstall = @()
            $skipped = 0
            $verified = 0
            $verifyFailed = 0
            $deferred = 0
            foreach ($pkg in $packages) {
                $directInstallerCurrent = $pkg.DirectInstaller -and $this.TestDirectInstallerCurrent($pkg)
                $isInstalled = ($pkg.Id -in $installedIds) -or $directInstallerCurrent
                if (-not $isInstalled) {
                    $isInstalled = $this.IsPackageInstalled($pkg.Id, $pkg.SourceName)
                }

                $verificationPassed = $false
                if ($pkg.VerifyCommand -and $this.ShouldDeferWslVerificationToAdminInstall($pkg, $ctx)) {
                    $this.LogWarning("Microsoft.WSL の検証は Phase 2b の管理者 WSL インストールに委譲します")
                    $deferred++
                    continue
                }

                if ($pkg.VerifyCommand -and ($isInstalled -or $directInstallerCurrent)) {
                    # Existing portable packages need their command shim before
                    # verification. Missing package directories are expected
                    # before the first install, so keep this lookup quiet.
                    $this.EnsurePortableLinkQuiet($pkg)
                    # Explicit pathEntries already support direct verification
                    # without changing PATH. Recover only the missing-link case.
                    if (-not $pkg.PathEntries) { $this.EnsurePathEntriesQuiet($pkg) }
                    $verificationPassed = if ($verifyCommandOnly) {
                        $this.TestPackageVerificationForPackage($pkg, $false)
                    }
                    else {
                        $this.TestPackageVerificationForPackage($pkg, $true)
                    }
                    if ($verificationPassed) {
                        if ($verifyCommandOnly) {
                            $verified++
                            $this.Log("スキップ (検証済み): $($pkg.Id)", "Gray")
                            continue
                        }
                    }
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
                        $toInstall += $this.NewInstallCandidate($pkg, $false, $isInstalled, $verificationPassed)
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
                            $toInstall += $this.NewInstallCandidate($pkg, $true, $isInstalled, $verificationPassed)
                        }
                        else {
                            $this.LogWarning("✗ $($pkg.Id) はインストール済みですが検証に失敗しました")
                            $verifyFailed++
                        }
                    }
                    else {
                        $toInstall += $this.NewInstallCandidate($pkg, $false, $isInstalled, $verificationPassed)
                    }
                }
                else {
                    $toInstall += $this.NewInstallCandidate($pkg, $false, $isInstalled, $verificationPassed)
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
                # A no-op phrase alone cannot prove an unverifiable package is
                # installed. With a verifier, only its successful execution can
                # establish usability; explicit package-conflict responses such
                # as 0x80073cfb are still handled by the verifier/recovery path.
                $alreadyInstalledInstallFailure = $this.IsAlreadyInstalledInstallFailure($installOutput)
                if ($alreadyInstalledInstallFailure -and -not $pkg.WasInstalled -and -not $pkg.VerifyCommand) {
                    $alreadyInstalledInstallFailure = $false
                }
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
                        if ($this.TestPackageVerificationForPackage($pkg, $false)) {
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
                    $this.LogWarning("✗ $($pkg.Id) のインストールに失敗しました (exit code: $($this.LastInstallExitCode))")
                    continue
                }

                Update-ProcessEnvironmentPath

                $this.EnsurePortableLink($pkg)
                $this.EnsurePathEntries($pkg)

                if ($pkg.VerifyCommand -and $this.TestPackageVerificationForPackage($pkg, $false)) {
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

    hidden [object] NewInstallCandidate([object]$pkg, [bool]$force, [bool]$wasInstalled, [bool]$wasVerified) {
        return [PSCustomObject]@{
            Id                    = $pkg.Id
            Version               = $pkg.Version
            SourceName            = $pkg.SourceName
            VerifyCommand         = $pkg.VerifyCommand
            InstallArgs           = $pkg.InstallArgs
            InstallTimeoutSeconds = $pkg.InstallTimeoutSeconds
            DirectInstaller       = $pkg.DirectInstaller
            CiSkipInstall         = $pkg.CiSkipInstall
            PortableLink          = $pkg.PortableLink
            PathEntries           = $pkg.PathEntries
            Force                 = $force
            WasInstalled          = $wasInstalled
            WasVerified           = $wasVerified
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
            $artifactContractSatisfied = $this.TestPackageArtifactContract($pkg)
            if ($wingetExitCode -eq 0 -and $artifactContractSatisfied) {
                $this.LastInstallSucceeded = $true
                $this.LastInstallExitCode = 0
                return $wingetOutput
            }

            if ($wingetExitCode -eq 0) {
                $this.LogWarning("WinGet は $($pkg.Id) のコマンドを導入しましたが、必要な隣接ファイルがありません。公式 archive で修復します")
            }

            if ($pkg.WasVerified -and ($pkg.WasInstalled -or $this.IsAlreadyInstalledInstallFailure($wingetOutput))) {
                return $wingetOutput
            }

            $this.LogWarning("WinGet $($pkg.Id) failed with exit code $wingetExitCode; attempting the configured direct fallback")
            foreach ($line in $wingetOutput) {
                if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                    $this.Log("  WinGet: $line", "Gray")
                }
            }
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
        $startedAt = [DateTime]::UtcNow
        if ($installTimeoutSeconds -gt 0) {
            $output = @(Invoke-Winget -Arguments $installArgs -TimeoutSeconds $installTimeoutSeconds)
            $this.LastInstallExitCode = [int]$LASTEXITCODE
            if ($this.LastInstallExitCode -eq 124) {
                $diagnosis = $this.GetWingetTimeoutDiagnosis([string]$pkg.Id, $startedAt)
                $this.Log("TIMEOUT_DIAGNOSTIC: $diagnosis", "Yellow")
            }
            return $output
        }
        $output = @(Invoke-Winget -Arguments $installArgs)
        $this.LastInstallExitCode = [int]$LASTEXITCODE
        return $output
    }

    hidden [string] GetWingetTimeoutDiagnosis([string]$packageId, [DateTime]$startedAt) {
        $logDirectory = $env:DOTFILES_WINGET_DIAGNOSTIC_LOG_DIR
        if ([string]::IsNullOrWhiteSpace($logDirectory) -and
            -not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
            $logDirectory = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir"
        }

        if ([string]::IsNullOrWhiteSpace($logDirectory) -or -not [System.IO.Directory]::Exists($logDirectory)) {
            return "package=$packageId class=unknown confidence=low evidence=no diagnostic log directory"
        }

        $matchingLog = $null
        $matchingText = $null
        foreach ($logPath in [System.IO.Directory]::GetFiles($logDirectory, "WinGet-*.log")) {
            $info = [System.IO.FileInfo]::new($logPath)
            if ($info.LastWriteTimeUtc -lt $startedAt.AddSeconds(-3)) { continue }
            $text = [System.IO.File]::ReadAllText($logPath)
            if ($text.IndexOf($packageId, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
            if ($null -eq $matchingLog -or $info.LastWriteTimeUtc -gt $matchingLog.LastWriteTimeUtc) {
                $matchingLog = $info
                $matchingText = $text
            }
        }

        if ($null -eq $matchingLog) {
            return "package=$packageId class=unknown confidence=low evidence=no matching recent WinGet log"
        }

        $lines = @($matchingText -split "\r?\n")
        $cacheLock = @($lines | Where-Object {
                $_ -match 'Failed to remove installer file|being used by another process|process cannot access the file'
            })
        $downloadStart = @($lines | Where-Object { $_ -match 'DeliveryOptimization downloading from url|Downloading to path' })
        $networkError = @($lines | Where-Object {
                $_ -match 'WinHttpSendRequest|0x80072ee2|0x80072efe|download failed|Failed to connect|connection.*timed out'
            })
        $sourceError = @($lines | Where-Object { $_ -match '0x8a15000[0-9a-f]|Failed to open source|source.*failed' })

        $classification = "unknown"
        $confidence = "low"
        $evidenceLines = @()
        if ($cacheLock.Count -gt 0) {
            $classification = "installer-cache-contention"
            $confidence = "medium"
            $evidenceLines = @($cacheLock | Select-Object -First 1) + @($downloadStart | Select-Object -First 1)
        }
        elseif ($networkError.Count -gt 0) {
            $classification = "network-download-failure"
            $confidence = "high"
            $evidenceLines = @($networkError | Select-Object -First 1)
        }
        elseif ($sourceError.Count -gt 0) {
            $classification = "source-resolution-failure"
            $confidence = "high"
            $evidenceLines = @($sourceError | Select-Object -First 1)
        }
        elseif ($downloadStart.Count -gt 0 -and $matchingText -notmatch 'Installer download completed|Download completed|download completed successfully') {
            $classification = "delivery-optimization-download-incomplete"
            $confidence = "medium"
            $evidenceLines = @($downloadStart | Select-Object -First 1)
        }

        $evidence = ($evidenceLines -join "; ") -replace 'https?://[^\s"'']+', '<url>'
        $evidence = $evidence -replace '(?i)[A-Z]:\\Users\\[^\\\s"'']+\\AppData\\Local\\Temp\\[^\s"'']+', '%LOCALAPPDATA%\\Temp\\<installer>'
        $evidence = $evidence.Trim()
        if ($evidence.Length -gt 240) { $evidence = $evidence.Substring(0, 240) }
        if ([string]::IsNullOrWhiteSpace($evidence)) { $evidence = "no classified evidence in $($matchingLog.Name)" }
        return "package=$packageId class=$classification confidence=$confidence evidence=$evidence"
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

        $archiveExtension = if ($url -match '(?i)\.tar\.gz(?:[?#]|$)') { ".tar.gz" } else { ".zip" }
        $archivePath = Join-Path $env:TEMP ("dotfiles-$([guid]::NewGuid().ToString('N'))$archiveExtension")
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
            if ($archiveExtension -eq ".tar.gz") {
                $extractOutput = @(
                    Invoke-ExternalCommandWithTimeout `
                        -Command "tar.exe" `
                        -Arguments @("-xzf", $archivePath, "-C", $stagingPath) `
                        -TimeoutSeconds $timeoutSeconds
                )
                if ($LASTEXITCODE -ne 0) {
                    $extractDetails = ($extractOutput | ForEach-Object { [string]$_ }) -join "`n"
                    throw "directInstaller tar.gz extraction failed for $($pkg.Id): $extractDetails"
                }
            }
            else {
                Expand-Archive -LiteralPath $archivePath -DestinationPath $stagingPath -Force
            }
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
        if ($this.TestPackageVerificationForPackage($pkg, $false)) {
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
        if ($this.TestPackageVerificationForPackage($pkg, $false)) {
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
    hidden [string[]] GetInstalledPackageIds([string[]]$candidateIds) {
        try {
            if (-not $candidateIds -or $candidateIds.Count -eq 0) {
                return @()
            }

            # Restrict the bulk query to the community source. Without an
            # explicit source winget may probe Microsoft Store and block on a
            # network timeout before the package loop even starts.
            $output = Invoke-Winget -Arguments @("list", "--source", "winget", "--disable-interactivity")
            if ($LASTEXITCODE -ne 0) { return @() }
            # winget list は固定幅表示なので列位置には依存せず、manifest にある完全一致 ID だけを拾う。
            # 表示名やバージョンもドットを含み得るため、形式だけで ID を推測してはいけない。
            $ids = @()
            $headerPassed = $false
            foreach ($line in $output) {
                if ($line -match '^-{2,}') { $headerPassed = $true; continue }
                if (-not $headerPassed) { continue }

                foreach ($candidateId in $candidateIds) {
                    if ([string]::IsNullOrWhiteSpace($candidateId)) { continue }
                    $escapedId = [regex]::Escape($candidateId)
                    if ($line -match "(?<!\S)$escapedId(?!\S)") {
                        $ids += $candidateId
                        break
                    }
                }
            }
            return @($ids | Select-Object -Unique)
        }
        catch {
            throw "インストール済みパッケージ一覧の取得に失敗しました: $($_.Exception.Message)"
        }
    }

    <#
        .SYNOPSIS
        旧 manifest から外したパッケージを、インストール済みの場合のみ削除する
    #>
    hidden [int] RemoveRetiredPackages([string]$manifestDirectory) {
        $retiredManifestPath = Join-Path $manifestDirectory "retired-packages.json"
        if (-not [System.IO.File]::Exists($retiredManifestPath)) {
            throw "retired package manifest is missing: $retiredManifestPath"
        }

        $retiredManifest = Get-Content -LiteralPath $retiredManifestPath -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
        $removedCount = 0
        foreach ($package in @($retiredManifest.packages)) {
            $packageId = [string]$package.id
            $packageName = [string]$package.name
            $sourceName = [string]$package.source
            if (
                [string]::IsNullOrWhiteSpace($packageId) -or
                [string]::IsNullOrWhiteSpace($packageName) -or
                $sourceName -notin @("winget", "msstore")
            ) {
                throw "retired package entry is missing a valid id, name, or source: $retiredManifestPath"
            }

            $arguments = @(
                "uninstall", "--id", $packageId, "--exact", "--source", $sourceName,
                "--silent", "--disable-interactivity", "--accept-source-agreements"
            )
            $output = @(Invoke-Winget -Arguments $arguments -TimeoutSeconds (Get-PackageInstallTimeoutSecond))
            $uninstallExitCode = [int]$LASTEXITCODE
            foreach ($line in $output) {
                if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                    $this.Log("  $line", "Gray")
                }
            }

            $queryArguments = @(
                "list", "--id", $packageId, "--exact", "--source", $sourceName,
                "--disable-interactivity"
            )
            $queryOutput = @(Invoke-Winget -Arguments $queryArguments -TimeoutSeconds (Get-PackageInstallTimeoutSecond))
            $queryExitCode = [int]$LASTEXITCODE
            $escapedPackageId = [regex]::Escape($packageId)
            $packageStillListed = @($queryOutput | Where-Object {
                    ([string]$_) -match "(?<!\S)$escapedPackageId(?!\S)"
                }).Count -gt 0
            if ($packageStillListed) {
                throw "retired package remains installed after uninstall: $packageName ($packageId)"
            }

            $queryExitCodeUnsigned = [BitConverter]::ToUInt32([BitConverter]::GetBytes($queryExitCode), 0)
            $queryExitCodeHex = $queryExitCodeUnsigned.ToString("X8")
            if ($queryExitCodeHex -ne "8A150014") {
                throw "unable to verify retired package state: $packageName ($packageId), list exit code $queryExitCodeHex"
            }

            $uninstallExitCodeUnsigned = [BitConverter]::ToUInt32([BitConverter]::GetBytes($uninstallExitCode), 0)
            $uninstallExitCodeHex = $uninstallExitCodeUnsigned.ToString("X8")
            if ($uninstallExitCode -eq 0) {
                $removedCount++
                $this.Log("RETIRED_PACKAGE_CLEANUP: id=$packageId status=removed", "Green")
                $this.Log("削除済み (retired package): $packageName ($packageId)", "Green")
                continue
            }

            if ($uninstallExitCodeHex -eq "8A150014") {
                $this.Log("RETIRED_PACKAGE_CLEANUP: id=$packageId status=absent", "Gray")
                $this.Log("未インストール (retired package): $packageName ($packageId)", "Gray")
                continue
            }

            throw "retired package uninstall failed: $packageName ($packageId), exit code $uninstallExitCodeHex"
        }

        return $removedCount
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
            throw "パッケージ確認中にエラーが発生しました ($packageId): $($_.Exception.Message)"
        }
    }

    hidden [bool] TestPackageVerification([object]$verifyCmd) {
        return $this.TestPackageVerificationInternal($verifyCmd, $false)
    }

    hidden [bool] TestPackageVerificationForPackage([object]$pkg, [bool]$quiet) {
        $pathEntries = if ($pkg.PSObject.Properties.Name -contains "PathEntries") { [string[]]@($pkg.PathEntries) } else { @() }
        $verified = $this.TestPackageVerificationInternal($pkg.VerifyCommand, $quiet, $pathEntries)
        if (-not $verified) {
            return $false
        }

        return $this.TestPackageArtifactContract($pkg)
    }

    hidden [bool] TestPackageArtifactContract([object]$pkg) {
        if ([string]$pkg.Id -ne "OpenAI.Codex") {
            return $true
        }

        $cliRelativePath = $this.GetDirectInstallerString($pkg.DirectInstaller, "executable")
        $directDestination = $this.ResolveDirectInstallerPath(
            $this.GetDirectInstallerString($pkg.DirectInstaller, "destination")
        )
        if (-not [string]::IsNullOrWhiteSpace($cliRelativePath) -and
            -not [string]::IsNullOrWhiteSpace($directDestination)) {
            $directCliPath = Join-Path $directDestination $cliRelativePath
            $directHostPath = Join-Path (Split-Path -Parent $directCliPath) "codex-code-mode-host.exe"
            if ([System.IO.File]::Exists($directCliPath) -and [System.IO.File]::Exists($directHostPath)) {
                return $true
            }
        }

        $localAppData = if ($env:LOCALAPPDATA) {
            $env:LOCALAPPDATA
        }
        elseif ($env:USERPROFILE) {
            Join-Path $env:USERPROFILE "AppData\Local"
        }
        else {
            [Environment]::GetFolderPath("LocalApplicationData")
        }
        $wingetPackagesPath = Join-Path $localAppData "Microsoft\WinGet\Packages"
        if ([System.IO.Directory]::Exists($wingetPackagesPath)) {
            foreach ($packageDirectory in [System.IO.Directory]::GetDirectories($wingetPackagesPath, "OpenAI.Codex_*")) {
                foreach ($cliName in @("codex.exe", "codex-x86_64-pc-windows-msvc.exe")) {
                    $cliPaths = [System.IO.Directory]::GetFiles($packageDirectory, $cliName, [System.IO.SearchOption]::AllDirectories)
                    foreach ($cliPath in $cliPaths) {
                        $hostPath = Join-Path (Split-Path -Parent $cliPath) "codex-code-mode-host.exe"
                        if ([System.IO.File]::Exists($hostPath)) {
                            return $true
                        }
                    }
                }
            }
        }

        $this.LogWarning("OpenAI.Codex の隣接実体が不足しています: codex.exe と codex-code-mode-host.exe の両方が必要です")
        return $false
    }

    hidden [bool] TestPackageVerificationQuiet([object]$verifyCmd) {
        return $this.TestPackageVerificationInternal($verifyCmd, $true, @())
    }

    hidden [bool] TestPackageVerificationInternal([object]$verifyCmd, [bool]$quiet) {
        return $this.TestPackageVerificationInternal($verifyCmd, $quiet, @())
    }

    hidden [bool] TestPackageVerificationInternal([object]$verifyCmd, [bool]$quiet, [string[]]$pathEntries) {
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
            $timeoutSeconds = $this.GetVerifyTimeoutSeconds($verifyCmd)

            if ($type -eq "commandExists") {
                return $null -ne (Get-ExternalCommand -Name $command)
            }

            if ($type -eq "appxPackage") {
                if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
                    $this.Log("検証コマンド実行エラー: Get-AppxPackage が利用できません", "Yellow")
                    return $false
                }

                $appxPackage = Get-AppxPackage -Name $command -ErrorAction SilentlyContinue
                if ($null -eq $appxPackage -or [string]::IsNullOrWhiteSpace([string]$appxPackage.InstallLocation)) {
                    return $false
                }
                $appxVersion = $null
                return [version]::TryParse([string]$appxPackage.Version, [ref]$appxVersion)
            }

            if ($type -eq "appxLaunchTarget") {
                return $this.TestAppxLaunchTarget($command, $arguments)
            }

            if ($type -eq "portableLinkCommand") {
                return $this.TestPortableLinkCommand($command, $arguments, $timeoutSeconds)
            }

            if ($type -eq "windowsInstalledProduct") {
                return $this.TestWindowsInstalledProduct($verifyCmd)
            }

            if ($type -eq "visualStudioInstanceVersion") {
                return $this.TestVisualStudioInstanceVersion($verifyCmd)
            }

            # Resolve applications explicitly so PowerShell aliases cannot
            # shadow them. If PATH has no executable, search only this package's
            # manifest pathEntries; verification itself must not publish PATH.
            $discoveredCommand = Get-Command -Name $command -ErrorAction SilentlyContinue
            $resolvedCommand = Get-Command -Name $command -CommandType Application -ErrorAction SilentlyContinue |
                Select-Object -First 1
            $commandPaths = @()
            if ($resolvedCommand) {
                if ($discoveredCommand -and $discoveredCommand.CommandType -eq [System.Management.Automation.CommandTypes]::Alias) {
                    $commandPath = if (-not [string]::IsNullOrWhiteSpace([string]$resolvedCommand.Path)) {
                        [string]$resolvedCommand.Path
                    }
                    else {
                        [string]$resolvedCommand.Source
                    }
                    $commandPaths = @($commandPath)
                }
                else {
                    # Keep normal PATH resolution behavior for compatibility.
                    $commandPaths = @([string]$command)
                }
            }
            else {
                $commandPaths = @($this.GetPackageCommandPaths([string]$command, $pathEntries))
                if ($commandPaths.Count -eq 0) {
                    # Preserve the existing process-level probe as a last resort;
                    # Invoke-VerifyCommand reports a real missing command as failure.
                    $commandPaths = @([string]$command)
                }
            }

            $lastOutput = @()
            $lastExitCode = 1
            foreach ($commandPath in $commandPaths) {
                $lastOutput = @(Invoke-VerifyCommand -Command $commandPath -Arguments $arguments -TimeoutSeconds $timeoutSeconds)
                if ($global:LASTEXITCODE -eq 0) {
                    return $true
                }
                $lastExitCode = [int]$global:LASTEXITCODE
            }

            $displayCommand = "$command $($arguments -join ' ')".Trim()
            if (-not $quiet) {
                $this.Log("検証コマンド失敗 (exit code: $lastExitCode): $displayCommand", "Yellow")
                foreach ($line in $lastOutput) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                        $this.Log("  $line", "Gray")
                    }
                }
            }
            return $false
        }
        catch {
            if (-not $quiet) {
                $this.Log("検証コマンド実行エラー: $($_.Exception.Message)", "Yellow")
            }
            return $false
        }
    }

    hidden [string[]] GetPackageCommandPaths([string]$command, [string[]]$pathEntries) {
        if ([string]::IsNullOrWhiteSpace($command) -or -not $pathEntries) {
            return @()
        }

        $commandName = [System.IO.Path]::GetFileName($command)
        if ($commandName -ne $command) {
            return @()
        }

        $extensions = @([System.IO.Path]::GetExtension($commandName))
        if ([string]::IsNullOrWhiteSpace($extensions[0])) {
            $extensions = @($env:PATHEXT -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($extensions.Count -eq 0) {
                $extensions = @('.COM', '.EXE', '.BAT', '.CMD')
            }
        }
        $executableNames = @($extensions | ForEach-Object { "$commandName$_" } | Select-Object -Unique)
        $commandPaths = [System.Collections.Generic.List[string]]::new()
        $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        foreach ($rawEntry in $pathEntries) {
            if ([string]::IsNullOrWhiteSpace($rawEntry)) { continue }
            $expandedEntry = [Environment]::ExpandEnvironmentVariables($rawEntry)
            $directories = @(Get-Item -Path $expandedEntry -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer })
            foreach ($directory in $directories) {
                foreach ($executableName in $executableNames) {
                    $matchingExecutables = @(Get-ChildItem -LiteralPath $directory.FullName -Filter $executableName -File -Recurse -ErrorAction SilentlyContinue)
                    foreach ($match in $matchingExecutables) {
                        if ($seenPaths.Add($match.FullName)) {
                            $commandPaths.Add($match.FullName)
                        }
                    }
                }
            }
        }

        return @($commandPaths)
    }

    hidden [bool] TestPortableLinkCommand([string]$linkName, [object[]]$arguments, [int]$timeoutSeconds) {
        if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
            $this.Log("portableLinkCommand 検証に LOCALAPPDATA が必要です", "Yellow")
            return $false
        }

        $linkPath = Join-Path (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links") $linkName
        if (-not (Test-Path -LiteralPath $linkPath -PathType Leaf)) {
            $this.Log("WinGet portable link が見つかりません: $linkPath", "Yellow")
            return $false
        }

        $output = @(Invoke-VerifyCommand -Command $linkPath -Arguments $arguments -TimeoutSeconds $timeoutSeconds)
        if ($LASTEXITCODE -eq 0) {
            return $true
        }

        $displayCommand = "$linkPath $($arguments -join ' ')".Trim()
        $this.Log("検証コマンド失敗 (exit code: $LASTEXITCODE): $displayCommand", "Yellow")
        foreach ($line in $output) {
            if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                $this.Log("  $line", "Gray")
            }
        }
        return $false
    }

    hidden [bool] TestWindowsInstalledProduct([object]$verifyCmd) {
        $appx = if ($verifyCmd.PSObject.Properties.Name -contains "appxPackage") { $verifyCmd.appxPackage } else { $null }
        if ($appx) {
            if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
                $this.Log("検証コマンド実行エラー: Get-AppxPackage が利用できません", "Yellow")
                return $false
            }

            $appxPackage = Get-AppxPackage -Name ([string]$appx.name) -ErrorAction SilentlyContinue |
                Where-Object { $_.PackageFamilyName -eq [string]$appx.packageFamilyName } |
                Select-Object -First 1
            $appxVersion = $null
            if ($null -ne $appxPackage -and
                [version]::TryParse([string]$appxPackage.Version, [ref]$appxVersion) -and
                -not [string]::IsNullOrWhiteSpace([string]$appxPackage.InstallLocation)) {
                $appxExecutable = Join-Path ([string]$appxPackage.InstallLocation) ([string]$appx.executable)
                if ($this.TestInstalledExecutableVersion(@($appxExecutable))) {
                    return $true
                }
                $this.Log("AppX package の実行ファイルまたは製品バージョンが不正です: $appxExecutable", "Yellow")
            }
            else {
                $this.Log("AppX package family またはインストールバージョンを確認できません: $($appx.name)", "Yellow")
            }
        }

        $uninstall = if ($verifyCmd.PSObject.Properties.Name -contains "uninstallEntry") { $verifyCmd.uninstallEntry } else { $null }
        if (-not $uninstall) {
            return $false
        }

        $productCodes = @()
        if ($uninstall.PSObject.Properties.Name -contains "productCodes") {
            $productCodes = @($uninstall.productCodes | ForEach-Object { ([string]$_).Trim().Trim("{}") } | Where-Object { $_ })
        }
        $registryRoots = @(
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
            "HKCU:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
            "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
        )

        $matchingRegistrationFound = $false
        foreach ($registryRoot in $registryRoots) {
            foreach ($registryKey in (Get-ChildItem -LiteralPath $registryRoot -ErrorAction SilentlyContinue)) {
                $entry = Get-ItemProperty -LiteralPath $registryKey.PSPath -ErrorAction SilentlyContinue
                if ($null -eq $entry) { continue }

                $keyName = if ($registryKey.PSObject.Properties.Name -contains "PSChildName") {
                    [string]$registryKey.PSChildName
                }
                else {
                    [string]$registryKey.Name.Split("\")[-1]
                }
                $uninstallString = if ($entry.PSObject.Properties.Name -contains "UninstallString") { [string]$entry.UninstallString } else { "" }
                $productCodeMatch = $productCodes.Count -gt 0 -and (
                    $productCodes -contains $keyName.Trim().Trim("{}") -or
                    (@($productCodes | Where-Object { $uninstallString -match [regex]::Escape($_) }).Count -gt 0)
                )
                $entryDisplayName = if ($entry.PSObject.Properties.Name -contains "DisplayName") { [string]$entry.DisplayName } else { "" }
                $entryPublisher = if ($entry.PSObject.Properties.Name -contains "Publisher") { [string]$entry.Publisher } else { "" }
                $expectedDisplayName = if ($uninstall.PSObject.Properties.Name -contains "displayName") { [string]$uninstall.displayName } else { "" }
                $expectedDisplayNamePattern = if ($uninstall.PSObject.Properties.Name -contains "displayNamePattern") { [string]$uninstall.displayNamePattern } else { "" }
                $expectedPublisher = if ($uninstall.PSObject.Properties.Name -contains "publisher") { [string]$uninstall.publisher } else { "" }
                $displayNameMatch = $true
                if (-not [string]::IsNullOrWhiteSpace($expectedDisplayName)) {
                    $displayNameMatch = $entryDisplayName -eq $expectedDisplayName
                }
                if (-not [string]::IsNullOrWhiteSpace($expectedDisplayNamePattern)) {
                    $displayNameMatch = $entryDisplayName -match $expectedDisplayNamePattern
                }
                $publisherMatch = [string]::IsNullOrWhiteSpace($expectedPublisher) -or
                $entryPublisher -eq $expectedPublisher

                $identityMatch = if ($productCodes.Count -gt 0) { $productCodeMatch } else { $displayNameMatch }
                if (-not $identityMatch -or -not $displayNameMatch -or -not $publisherMatch) { continue }
                $matchingRegistrationFound = $true

                [string[]]$executablePaths = @()
                if ($uninstall.PSObject.Properties.Name -contains "executablePaths") {
                    $executablePaths = [string[]]@($uninstall.executablePaths)
                }
                $displayIconValue = if ($entry.PSObject.Properties.Name -contains "DisplayIcon") { [string]$entry.DisplayIcon } else { "" }
                if (-not [string]::IsNullOrWhiteSpace($displayIconValue)) {
                    $displayIcon = [regex]::Match($displayIconValue, '^\s*"?([^",]+\.exe)').Groups[1].Value
                    if ($displayIcon) { $executablePaths = [string[]]@($executablePaths) + [string[]]@($displayIcon) }
                }
                if ($this.TestInstalledExecutableVersion($executablePaths)) {
                    return $true
                }
                $this.Log("一致するアンインストール登録に実行可能な製品ファイルがありません: $($verifyCmd.command) ($($executablePaths -join ', '))", "Yellow")
            }
        }

        if (-not $matchingRegistrationFound) {
            $this.Log("製品ID/表示名/発行元に一致するアンインストール登録がありません: $($verifyCmd.command)", "Yellow")
        }

        return $false
    }

    hidden [bool] TestInstalledExecutableVersion([string[]]$executablePaths) {
        foreach ($rawPath in $executablePaths) {
            if ([string]::IsNullOrWhiteSpace($rawPath)) { continue }
            $path = [Environment]::ExpandEnvironmentVariables($rawPath)
            $files = @(Get-ChildItem -Path $path -File -ErrorAction SilentlyContinue)
            foreach ($file in $files) {
                $fileVersion = if (-not [string]::IsNullOrWhiteSpace([string]$file.VersionInfo.ProductVersion)) {
                    [string]$file.VersionInfo.ProductVersion
                }
                else {
                    [string]$file.VersionInfo.FileVersion
                }
                if ($fileVersion -match '^\s*[vV]?\d+(?:\.\d+){1,3}(?:\s|[-+]|$)') {
                    return $true
                }
            }
        }
        return $false
    }

    hidden [bool] TestVisualStudioInstanceVersion([object]$verifyCmd) {
        $vswhere = Get-Command -Name "vswhere.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        $vswherePath = if ($vswhere) { [string]$vswhere.Source } else { $null }
        if ([string]::IsNullOrWhiteSpace($vswherePath)) {
            $programFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
            if ($programFilesX86) {
                $candidate = Join-Path $programFilesX86 "Microsoft Visual Studio\Installer\vswhere.exe"
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    $vswherePath = $candidate
                }
            }
        }
        if ([string]::IsNullOrWhiteSpace($vswherePath)) {
            $this.Log("Visual Studio Installer の vswhere.exe が見つかりません", "Yellow")
            return $false
        }

        $arguments = @(
            "-all",
            "-products", [string]$verifyCmd.productId,
            "-requires", [string]$verifyCmd.requiredComponent,
            "-format", "json",
            "-utf8"
        )
        $output = @(Invoke-VerifyCommand -Command $vswherePath -Arguments $arguments -TimeoutSeconds 30)
        if ($LASTEXITCODE -ne 0) {
            $this.Log("vswhere が Visual Studio インスタンスを確認できませんでした (exit code: $LASTEXITCODE)", "Yellow")
            return $false
        }

        try {
            $instances = @((($output -join [Environment]::NewLine) | ConvertFrom-Json))
        }
        catch {
            $this.Log("vswhere の JSON 出力を解析できません: $($_.Exception.Message)", "Yellow")
            return $false
        }

        foreach ($instance in $instances) {
            $version = $null
            if (-not [version]::TryParse([string]$instance.installationVersion, [ref]$version)) { continue }
            $minimumVersion = $null
            if (-not [version]::TryParse([string]$verifyCmd.minimumVersion, [ref]$minimumVersion) -or
                $version -lt $minimumVersion) { continue }
            if ([string]::IsNullOrWhiteSpace([string]$instance.installationPath)) { continue }

            $compilerPattern = Join-Path ([string]$instance.installationPath) ([string]$verifyCmd.compilerRelativePath)
            if (Get-ChildItem -Path $compilerPattern -File -ErrorAction SilentlyContinue | Select-Object -First 1) {
                return $true
            }
        }

        $this.Log("VCTools を含む Build Tools の cl.exe が見つかりません: $($verifyCmd.compilerRelativePath)", "Yellow")
        return $false
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

        $appxVersion = $null
        if (-not [version]::TryParse([string]$appxPackage.Version, [ref]$appxVersion)) {
            $this.LogWarning("AppX package version が不正です: $packageName")
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
            if ($null -eq $match) {
                return $false
            }

            $executableRelativePath = [string]$match.Node.GetAttribute("Executable")
            if ([string]::IsNullOrWhiteSpace($executableRelativePath)) {
                $this.LogWarning("AppX manifest に executable がありません: $applicationId")
                return $false
            }

            $executablePath = Join-Path $installLocation $executableRelativePath
            if (Test-Path -LiteralPath $executablePath -PathType Leaf) {
                return $true
            }
            $this.LogWarning("AppX manifest の executable が存在しません: $executablePath")
            return $false
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

    hidden [void] EnsureProcessPathEntries([object]$pkg) {
        $this.EnsurePathEntriesInternal($pkg, $true, $false)
    }

    hidden [string] FindPortableCommandDirectory([object]$pkg) {
        if (-not $pkg.VerifyCommand -or
            -not ($pkg.VerifyCommand.PSObject.Properties.Name -contains 'command')) { return '' }
        $commandName = [string]$pkg.VerifyCommand.command
        if ($commandName -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_.-]*$' -or
            [string]$pkg.Id -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_.-]*$') { return '' }
        if (($pkg.VerifyCommand.PSObject.Properties.Name -contains 'type') -and
            [string]$pkg.VerifyCommand.type -notin @('command', 'commandExists')) { return '' }

        $executableName = if ($commandName.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase)) { $commandName } else { "$commandName.exe" }
        $candidates = @(
            foreach ($base in @($env:LOCALAPPDATA, $env:ProgramFiles)) {
                if (-not $base) { continue }
                $relativeRoot = if ($base -eq $env:LOCALAPPDATA) { 'Microsoft\WinGet\Packages' } else { 'WinGet\Packages' }
                $packagesRoot = Join-Path $base $relativeRoot
                foreach ($packageDirectory in @(Get-ChildItem -LiteralPath $packagesRoot -Directory -Filter "$($pkg.Id)_*" -ErrorAction SilentlyContinue)) {
                    Get-ChildItem -LiteralPath $packageDirectory.FullName -File -Filter $executableName -Recurse -ErrorAction SilentlyContinue
                }
            }
        )
        if ($candidates.Count -eq 1) { return $candidates[0].DirectoryName }
        if ($candidates.Count -gt 1) {
            $this.LogWarning("Multiple package executables found; cannot choose a PATH entry: $($pkg.Id) / $executableName")
        }
        return ''
    }

    hidden [void] EnsurePathEntriesInternal([object]$pkg, [bool]$quiet) {
        $this.EnsurePathEntriesInternal($pkg, $quiet, $true)
    }

    hidden [void] EnsurePathEntriesInternal([object]$pkg, [bool]$quiet, [bool]$persist) {
        $pathEntries = @($pkg.PathEntries)
        if (-not $pkg.PathEntries) {
            # WinGet can report "already installed" even if its Links shim is
            # missing. Use the matching package's real directory, including
            # nested bin directories, so sibling DLLs/resources remain intact.
            $recoveredDirectory = $this.FindPortableCommandDirectory($pkg)
            if (-not $recoveredDirectory) { return }
            $pathEntries = @($recoveredDirectory)
        }

        $resolvedEntries = [System.Collections.Generic.List[string]]::new()
        $missingEntries = [System.Collections.Generic.List[string]]::new()
        foreach ($rawEntry in $pathEntries) {
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

        if ($updatedUserPath -and $persist) {
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
