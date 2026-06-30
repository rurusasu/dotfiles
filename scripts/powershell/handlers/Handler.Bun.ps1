<#
.SYNOPSIS
    Bun ポータブルパッケージ設定ハンドラー

.DESCRIPTION
    winget の Oven-sh.Bun パッケージは portable archive 形式で、
    実行ファイルが bun-windows-x64\bun.exe というサブディレクトリに配置される。
    実行ファイル名は bun.exe のままなので、shim は作らず実体ディレクトリを
    USER PATH に追加する。

.NOTES
    Order = 8 (Codex の後、Docker の前)
#>

$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class BunHandler : SetupHandlerBase {
    BunHandler() {
        $this.Name = "Bun"
        $this.Description = "Bun PATH 設定"
        $this.Order = 8
        $this.RequiresAdmin = $false
        $this.Phase = 1
    }

    [bool] CanApply([SetupContext]$ctx) {
        $bunExe = $this.GetBunExecutablePath()
        if (-not $bunExe) {
            $this.Log("Bun パッケージがインストールされていません", "Gray")
            return $false
        }

        $bunBinDir = Split-Path -Parent $bunExe
        $linkPath = Join-Path $this.GetLinksPath() "bun.exe"

        if ($this.IsPathInUserPath($bunBinDir) -and -not (Test-Path -LiteralPath $linkPath)) {
            $this.Log("Bun 実体 PATH は既に設定されています", "Gray")
            return $false
        }

        return $true
    }

    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            $bunExe = $this.GetBunExecutablePath()
            if (-not $bunExe) {
                return $this.CreateFailureResult("Bun 実行ファイルが見つかりません")
            }

            $this.RemoveLegacyShim((Join-Path $this.GetLinksPath() "bun.exe"))
            $this.EnsureUserPathEntry((Split-Path -Parent $bunExe), "Bun executable directory")

            return $this.CreateSuccessResult("Bun PATH を設定しました")
        }
        catch {
            return $this.CreateFailureResult("Bun 設定に失敗しました", $_.Exception)
        }
    }

    hidden [string] GetBunExecutablePath() {
        $packagesBase = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
        $bunPattern = "Oven-sh.Bun_*"

        $bunDir = Get-ChildItem -Path $packagesBase -Directory -Filter $bunPattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $bunDir) {
            return $null
        }

        $exePath = Join-Path $bunDir.FullName "bun-windows-x64\bun.exe"
        if (Test-Path $exePath) {
            return $exePath
        }

        return $null
    }

    hidden [string] GetLinksPath() {
        return Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"
    }

    hidden [void] RemoveLegacyShim([string]$linkPath) {
        if (Test-Path -LiteralPath $linkPath) {
            Remove-Item -LiteralPath $linkPath -Force
            $this.Log("旧 bun.exe shim を削除しました: $linkPath", "Green")
        }
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

        $processItems = if ($env:PATH) { @($env:PATH -split ";" | Where-Object { $_ }) } else { @() }
        foreach ($item in $processItems) {
            if ($this.NormalizePathForComparison($item) -eq $this.NormalizePathForComparison($targetPath)) {
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
