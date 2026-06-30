<#
.SYNOPSIS
    1Password CLI の host-side PATH 設定ハンドラー

.DESCRIPTION
    VS Code Dev Containers の initializeCommand は Windows 側の cmd.exe から
    `op` を解決する。op.exe は winget パッケージ内の実体名とコマンド名が
    一致しているため、shim は作らず実体ディレクトリを USER PATH に追加する。

.NOTES
    Order = 9 (Winget/Codex/Bun の後、Chezmoi の前)
#>

$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class OnePasswordCliHandler : SetupHandlerBase {
    OnePasswordCliHandler() {
        $this.Name = "OnePasswordCli"
        $this.Description = "1Password CLI PATH 設定"
        $this.Order = 9
        $this.RequiresAdmin = $false
        $this.Phase = 1
    }

    [bool] CanApply([SetupContext]$ctx) {
        $opExe = $this.GetOnePasswordCliExecutablePath()
        if (-not $opExe) {
            $this.Log("1Password CLI パッケージがインストールされていません", "Gray")
            return $false
        }

        $packageDir = Split-Path -Parent $opExe
        $windowsAppsShim = Join-Path $this.GetWindowsAppsPath() "op.exe"
        $linksShim = Join-Path $this.GetLinksPath() "op.exe"

        if (
            $this.IsPathInUserPath($packageDir) -and
            -not (Test-Path -LiteralPath $windowsAppsShim) -and
            -not (Test-Path -LiteralPath $linksShim)
        ) {
            $this.Log("1Password CLI 実体 PATH は既に設定されています", "Gray")
            return $false
        }

        return $true
    }

    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            $opExe = $this.GetOnePasswordCliExecutablePath()
            if (-not $opExe) {
                return $this.CreateFailureResult("1Password CLI 実行ファイルが見つかりません")
            }

            $this.RemoveLegacyShim((Join-Path $this.GetWindowsAppsPath() "op.exe"))
            $this.RemoveLegacyShim((Join-Path $this.GetLinksPath() "op.exe"))
            $this.EnsureUserPathEntry((Split-Path -Parent $opExe), "1Password CLI package directory")

            return $this.CreateSuccessResult("1Password CLI PATH を設定しました")
        }
        catch {
            return $this.CreateFailureResult("1Password CLI PATH 設定に失敗しました", $_.Exception)
        }
    }

    hidden [void] RemoveLegacyShim([string]$linkPath) {
        if (Test-Path -LiteralPath $linkPath) {
            Remove-Item -LiteralPath $linkPath -Force
            $this.Log("旧 op.exe shim を削除しました: $linkPath", "Green")
        }
    }

    hidden [string] GetOnePasswordCliExecutablePath() {
        $packagesBase = Join-Path $this.GetLocalAppDataPath() "Microsoft\WinGet\Packages"
        $packageDir = Get-ChildItem -Path $packagesBase -Directory -Filter "AgileBits.1Password.CLI_*" -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $packageDir) {
            return $null
        }

        $exePath = Join-Path $packageDir.FullName "op.exe"
        if (Test-Path $exePath) {
            return $exePath
        }

        return $null
    }

    hidden [string] GetWindowsAppsPath() {
        return Join-Path $this.GetLocalAppDataPath() "Microsoft\WindowsApps"
    }

    hidden [string] GetLinksPath() {
        return Join-Path $this.GetLocalAppDataPath() "Microsoft\WinGet\Links"
    }

    hidden [string] GetLocalAppDataPath() {
        if ($env:LOCALAPPDATA) {
            return $env:LOCALAPPDATA
        }

        return Join-Path $this.GetHomeDir() "AppData\Local"
    }

    hidden [string] GetHomeDir() {
        if ($env:USERPROFILE) {
            return $env:USERPROFILE
        }
        if ($env:HOME) {
            return $env:HOME
        }
        return [Environment]::GetFolderPath("UserProfile")
    }

    hidden [bool] IsPathInUserPath([string]$targetPath) {
        $userPath = Get-UserEnvironmentPath
        if (-not $userPath) { return $false }

        $normalizedTarget = $this.NormalizePathForComparison($targetPath)
        foreach ($item in @($userPath -split ";" | Where-Object { $_ })) {
            if ($this.NormalizePathForComparison($item) -eq $normalizedTarget) {
                return $true
            }
        }
        return $false
    }

    hidden [void] EnsureUserPathEntry([string]$targetPath, [string]$label) {
        if ($this.IsPathInUserPath($targetPath)) {
            $this.Log("$label は既に USER PATH に含まれています", "Gray")
        }
        else {
            $userPath = Get-UserEnvironmentPath
            $userItems = if ($userPath) { @($userPath -split ";" | Where-Object { $_ }) } else { @() }
            Set-UserEnvironmentPath -Path (($userItems + @($targetPath)) -join ";")
            $this.Log("USER PATH に $label を追加しました: $targetPath", "Green")
        }

        $normalizedTarget = $this.NormalizePathForComparison($targetPath)
        $processItems = if ($env:PATH) { @($env:PATH -split ";" | Where-Object { $_ }) } else { @() }
        foreach ($item in $processItems) {
            if ($this.NormalizePathForComparison($item) -eq $normalizedTarget) {
                return
            }
        }

        $env:PATH = if ($env:PATH) { "$env:PATH;$targetPath" } else { $targetPath }
    }

    hidden [string] NormalizePathForComparison([string]$path) {
        if (-not $path) { return "" }
        $trimChars = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        return $path.Trim('"').TrimEnd($trimChars).ToLowerInvariant()
    }
}
