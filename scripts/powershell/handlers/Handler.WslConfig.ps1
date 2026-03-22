<#
.SYNOPSIS
    WSL 設定ファイル (.wslconfig) を管理するハンドラー

.DESCRIPTION
    - .wslconfig を %USERPROFILE% にコピー
    - WSL を再起動して設定を反映

.NOTES
    Order = 20 (WSL 依存処理)
    VHD サイズ管理は VhdManagerHandler (Order=21) が担当
#>

# 依存ファイルの読み込み
$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class WslConfigHandler : SetupHandlerBase {
    WslConfigHandler() {
        $this.Name = "WslConfig"
        $this.Description = ".wslconfig の適用"
        $this.Order = 20
        $this.RequiresAdmin = $false
    }

    <#
    .SYNOPSIS
        実行可否を判定する
    .DESCRIPTION
        以下の条件をチェック:
        - windows\.wslconfig ファイルが存在するか
        - SkipWslConfigApply オプションが設定されていないか
    #>
    [bool] CanApply([SetupContext]$ctx) {
        if ($ctx.GetOption("SkipWslConfigApply", $false)) {
            $this.Log("SkipWslConfigApply が設定されているためスキップします", "Gray")
            return $false
        }

        $sourcePath = $this.GetSourceWslConfigPath($ctx)
        if (-not (Test-PathExist -Path $sourcePath)) {
            $this.LogWarning(".wslconfig が見つかりません: $sourcePath")
            return $false
        }

        return $true
    }

    <#
    .SYNOPSIS
        .wslconfig を適用する
    #>
    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            $sourcePath = $this.GetSourceWslConfigPath($ctx)
            $destPath = $this.GetDestWslConfigPath()

            $this.Log(".wslconfig をコピーしています: $sourcePath -> $destPath")
            try {
                Copy-FileSafe -Source $sourcePath -Destination $destPath -Force
            } catch {
                return $this.CreateFailureResult("ファイルコピーに失敗: $($_.Exception.Message)", $_.Exception)
            }

            # .wslconfig は全 WSL ディストリビューションに影響するため再起動が必要
            # ただし wsl --shutdown は Docker Desktop の WSL 統合を壊す可能性があるため
            # 対象ディストリビューションのみ再起動する
            $this.Log("WSL ディストリビューション '$($ctx.DistroName)' を再起動して設定を反映します")
            Invoke-Wsl --terminate $ctx.DistroName

            return $this.CreateSuccessResult(".wslconfig を適用しました")
        } catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }

    <#
    .SYNOPSIS
        ソース .wslconfig のパスを取得する
    #>
    hidden [string] GetSourceWslConfigPath([SetupContext]$ctx) {
        return Join-Path $ctx.DotfilesPath "windows\.wslconfig"
    }

    <#
    .SYNOPSIS
        宛先 .wslconfig のパスを取得する
    #>
    hidden [string] GetDestWslConfigPath() {
        return Join-Path $env:USERPROFILE ".wslconfig"
    }
}
