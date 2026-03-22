<#
.SYNOPSIS
    npm グローバルパッケージ管理ハンドラー

.DESCRIPTION
    - npm install -g: パッケージリストからグローバルインストール
    - npm list -g: インストール済みパッケージを表示

.NOTES
    Order = 6 (Winget の後、WSL 非依存処理)
    Mode オプションで動作を切り替え:
    - "import" (デフォルト): パッケージをインストール
    - "list": インストール済みパッケージを表示
#>

$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class NpmHandler : SetupHandlerBase {
    NpmHandler() {
        $this.Name = "Npm"
        $this.Description = "npm グローバルパッケージ管理"
        $this.Order = 6
        $this.RequiresAdmin = $false
        $this.Phase = 1
    }

    <#
    .SYNOPSIS
        実行可否を判定する
    .DESCRIPTION
        以下の条件をチェック:
        - npm コマンドが利用可能か
        - パッケージリストファイルが存在するか（import モード時）
    #>
    [bool] CanApply([SetupContext]$ctx) {
        $npmCmd = Get-ExternalCommand -Name "npm"
        if (-not $npmCmd) {
            $this.LogWarning("npm が見つかりません。Node.js をインストールしてください")
            $this.Log("インストール方法: winget install OpenJS.NodeJS.LTS", "Yellow")
            return $false
        }

        if (-not $this.TestNpmExecutable()) {
            $this.LogWarning("npm が正常に動作しません")
            return $false
        }

        $mode = $ctx.GetOption("NpmMode", "import")

        if ($mode -eq "import") {
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
        npm が実際に動作するか確認する
    #>
    hidden [bool] TestNpmExecutable() {
        try {
            $output = Invoke-Npm -Arguments @("--version")
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
        npm 操作を実行する
    #>
    [SetupResult] Apply([SetupContext]$ctx) {
        $mode = $ctx.GetOption("NpmMode", "import")

        $result = $null
        switch ($mode) {
            "import" { $result = $this.ImportPackages($ctx) }
            "list" { $result = $this.ListPackages($ctx) }
            default {
                $result = $this.CreateFailureResult("不明なモード: $mode (import または list を指定してください)")
            }
        }
        return $result
    }

    <#
    .SYNOPSIS
        パッケージをグローバルインストールする
    #>
    hidden [SetupResult] ImportPackages([SetupContext]$ctx) {
        try {
            $packagesPath = $this.GetPackagesPath($ctx)
            $this.Log("npm グローバルパッケージをインストールしています...")
            $this.Log("ソース: $packagesPath")

            $packagesJson = Get-JsonContent -Path $packagesPath
            $packages = $packagesJson.globalPackages

            if (-not $packages -or $packages.Count -eq 0) {
                $this.Log("インストールするパッケージがありません", "Gray")
                return $this.CreateSuccessResult("パッケージリストが空です")
            }

            # インストール済みパッケージを取得
            $installed = $this.GetInstalledPackages()

            # 未インストールのパッケージをフィルタリング
            $toInstall = @()
            foreach ($pkg in $packages) {
                # パッケージ名からバージョンを除去（@scope/name@version → @scope/name）
                $pkgName = $pkg -replace '@[\d\.]+$', ''
                if ($installed -notcontains $pkgName) {
                    $toInstall += $pkg
                } else {
                    $this.Log("スキップ (インストール済み): $pkgName", "Gray")
                }
            }

            if ($toInstall.Count -eq 0) {
                $this.Log("すべてのパッケージがインストール済みです", "Green")
                return $this.CreateSuccessResult("インストール済み: $($packages.Count) 個")
            }

            $failed = @()
            $succeeded = @()

            foreach ($pkg in $toInstall) {
                $this.Log("インストール中: $pkg")
                Invoke-Npm -Arguments @("install", "-g", $pkg) | Out-Null

                if ($LASTEXITCODE -eq 0) {
                    $succeeded += $pkg
                    $this.Log("✓ $pkg", "Green")
                }
                else {
                    $failed += $pkg
                    $this.LogWarning("✗ $pkg のインストールに失敗しました")
                }
            }

            $skipped = $packages.Count - $toInstall.Count
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
        インストール済みグローバルパッケージ名の一覧を取得する
    #>
    hidden [string[]] GetInstalledPackages() {
        try {
            $output = Invoke-Npm -Arguments @("list", "-g", "--depth=0", "--json")
            if ($LASTEXITCODE -ne 0) {
                return @()
            }
            $json = $output | ConvertFrom-Json
            if ($json.dependencies) {
                return @($json.dependencies.PSObject.Properties.Name)
            }
            return @()
        }
        catch {
            return @()
        }
    }

    <#
    .SYNOPSIS
        インストール済みグローバルパッケージを表示する
    #>
    hidden [SetupResult] ListPackages([SetupContext]$ctx) {
        try {
            $this.Log("インストール済み npm グローバルパッケージ:")
            Invoke-Npm -Arguments @("list", "-g", "--depth=0")

            if ($LASTEXITCODE -eq 0) {
                return $this.CreateSuccessResult("パッケージリストを表示しました")
            }
            else {
                return $this.CreateFailureResult("パッケージリストの取得に失敗しました")
            }
        }
        catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }

    <#
    .SYNOPSIS
        パッケージリストファイルのパスを取得する
    #>
    hidden [string] GetPackagesPath([SetupContext]$ctx) {
        return Join-Path $ctx.DotfilesPath "windows\npm\packages.json"
    }
}
