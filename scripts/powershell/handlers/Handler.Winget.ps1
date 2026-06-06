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
            # exit code 0 かつ出力に v があるか確認（例: v1.6.3133）
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
                                $portableLink = $null
                                if ($pkg.PSObject.Properties.Name -contains "portableLink") {
                                    $portableLink = $pkg.portableLink
                                }
                                $pathEntries = @()
                                if ($pkg.PSObject.Properties.Name -contains "pathEntries") {
                                    $pathEntries = @($pkg.pathEntries)
                                }
                                $packages += [PSCustomObject]@{
                                    Id            = $pkg.PackageIdentifier
                                    Version       = $version
                                    SourceName    = $sourceName
                                    VerifyCommand = $verifyCommand
                                    InstallArgs   = $installArgs
                                    InstallTimeoutSeconds = $installTimeoutSeconds
                                    PortableLink  = $portableLink
                                    PathEntries   = $pathEntries
                                }
                            }
                        }
                    }
                }
            }

            if ($ctx.GetOption("WingetVerifyCommandOnly", $false)) {
                $packages = @($packages | Where-Object { $null -ne $_.VerifyCommand })
                $this.Log("CI 検証モード: verifyCommand 付きパッケージのみ対象にします ($($packages.Count) 個)", "Gray")
            }

            if ($packages.Count -eq 0) {
                $this.Log("インストールするパッケージがありません", "Gray")
                return $this.CreateSuccessResult("パッケージリストが空です")
            }

            # インストール済みパッケージを一括取得（winget list を1回だけ実行）
            # 正規表現で検出できないパッケージ（ARP エントリ等）は個別チェックにフォールバック
            $installedIds = $this.GetInstalledPackageIds()

            # 未インストール、または検証に失敗したパッケージをフィルタリング
            $toInstall = @()
            $skipped = 0
            $verified = 0
            $verifyFailed = 0
            $deferred = 0
            foreach ($pkg in $packages) {
                if ($pkg.VerifyCommand) {
                    Update-ProcessEnvironmentPath
                    $this.EnsurePortableLink($pkg)
                    $this.EnsurePathEntries($pkg)
                    if ($this.ShouldDeferWslVerificationToAdminInstall($pkg, $ctx) -and -not (Test-WslAvailable)) {
                        $this.LogWarning("Microsoft.WSL の検証は Phase 2b の管理者 WSL インストールに委譲します")
                        $deferred++
                        continue
                    }
                    if ($this.TestPackageVerification($pkg.VerifyCommand)) {
                        $this.Log("スキップ (検証済み): $($pkg.Id)", "Gray")
                        $verified++
                        continue
                    }
                }

                if ($pkg.Id -in $installedIds -or $this.IsPackageInstalled($pkg.Id)) {
                    if ($pkg.VerifyCommand) {
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
                            $toInstall += [PSCustomObject]@{
                                Id            = $pkg.Id
                                Version       = $pkg.Version
                                SourceName    = $pkg.SourceName
                                VerifyCommand = $pkg.VerifyCommand
                                InstallArgs   = $pkg.InstallArgs
                                InstallTimeoutSeconds = $pkg.InstallTimeoutSeconds
                                PortableLink  = $pkg.PortableLink
                                PathEntries   = $pkg.PathEntries
                                Force         = $true
                            }
                        }
                        else {
                            $this.LogWarning("✗ $($pkg.Id) はインストール済みですが検証に失敗しました")
                            $verifyFailed++
                        }
                    }
                    else {
                        $this.Log("スキップ (インストール済み): $($pkg.Id)", "Gray")
                        $skipped++
                    }
                }
                else {
                    $toInstall += [PSCustomObject]@{
                        Id            = $pkg.Id
                        Version       = $pkg.Version
                        SourceName    = $pkg.SourceName
                        VerifyCommand = $pkg.VerifyCommand
                        InstallArgs   = $pkg.InstallArgs
                        InstallTimeoutSeconds = $pkg.InstallTimeoutSeconds
                        PortableLink  = $pkg.PortableLink
                        PathEntries   = $pkg.PathEntries
                        Force         = $false
                    }
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

            # 未インストール分をインストール
            $succeeded = 0
            $failed = 0

            foreach ($pkg in $toInstall) {
                $logSuffix = if ($pkg.Version) { " (v$($pkg.Version))" } else { "" }
                $this.Log("インストール中: $($pkg.Id)$logSuffix")
                $installArgs = $this.NewWingetInstallArguments($pkg, [bool]$pkg.Force)

                $installOutput = $this.InvokeWingetInstall($pkg, $installArgs)
                $alreadyInstalledInstallFailure = $this.IsAlreadyInstalledInstallFailure($installOutput)
                foreach ($line in $installOutput) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                        $this.Log("  $line", "Gray")
                    }
                }

                if ($LASTEXITCODE -ne 0) {
                    Update-ProcessEnvironmentPath
                    $this.EnsurePortableLink($pkg)
                    $this.EnsurePathEntries($pkg)

                    if ($pkg.VerifyCommand -and $this.TestPackageVerification($pkg.VerifyCommand)) {
                        $verified++
                        $this.Log("✓ $($pkg.Id) (winget install は失敗扱いでしたが検証済み)", "Green")
                        continue
                    }

                    if ($alreadyInstalledInstallFailure -and $pkg.VerifyCommand -and $this.RecoverPackageVerification($pkg)) {
                        $verified++
                        continue
                    }

                    if ($alreadyInstalledInstallFailure -and $pkg.VerifyCommand) {
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
            $text -match 'already installed' -or
            $text -match '別のバージョンが既にインストールされています'
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
        # Version が packages.json に書かれていれば --version で固定する。
        # msstore source は固定 version 指定をサポートしないため除外。
        if ($pkg.Version -and $pkg.SourceName -ne "msstore") {
            $installArgs += "--version"
            $installArgs += $pkg.Version
        }
        if ($pkg.SourceName -eq "msstore") {
            $installArgs += "--source"
            $installArgs += "msstore"
        }
        if ($pkg.InstallArgs) {
            $installArgs += @($pkg.InstallArgs)
        }
        if ($force) {
            $installArgs += "--force"
        }
        return $installArgs
    }

    hidden [object[]] InvokeWingetInstall([object]$pkg, [object[]]$installArgs) {
        $installTimeoutSeconds = $this.GetInstallTimeoutSeconds($pkg)
        if ($installTimeoutSeconds -gt 0) {
            return @(Invoke-Winget -Arguments $installArgs -TimeoutSeconds $installTimeoutSeconds)
        }
        return @(Invoke-Winget -Arguments $installArgs)
    }

    hidden [int] GetInstallTimeoutSeconds([object]$pkg) {
        if ($null -eq $pkg -or -not ($pkg.PSObject.Properties.Name -contains "InstallTimeoutSeconds")) {
            return 0
        }
        $rawTimeout = $pkg.InstallTimeoutSeconds
        if ($null -eq $rawTimeout) {
            return 0
        }
        $timeoutSeconds = 0
        if ([int]::TryParse([string]$rawTimeout, [ref]$timeoutSeconds) -and $timeoutSeconds -gt 0) {
            return $timeoutSeconds
        }
        return 0
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
            $output = Invoke-Winget -Arguments @("list", "--disable-interactivity")
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
    hidden [bool] IsPackageInstalled([string]$packageId) {
        try {
            Invoke-Winget -Arguments @("list", "--id", $packageId, "--exact", "--disable-interactivity") | Out-Null
            return $LASTEXITCODE -eq 0
        }
        catch {
            $this.LogWarning("パッケージ確認中にエラーが発生しました ($packageId): $($_.Exception.Message)")
            return $false
        }
    }

    hidden [bool] TestPackageVerification([object]$verifyCmd) {
        if (-not ($verifyCmd.PSObject.Properties.Name -contains "command")) {
            $this.LogWarning("verifyCommand に 'command' フィールドがありません")
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

            $timeoutSeconds = $this.GetVerifyTimeoutSeconds($verifyCmd)
            $output = @(Invoke-VerifyCommand -Command $command -Arguments $arguments -TimeoutSeconds $timeoutSeconds)
            if ($LASTEXITCODE -eq 0) {
                return $true
            }

            $displayCommand = "$command $($arguments -join ' ')".Trim()
            $this.Log("検証コマンド失敗 (exit code: $LASTEXITCODE): $displayCommand", "Yellow")
            foreach ($line in $output) {
                if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                    $this.Log("  $line", "Gray")
                }
            }
            return $LASTEXITCODE -eq 0
        }
        catch {
            $this.Log("検証コマンド実行エラー: $($_.Exception.Message)", "Yellow")
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
        if (-not $packageDir) {
            $this.LogWarning("portableLink のパッケージディレクトリが見つかりません: $($pkg.Id)")
            return
        }

        $target = Get-ChildItem -Path $packageDir.FullName -File -Filter $targetPattern -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $target) {
            $this.LogWarning("portableLink の対象 exe が見つかりません: $($pkg.Id) ($targetPattern)")
            return
        }

        $linksPath = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"
        if (-not (Test-Path -LiteralPath $linksPath)) {
            New-Item -ItemType Directory -Path $linksPath -Force | Out-Null
        }

        $linkPath = Join-Path $linksPath $linkName
        if (-not $this.IsPortableLinkCurrent($linkPath, $target.FullName)) {
            $this.CreatePortableLink($linkPath, $target.FullName)
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
        if (-not $pkg.PathEntries) { return }

        $resolvedEntries = [System.Collections.Generic.List[string]]::new()
        foreach ($rawEntry in @($pkg.PathEntries)) {
            if ([string]::IsNullOrWhiteSpace([string]$rawEntry)) { continue }

            $expanded = [Environment]::ExpandEnvironmentVariables([string]$rawEntry)
            $resolvedMatches = @(Get-Item -Path $expanded -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer })
            if ($resolvedMatches.Count -eq 0 -and (Test-Path -LiteralPath $expanded -PathType Container)) {
                $resolvedMatches = @(Get-Item -LiteralPath $expanded -ErrorAction SilentlyContinue)
            }

            if ($resolvedMatches.Count -eq 0) {
                $this.LogWarning("pathEntries のディレクトリが見つかりません: $($pkg.Id) ($rawEntry)")
                continue
            }

            foreach ($match in $resolvedMatches) {
                if (-not [string]::IsNullOrWhiteSpace($match.FullName)) {
                    $resolvedEntries.Add($match.FullName)
                }
            }
        }

        if ($resolvedEntries.Count -eq 0) { return }

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
        $cargoBinPath = Join-Path $env:USERPROFILE ".cargo\bin"

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
