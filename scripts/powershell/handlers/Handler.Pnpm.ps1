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
    PnpmHandler() {
        $this.Name = "Pnpm"
        $this.Description = "pnpm グローバルパッケージ管理（Windows）"
        $this.Order = 7
        $this.RequiresAdmin = $false
        $this.Phase = 1
    }

    [bool] CanApply([SetupContext]$ctx) {
        $pnpmCmd = Get-ExternalCommand -Name "pnpm"
        if (-not $pnpmCmd -or -not $this.TestPnpmExecutable()) {
            # pnpm がなければ自動セットアップを試行
            if (-not $this.TryBootstrapPnpm()) {
                return $false
            }
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
        # 方法1: corepack enable で pnpm を有効化
        $corepackCmd = Get-ExternalCommand -Name "corepack"
        if ($corepackCmd) {
            $this.Log("pnpm が見つかりません。corepack で有効化を試みます...")
            try {
                Invoke-Corepack -Arguments @("enable")
                if ($LASTEXITCODE -eq 0) {
                    Invoke-Corepack -Arguments @("prepare", "pnpm@latest", "--activate")
                    if ($LASTEXITCODE -eq 0 -and $this.TestPnpmExecutable()) {
                        $this.Log("corepack で pnpm を有効化しました", "Green")
                        return $true
                    }
                }
            }
            catch {
                $this.Log("corepack での有効化に失敗: $($_.Exception.Message)", "Yellow")
            }
        }

        # 方法2: npm install -g pnpm
        $npmCmd = Get-ExternalCommand -Name "npm"
        if ($npmCmd) {
            $this.Log("npm 経由で pnpm をインストールします...")
            try {
                Invoke-Npm -Arguments @("install", "-g", "pnpm")
                if ($LASTEXITCODE -eq 0 -and $this.TestPnpmExecutable()) {
                    $this.Log("npm で pnpm をインストールしました", "Green")
                    return $true
                }
            }
            catch {
                $this.Log("npm での pnpm インストールに失敗: $($_.Exception.Message)", "Yellow")
            }
        }

        $this.LogWarning("pnpm をセットアップできませんでした。Node.js がインストールされているか確認してください")
        $this.Log("手動インストール: winget install OpenJS.NodeJS.LTS && corepack enable && corepack prepare pnpm@latest --activate", "Yellow")
        return $false
    }

    hidden [bool] TestPnpmExecutable() {
        try {
            $output = Invoke-Pnpm -Arguments @("--version")
            if ($LASTEXITCODE -eq 0 -and $output -match '\d+\.\d+') {
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
            $pnpmBinPath = $this.EnsurePnpmSetup()
            $this.AddPnpmBinToPath($pnpmBinPath)

            $packagesPath = $this.GetPackagesPath($ctx)
            $this.Log("pnpm グローバルパッケージをインストールしています...")
            $this.Log("ソース: $packagesPath")

            $packagesJson = Get-JsonContent -Path $packagesPath
            $packages = $packagesJson.globalPackages

            if (-not $packages -or $packages.Count -eq 0) {
                $this.Log("インストールするパッケージがありません", "Gray")
                return $this.CreateSuccessResult("パッケージリストが空です")
            }

            $failed = @()
            $succeeded = @()
            $verifyFailed = @()
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

            foreach ($pkgEntry in $packages) {
                $pkgSpec = if ($pkgEntry -is [string]) { $pkgEntry } else { $pkgEntry.name }
                $pkgName = $pkgSpec -replace '(?<=.)@[^\s@]+$', ''
                $verifyCmd = if ($pkgEntry -is [string]) { $null } else { $pkgEntry.verifyCommand }
                $installArgs = @()
                if ($pkgEntry -isnot [string]) {
                    if ($pkgEntry -is [System.Collections.IDictionary] -and $pkgEntry.Contains("installArgs")) {
                        foreach ($arg in @($pkgEntry["installArgs"])) {
                            if (-not [string]::IsNullOrWhiteSpace([string]$arg)) {
                                $installArgs += [string]$arg
                            }
                        }
                    }
                    elseif ($pkgEntry.PSObject.Properties.Name -contains "installArgs") {
                        foreach ($arg in @($pkgEntry.installArgs)) {
                            if (-not [string]::IsNullOrWhiteSpace([string]$arg)) {
                                $installArgs += [string]$arg
                            }
                        }
                    }
                }

                if ($this.IsPackageInstalled($pkgName, $globalRootForCheck)) {
                    if ($verifyCmd) {
                        if ($this.TestPackageVerification($verifyCmd)) {
                            $this.Log("スキップ (検証済み): $pkgName", "Gray")
                            $verified++
                            continue
                        }

                        $this.LogWarning("インストール済みですが検証に失敗しました。再インストールします: $pkgName")
                    }
                    else {
                        $this.Log("スキップ (インストール済み): $pkgName", "Gray")
                        $skipped++
                        continue
                    }
                }

                $this.Log("インストール中: $pkgSpec")
                $pnpmExitCode = $this.InvokePnpmInstall(@("add", "-g", "--reporter=append-only") + $installArgs + @($pkgSpec))

                if ($pnpmExitCode -ne 0) {
                    $failed += $pkgSpec
                    $this.LogWarning("✗ $pkgSpec のインストールに失敗しました")
                    continue
                }

                if ($verifyCmd -and $this.TestPackageVerification($verifyCmd)) {
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

            # ルート取得済みなら再利用、失敗時は 0-arg 版でリトライ
            if ($globalRootForCheck) {
                $this.EnsureGeminiCommandShim($globalRootForCheck)
            }
            else {
                $this.EnsureGeminiCommandShim()
            }

            $parts = @()
            if ($succeeded.Count -gt 0) { $parts += "$($succeeded.Count) 個インストール" }
            if ($verifyFailed.Count -gt 0) { $parts += "$($verifyFailed.Count) 個検証失敗" }
            if ($failed.Count -gt 0) { $parts += "$($failed.Count) 個失敗" }
            if ($verified -gt 0) { $parts += "$verified 個検証済み" }
            $parts += "$skipped 個スキップ"
            $message = $parts -join ", "
            if ($failed.Count -gt 0 -or $verifyFailed.Count -gt 0) {
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

    hidden [bool] TestPackageVerification([object]$verifyCmd) {
        try {
            $command = $verifyCmd.command
            $arguments = @($verifyCmd.args)
            $null = Invoke-VerifyCommand -Command $command -Arguments $arguments
            return $LASTEXITCODE -eq 0
        }
        catch {
            $this.Log("検証コマンド実行エラー: $($_.Exception.Message)", "Yellow")
            return $false
        }
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

        # PNPM_HOME が確定済みならそのまま返す（pnpm >= 9 では PNPM_HOME = global bin）
        # pnpm bin -g は PNPM_HOME が PATH にないとエラーを返すため、
        # PATH 追加は AddPnpmBinToPath に一元化し、ここでは呼ばない
        if ($env:PNPM_HOME) {
            return $env:PNPM_HOME
        }

        # PNPM_HOME が未設定 → pnpm setup を実行
        $this.Log("PNPM_HOME が未設定です。pnpm setup を実行します...")
        $null = Invoke-Pnpm -Arguments @("setup")
        if ($LASTEXITCODE -ne 0) {
            $this.LogWarning("pnpm setup に失敗しました")
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

        return $env:PNPM_HOME
    }

    hidden [void] AddPnpmBinToPath([string]$pnpmBinPath) {
        try {
            if (-not $pnpmBinPath) {
                $this.Log("pnpm グローバル bin パスを取得できません", "Gray")
                return
            }

            $pathsToAdd = @($pnpmBinPath)
            $childBinPath = Join-Path $pnpmBinPath "bin"
            if ($pathsToAdd -notcontains $childBinPath) {
                $pathsToAdd += $childBinPath
            }

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

    hidden [void] EnsureGeminiCommandShim() {
        $globalRoot = ""
        try {
            $rawRoot = Invoke-Pnpm -Arguments @("root", "-g")
            if ($LASTEXITCODE -ne 0 -or -not $rawRoot) { return }
            $globalRoot = $rawRoot.Trim()
        }
        catch {
            return
        }
        $this.EnsureGeminiCommandShim($globalRoot)
    }

    hidden [void] EnsureGeminiCommandShim([string]$globalRoot) {
        if (-not $globalRoot) { return }

        $entrypoint = Join-Path $globalRoot "@google\gemini-cli\dist\index.js"
        if (-not (Test-Path -LiteralPath $entrypoint -PathType Leaf)) {
            $this.Log("Gemini CLI のエントリポイントが見つからないため shim 作成をスキップします", "Gray")
            return
        }

        if ($this.TestGeminiCommand()) {
            $this.Log("gemini コマンドは正常です。shim 作成は不要です", "Gray")
            return
        }

        $localBin = Join-Path $env:USERPROFILE ".local\bin"
        New-Item -ItemType Directory -Path $localBin -Force | Out-Null

        $shimPath = Join-Path $localBin "gemini.cmd"
        $shimContent = @(
            "@echo off"
            "setlocal"
            "for /f ""delims="" %%i in ('pnpm root -g') do set ""PNPM_GLOBAL=%%i"""
            "set ""GEMINI_JS=%PNPM_GLOBAL%\@google\gemini-cli\dist\index.js"""
            "if not exist ""%GEMINI_JS%"" ("
            "  echo [ERROR] Gemini CLI entrypoint not found: %GEMINI_JS%"
            "  exit /b 1"
            ")"
            "node ""%GEMINI_JS%"" %*"
            "exit /b %ERRORLEVEL%"
            ""
        ) -join "`r`n"
        [System.IO.File]::WriteAllText($shimPath, $shimContent, [System.Text.Encoding]::ASCII)

        $this.PrependUserPath($localBin)
        $this.Log("gemini.cmd shim を作成しました: $shimPath", "Green")
        $this.Log("Windows では ~/.local/bin/gemini.cmd を優先して実行します", "Gray")
    }

    hidden [bool] TestGeminiCommand() {
        try {
            $output = Invoke-Gemini -Arguments @("--version")
            return ($LASTEXITCODE -eq 0 -and ($output -match '\d+\.\d+'))
        }
        catch {
            return $false
        }
    }

    hidden [void] PrependUserPath([string]$pathToPrepend) {
        $userPath = Get-UserEnvironmentPath
        $items = if ($userPath) { @($userPath -split ";" | Where-Object { $_ }) } else { @() }
        $items = @($items | Where-Object { $_ -ne $pathToPrepend })
        $newPath = (@($pathToPrepend) + $items) -join ";"
        Set-UserEnvironmentPath -Path $newPath

        $processItems = if ($env:PATH) { @($env:PATH -split ";" | Where-Object { $_ }) } else { @() }
        if (-not ($processItems -contains $pathToPrepend)) {
            $env:PATH = "$pathToPrepend;$env:PATH"
        }
    }

    hidden [string] GetPackagesPath([SetupContext]$ctx) {
        return Join-Path $ctx.DotfilesPath "windows\pnpm\packages.json"
    }
}
