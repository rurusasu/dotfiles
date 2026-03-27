<#
.SYNOPSIS
    WSL VHD サイズ管理ハンドラー

.DESCRIPTION
    - WSL VHD (ext4.vhdx) の仮想サイズを管理
    - .wslconfig の defaultVhdSize に基づいて拡張/縮小を判断
    - 拡張: diskpart を使用
    - 縮小: Hyper-V (Resize-VHD) を使用（要 AllowVhdShrink オプション）

.NOTES
    Order = 21 (WslConfig の直後)
    RequiresAdmin = $true
#>

# 依存ファイルの読み込み
$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class VhdManagerHandler : SetupHandlerBase {
    VhdManagerHandler() {
        $this.Name = "VhdManager"
        $this.Description = "WSL VHD サイズ管理"
        $this.Order = 21
        $this.RequiresAdmin = $true
    }

    <#
    .SYNOPSIS
        実行可否を判定する
    .DESCRIPTION
        以下の条件をチェック:
        - SkipVhdExpand オプションが設定されていないか
        - WSL ディストリビューションが存在するか
    #>
    [bool] CanApply([SetupContext]$ctx) {
        if ($ctx.GetOption("SkipVhdExpand", $false)) {
            $this.Log("SkipVhdExpand が設定されているためスキップします", "Gray")
            return $false
        }

        # ディストリビューションの BasePath を確認
        $basePath = $this.GetWslDistroBasePath($ctx.DistroName)
        if (-not $basePath) {
            $this.Log("WSL ディストリビューションが見つかりません: $($ctx.DistroName)", "Gray")
            return $false
        }

        $vhdxPath = Join-Path $basePath "ext4.vhdx"
        if (-not (Test-PathExist -Path $vhdxPath)) {
            $this.Log("VHDX が見つかりません: $vhdxPath", "Gray")
            return $false
        }

        return $true
    }

    <#
    .SYNOPSIS
        VHD サイズを管理する
    #>
    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            $basePath = $this.GetWslDistroBasePath($ctx.DistroName)
            $vhdxPath = Join-Path $basePath "ext4.vhdx"

            # 目標サイズを取得
            $targetMB = $this.GetTargetVhdSizeMB($ctx)
            $targetBytes = [long]$targetMB * 1MB
            $targetGB = [math]::Round($targetMB / 1024, 2)

            # 現在の仮想サイズを取得
            $currentVirtualSizeBytes = $this.GetVhdxVirtualSize($vhdxPath)

            if ($currentVirtualSizeBytes -le 0) {
                $this.Log("VHDX 仮想サイズを取得できませんでした。拡張を試行します")
                $currentVirtualSizeGB = "不明"
            } else {
                $currentVirtualSizeGB = [math]::Round($currentVirtualSizeBytes / 1GB, 2)
            }

            $this.Log("VHDX 仮想サイズ: ${currentVirtualSizeGB}GB, ターゲット: ${targetGB}GB")

            # サイズが同じ場合は早期リターン（Docker Desktop 停止などの処理をスキップ）
            if ($currentVirtualSizeBytes -gt 0 -and $currentVirtualSizeBytes -eq $targetBytes) {
                $this.Log("VHDX は既にターゲットサイズです", "Gray")
                return $this.CreateSuccessResult("VHD は既にターゲットサイズです")
            }

            # Docker Desktop を停止（VHDX 操作中の競合を防ぐ）
            $dockerWasRunning = $null -ne (Get-ProcessSafe -Name "Docker Desktop")
            if ($dockerWasRunning) {
                $this.Log("Docker Desktop を一時停止します")
                Stop-ProcessSafe -Name "Docker Desktop"
                Start-SleepSafe -Seconds 2
            }

            try {
                # 対象ディストリビューションのみ停止（--shutdown は他ディストリビューションに影響）
                Invoke-Wsl --terminate $ctx.DistroName

                $result = $this.ManageVhdSize($ctx, $vhdxPath, $currentVirtualSizeBytes, $targetBytes, $targetGB)
                return $result

            } finally {
                # Docker Desktop を再起動
                if ($dockerWasRunning) {
                    $this.Log("Docker Desktop を再起動します")
                    $dockerExe = Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe"
                    if (Test-PathExist -Path $dockerExe) {
                        Start-ProcessSafe -FilePath $dockerExe
                    }
                }
            }
        } catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }

    <#
    .SYNOPSIS
        VHD サイズを管理する（拡張/縮小/スキップを判断）
    #>
    hidden [SetupResult] ManageVhdSize([SetupContext]$ctx, [string]$vhdxPath, [long]$currentBytes, [long]$targetBytes, [double]$targetGB) {
        $currentGB = if ($currentBytes -gt 0) { [math]::Round($currentBytes / 1GB, 2) } else { "不明" }
        $targetMB = [int]($targetBytes / 1MB)

        if ($currentBytes -le 0) {
            # サイズ不明の場合は拡張を試行
            $this.TryExpandVhd($vhdxPath, $targetMB, $targetGB)
            $this.ResizeFilesystem($ctx)
            return $this.CreateSuccessResult("VHD 拡張を試行しました（サイズ不明のため）")

        } elseif ($targetBytes -gt $currentBytes) {
            # 拡張
            $this.Log("VHDX を拡張します: ${currentGB}GB -> ${targetGB}GB")
            $this.TryExpandVhd($vhdxPath, $targetMB, $targetGB)
            $this.ResizeFilesystem($ctx)
            return $this.CreateSuccessResult("VHD を ${targetGB}GB へ拡張しました")

        } elseif ($targetBytes -lt $currentBytes) {
            # 縮小
            $this.Log("VHDX を縮小します: ${currentGB}GB -> ${targetGB}GB")
            $this.ShrinkVhd($ctx, $vhdxPath, $targetBytes)
            return $this.CreateSuccessResult("VHD を ${targetGB}GB へ縮小しました")

        } else {
            # 同じサイズ
            $this.Log("VHDX は既にターゲットサイズです", "Gray")
            return $this.CreateSuccessResult("VHD は既にターゲットサイズです")
        }
    }

    <#
    .SYNOPSIS
        VHDX の拡張を試行する（既に十分なサイズの場合はスキップ）
    #>
    hidden [void] TryExpandVhd([string]$vhdxPath, [int]$targetMB, [double]$targetGB) {
        $diskpartScript = @"
select vdisk file="$vhdxPath"
expand vdisk maximum=$targetMB
exit
"@
        try {
            Invoke-Diskpart -ScriptContent $diskpartScript
            $this.Log("VHDX を ${targetGB}GB へ拡張しました")
        } catch {
            if ($_.Exception.Message -match "パラメーター" -or $_.Exception.Message -match "-2147024809") {
                $this.Log("VHDX は既にターゲットサイズ以上のため、拡張をスキップしました", "Gray")
            } else {
                throw
            }
        }
    }

    <#
    .SYNOPSIS
        VHDX ファイルの仮想サイズを取得する
    #>
    hidden [long] GetVhdxVirtualSize([string]$vhdxPath) {
        # 方法1: Get-VHD (Hyper-V) を使用
        try {
            if (Get-Command Get-VHD -ErrorAction SilentlyContinue) {
                $vhd = Get-VHD -Path $vhdxPath
                return $vhd.Size
            }
        } catch {
            # Get-VHD が失敗した場合は次の方法を試す
            $null = $_.Exception
        }

        # 方法2: diskpart で detail vdisk を使用
        try {
            return $this.GetVhdxVirtualSizeViaDiskpart($vhdxPath)
        } catch {
            return -1
        }
    }

    <#
    .SYNOPSIS
        diskpart を使って VHDX の仮想サイズを取得する
    #>
    hidden [long] GetVhdxVirtualSizeViaDiskpart([string]$vhdxPath) {
        $diskpartScript = @"
select vdisk file="$vhdxPath"
detail vdisk
exit
"@
        $tmp = New-TemporaryFile
        try {
            Set-Content -Path $tmp -Value $diskpartScript -NoNewline
            $outFile = [System.IO.Path]::GetTempFileName()
            try {
                $cmdLine = "diskpart /s ""$($tmp.FullName)"" > ""$outFile"" 2>&1"
                & cmd /c $cmdLine
                $output = Get-Content -Path $outFile -ErrorAction SilentlyContinue

                foreach ($line in $output) {
                    if ($line -match '仮想サイズ\s*[:：]\s*(\d+)\s*(GB|MB|TB)' -or
                        $line -match 'Virtual size\s*[:：]\s*(\d+)\s*(GB|MB|TB)') {
                        $size = [long]$Matches[1]
                        $unit = $Matches[2].ToUpper()
                        switch ($unit) {
                            "TB" { return $size * 1TB }
                            "GB" { return $size * 1GB }
                            "MB" { return $size * 1MB }
                        }
                    }
                }
                return -1
            } finally {
                Remove-Item -Path $outFile -Force -ErrorAction SilentlyContinue
            }
        } finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }

    <#
    .SYNOPSIS
        VHDX を縮小する
    #>
    hidden [void] ShrinkVhd([SetupContext]$ctx, [string]$vhdxPath, [long]$targetBytes) {
        if (-not (Get-Command Resize-VHD -ErrorAction SilentlyContinue)) {
            $this.LogWarning("VHDX の縮小には Hyper-V が必要です")
            $this.LogWarning("実行: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-PowerShell")
            return
        }

        $targetGB = [math]::Round($targetBytes / 1GB, 2)

        $this.LogWarning("VHDX の縮小はデータ損失のリスクがあります")
        $this.LogWarning("縮小前に WSL 内のデータをバックアップしてください")

        if (-not $ctx.GetOption("AllowVhdShrink", $false)) {
            $this.LogWarning("縮小を実行するには Options に AllowVhdShrink=`$true を指定してください")
            return
        }

        $distroName = $ctx.DistroName
        $this.Log("WSL 内でファイルシステムを縮小します...")

        # ルートデバイスを動的に検出（ResizeFilesystem と同じロジック）
        $findRoot = 'lsblk -f | awk ''\$2=="ext4" && \$7=="/" {print "/dev/"\$1; exit}'''
        $dev = Invoke-Wsl -d $distroName -u root -- sh -lc $findRoot | Select-Object -First 1
        if (-not $dev) {
            $findFallback = 'lsblk -f | awk ''\$2=="ext4" && \$7=="/mnt/wslg/distro" {print "/dev/"\$1; exit}'''
            $dev = Invoke-Wsl -d $distroName -u root -- sh -lc $findFallback | Select-Object -First 1
        }
        if (-not $dev) {
            $this.LogWarning("縮小対象のデバイスを特定できませんでした")
            return
        }
        $dev = $dev.Trim()
        $this.Log("デバイス: $dev")

        Invoke-Wsl -d $distroName -u root -- sh -lc "e2fsck -f -y $dev" 2>$null

        $targetSizeK = [math]::Floor($targetBytes / 1KB)
        Invoke-Wsl -d $distroName -u root -- sh -lc "resize2fs $dev ${targetSizeK}K" 2>$null

        Invoke-Wsl --terminate $distroName

        $this.Log("VHDX を縮小しています...")
        Resize-VHD -Path $vhdxPath -SizeBytes $targetBytes
        $this.Log("VHDX を ${targetGB}GB へ縮小しました")
    }

    <#
    .SYNOPSIS
        ファイルシステムをリサイズする
    #>
    hidden [void] ResizeFilesystem([SetupContext]$ctx) {
        $distroName = $ctx.DistroName

        $findRoot = 'lsblk -f | awk ''\$2=="ext4" && \$7=="/" {print "/dev/"\$1; exit}'''
        $dev = Invoke-Wsl -d $distroName -u root -- sh -lc $findRoot | Select-Object -First 1

        if (-not $dev) {
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
                $basePath = $props.BasePath -replace '\\\\', '\'
                return $basePath
            }
        }
        return $null
    }

    <#
    .SYNOPSIS
        目標 VHD サイズを取得する（MB 単位）
    #>
    hidden [int] GetTargetVhdSizeMB([SetupContext]$ctx) {
        $configPaths = @(
            (Join-Path $ctx.DotfilesPath "windows\.wslconfig"),
            (Join-Path $env:USERPROFILE ".wslconfig")
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

        $this.LogWarning("defaultVhdSize を読み取れないため、32768MB で拡張します")
        return 32768
    }
}
