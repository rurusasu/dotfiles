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

            # 方法1: wsl --install --no-distribution
            $this.Log("wsl --install --no-distribution を実行中...")
            $output = Invoke-Wsl -TimeoutSeconds (Get-WslInstallTimeoutSecond) --install --no-distribution 2>&1
            $this.LogNativeOutput($output)

            if ($LASTEXITCODE -eq 0) {
                return $this.CreateRebootRequiredResult()
            }

            # 方法2: wsl --install が失敗した場合、dism.exe で Optional Feature を直接有効化
            $this.LogWarning("wsl --install が失敗しました。dism.exe で Windows Optional Feature を有効化します...")
            $dismSuccess = $this.EnableWslFeatures()

            if ($dismSuccess) {
                return $this.CreateRebootRequiredResult()
            }

            return $this.CreateFailureResult(
                "WSL のインストールに失敗しました。手動で以下を管理者 PowerShell で実行してください:`n" +
                "  dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart`n" +
                "  dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart"
            )
        }
        catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }

    <#
    .SYNOPSIS
        dism.exe で WSL 関連の Windows Optional Feature を有効化する
    .OUTPUTS
        全て成功なら $true
    #>
    hidden [bool] EnableWslFeatures() {
        $features = @(
            "Microsoft-Windows-Subsystem-Linux",
            "VirtualMachinePlatform"
        )
        $allSuccess = $true

        foreach ($feature in $features) {
            $this.Log("dism.exe: $feature を有効化中...")
            $output = Invoke-Dism -TimeoutSeconds (Get-WslInstallTimeoutSecond) /online /enable-feature /featurename:$feature /all /norestart 2>&1
            $this.LogNativeOutput($output)

            $exitCode = $LASTEXITCODE
            if (-not $this.IsSuccessfulDismExitCode($exitCode)) {
                $this.LogWarning("$feature の有効化に失敗しました (exit=$LASTEXITCODE)")
                $allSuccess = $false
            }
            elseif ($exitCode -eq 3010 -or $exitCode -eq 1641) {
                $this.Log("$feature を有効化しました（再起動が必要）", "Green")
            }
            else {
                $this.Log("$feature を有効化しました", "Green")
            }
        }

        return $allSuccess
    }

    hidden [bool] IsSuccessfulDismExitCode([int]$exitCode) {
        return $exitCode -eq 0 -or
            $exitCode -eq 3010 -or
            $exitCode -eq 1641
    }

    hidden [void] LogNativeOutput([object[]]$output) {
        foreach ($item in @($output)) {
            $line = [string]$item
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($this.IsGarbledNativeOutput($line)) { continue }
            $this.Log("  $line", "Gray")
        }
    }

    hidden [bool] IsGarbledNativeOutput([string]$line) {
        return $line -match "`0" -or
            $line -match '�' -or
            $line -match '[\x00-\x08\x0B\x0C\x0E-\x1F]'
    }

    hidden [SetupResult] CreateRebootRequiredResult() {
        $this.Log("WSL コンポーネントのインストールが完了しました", "Green")
        $this.Log("WSL を有効にするには PC の再起動が必要です", "Yellow")
        $this.Log("再起動後に install.cmd を再実行してください", "Yellow")
        return $this.CreateSuccessResult("WSL をインストールしました（再起動が必要）")
    }
}
