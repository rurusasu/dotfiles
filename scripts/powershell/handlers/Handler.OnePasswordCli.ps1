<#
.SYNOPSIS
    1Password CLI の host-side PATH 設定ハンドラー

.DESCRIPTION
    VS Code Dev Containers の initializeCommand は Windows 側の cmd.exe から
    `op` を解決する。op.exe は winget パッケージ内の実体名とコマンド名が
    一致しているため、実体ディレクトリを USER PATH に追加する。
    既に起動している VS Code が古い PATH を保持している場合に備えて、
    既存 PATH 上の shim は現行 exe へのシンボリックリンクとして維持する。

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
        if (-not $this.IsPathFirstInUserPath($packageDir)) {
            return $true
        }

        $compatibilityShims = @(
            @{
                Directory = $this.GetWindowsAppsPath()
                LinkPath  = Join-Path $this.GetWindowsAppsPath() "op.exe"
            },
            @{
                Directory = $this.GetLinksPath()
                LinkPath  = Join-Path $this.GetLinksPath() "op.exe"
            }
        )

        foreach ($shim in $compatibilityShims) {
            if (
                $this.NeedsCompatibilityShim($shim.Directory, $shim.LinkPath) -and
                -not $this.IsPortableLinkCurrent($shim.LinkPath, $opExe)
            ) {
                return $true
            }
        }

        $this.Log("1Password CLI PATH と互換 shim は既に設定されています", "Gray")

        return $false
    }

    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            $opExe = $this.GetOnePasswordCliExecutablePath()
            if (-not $opExe) {
                return $this.CreateFailureResult("1Password CLI 実行ファイルが見つかりません")
            }

            $packageDir = Split-Path -Parent $opExe
            $this.EnsureUserPathEntry($packageDir, "1Password CLI package directory")
            $this.EnsureCompatibilityShim($this.GetWindowsAppsPath(), "op.exe", $opExe, "WindowsApps")
            $this.EnsureCompatibilityShim($this.GetLinksPath(), "op.exe", $opExe, "WinGet Links")

            return $this.CreateSuccessResult("1Password CLI PATH を設定しました")
        }
        catch {
            return $this.CreateFailureResult("1Password CLI PATH 設定に失敗しました", $_.Exception)
        }
    }

    hidden [void] EnsureCompatibilityShim([string]$directory, [string]$linkName, [string]$targetExe, [string]$label) {
        $linkPath = Join-Path $directory $linkName
        if (-not $this.NeedsCompatibilityShim($directory, $linkPath)) {
            $this.Log("$label は現在の PATH に無いため互換 shim を作成しません", "Gray")
            return
        }

        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }

        if ($this.IsPortableLinkCurrent($linkPath, $targetExe)) {
            $this.Log("$label の op.exe shim は最新です", "Gray")
            return
        }

        $this.CreatePortableLink($linkPath, $targetExe)
        $this.Log("$label の op.exe shim を現行 exe への symlink に更新しました", "Green")
    }

    hidden [bool] NeedsCompatibilityShim([string]$directory, [string]$linkPath) {
        return (
            $this.IsPathInUserPath($directory) -or
            $this.IsPathInProcessPath($directory) -or
            (Test-Path -LiteralPath $linkPath)
        )
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

    hidden [bool] IsPathFirstInUserPath([string]$targetPath) {
        $userPath = Get-UserEnvironmentPath
        $userItems = if ($userPath) { @($userPath -split ";" | Where-Object { $_ }) } else { @() }
        if ($userItems.Count -eq 0) { return $false }

        return $this.NormalizePathForComparison($userItems[0]) -eq $this.NormalizePathForComparison($targetPath)
    }

    hidden [bool] IsPathInUserPath([string]$targetPath) {
        return $this.IsPathInPathList((Get-UserEnvironmentPath), $targetPath)
    }

    hidden [bool] IsPathInProcessPath([string]$targetPath) {
        return $this.IsPathInPathList($env:PATH, $targetPath)
    }

    hidden [void] EnsureUserPathEntry([string]$targetPath, [string]$label) {
        $normalizedTarget = $this.NormalizePathForComparison($targetPath)
        $userPath = Get-UserEnvironmentPath
        $userItems = if ($userPath) { @($userPath -split ";" | Where-Object { $_ }) } else { @() }
        $filteredUserItems = @($userItems | Where-Object {
                $this.NormalizePathForComparison($_) -ne $normalizedTarget
            })

        if ($userItems.Count -gt 0 -and $this.NormalizePathForComparison($userItems[0]) -eq $normalizedTarget) {
            $this.Log("$label は既に USER PATH の先頭にあります", "Gray")
        }
        else {
            Set-UserEnvironmentPath -Path ((@($targetPath) + $filteredUserItems) -join ";")
            $this.Log("USER PATH の先頭に $label を設定しました: $targetPath", "Green")
        }

        $processItems = if ($env:PATH) { @($env:PATH -split ";" | Where-Object { $_ }) } else { @() }
        if ($processItems.Count -gt 0 -and $this.NormalizePathForComparison($processItems[0]) -eq $normalizedTarget) {
            return
        }

        $filteredProcessItems = @($processItems | Where-Object {
                $this.NormalizePathForComparison($_) -ne $normalizedTarget
            })
        $env:PATH = ((@($targetPath) + $filteredProcessItems) -join ";")
    }

    hidden [bool] IsPathInPathList([string]$pathList, [string]$targetPath) {
        if (-not $pathList) { return $false }

        $normalizedTarget = $this.NormalizePathForComparison($targetPath)
        foreach ($item in @($pathList -split ";" | Where-Object { $_ })) {
            if ($this.NormalizePathForComparison($item) -eq $normalizedTarget) {
                return $true
            }
        }
        return $false
    }

    hidden [string] NormalizePathForComparison([string]$path) {
        if (-not $path) { return "" }
        $trimChars = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        return $path.Trim('"').TrimEnd($trimChars).ToLowerInvariant()
    }
}
