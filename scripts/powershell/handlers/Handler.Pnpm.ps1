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
    }

    [bool] CanApply([SetupContext]$ctx) {
        $pnpmCmd = Get-ExternalCommand -Name "pnpm"
        if (-not $pnpmCmd) {
            $this.LogWarning("pnpm が見つかりません")
            $this.Log("インストール方法: corepack enable && corepack prepare pnpm@latest --activate", "Yellow")
            return $false
        }

        if (-not $this.TestPnpmExecutable()) {
            $this.LogWarning("pnpm が正常に動作しません")
            return $false
        }

        $packagesPath = $this.GetPackagesPath($ctx)
        if (-not (Test-PathExist -Path $packagesPath)) {
            $this.LogWarning("パッケージリストが見つかりません: $packagesPath")
            return $false
        }

        return $true
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
            $this.AddPnpmBinToPath()

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
            $skipped = 0

            foreach ($pkg in $packages) {
                $pkgName = $pkg -replace '@[\d\.]+$', ''
                if ($this.IsPackageInstalled($pkgName)) {
                    $this.Log("スキップ (インストール済み): $pkgName", "Gray")
                    $skipped++
                    continue
                }

                $this.Log("インストール中: $pkg")
                Invoke-Pnpm -Arguments @("add", "-g", $pkg) | Out-Null

                if ($LASTEXITCODE -eq 0) {
                    $succeeded += $pkg
                    $this.Log("✓ $pkg", "Green")
                }
                else {
                    $failed += $pkg
                    $this.LogWarning("✗ $pkg のインストールに失敗しました")
                }
            }

            $this.EnsureGeminiCommandShim()

            if ($failed.Count -eq 0) {
                return $this.CreateSuccessResult("$($succeeded.Count) 個インストール, $skipped 個スキップ")
            }
            else {
                return $this.CreateSuccessResult("$($succeeded.Count) 個成功, $($failed.Count) 個失敗, $skipped 個スキップ")
            }
        }
        catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }

    hidden [bool] IsPackageInstalled([string]$pkgName) {
        try {
            $globalRoot = Invoke-Pnpm -Arguments @("root", "-g")
            if ($LASTEXITCODE -ne 0 -or -not $globalRoot) { return $false }
            $globalRoot = $globalRoot.Trim()
            $pkgPath = Join-Path $globalRoot $pkgName
            return (Test-Path -LiteralPath $pkgPath -PathType Container)
        }
        catch {
            return $false
        }
    }

    hidden [void] AddPnpmBinToPath() {
        try {
            $pnpmBinPath = (Invoke-Pnpm -Arguments @("bin", "-g")).Trim()
            if ($LASTEXITCODE -ne 0 -or -not $pnpmBinPath) {
                $this.Log("pnpm グローバル bin パスを取得できません", "Gray")
                return
            }

            if (-not (Test-Path $pnpmBinPath)) {
                New-Item -ItemType Directory -Path $pnpmBinPath -Force | Out-Null
            }

            $userPath = Get-UserEnvironmentPath
            $pathItems = if ($userPath) { $userPath -split ";" } else { @() }

            if ($pathItems -contains $pnpmBinPath) {
                $this.Log("pnpm bin は既に PATH に含まれています", "Gray")
                return
            }

            $newPath = ($pnpmBinPath, $userPath | Where-Object { $_ }) -join ";"
            Set-UserEnvironmentPath -Path $newPath
            $this.Log("pnpm bin を USER PATH に追加しました: $pnpmBinPath", "Green")
            $this.Log("ターミナルを再起動すると claude / gemini コマンドが使えます", "Gray")
        }
        catch {
            $this.Log("pnpm bin パスの追加に失敗しました: $($_.Exception.Message)", "Yellow")
        }
    }

    hidden [void] EnsureGeminiCommandShim() {
        try {
            $globalRoot = (Invoke-Pnpm -Arguments @("root", "-g")).Trim()
        }
        catch {
            return
        }
        if ($LASTEXITCODE -ne 0 -or -not $globalRoot) { return }

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
            $output = & gemini --version 2>&1
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
