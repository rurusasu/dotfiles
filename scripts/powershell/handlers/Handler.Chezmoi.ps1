<#
.SYNOPSIS
    chezmoi による dotfiles 適用を管理するハンドラー

.DESCRIPTION
    - chezmoi コマンドの検出（PATH、WinGet Links、WinGet Packages）
    - chezmoi apply の実行

.NOTES
    Order = 100 (WSL 非依存処理)
    WSL 関連の処理とは独立して実行可能
#>

# 依存ファイルの読み込み
$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\SetupHandler.ps1")
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class ChezmoiHandler : SetupHandlerBase {
    # 検出された chezmoi 実行ファイルのパス
    hidden [string]$ChezmoiExePath

    ChezmoiHandler() {
        $this.Name = "Chezmoi"
        $this.Description = "chezmoi による dotfiles 適用"
        $this.Order = 100
        $this.RequiresAdmin = $false
    }

    <#
    .SYNOPSIS
        実行可否を判定する
    .DESCRIPTION
        以下の条件をチェック:
        - chezmoi コマンドが利用可能か
        - chezmoi ソースディレクトリが存在するか
    #>
    [bool] CanApply([SetupContext]$ctx) {
        # chezmoi の検出
        $this.ChezmoiExePath = $this.FindChezmoiExe()
        if (-not $this.ChezmoiExePath) {
            $this.ShowChezmoiInstallInstructions($ctx)
            return $false
        }

        # ソースディレクトリの確認
        $sourcePath = $this.GetChezmoiSourcePath($ctx)
        if (-not (Test-PathExist -Path $sourcePath)) {
            $this.LogWarning("chezmoi ソースディレクトリが見つかりません: $sourcePath")
            return $false
        }

        return $true
    }

    <#
    .SYNOPSIS
        chezmoi apply を実行する
    #>
    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            $sourcePath = $this.GetChezmoiSourcePath($ctx)
            $this.Log("chezmoi でターミナル設定を適用します: $sourcePath")

            Invoke-Chezmoi -ExePath $this.ChezmoiExePath --source $sourcePath apply

            if ($LASTEXITCODE -eq 0) {
                $this.Log("chezmoi apply 完了", "Green")
                $this.Log("Windows Terminal を起動中なら、再起動すると確実に反映されます", "Gray")
                return $this.CreateSuccessResult("dotfiles を適用しました")
            } else {
                $this.LogError("chezmoi apply が失敗しました (exit=$LASTEXITCODE)")
                $this.Log("手動で実行してください: chezmoi --source `"$sourcePath`" apply", "Yellow")
                return $this.CreateFailureResult("chezmoi apply が失敗しました (exit=$LASTEXITCODE)")
            }
        } catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }

    <#
    .SYNOPSIS
        chezmoi 実行ファイルを検索する
    .DESCRIPTION
        以下の順序で検索:
        1. PATH 内の chezmoi
        2. WinGet Links ディレクトリ
        3. WinGet Packages ディレクトリ
    #>
    hidden [string] FindChezmoiExe() {
        # 1. PATH から検索
        $cmd = Get-ExternalCommand -Name "chezmoi"
        if ($cmd) {
            return $cmd.Source
        }

        # 2. WinGet Links ディレクトリ
        $linksPath = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\chezmoi.exe"
        if (Test-PathExist -Path $linksPath) {
            return $linksPath
        }

        # 3. WinGet Packages ディレクトリ
        $packagesRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
        if (Test-PathExist -Path $packagesRoot) {
            $pkgDir = Get-ChildItemSafe -Path $packagesRoot -Directory |
                Where-Object { $_.Name -like 'twpayne.chezmoi*' } |
                Select-Object -First 1

            if ($pkgDir) {
                $exe = Join-Path $pkgDir.FullName "chezmoi.exe"
                if (Test-PathExist -Path $exe) {
                    return $exe
                }
            }
        }

        # 4. Programs ディレクトリ（カスタムインストール）
        $programsPath = Join-Path $env:LOCALAPPDATA "Programs\chezmoi\chezmoi.exe"
        if (Test-PathExist -Path $programsPath) {
            return $programsPath
        }

        return $null
    }

    <#
    .SYNOPSIS
        chezmoi インストール手順を表示する
    #>
    hidden [void] ShowChezmoiInstallInstructions([SetupContext]$ctx) {
        $sourcePath = $this.GetChezmoiSourcePath($ctx)

        Write-Host ""
        Write-Host "========================================" -ForegroundColor Yellow
        Write-Host "chezmoi がインストールされていません" -ForegroundColor Yellow
        Write-Host "========================================" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Windows Terminal / WezTerm 設定を適用するには、以下のいずれかを実行してください:" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  # 方法1: winget で chezmoi をインストールして適用"
        Write-Host "  winget install -e --id twpayne.chezmoi"
        Write-Host "  chezmoi init --source `"$sourcePath`""
        Write-Host "  chezmoi apply"
        Write-Host ""
        Write-Host "  # 方法2: GitHub から直接取得（クローン不要）"
        Write-Host "  winget install -e --id twpayne.chezmoi"
        Write-Host "  chezmoi init rurusasu/dotfiles --source-path chezmoi"
        Write-Host "  chezmoi apply"
        Write-Host ""
    }

    <#
    .SYNOPSIS
        chezmoi ソースディレクトリのパスを取得する
    #>
    hidden [string] GetChezmoiSourcePath([SetupContext]$ctx) {
        return Join-Path $ctx.DotfilesPath "chezmoi"
    }
}
