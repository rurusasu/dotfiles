<#
.SYNOPSIS
    Herdr Windows preview installer handler.

.DESCRIPTION
    Herdr does not have a supported Windows stable package in the current
    catalog. The official installer manages the preview binary and its
    versioned install directory, so this handler invokes that installer in
    user scope and verifies the resulting executable.

.NOTES
    Order = 8 (after Codex, alongside other user-scope CLI setup)
#>

$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class HerdrHandler : SetupHandlerBase {
    HerdrHandler() {
        $this.Name = "Herdr"
        $this.Description = "Herdr Windows preview installer"
        $this.Order = 8
        $this.RequiresAdmin = $false
        $this.Phase = 1
    }

    [bool] CanApply([SetupContext]$ctx) {
        return $true
    }

    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            $installerUrl = "https://herdr.dev/install.ps1"
            $installer = Invoke-RestMethod -Uri $installerUrl -UseBasicParsing
            if ([string]::IsNullOrWhiteSpace([string]$installer)) {
                return $this.CreateFailureResult("Herdr installer が空の応答を返しました")
            }

            $global:LASTEXITCODE = 0
            & ([scriptblock]::Create([string]$installer))
            if ($LASTEXITCODE -ne 0) {
                return $this.CreateFailureResult("Herdr preview installer が失敗しました (exit=$LASTEXITCODE)")
            }

            $herdrPath = $this.GetHerdrExecutablePath()
            if (-not $herdrPath) {
                return $this.CreateFailureResult("Herdr installer 実行後に herdr.exe が PATH に見つかりません")
            }

            Invoke-VerifyCommand -Command $herdrPath -Arguments @("--version") | Out-Null
            if ($LASTEXITCODE -ne 0) {
                return $this.CreateFailureResult("Herdr のバージョン検証に失敗しました")
            }

            return $this.CreateSuccessResult("Herdr Windows preview をインストールしました")
        }
        catch {
            return $this.CreateFailureResult("Herdr Windows preview のインストールに失敗しました", $_.Exception)
        }
    }

    hidden [string] GetHerdrExecutablePath() {
        $command = Get-ExternalCommand -Name "herdr"
        if ($command) {
            return $command.Source
        }

        $managedPath = Join-Path $this.GetLocalAppDataPath() "Programs\Herdr\bin\herdr.exe"
        if (Test-Path -LiteralPath $managedPath) {
            return $managedPath
        }

        return $null
    }

    hidden [string] GetLocalAppDataPath() {
        if ($env:LOCALAPPDATA) {
            return $env:LOCALAPPDATA
        }

        $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
        return Join-Path $homeDir "AppData\Local"
    }
}
