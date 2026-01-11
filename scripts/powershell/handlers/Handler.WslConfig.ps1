<#
.SYNOPSIS
    WSL 設定ファイル (.wslconfig) と VHD 拡張を管理するハンドラー

.DESCRIPTION
    - .wslconfig を %USERPROFILE% にコピー
    - WSL VHD (ext4.vhdx) のサイズ拡張
    - ファイルシステムのリサイズ

.NOTES
    Order = 10 (WSL 依存処理の最初)
    WSL ディストリビューションが登録された直後に実行される想定
#>

# 依存ファイルの読み込み
$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\SetupHandler.ps1")
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class WslConfigHandler : SetupHandlerBase {
    WslConfigHandler() {
        $this.Name = "WslConfig"
        $this.Description = ".wslconfig の適用と VHD 拡張"
        $this.Order = 20
        $this.RequiresAdmin = $true
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
        # スキップオプションのチェック
        if ($ctx.GetOption("SkipWslConfigApply", $false)) {
            $this.Log("SkipWslConfigApply が設定されているためスキップします", "Gray")
            return $false
        }

        # ソースファイルの存在チェック
        $sourcePath = $this.GetSourceWslConfigPath($ctx)
        if (-not (Test-PathExist -Path $sourcePath)) {
            $this.LogWarning(".wslconfig が見つかりません: $sourcePath")
            return $false
        }

        return $true
    }

    <#
    .SYNOPSIS
        .wslconfig を適用し、VHD を拡張する
    #>
    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            # .wslconfig のコピー
            $copyResult = $this.ApplyWslConfig($ctx)
            if (-not $copyResult) {
                return $this.CreateFailureResult(".wslconfig のコピーに失敗しました")
            }

            # VHD 拡張（スキップオプションがない場合）
            if (-not $ctx.GetOption("SkipVhdExpand", $false)) {
                $this.ExpandVhd($ctx)
            } else {
                $this.Log("SkipVhdExpand が設定されているため VHD 拡張をスキップします", "Gray")
            }

            return $this.CreateSuccessResult(".wslconfig を適用しました")
        } catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }

    <#
    .SYNOPSIS
        .wslconfig ファイルをコピーする
    #>
    hidden [bool] ApplyWslConfig([SetupContext]$ctx) {
        $sourcePath = $this.GetSourceWslConfigPath($ctx)
        $destPath = $this.GetDestWslConfigPath()

        $this.Log(".wslconfig をコピーしています: $sourcePath -> $destPath")
        try {
            Copy-FileSafe -Source $sourcePath -Destination $destPath -Force
        } catch {
            $this.LogError("ファイルコピーに失敗: $($_.Exception.Message)")
            return $false
        }

        # WSL を再起動して設定を反映
        $this.Log("WSL を再起動して設定を反映します")
        Invoke-Wsl --shutdown

        return $true
    }

    <#
    .SYNOPSIS
        VHD を拡張する
    #>
    hidden [void] ExpandVhd([SetupContext]$ctx) {
        $basePath = $this.GetWslDistroBasePath($ctx.DistroName)
        if (-not $basePath) {
            $this.LogWarning("WSL ディストリの BasePath を取得できませんでした: $($ctx.DistroName)")
            return
        }

        $vhdxPath = Join-Path $basePath "ext4.vhdx"
        if (-not (Test-PathExist -Path $vhdxPath)) {
            $this.LogWarning("VHDX が見つかりません: $vhdxPath")
            return
        }

        # 目標サイズを取得
        $targetMB = $this.GetTargetVhdSizeMB($ctx)
        $this.Log("VHDX を ${targetMB}MB へ拡張します: $vhdxPath")

        # WSL をシャットダウン
        Invoke-Wsl --shutdown

        # diskpart で拡張
        $diskpartScript = @"
select vdisk file="$vhdxPath"
expand vdisk maximum=$targetMB
exit
"@
        Invoke-Diskpart -ScriptContent $diskpartScript

        # ファイルシステムをリサイズ
        $this.ResizeFilesystem($ctx)
    }

    <#
    .SYNOPSIS
        ファイルシステムをリサイズする
    #>
    hidden [void] ResizeFilesystem([SetupContext]$ctx) {
        $distroName = $ctx.DistroName

        # ルートデバイスを検索
        $findRoot = 'lsblk -f | awk ''\$2=="ext4" && \$7=="/" {print "/dev/"\$1; exit}'''
        $dev = Invoke-Wsl -d $distroName -u root -- sh -lc $findRoot | Select-Object -First 1

        if (-not $dev) {
            # フォールバック: /mnt/wslg/distro を検索
            $findFallback = 'lsblk -f | awk ''\$2=="ext4" && \$7=="/mnt/wslg/distro" {print "/dev/"\$1; exit}'''
            $dev = Invoke-Wsl -d $distroName -u root -- sh -lc $findFallback | Select-Object -First 1
        }

        if ($dev) {
            $dev = $dev.Trim()
            $this.Log("ファイルシステムを拡張します: $dev")
            Invoke-Wsl -d $distroName -u root -- sh -lc "resize2fs $dev"
        } else {
            $this.LogWarning("拡張対象のデバイスを特定できませんでした")
        }
    }

    <#
    .SYNOPSIS
        WSL ディストリビューションの BasePath を取得する
    #>
    hidden [string] GetWslDistroBasePath([string]$distroName) {
        $root = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"
        $keys = Get-RegistryChildItem -Path $root
        
        foreach ($k in $keys) {
            $props = Get-RegistryValue -Path $k.PSPath
            if ($props.DistributionName -and $props.DistributionName -ieq $distroName) {
                return $props.BasePath
            }
        }
        return $null
    }

    <#
    .SYNOPSIS
        目標 VHD サイズを取得する（MB 単位）
    #>
    hidden [int] GetTargetVhdSizeMB([SetupContext]$ctx) {
        # .wslconfig から defaultVhdSize を読み取る
        $configPaths = @(
            $this.GetSourceWslConfigPath($ctx),
            $this.GetDestWslConfigPath()
        )

        foreach ($configPath in $configPaths) {
            if (Test-PathExist -Path $configPath) {
                $content = Get-FileContentSafe -Path $configPath
                $match = [regex]::Match($content, 'defaultVhdSize\s*=\s*(\d+)\s*(GB|MB)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                if ($match.Success) {
                    $num = [int]$match.Groups[1].Value
                    $unit = $match.Groups[2].Value.ToUpper()
                    if ($unit -eq "GB") {
                        return $num * 1024
                    }
                    return $num
                }
            }
        }

        # デフォルト値
        $this.LogWarning("defaultVhdSize を読み取れないため、32768MB で拡張します")
        return 32768
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
