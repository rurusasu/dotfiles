<#
.SYNOPSIS
    winget パッケージ管理ハンドラー

.DESCRIPTION
    - winget import: パッケージリストからインストール
    - winget export: インストール済みパッケージをエクスポート

.NOTES
    Order = 90 (WSL 非依存処理)
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
        $this.RequiresAdmin = $true
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

            # packages.json を読み込んで各パッケージを個別にチェック
            $packagesJson = Get-JsonContent -Path $packagesPath
            $packages = @()
            foreach ($source in $packagesJson.Sources) {
                $sourceName = $source.SourceDetails.Name
                foreach ($pkg in $source.Packages) {
                    $packages += [PSCustomObject]@{
                        Id         = $pkg.PackageIdentifier
                        SourceName = $sourceName
                    }
                }
            }

            $installed = 0
            $skipped = 0
            $failed = 0

            # winget 終了コード定数
            $WINGET_ALREADY_INSTALLED   = -1978335215  # 0x8A150011: インストール済み (exact match)
            $WINGET_NO_APPLICABLE_UPDATE = -1978335189  # 0x8A15002B: インストール済み・アップグレード不要
            #   → 1Password / Claude 等: winget install 実行時に「既にインストール済みでアップグレードなし」を返す。
            #     昇格/非昇格問わず発生する。machine scope 非対応かつ既インストールのパッケージが該当。

            $needsManualInstall = [System.Collections.Generic.List[string]]::new()

            # -UserScopeOnly: machine scope をスキップして user scope のみ試みる
            $userScopeOnly = $ctx.GetOption("UserScopeOnly", $false)
            if ($userScopeOnly) {
                $this.Log("User scope only モードで実行中（非昇格）", "Cyan")
            }

            foreach ($pkg in $packages) {
                $id = $pkg.Id
                $this.Log("インストール: $id")

                $userArgs = @(
                    "install", "--id", $id, "--exact", "--silent",
                    "--accept-package-agreements", "--accept-source-agreements"
                )
                if ($pkg.SourceName -eq "msstore") {
                    $userArgs += "--source"
                    $userArgs += "msstore"
                }

                if ($userScopeOnly) {
                    # 非昇格モード: user scope のみ
                    $result = Invoke-WingetInstall -Arguments $userArgs
                    if ($result.ExitCode -eq 0) {
                        $this.Log("インストール完了: $id", "Green")
                        $installed++
                    } elseif ($result.ExitCode -eq $WINGET_ALREADY_INSTALLED -or $result.ExitCode -eq $WINGET_NO_APPLICABLE_UPDATE) {
                        $this.Log("スキップ (インストール済み): $id", "Gray")
                        $skipped++
                    } else {
                        $msg = ($result.Output | Where-Object { $_ -match '\S' } | Select-Object -Last 2) -join "; "
                        $this.LogWarning("インストール失敗: $id (exit=$($result.ExitCode)) [$msg]")
                        $failed++
                    }
                } else {
                    # 通常モード: machine scope → 失敗時 user scope にフォールバック
                    $installArgs = @(
                        "install", "--id", $id, "--exact", "--silent",
                        "--accept-package-agreements", "--accept-source-agreements",
                        "--scope", "machine"
                    )
                    if ($pkg.SourceName -eq "msstore") {
                        $installArgs += "--source"
                        $installArgs += "msstore"
                    }
                    $installResult = Invoke-WingetInstall -Arguments $installArgs

                    if ($installResult.ExitCode -eq 0) {
                        $this.Log("インストール完了: $id", "Green")
                        $installed++
                    } elseif ($installResult.ExitCode -eq $WINGET_ALREADY_INSTALLED -or $installResult.ExitCode -eq $WINGET_NO_APPLICABLE_UPDATE) {
                        $this.Log("スキップ (インストール済み): $id", "Gray")
                        $skipped++
                    } else {
                        # machine scope 非対応 → user scope でリトライ
                        $this.Log("machine scope 非対応、user scope でリトライ: $id", "Yellow")
                        $retryResult = Invoke-WingetInstall -Arguments $userArgs
                        if ($retryResult.ExitCode -eq 0) {
                            $this.Log("インストール完了 (user scope): $id", "Green")
                            $installed++
                        } elseif ($retryResult.ExitCode -eq $WINGET_ALREADY_INSTALLED -or $retryResult.ExitCode -eq $WINGET_NO_APPLICABLE_UPDATE) {
                            $this.Log("スキップ (インストール済み): $id", "Gray")
                            $skipped++
                        } else {
                            $msg = ($retryResult.Output | Where-Object { $_ -match '\S' } | Select-Object -Last 2) -join "; "
                            $this.LogWarning("インストール失敗: $id (exit=$($retryResult.ExitCode)) [$msg]")
                            $needsManualInstall.Add($id)
                            $failed++
                        }
                    }
                }
            }

            $summary = "インストール済み: $installed, スキップ: $skipped, 失敗: $failed"
            $this.Log($summary, "Green")

            if ($needsManualInstall.Count -gt 0) {
                # user scope 専用パッケージ用スクリプトを生成
                $pendingScript = Join-Path $env:TEMP "dotfiles-user-install.ps1"
                $lines = @("# user scope 専用パッケージの一括インストール (非昇格で実行)")
                $lines += "# 生成日時: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                $lines += ""
                foreach ($manualId in $needsManualInstall) {
                    $lines += "winget install --id $manualId --exact --silent --accept-package-agreements --accept-source-agreements"
                }
                $lines | Set-Content -Path $pendingScript -Encoding UTF8

                $this.LogWarning("")
                $this.LogWarning("━━━ 手動インストールが必要なパッケージ ($($needsManualInstall.Count)件) ━━━")
                $this.LogWarning("以下のパッケージは user scope 専用です。")
                $this.LogWarning("【一括インストール】管理者権限なしの PowerShell で実行:")
                $this.LogWarning("")
                $this.LogWarning("  powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$pendingScript`"")
                $this.LogWarning("")
                $this.LogWarning("  または:")
                $this.LogWarning("")
                $this.LogWarning("  .\install.ps1 -UserScopeOnly")
                $this.LogWarning("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            }

            if ($failed -gt 0) {
                return $this.CreateSuccessResult("パッケージをインストールしました（一部失敗: $failed）")
            }
            return $this.CreateSuccessResult("パッケージをインストールしました ($summary)")
        } catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
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
        パッケージリストファイルのパスを取得する
    #>
    hidden [string] GetPackagesPath([SetupContext]$ctx) {
        return Join-Path $ctx.DotfilesPath "windows\winget\packages.json"
    }
}
