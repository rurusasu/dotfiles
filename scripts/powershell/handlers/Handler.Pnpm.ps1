<#
.SYNOPSIS
    pnpm グローバルパッケージ管理ハンドラー（Windows）

.DESCRIPTION
    - pnpm add -g: パッケージリストからグローバルインストール

.NOTES
    Order = 7 (Winget/Npm の後、WSL 非依存処理)
    Mode オプションで動作を切り替え:
    - "import" (デフォルト): パッケージをインストール
#>

$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class PnpmHandler : SetupHandlerBase {
    hidden [string]$BootstrapPnpmDirectory

    PnpmHandler() {
        $this.Name = "Pnpm"
        $this.Description = "pnpm グローバルパッケージ管理（Windows）"
        $this.Order = 7
        $this.RequiresAdmin = $false
        $this.Phase = 1
    }

    [bool] CanApply([SetupContext]$ctx) {
        $packagesPath = $this.GetPackagesPath($ctx)
        if (Test-PathExist -Path $packagesPath) {
            $manifest = Get-JsonContent -Path $packagesPath -ErrorAction Stop
            if (@($manifest.globalPackages).Count -eq 0) { return $false }
        }
        $pnpmCmd = Get-ExternalCommand -Name "pnpm"
        if (-not $pnpmCmd) {
            # CanApply は副作用を持たせず、Apply 側で bootstrap 可能かだけ判定する
            $npmCmd = Get-ExternalCommand -Name "npm"
            $corepackCmd = Get-ExternalCommand -Name "corepack"
            if (-not $npmCmd -and -not $corepackCmd) {
                $this.LogWarning("pnpm をセットアップできる npm/corepack が見つかりません")
                return $false
            }
        }
        elseif (-not $this.TestPnpmExecutable()) {
            $this.LogWarning("pnpm が正常に動作しません。Apply で再セットアップを試みます")
        }

        $packagesPath = $this.GetPackagesPath($ctx)
        if (-not (Test-PathExist -Path $packagesPath)) {
            $this.LogWarning("パッケージリストが見つかりません: $packagesPath")
            return $false
        }

        return $true
    }

    <#
    .SYNOPSIS
        pnpm がない場合に corepack または npm 経由で自動セットアップする
    .OUTPUTS
        セットアップ成功時は $true、失敗時は $false
    #>
    hidden [bool] TryBootstrapPnpm() {
        return $this.TryBootstrapPnpm('')
    }

    hidden [bool] TryBootstrapPnpm([string]$knownNpmPrefix) {
        $this.BootstrapPnpmDirectory = $null

        # 方法1: npm で pnpm をインストール
        # Corepack は Windows で extensionless な pnpm shim を生成することがあり、
        # pnpm add -g 実行時に ERROR_BAD_EXE_FORMAT (os error 193) になるため、
        # Windows のグローバル npm bin に .cmd shim を配置する経路を優先する。
        $npmCmd = Get-ExternalCommand -Name "npm"
        if ($npmCmd) {
            $this.Log("pnpm 12.4.0 以降を npm 経由でセットアップします...")
            try {
                $this.AddRuntimeNodeDirectoryToProcessPath($npmCmd)
                $npmOutput = @(Invoke-Npm -Arguments @("install", "-g", "pnpm@latest"))
                $npmExitCode = [int]$LASTEXITCODE
                if ($npmExitCode -eq 0) {
                    $npmGlobalPrefix = $knownNpmPrefix
                    $prefixExitCode = 0
                    if (-not $npmGlobalPrefix) {
                        $prefixOutput = @(Invoke-Npm -Arguments @("prefix", "-g"))
                        $prefixExitCode = [int]$LASTEXITCODE
                        $npmGlobalPrefix = ($prefixOutput | Select-Object -Last 1)
                    }
                    if ($prefixExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$npmGlobalPrefix)) {
                        $npmGlobalPrefix = ([string]$npmGlobalPrefix).Trim()
                        $this.PrependUserPath($npmGlobalPrefix)
                        $npmPnpmShim = Join-Path $npmGlobalPrefix "pnpm.cmd"
                        if ($this.TestPnpmExecutableAtPath($npmPnpmShim)) {
                            $this.BootstrapPnpmDirectory = $npmGlobalPrefix
                            $this.Log("npm で pnpm をインストールしました", "Green")
                            return $true
                        }
                    }

                    $this.LogWarning("npm install は成功しましたが、npm global prefix の pnpm が使用できないか 12.4.0 未満です")
                }

                if ($npmExitCode -ne 0) {
                    foreach ($line in $npmOutput) {
                        if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                            $this.Log("npm: $line", "Yellow")
                        }
                    }
                    $this.LogWarning("npm install -g pnpm@latest exited with code $npmExitCode")
                }
            }
            catch {
                $this.Log("npm での pnpm インストールに失敗: $($_.Exception.Message)", "Yellow")
            }
        }

        # 方法2: corepack enable で pnpm を有効化（npm がない環境向け）
        $corepackCmd = Get-ExternalCommand -Name "corepack"
        if ($corepackCmd) {
            $this.Log("pnpm が見つかりません。corepack で有効化を試みます...")
            try {
                $this.AddRuntimeNodeDirectoryToProcessPath($corepackCmd)
                $enableOutput = @(Invoke-Corepack -Arguments @("enable"))
                $enableExitCode = [int]$LASTEXITCODE
                if ($enableExitCode -eq 0) {
                    $prepareOutput = @(Invoke-Corepack -Arguments @("prepare", "pnpm@latest", "--activate"))
                    $prepareExitCode = [int]$LASTEXITCODE
                    $corepackPath = Get-ExternalCommandPath -CommandInfo $corepackCmd
                    $corepackDirectory = if ($corepackPath) { Split-Path -Parent $corepackPath } else { $null }
                    $corepackPnpmShim = if ($corepackDirectory) { Join-Path $corepackDirectory "pnpm.cmd" } else { $null }
                    if ($prepareExitCode -eq 0 -and $corepackPnpmShim -and $this.TestPnpmExecutableAtPath($corepackPnpmShim)) {
                        $this.BootstrapPnpmDirectory = $corepackDirectory
                        $this.Log("corepack で pnpm を有効化しました", "Green")
                        return $true
                    }
                    if ($prepareExitCode -eq 0) {
                        $this.LogWarning("corepack prepare は成功しましたが、pnpm shim の検証に失敗しました: $corepackPnpmShim")
                    }
                    else {
                        foreach ($line in $prepareOutput) {
                            if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                                $this.Log("corepack prepare: $line", "Yellow")
                            }
                        }
                        $this.LogWarning("corepack prepare pnpm@latest exited with code $prepareExitCode")
                    }
                }
                else {
                    foreach ($line in $enableOutput) {
                        if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                            $this.Log("corepack enable: $line", "Yellow")
                        }
                    }
                    $this.LogWarning("corepack enable exited with code $enableExitCode")
                }
            }
            catch {
                $this.Log("corepack での有効化に失敗: $($_.Exception.Message)", "Yellow")
            }
        }

        $this.LogWarning("pnpm をセットアップできませんでした。Node.js がインストールされているか確認してください")
        $this.Log("手動インストール: winget install OpenJS.NodeJS.LTS && npm install -g pnpm@latest", "Yellow")
        return $false
    }

    hidden [void] AddRuntimeNodeDirectoryToProcessPath([object]$runtimeCommand) {
        $runtimePath = Get-ExternalCommandPath -CommandInfo $runtimeCommand
        if (-not $runtimePath) { return }

        $runtimeDirectory = Split-Path -Parent $runtimePath
        $nodeExecutable = Join-Path $runtimeDirectory "node.exe"
        if (-not (Test-Path -LiteralPath $nodeExecutable -PathType Leaf)) { return }

        foreach ($pathEntry in @($env:PATH -split ";")) {
            if ([System.StringComparer]::OrdinalIgnoreCase.Equals($pathEntry.TrimEnd("\"), $runtimeDirectory.TrimEnd("\"))) {
                return
            }
        }

        if ([string]::IsNullOrWhiteSpace($env:PATH)) {
            $env:PATH = $runtimeDirectory
        }
        else {
            $env:PATH = "$runtimeDirectory;$env:PATH"
        }
        $this.Log("Node.js ディレクトリを現プロセス PATH に追加しました: $runtimeDirectory", "Gray")
    }

    hidden [bool] TestPnpmExecutableAtPath([string]$pnpmPath) {
        try {
            if (-not $pnpmPath -or -not (Test-Path -LiteralPath $pnpmPath -PathType Leaf)) {
                return $false
            }
            $output = Invoke-NativeCommand -Command $pnpmPath -Arguments @("--version")
            return ($LASTEXITCODE -eq 0 -and $this.IsSupportedPnpmVersion($output))
        }
        catch {
            return $false
        }
    }

    hidden [bool] IsSupportedPnpmVersion([object]$output) {
        # Negated --allow-build and approve-builds decisions with no pending
        # packages require 12.4.0. Reject diagnostic text and prereleases too.
        $versionText = (@($output) -join "`n").Trim()
        if ($versionText -notmatch '^\d+\.\d+\.\d+$') { return $false }
        $parsedVersion = $null
        return ([version]::TryParse($versionText, [ref]$parsedVersion) -and $parsedVersion -ge [version]'12.4.0')
    }

    hidden [bool] TestPnpmExecutable() {
        try {
            $output = Invoke-Pnpm -Arguments @("--version")
            if ($LASTEXITCODE -eq 0 -and $this.IsSupportedPnpmVersion($output)) {
                return $true
            }
            return $false
        }
        catch {
            return $false
        }
    }

    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            try { Update-NpmGlobalCommandPath -Cache $ctx.Options }
            catch { $this.LogWarning("npm global PATH recovery failed: $($_.Exception.Message)") }
            # Match Invoke-Pnpm's .cmd preference, which can differ from pnpm.exe
            # returned by an unqualified command lookup.
            $pnpmCmd = Get-ExternalCommand -Name 'pnpm.cmd'
            if (-not $pnpmCmd) { $pnpmCmd = Get-ExternalCommand -Name 'pnpm' }
            $pnpmCommandPath = Get-ExternalCommandPath -CommandInfo $pnpmCmd
            $existingPnpmDirectory = $null
            $pnpmIsUnusable = $pnpmCmd -and $pnpmCommandPath -and
            (Test-Path -LiteralPath $pnpmCommandPath -PathType Leaf) -and
            -not $this.TestPnpmExecutable()
            if (-not $pnpmCmd -or $pnpmIsUnusable) {
                if (-not $this.TryBootstrapPnpm([string]$ctx.Options['NpmGlobalPrefix'])) {
                    return $this.CreateFailureResult("pnpm のセットアップに失敗しました")
                }
            }
            elseif ($pnpmCommandPath -and (Test-Path -LiteralPath $pnpmCommandPath -PathType Leaf)) {
                $existingPnpmDirectory = Split-Path -Parent $pnpmCommandPath
            }
            $pnpmBinPath = $this.EnsurePnpmSetup()
            if (-not $pnpmBinPath) {
                if ($this.TestPnpmExecutable()) {
                    $this.LogWarning("pnpm setup に失敗しましたが、既存の pnpm runtime は利用可能なため継続します")
                }
                else {
                    return $this.CreateFailureResult("pnpm setup に失敗しました。グローバル bin を準備できません")
                }
            }
            $this.AddPnpmBinToPath($pnpmBinPath)
            if ($this.BootstrapPnpmDirectory) {
                # AddPnpmBinToPath can put a different installation ahead of the
                # npm/Corepack shim. Keep the package manager selected at bootstrap first.
                $this.PrependUserPath($this.BootstrapPnpmDirectory)
            }
            elseif ($existingPnpmDirectory) {
                $this.PrependProcessPath($existingPnpmDirectory)
                # Adding home/bin may expose a .cmd shim even if the validated
                # installation was an .exe. Only re-probe when selection changed.
                $afterPathCommand = Get-ExternalCommand -Name 'pnpm.cmd'
                if (-not $afterPathCommand) { $afterPathCommand = Get-ExternalCommand -Name 'pnpm' }
                $afterPath = Get-ExternalCommandPath -CommandInfo $afterPathCommand
                if ($afterPath -ne $pnpmCommandPath -and -not $this.TestPnpmExecutable()) {
                    if (-not $this.TryBootstrapPnpm([string]$ctx.Options['NpmGlobalPrefix'])) {
                        return $this.CreateFailureResult("PATH 更新後の pnpm のセットアップに失敗しました")
                    }
                    $this.PrependUserPath($this.BootstrapPnpmDirectory)
                }
            }

            $packagesPath = $this.GetPackagesPath($ctx)
            $this.Log("pnpm グローバルパッケージをインストールしています...")
            $this.Log("ソース: $packagesPath")

            $packagesJson = Get-JsonContent -Path $packagesPath
            $packages = @($packagesJson.globalPackages)

            if (-not $packages -or $packages.Count -eq 0) {
                $this.Log("インストールするパッケージがありません", "Gray")
                return $this.CreateSuccessResult("パッケージリストが空です")
            }

            # Persist explicit denials before any verification/skip or install.
            # Removing an old allow flag alone does not revoke saved permission.
            $denials = @($packages | ForEach-Object {
                    $this.GetPackageStringArray($_, 'installArgs') | Where-Object {
                        $_ -match '^--allow-build=!.+'
                    } | ForEach-Object { $_.Substring('--allow-build='.Length) }
                } | Sort-Object -Unique)
            if ($denials.Count -gt 0) {
                $policyOutput = @(Invoke-Pnpm -Arguments (@('approve-builds', '-g') + $denials))
                $policyExitCode = $LASTEXITCODE
                foreach ($line in $policyOutput) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$line)) { $this.Log("pnpm approve-builds: $line", 'Gray') }
                }
                if ($policyExitCode -ne 0) {
                    return $this.CreateFailureResult("pnpm approve-builds exited with code $policyExitCode")
                }
            }

            $failed = @()
            $succeeded = @()
            $verifyFailed = @()
            $postInstallFailed = @()
            $preserved = @()
            $skipped = 0
            $verified = 0

            # グローバルルートを一度だけ取得（ループ内で毎回 pnpm root -g を実行しないよう）
            $globalRootForCheck = ""
            try {
                $rawRoot = Invoke-Pnpm -Arguments @("root", "-g")
                if ($LASTEXITCODE -eq 0 -and $rawRoot) { $globalRootForCheck = $rawRoot.Trim() }
            }
            catch {
                $this.Log("pnpm root の取得に失敗しました: $($_.Exception.Message)", "Gray")
            }

            # Ask pnpm once which global packages are outdated. A verified
            # package absent from this result does not need to be re-linked by
            # pnpm add -g; packages that are missing, unverifiable, or listed
            # as outdated still follow the normal install/update path.
            $outdatedState = $this.GetOutdatedGlobalPackageState()
            $outdatedNames = @($outdatedState.Names)
            $outdatedCheckAvailable = [bool]$outdatedState.Available

            foreach ($pkgEntry in $packages) {
                $pkgSpec = if ($pkgEntry -is [string]) { $pkgEntry } else { $pkgEntry.name }
                $pkgName = $pkgSpec -replace '(?<=.)@[^\s@]+$', ''
                $verifyCmd = $this.GetPackageProperty($pkgEntry, "verifyCommand")
                $postInstallCmd = $this.GetPackageProperty($pkgEntry, "postInstallCommand")
                $installArgs = $this.GetPackageStringArray($pkgEntry, "installArgs")
                $wasVerified = $false

                if ($this.IsPackageInstalled($pkgName, $globalRootForCheck)) {
                    if ($verifyCmd) {
                        if ($this.TestPackageVerification($verifyCmd, $globalRootForCheck)) {
                            if ($outdatedCheckAvailable -and $pkgName -notin $outdatedNames -and -not $postInstallCmd) {
                                $this.Log("スキップ (検証済み/最新): $pkgName", "Gray")
                                $skipped++
                                $verified++
                                continue
                            }

                            $this.Log("検証済み。更新対象です: $pkgName", "Gray")
                            $verified++
                            $wasVerified = $true
                        }
                        else {
                            $this.LogWarning("インストール済みですが検証に失敗しました。再インストールします: $pkgName")
                        }
                    }
                    else {
                        $this.Log("インストール済み。latest を確認します: $pkgName", "Gray")
                    }
                }

                $this.Log("インストール/更新中: $pkgSpec")
                $pnpmExitCode = $this.InvokePnpmInstall(@("add", "-g", "--reporter=append-only", "--yes") + $installArgs + @($pkgSpec))

                if ($pnpmExitCode -ne 0) {
                    if ($wasVerified -and $this.TestPackageVerification($verifyCmd, $globalRootForCheck)) {
                        $preserved += $pkgSpec
                        $this.LogWarning("⚠ $pkgSpec の更新に失敗しましたが、既存の実行可能状態を維持しました (exit code: $pnpmExitCode)")
                        continue
                    }
                    $failed += $pkgSpec
                    $this.LogWarning("✗ $pkgSpec のインストールに失敗しました")
                    continue
                }

                if ($postInstallCmd -and -not $this.InvokePackagePostInstall($postInstallCmd)) {
                    $postInstallFailed += $pkgSpec
                    $this.LogWarning("✗ $pkgSpec の post-install に失敗しました")
                    continue
                }

                if ($verifyCmd -and $this.TestPackageVerification($verifyCmd, $globalRootForCheck)) {
                    $succeeded += $pkgSpec
                    $this.Log("✓ $pkgSpec", "Green")
                }
                elseif ($verifyCmd) {
                    $verifyFailed += $pkgSpec
                    $this.LogWarning("✗ $pkgSpec のインストールは成功しましたが検証に失敗しました")
                }
                else {
                    $succeeded += $pkgSpec
                    $this.Log("✓ $pkgSpec", "Green")
                }
            }

            $parts = @()
            if ($succeeded.Count -gt 0) { $parts += "$($succeeded.Count) 個インストール" }
            if ($postInstallFailed.Count -gt 0) { $parts += "$($postInstallFailed.Count) 個post-install失敗" }
            if ($verifyFailed.Count -gt 0) { $parts += "$($verifyFailed.Count) 個検証失敗" }
            if ($failed.Count -gt 0) { $parts += "$($failed.Count) 個失敗" }
            if ($preserved.Count -gt 0) { $parts += "$($preserved.Count) 個更新失敗（既存を維持）" }
            if ($verified -gt 0) { $parts += "$verified 個検証済み" }
            $parts += "$skipped 個スキップ"
            $message = $parts -join ", "
            if ($failed.Count -gt 0 -or $postInstallFailed.Count -gt 0 -or $verifyFailed.Count -gt 0) {
                return $this.CreateFailureResult($message)
            }
            return $this.CreateSuccessResult($message)
        }
        catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }

    hidden [bool] IsPackageInstalled([string]$pkgName) {
        try {
            $root = Invoke-Pnpm -Arguments @("root", "-g")
            if ($LASTEXITCODE -ne 0 -or -not $root) { return $false }
            return $this.IsPackageInstalled($pkgName, $root.Trim())
        }
        catch {
            return $false
        }
    }

    hidden [bool] IsPackageInstalled([string]$pkgName, [string]$globalRoot) {
        if (-not $globalRoot) { return $false }
        $pkgPath = Join-Path $globalRoot $pkgName
        return (Test-Path -LiteralPath $pkgPath -PathType Container)
    }

    hidden [object] GetOutdatedGlobalPackageState() {
        try {
            $output = @(Invoke-Pnpm -Arguments @("outdated", "--global", "--format", "json"))
            $exitCode = [int]$LASTEXITCODE
            $jsonText = (($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).Trim()

            if ([string]::IsNullOrWhiteSpace($jsonText)) {
                if ($exitCode -eq 0) {
                    return [PSCustomObject]@{ Available = $true; Names = @() }
                }
                throw "pnpm outdated exited with code $exitCode without JSON output"
            }

            $json = $jsonText | ConvertFrom-Json -ErrorAction Stop
            $names = @()
            if ($json -is [System.Array]) {
                foreach ($entry in @($json)) {
                    if ($entry -and ($entry.PSObject.Properties.Name -contains "name")) {
                        $names += [string]$entry.name
                    }
                }
            }
            else {
                foreach ($property in @($json.PSObject.Properties)) {
                    $names += [string]$property.Name
                }
            }

            return [PSCustomObject]@{
                Available = $true
                Names     = @($names | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
            }
        }
        catch {
            $this.LogWarning("pnpm outdated の取得に失敗しました。既存パッケージも更新を試みます: $($_.Exception.Message)")
            return [PSCustomObject]@{ Available = $false; Names = @() }
        }
    }

    hidden [object] GetPackageProperty([object]$pkgEntry, [string]$propertyName) {
        if ($pkgEntry -is [string] -or -not $pkgEntry) { return $null }
        if ($pkgEntry -is [System.Collections.IDictionary] -and $pkgEntry.Contains($propertyName)) {
            return $pkgEntry[$propertyName]
        }

        $property = $pkgEntry.PSObject.Properties[$propertyName]
        if ($property) {
            return $property.Value
        }
        return $null
    }

    hidden [string[]] GetPackageStringArray([object]$pkgEntry, [string]$propertyName) {
        $values = @()
        $propertyValue = $this.GetPackageProperty($pkgEntry, $propertyName)
        foreach ($value in @($propertyValue)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
                $values += [string]$value
            }
        }
        return $values
    }

    hidden [bool] InvokePackagePostInstall([object]$postInstallCmd) {
        try {
            $command = $postInstallCmd.command
            $arguments = @($postInstallCmd.args)
            $timeoutSeconds = Get-PackageInstallTimeoutSecond
            $environmentTimeout = 0
            $hasEnvironmentOverride = [int]::TryParse($env:DOTFILES_INSTALL_TIMEOUT_SECONDS, [ref]$environmentTimeout) -and
            $environmentTimeout -ge 0
            if (-not $hasEnvironmentOverride) {
                $timeoutSeconds = $this.GetCommandTimeoutSeconds($postInstallCmd, $timeoutSeconds)
            }
            $displayCommand = (@($command) + $arguments) -join " "
            $this.Log("post-install 実行中: $displayCommand", "Gray")

            $output = Invoke-VerifyCommand -Command $command -Arguments $arguments -TimeoutSeconds $timeoutSeconds
            $output | ForEach-Object {
                if ($_ -notmatch '^\s*$') {
                    $this.Log("  $_", "Gray")
                }
            }

            if ($LASTEXITCODE -eq 124) {
                $this.Log("post-install コマンドがタイムアウトしました (${timeoutSeconds}s): $displayCommand", "Yellow")
            }
            return $LASTEXITCODE -eq 0
        }
        catch {
            $this.Log("post-install コマンド実行エラー: $($_.Exception.Message)", "Yellow")
            return $false
        }
    }

    hidden [bool] TestPackageVerification([object]$verifyCmd, [string]$globalRoot = "") {
        try {
            $command = $verifyCmd.command
            $arguments = @($this.GetPackageProperty($verifyCmd, "args"))
            $verifyType = $this.GetVerifyType($verifyCmd)
            if ($verifyType -eq "commandExists") {
                $this.Log("検証中: command -v $command", "Gray")
                $cmd = Get-ExternalCommand -Name $command
                if ($cmd) {
                    $this.Log("  $(Get-ExternalCommandPath -CommandInfo $cmd)", "Gray")
                    return $true
                }
                $this.Log("検証コマンドが見つかりません: $command", "Yellow")
                return $false
            }

            if ($verifyType -eq "nodeModule") {
                $moduleName = [string]$this.GetPackageProperty($verifyCmd, "moduleName")
                $moduleFromPackage = [string]$this.GetPackageProperty($verifyCmd, "moduleFromPackage")
                $moduleSmokeTest = [string]$this.GetPackageProperty($verifyCmd, "moduleSmokeTest")
                if ($moduleSmokeTest -and ($moduleSmokeTest -ne "pty" -or -not $moduleFromPackage)) {
                    $this.LogWarning("Node モジュール検証の smoke test 設定が不正です: $moduleSmokeTest")
                    return $false
                }
                if (-not $globalRoot -or -not $moduleName) {
                    $this.LogWarning("Node モジュール検証に global root または moduleName がありません: $moduleName")
                    return $false
                }

                # pnpm isolates transitive dependencies below each package's node_modules.
                # Resolve them from the owning package instead of from the global root.
                $moduleNameLiteral = ConvertTo-Json -InputObject $moduleName -Compress
                if ($moduleFromPackage) {
                    $moduleFromPackageLiteral = ConvertTo-Json -InputObject $moduleFromPackage -Compress
                    $nodeProbe = "const {createRequire}=require('node:module'); const owner=require.resolve($moduleFromPackageLiteral+'/package.json'); const load=createRequire(owner); const pty=load($moduleNameLiteral); if(typeof pty.spawn!=='function') throw new Error('module does not export spawn');"
                }
                else {
                    $nodeProbe = "const pty = require($moduleNameLiteral); if (typeof pty.spawn !== 'function') throw new Error('module does not export spawn');"
                }
                if ($moduleSmokeTest -eq "pty") {
                    $nodeProbe += " const shell=process.env.ComSpec||'cmd.exe'; const child=pty.spawn(shell,['/d','/s','/c','exit 0'],{name:'xterm-color',cols:80,rows:24,cwd:process.cwd(),env:process.env}); const timer=setTimeout(()=>{try{child.kill()}catch{}; console.error('PTY smoke test timed out'); process.exit(1)},20000); child.onExit(({exitCode,signal})=>{clearTimeout(timer); if(exitCode!==0||signal){console.error('PTY smoke test failed',exitCode,signal); process.exitCode=1}});"
                }
                $previousNodePath = $env:NODE_PATH
                $nodePathEntries = @($globalRoot)
                [string[]]$moduleOutput = @()
                [int]$moduleExitCode = 1
                if ($previousNodePath) {
                    $nodePathEntries += @($previousNodePath -split [regex]::Escape([string][System.IO.Path]::PathSeparator) | Where-Object { $_ })
                }
                $env:NODE_PATH = $nodePathEntries -join [System.IO.Path]::PathSeparator
                try {
                    $this.Log("検証中: node require($moduleName)", "Gray")
                    $moduleOutput = Invoke-VerifyCommand -Command "node" -Arguments @("-e", $nodeProbe) -TimeoutSeconds ($this.GetVerifyTimeoutSeconds($verifyCmd))
                    $moduleExitCode = [int]$LASTEXITCODE
                }
                finally {
                    if ($null -eq $previousNodePath) {
                        Remove-Item Env:\NODE_PATH -ErrorAction SilentlyContinue
                    }
                    else {
                        $env:NODE_PATH = $previousNodePath
                    }
                }

                $moduleOutput | ForEach-Object {
                    if ($_ -notmatch '^\s*$') {
                        $this.Log("  $_", "Gray")
                    }
                }
                if ($moduleExitCode -ne 0) {
                    $this.LogWarning("Node モジュールを読み込めませんでした (exit code: $moduleExitCode): $moduleName")
                    return $false
                }
            }

            $timeoutSeconds = $this.GetVerifyTimeoutSeconds($verifyCmd)
            $displayCommand = (@($command) + $arguments) -join " "
            $this.Log("検証中: $displayCommand", "Gray")

            $output = Invoke-VerifyCommand -Command $command -Arguments $arguments -TimeoutSeconds $timeoutSeconds
            $output | ForEach-Object {
                if ($_ -notmatch '^\s*$') {
                    $this.Log("  $_", "Gray")
                }
            }

            if ($LASTEXITCODE -eq 124) {
                $this.Log("検証コマンドがタイムアウトしました (${timeoutSeconds}s): $displayCommand", "Yellow")
            }
            return $LASTEXITCODE -eq 0
        }
        catch {
            $this.Log("検証コマンド実行エラー: $($_.Exception.Message)", "Yellow")
            return $false
        }
    }

    hidden [int] GetVerifyTimeoutSeconds([object]$verifyCmd) {
        return $this.GetCommandTimeoutSeconds($verifyCmd, 120)
    }

    hidden [int] GetCommandTimeoutSeconds([object]$commandSpec, [int]$defaultSeconds) {
        if ($commandSpec -is [hashtable] -and $commandSpec.ContainsKey("timeoutSeconds")) {
            $timeoutSeconds = [int]$commandSpec["timeoutSeconds"]
            if ($timeoutSeconds -gt 0) {
                return $timeoutSeconds
            }
        }
        if ($commandSpec -and ($commandSpec.PSObject.Properties.Name -contains "timeoutSeconds")) {
            $timeoutSeconds = [int]$commandSpec.timeoutSeconds
            if ($timeoutSeconds -gt 0) {
                return $timeoutSeconds
            }
        }
        return $defaultSeconds
    }

    hidden [string] GetVerifyType([object]$verifyCmd) {
        if ($verifyCmd -is [hashtable] -and $verifyCmd.ContainsKey("type")) {
            return [string]$verifyCmd["type"]
        }
        if ($verifyCmd -and ($verifyCmd.PSObject.Properties.Name -contains "type")) {
            return [string]$verifyCmd.type
        }
        return "command"
    }

    hidden [int] InvokePnpmInstall([string[]]$arguments) {
        Invoke-Pnpm -Arguments $arguments | ForEach-Object {
            if ($_ -notmatch '^\s*$') {
                $this.Log("  $_", "Gray")
            }
        }
        return $LASTEXITCODE
    }

    hidden [string] EnsurePnpmSetup() {
        # PNPM_HOME がプロセスに未設定の場合、レジストリから復元
        # （前回の pnpm setup で登録済みだが新規シェルにしか反映されないため）
        if (-not $env:PNPM_HOME) {
            $registryPnpmHome = [System.Environment]::GetEnvironmentVariable('PNPM_HOME', 'User')
            if ($registryPnpmHome) {
                $env:PNPM_HOME = $registryPnpmHome
                $this.Log("PNPM_HOME をレジストリから復元しました: $registryPnpmHome", "Gray")
            }
        }

        # pnpm >= 11 keeps global executables below PNPM_HOME/bin.
        # Keep PNPM_HOME as the parent; do not create a nested bin/bin.
        if ($env:PNPM_HOME) {
            return Join-Path $env:PNPM_HOME 'bin'
        }

        # PNPM_HOME が未設定 → pnpm setup を実行
        $this.Log("PNPM_HOME が未設定です。pnpm setup を実行します...")
        $setupOutput = @(Invoke-Pnpm -Arguments @("setup"))
        $setupExitCode = $LASTEXITCODE
        foreach ($line in $setupOutput) {
            if (-not [string]::IsNullOrWhiteSpace([string]$line)) { $this.Log("pnpm setup: $line", 'Gray') }
        }
        if ($setupExitCode -ne 0) {
            $this.LogWarning("pnpm setup exited with code $setupExitCode")
            return $null
        }
        $this.Log("pnpm setup が完了しました", "Green")

        # pnpm setup でレジストリに設定された PNPM_HOME をプロセスに反映
        $registryPnpmHome = [System.Environment]::GetEnvironmentVariable('PNPM_HOME', 'User')
        if ($registryPnpmHome) {
            $env:PNPM_HOME = $registryPnpmHome
        }
        elseif ($env:LOCALAPPDATA) {
            $env:PNPM_HOME = Join-Path $env:LOCALAPPDATA "pnpm"
        }

        if (-not $env:PNPM_HOME) { return $null }
        return Join-Path $env:PNPM_HOME 'bin'
    }

    hidden [void] AddPnpmBinToPath([string]$pnpmBinPath) {
        try {
            if (-not $pnpmBinPath) {
                $this.Log("pnpm グローバル bin パスを取得できません", "Gray")
                return
            }

            $pathsToAdd = @($pnpmBinPath)

            foreach ($pathToAdd in $pathsToAdd) {
                if (-not (Test-Path -LiteralPath $pathToAdd)) {
                    New-Item -ItemType Directory -Path $pathToAdd -Force | Out-Null
                }
            }

            $userPath = Get-UserEnvironmentPath
            $pathItems = if ($userPath) { @($userPath -split ";" | Where-Object { $_ }) } else { @() }

            $missingUserPaths = @($pathsToAdd | Where-Object { $_ -notin $pathItems })
            if ($missingUserPaths.Count -gt 0) {
                $newPath = (@($missingUserPaths) + $pathItems) -join ";"
                Set-UserEnvironmentPath -Path $newPath
                $this.Log("pnpm bin を USER PATH に追加しました: $($missingUserPaths -join ';')", "Green")
            }
            else {
                $this.Log("pnpm bin は既に PATH に含まれています", "Gray")
            }

            # 現プロセスの PATH にも追加（pnpm add -g が同一セッションで動作するよう）
            $processItems = if ($env:PATH) { @($env:PATH -split ";" | Where-Object { $_ }) } else { @() }
            $missingProcessPaths = @($pathsToAdd | Where-Object { $_ -notin $processItems })
            if ($missingProcessPaths.Count -gt 0) {
                $env:PATH = (@($missingProcessPaths) + $processItems) -join ";"
                $this.Log("pnpm bin を現プロセス PATH に追加しました: $($missingProcessPaths -join ';')", "Gray")
            }
        }
        catch {
            $this.Log("pnpm bin パスの追加に失敗しました: $($_.Exception.Message)", "Yellow")
        }
    }

    hidden [void] PrependUserPath([string]$pathToPrepend) {
        $userPath = Get-UserEnvironmentPath
        $items = if ($userPath) { @($userPath -split ";" | Where-Object { $_ }) } else { @() }
        $items = @($items | Where-Object {
                -not [System.StringComparer]::OrdinalIgnoreCase.Equals($_.TrimEnd("\"), $pathToPrepend.TrimEnd("\"))
            })
        $newPath = (@($pathToPrepend) + $items) -join ";"
        Set-UserEnvironmentPath -Path $newPath

        $this.PrependProcessPath($pathToPrepend)
    }

    hidden [void] PrependProcessPath([string]$pathToPrepend) {
        $processItems = if ($env:PATH) { @($env:PATH -split ";" | Where-Object { $_ }) } else { @() }
        $processItems = @($processItems | Where-Object {
                -not [System.StringComparer]::OrdinalIgnoreCase.Equals($_.TrimEnd("\"), $pathToPrepend.TrimEnd("\"))
            })
        $env:PATH = (@($pathToPrepend) + $processItems) -join ";"
    }

    hidden [string] GetPackagesPath([SetupContext]$ctx) {
        return Join-Path $ctx.DotfilesPath "windows\pnpm\packages.json"
    }
}
