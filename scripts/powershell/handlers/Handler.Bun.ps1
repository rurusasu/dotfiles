<#
.SYNOPSIS
    bun グローバルパッケージ管理ハンドラー（Windows）

.DESCRIPTION
    - bun add -g: パッケージリストからグローバルインストール

.NOTES
    Order = 7 (Winget/Npm の後、WSL 非依存処理)
    Mode オプションで動作を切り替え:
    - "import" (デフォルト): パッケージをインストール
#>

$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class BunHandler : SetupHandlerBase {
    BunHandler() {
        $this.Name = "Bun"
        $this.Description = "bun グローバルパッケージ管理（Windows）"
        $this.Order = 7
        $this.RequiresAdmin = $false
    }

    <#
    .SYNOPSIS
        実行可否を判定する
    .DESCRIPTION
        以下の条件をチェック:
        - bun コマンドが利用可能か
        - パッケージリストファイルが存在するか
    #>
    [bool] CanApply([SetupContext]$ctx) {
        $bunCmd = Get-ExternalCommand -Name "bun"
        if (-not $bunCmd) {
            $this.LogWarning("bun が見つかりません")
            $this.Log("インストール方法: winget install Oven-sh.Bun", "Yellow")
            return $false
        }

        if (-not $this.TestBunExecutable()) {
            $this.LogWarning("bun が正常に動作しません")
            return $false
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
        bun が実際に動作するか確認する
    #>
    hidden [bool] TestBunExecutable() {
        try {
            $output = Invoke-Bun -Arguments @("--version")
            if ($LASTEXITCODE -eq 0 -and $output -match '\d+\.\d+') {
                return $true
            }
            return $false
        }
        catch {
            return $false
        }
    }

    <#
    .SYNOPSIS
        bun グローバルパッケージをインストールする
    #>
    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            $this.CreateBunxShim()
            $this.AddBunBinToPath()

            $packagesPath = $this.GetPackagesPath($ctx)
            $this.Log("bun グローバルパッケージをインストールしています...")
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
                Invoke-Bun -Arguments @("add", "-g", $pkg) | Out-Null

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

    <#
    .SYNOPSIS
        指定パッケージが bun でグローバルインストール済みか確認する
    .DESCRIPTION
        ~/.bun/install/global/node_modules/ 配下にパッケージディレクトリが
        存在するかで判定する。bun pm ls -g は不安定なため使用しない。
        スコープ付きパッケージ (@org/pkg) にも対応。
    #>
    hidden [bool] IsPackageInstalled([string]$pkgName) {
        $globalModules = Join-Path $env:USERPROFILE ".bun\install\global\node_modules"
        if (-not (Test-Path $globalModules)) { return $false }

        # パッケージディレクトリの存在チェック
        # スコープ付き (@anthropic-ai/claude-code) もそのまま node_modules 配下に存在する
        $pkgPath = Join-Path $globalModules $pkgName
        return (Test-Path -LiteralPath $pkgPath -PathType Container)
    }

    <#
    .SYNOPSIS
        ~/.bun/bin を User PATH に追加する
    .DESCRIPTION
        bun install -g でインストールしたコマンド（claude, gemini 等）を
        ターミナルから直接実行できるようにするため、~/.bun/bin を永続的に
        User 環境変数 PATH に追加する。既に含まれている場合はスキップ。
    #>
    hidden [void] AddBunBinToPath() {
        $bunBinPath = Join-Path $env:USERPROFILE ".bun\bin"

        if (-not (Test-Path $bunBinPath)) {
            $this.Log(".bun\bin ディレクトリが存在しません。スキップ: $bunBinPath", "Gray")
            return
        }

        $userPath = Get-UserEnvironmentPath
        $pathItems = if ($userPath) { $userPath -split ";" } else { @() }

        if ($pathItems -contains $bunBinPath) {
            $this.Log(".bun\bin は既に PATH に含まれています", "Gray")
            return
        }

        $newPath = ($bunBinPath, $userPath | Where-Object { $_ }) -join ";"
        Set-UserEnvironmentPath -Path $newPath
        $this.Log(".bun\bin を USER PATH に追加しました: $bunBinPath", "Green")
        $this.Log("ターミナルを再起動すると claude / gemini コマンドが使えます", "Gray")
    }

    <#
    .SYNOPSIS
        bunx.cmd シムを bun.exe と同じディレクトリに作成する
    .DESCRIPTION
        WinGet でインストールした bun には bunx.exe が含まれないため、
        "bun x %*" を呼び出す .cmd シムを作成して代替する。
    #>
    hidden [void] CreateBunxShim() {
        $bunCmd = Get-Command bun -ErrorAction SilentlyContinue
        if (-not $bunCmd) { return }

        $bunDir  = Split-Path $bunCmd.Source
        $shimPath = Join-Path $bunDir "bunx.cmd"

        if (Test-Path $shimPath) {
            $this.Log("bunx.cmd は既に存在します: $shimPath", "Gray")
            return
        }

        $shimContent = "@echo off`r`n""%~dp0bun.exe"" x %*`r`n"
        [System.IO.File]::WriteAllText($shimPath, $shimContent, [System.Text.Encoding]::ASCII)
        $this.Log("bunx.cmd を作成しました: $shimPath", "Green")
    }

    <#
    .SYNOPSIS
        Windows で gemini コマンドが壊れている場合に shim を作成する
    .DESCRIPTION
        Bun の gemini.exe ラッパーが shebang を解釈できず失敗するケース向け。
        ~/.local/bin/gemini.cmd を作成し、bun + index.js 直実行で回避する。
    #>
    hidden [void] EnsureGeminiCommandShim() {
        $entrypoint = Join-Path $env:USERPROFILE ".bun\install\global\node_modules\@google\gemini-cli\dist\index.js"
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
            "set ""GEMINI_JS=%USERPROFILE%\.bun\install\global\node_modules\@google\gemini-cli\dist\index.js"""
            "if not exist ""%GEMINI_JS%"" ("
            "  echo [ERROR] Gemini CLI entrypoint not found: %GEMINI_JS%"
            "  exit /b 1"
            ")"
            "bun ""%GEMINI_JS%"" %*"
            "exit /b %ERRORLEVEL%"
            ""
        ) -join "`r`n"
        [System.IO.File]::WriteAllText($shimPath, $shimContent, [System.Text.Encoding]::ASCII)

        $this.PrependUserPath($localBin)
        $this.Log("gemini.cmd shim を作成しました: $shimPath", "Green")
        $this.Log("Windows では ~/.local/bin/gemini.cmd を優先して実行します", "Gray")
    }

    <#
    .SYNOPSIS
        gemini コマンドのヘルスチェック
    #>
    hidden [bool] TestGeminiCommand() {
        try {
            $output = & gemini --version 2>&1
            return ($LASTEXITCODE -eq 0 -and ($output -match '\d+\.\d+'))
        }
        catch {
            return $false
        }
    }

    <#
    .SYNOPSIS
        指定パスを User PATH の先頭に追加する
    #>
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

    <#
    .SYNOPSIS
        パッケージリストファイルのパスを取得する
    #>
    hidden [string] GetPackagesPath([SetupContext]$ctx) {
        return Join-Path $ctx.DotfilesPath "windows\bun\packages.json"
    }
}
