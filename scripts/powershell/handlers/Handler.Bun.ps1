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
    #>
    hidden [bool] IsPackageInstalled([string]$pkgName) {
        try {
            $output = Invoke-Bun -Arguments @("pm", "ls", "-g") 2>&1
            if ($LASTEXITCODE -ne 0) { return $false }
            return ($output | Where-Object { $_ -match [regex]::Escape($pkgName) }).Count -gt 0
        }
        catch {
            return $false
        }
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
        パッケージリストファイルのパスを取得する
    #>
    hidden [string] GetPackagesPath([SetupContext]$ctx) {
        return Join-Path $ctx.DotfilesPath "windows\bun\packages.json"
    }
}
