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
        } catch {
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
                    $sourceName = $source.SourceDetails.Name
                    if ($source.Packages) {
                        foreach ($pkg in $source.Packages) {
                            if ($pkg.PackageIdentifier) {
                                $packages += [PSCustomObject]@{
                                    Id         = $pkg.PackageIdentifier
                                    SourceName = $sourceName
                                }
                            }
                        }
                    }
                }
            }

            if ($packages.Count -eq 0) {
                $this.Log("インストールするパッケージがありません", "Gray")
                return $this.CreateSuccessResult("パッケージリストが空です")
            }

            # インストール済みパッケージを一括取得（winget list を1回だけ実行）
            $installedIds = $this.GetInstalledPackageIds()

            # 未インストールのパッケージをフィルタリング
            $toInstall = @()
            $skipped = 0
            foreach ($pkg in $packages) {
                if ($pkg.Id -in $installedIds) {
                    $this.Log("スキップ (インストール済み): $($pkg.Id)", "Gray")
                    $skipped++
                } else {
                    $toInstall += $pkg
                }
            }

            if ($toInstall.Count -eq 0) {
                $this.Log("すべてのパッケージがインストール済みです", "Green")
                $this.EnsureCargoPath()
                return $this.CreateSuccessResult("インストール済み: $($packages.Count) 個")
            }

            # 未インストール分をインストール
            $succeeded = 0
            $failed = 0

            foreach ($pkg in $toInstall) {
                $this.Log("インストール中: $($pkg.Id)")
                $installArgs = @(
                    "install", "-e", "--id", $pkg.Id,
                    "--silent",
                    "--accept-package-agreements",
                    "--accept-source-agreements"
                )
                if ($pkg.SourceName -eq "msstore") {
                    $installArgs += "--source"
                    $installArgs += "msstore"
                }

                Invoke-Winget -Arguments $installArgs | Out-Null

                if ($LASTEXITCODE -eq 0) {
                    $succeeded++
                    $this.Log("✓ $($pkg.Id)", "Green")
                } else {
                    $failed++
                    $this.LogWarning("✗ $($pkg.Id) のインストールに失敗しました")
                }
            }

            # Rustup インストール後: ~/.cargo/bin を PATH に追加
            $this.EnsureCargoPath()

            if ($failed -eq 0) {
                return $this.CreateSuccessResult("$succeeded 個インストール, $skipped 個スキップ")
            } else {
                return $this.CreateSuccessResult("パッケージをインストールしました（一部失敗: $failed）")
            }
        } catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
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
            # winget list の出力からパッケージ ID を抽出
            # 形式: Name  Id  Version  Source (固定幅カラム、2+ スペース区切り)
            $ids = @()
            $headerFound = $false
            foreach ($line in $output) {
                if ($line -match '^-{2,}') { $headerFound = $true; continue }
                if (-not $headerFound) { continue }
                $parts = @($line -split '\s{2,}' | Where-Object { $_ })
                if ($parts.Count -ge 2) {
                    $ids += $parts[1].Trim()
                }
            }
            return $ids
        }
        catch {
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
            return $false
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
            } else {
                # 一部エクスポートできないパッケージがあっても続行
                $this.LogWarning("一部のパッケージがエクスポートできなかった可能性があります（正常な動作です）")
                return $this.CreateSuccessResult("パッケージリストをエクスポートしました（一部除外）: $packagesPath")
            }
        } catch {
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
