<#
.SYNOPSIS
    mise によるツールインストールと pre-commit セットアップを管理するハンドラー

.DESCRIPTION
    - mise コマンドの検出
    - mise install の実行（treefmt, pre-commit 等）
    - pre-commit hooks の自動セットアップ（mise の postinstall フック経由）

.NOTES
    Order = 15 (Winget の後、他の処理の前)
    Winget で mise がインストールされた後に実行
#>

# 依存ファイルの読み込み
# 注: SetupHandler.ps1 は install.ps1 またはテストフレームワークによって事前にロードされている前提
# クラスキャッシュ問題を防ぐため、ここでは読み込まない
$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class MiseHandler : SetupHandlerBase {
    # 検出された mise 実行ファイルのパス
    hidden [string]$MiseExePath

    MiseHandler() {
        $this.Name = "Mise"
        $this.Description = "mise によるツールインストール"
        $this.Order = 15
        $this.RequiresAdmin = $false
    }

    <#
    .SYNOPSIS
        実行可否を判定する
    .DESCRIPTION
        以下の条件をチェック:
        - mise コマンドが利用可能か
        - .mise.toml が存在するか
    #>
    [bool] CanApply([SetupContext]$ctx) {
        # スキップオプションのチェック
        if ($ctx.GetOption("SkipMiseInstall", $false)) {
            $this.Log("mise install をスキップします（SkipMiseInstall オプション）", "Gray")
            return $false
        }

        # mise の検出
        $this.MiseExePath = $this.FindMiseExe()
        if (-not $this.MiseExePath) {
            $this.ShowMiseInstallInstructions()
            return $false
        }

        # mise が実際に動作するか確認（DLL不足などを検出）
        if (-not $this.TestMiseExecutable()) {
            $this.LogWarning("mise が正常に動作しません（Visual C++ Redistributable が必要な可能性があります）")
            $this.Log("修正方法: winget install -e --id Microsoft.VCRedist.2015+.x64", "Yellow")
            return $false
        }

        # .mise.toml の確認
        $configPath = $this.GetMiseConfigPath($ctx)
        if (-not (Test-PathExist -Path $configPath)) {
            $this.LogWarning(".mise.toml が見つかりません: $configPath")
            return $false
        }

        return $true
    }

    <#
    .SYNOPSIS
        mise install を実行する
    #>
    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            $configPath = $this.GetMiseConfigPath($ctx)
            $this.Log("mise でツールをインストールします")
            $this.Log("設定ファイル: $configPath", "Gray")

            # mise trust を実行（初回実行時に必要）
            $this.TrustMiseConfig($ctx)

            # mise install を実行
            $result = $this.RunMiseInstall($ctx)

            if ($result) {
                return $this.CreateSuccessResult("mise ツールをインストールしました（pre-commit hooks 含む）")
            } else {
                return $this.CreateFailureResult("mise install が失敗しました")
            }
        } catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }

    <#
    .SYNOPSIS
        mise trust を実行する（設定ファイルを信頼）
    #>
    hidden [void] TrustMiseConfig([SetupContext]$ctx) {
        $configPath = $this.GetMiseConfigPath($ctx)
        $this.Log("mise 設定ファイルを trust します", "Gray")

        $originalLocation = Get-Location
        try {
            Set-Location $ctx.DotfilesPath
            Invoke-MiseCommand -MiseExePath $this.MiseExePath -Arguments @("trust", $configPath) | Out-Null
        } finally {
            Set-Location $originalLocation
        }
    }

    <#
    .SYNOPSIS
        mise install を実行する
    #>
    hidden [bool] RunMiseInstall([SetupContext]$ctx) {
        $originalLocation = Get-Location
        try {
            Set-Location $ctx.DotfilesPath

            $this.Log("mise install を実行中...")
            $output = Invoke-MiseCommand -MiseExePath $this.MiseExePath -Arguments @("install")

            if ($LASTEXITCODE -eq 0) {
                $this.Log("mise install 完了", "Green")

                # インストールされたツールを表示
                $this.ShowInstalledTools()

                return $true
            } else {
                $this.LogError("mise install が失敗しました (exit=$LASTEXITCODE)")
                if ($output) {
                    $this.Log("出力: $output", "Gray")
                }
                return $false
            }
        } finally {
            Set-Location $originalLocation
        }
    }

    <#
    .SYNOPSIS
        インストールされたツールを表示する
    #>
    hidden [void] ShowInstalledTools() {
        try {
            $tools = Invoke-MiseCommand -MiseExePath $this.MiseExePath -Arguments @("list")
            if ($LASTEXITCODE -eq 0 -and $tools) {
                $this.Log("インストール済みツール:", "Gray")
                foreach ($line in $tools) {
                    if ($line -and $line.Trim()) {
                        $this.Log("  $line", "Gray")
                    }
                }
            }
        } catch {
            # ツール一覧の表示に失敗しても続行（mise list はオプション機能）
            $this.Log("ツール一覧の取得をスキップしました", "Gray")
        }
    }

    <#
    .SYNOPSIS
        mise 実行ファイルを検索する
    .DESCRIPTION
        以下の順序で検索:
        1. PATH 内の mise
        2. WinGet Links ディレクトリ
        3. WinGet Packages ディレクトリ
    #>
    hidden [string] FindMiseExe() {
        # 1. PATH から検索
        $cmd = Get-ExternalCommand -Name "mise"
        if ($cmd) {
            return $cmd.Source
        }

        # 2. WinGet Links ディレクトリ
        $linksPath = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\mise.exe"
        if (Test-PathExist -Path $linksPath) {
            return $linksPath
        }

        # 3. WinGet Packages ディレクトリ
        $packagesRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
        if (Test-PathExist -Path $packagesRoot) {
            $pkgDir = Get-ChildItemSafe -Path $packagesRoot -Directory |
                Where-Object { $_.Name -like 'jdx.mise*' } |
                Select-Object -First 1

            if ($pkgDir) {
                $exe = Join-Path $pkgDir.FullName "mise.exe"
                if (Test-PathExist -Path $exe) {
                    return $exe
                }
            }
        }

        # 4. Programs ディレクトリ（カスタムインストール）
        $programsPath = Join-Path $env:LOCALAPPDATA "Programs\mise\mise.exe"
        if (Test-PathExist -Path $programsPath) {
            return $programsPath
        }

        # 5. Cargo インストール
        $cargoPath = Join-Path $env:USERPROFILE ".cargo\bin\mise.exe"
        if (Test-PathExist -Path $cargoPath) {
            return $cargoPath
        }

        return $null
    }

    <#
    .SYNOPSIS
        mise が実際に動作するか確認する
    .DESCRIPTION
        mise --version を実行して、DLL不足などのエラーがないか確認
    #>
    hidden [bool] TestMiseExecutable() {
        try {
            $output = Invoke-MiseCommand -MiseExePath $this.MiseExePath -Arguments @("--version")
            # exit code 0 かつ出力にバージョン情報が含まれているか確認
            if ($LASTEXITCODE -eq 0 -and $output -match '\d+\.\d+') {
                return $true
            }
            return $false
        } catch {
            # 例外が発生した場合（DLL不足など）
            return $false
        }
    }

    <#
    .SYNOPSIS
        mise インストール手順を表示する
    #>
    hidden [void] ShowMiseInstallInstructions() {
        Write-Host ""
        Write-Host "mise がインストールされていません" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "インストール方法:" -ForegroundColor Cyan
        Write-Host "  winget install -e --id jdx.mise"
        Write-Host ""
        Write-Host "インストール後、シェルを再起動してから再度このスクリプトを実行してください。"
        Write-Host ""
    }

    <#
    .SYNOPSIS
        .mise.toml のパスを取得する
    #>
    hidden [string] GetMiseConfigPath([SetupContext]$ctx) {
        return Join-Path $ctx.DotfilesPath ".mise.toml"
    }
}
