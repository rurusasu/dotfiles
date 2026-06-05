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

            $toInstall = @()
            $skipped = 0
            $verified = 0
            foreach ($pkg in $packages) {
                # パッケージ名からバージョンを除去（@scope/name@version → @scope/name）
                $pkgSpec = if ($pkg -is [string]) { $pkg } else { $pkg.name }
                $pkgName = $pkgSpec -replace '@[\d\.]+$', ''
                $verifyCmd = if ($pkg -is [string]) { $null } else { $pkg.verifyCommand }

                if ($installed -contains $pkgName) {
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

                $toInstall += [PSCustomObject]@{
                    Spec          = $pkgSpec
                    VerifyCommand = $verifyCmd
                }
            }

            if ($toInstall.Count -eq 0) {
                $this.Log("すべてのパッケージがインストール済みで、検証対象も正常です", "Green")
                $parts = @()
                if ($verified -gt 0) { $parts += "$verified 個検証済み" }
                $parts += "$skipped 個スキップ"
                return $this.CreateSuccessResult($parts -join ", ")
            }

            $failed = @()
            $succeeded = @()
            $verifyFailed = @()

            foreach ($pkg in $toInstall) {
                $this.Log("インストール中: $($pkg.Spec)")
                Invoke-Npm -Arguments @("install", "-g", $pkg.Spec) | Out-Null

                if ($LASTEXITCODE -ne 0) {
                    $failed += $pkg.Spec
                    $this.LogWarning("✗ $($pkg.Spec) のインストールに失敗しました")
                    continue
                }

                if ($pkg.VerifyCommand -and $this.TestPackageVerification($pkg.VerifyCommand)) {
                    $succeeded += $pkg.Spec
                    $this.Log("✓ $($pkg.Spec)", "Green")
                } elseif ($pkg.VerifyCommand) {
                    $verifyFailed += $pkg.Spec
                    $this.LogWarning("✗ $($pkg.Spec) のインストールは成功しましたが検証に失敗しました")
                } else {
                    $succeeded += $pkg.Spec
                    $this.Log("✓ $($pkg.Spec)", "Green")
                }
            }

            $parts = @()
            if ($succeeded.Count -gt 0) { $parts += "$($succeeded.Count) 個インストール" }
            if ($verifyFailed.Count -gt 0) { $parts += "$($verifyFailed.Count) 個検証失敗" }
            if ($failed.Count -gt 0) { $parts += "$($failed.Count) 個失敗" }
            if ($verified -gt 0) { $parts += "$verified 個検証済み" }
            $parts += "$skipped 個スキップ"
            return $this.CreateSuccessResult($parts -join ", ")
        }
        catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
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
