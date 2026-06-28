<#
.SYNOPSIS
    1Password CLI の host-side shim 設定ハンドラー

.DESCRIPTION
    VS Code Dev Containers の initializeCommand は Windows 側の cmd.exe から
    `op` を解決する。起動済み Code.exe は PATH 更新を拾わないため、既定で
    PATH に入りやすい WindowsApps と WinGet Links に op.exe shim を作成する。

.NOTES
    Order = 9 (Winget/Codex/Bun の後、Chezmoi の前)
#>

$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class OnePasswordCliHandler : SetupHandlerBase {
    OnePasswordCliHandler() {
        $this.Name = "OnePasswordCli"
        $this.Description = "1Password CLI op.exe shim 作成"
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

        $windowsApps = $this.GetWindowsAppsPath()
        $linksPath = $this.GetLinksPath()
        $windowsAppsShim = Join-Path $windowsApps "op.exe"
        $linksShim = Join-Path $linksPath "op.exe"

        if (
            $this.IsPortableLinkCurrent($windowsAppsShim, $opExe) -and
            $this.IsPortableLinkCurrent($linksShim, $opExe) -and
            $this.IsPathInUserPath($windowsApps) -and
            $this.IsPathInUserPath($linksPath)
        ) {
            $this.Log("op.exe shim と PATH 設定は既に完了しています", "Gray")
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

            $windowsApps = $this.GetWindowsAppsPath()
            $linksPath = $this.GetLinksPath()
            $this.EnsureDirectory($windowsApps)
            $this.EnsureDirectory($linksPath)

            $this.EnsureShimCurrent((Join-Path $windowsApps "op.exe"), $opExe)
            $this.EnsureShimCurrent((Join-Path $linksPath "op.exe"), $opExe)

            $this.EnsureUserPathEntry($windowsApps, "WindowsApps")
            $this.EnsureUserPathEntry($linksPath, "WinGet Links")

            return $this.CreateSuccessResult("op.exe shim と PATH を設定しました")
        }
        catch {
            return $this.CreateFailureResult("1Password CLI shim 設定に失敗しました", $_)
        }
    }

    hidden [void] EnsureShimCurrent([string]$linkPath, [string]$targetExe) {
        if (-not $this.IsPortableLinkCurrent($linkPath, $targetExe)) {
            $this.CreatePortableLink($linkPath, $targetExe)
        }
        else {
            $this.Log("op.exe shim は最新です: $linkPath", "Gray")
        }
    }

    hidden [void] EnsureDirectory([string]$path) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
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
