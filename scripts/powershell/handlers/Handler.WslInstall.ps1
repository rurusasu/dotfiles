<#
.SYNOPSIS
    WSL コンポーネントのインストールを管理するハンドラー

.DESCRIPTION
    - wsl --install --no-distribution で WSL 基盤を有効化
    - winget install Microsoft.WSL では Optional Feature が有効化されないため、
      wsl --install を使用する

.NOTES
    Order = 5 (WSL 依存ハンドラより先に実行)
    RequiresAdmin = $true (Windows Optional Feature の有効化に管理者権限が必要)
#>

$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class WslInstallHandler : SetupHandlerBase {
    WslInstallHandler() {
        $this.Name = "WslInstall"
        $this.Description = "WSL コンポーネントのインストール"
        $this.Order = 5
        $this.RequiresAdmin = $true
    }

    <#
    .SYNOPSIS
        実行可否を判定する
    .DESCRIPTION
        WSL が既に利用可能なら実行不要
    #>
    [bool] CanApply([SetupContext]$ctx) {
        if ($ctx.GetOption("SkipWslInstall", $false)) {
            $this.Log("SkipWslInstall が設定されているためスキップします", "Gray")
            return $false
        }

        # WSL が既に利用可能なら不要
        if (Test-WslAvailable) {
            $this.Log("WSL は既にインストール済みです", "Gray")
            return $false
        }

        return $true
    }

    <#
    .SYNOPSIS
        WSL をインストールする
    #>
    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            $this.Log("WSL コンポーネントをインストールしています...")
            $this.Log("wsl --install --no-distribution を実行中...")

            # wsl --install は stderr に進捗を出力するため 2>&1 でマージ
            $output = & wsl --install --no-distribution 2>&1
            $output | ForEach-Object { $this.Log("  $_", "Gray") }

            if ($LASTEXITCODE -ne 0) {
                return $this.CreateFailureResult("wsl --install が失敗しました (exit=$LASTEXITCODE)")
            }

            $this.Log("WSL コンポーネントのインストールが完了しました", "Green")
            $this.Log("WSL を有効にするには PC の再起動が必要です", "Yellow")
            $this.Log("再起動後に install.cmd を再実行してください", "Yellow")

            return $this.CreateSuccessResult("WSL をインストールしました（再起動が必要）")
        } catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }
}
