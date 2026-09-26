<#
.SYNOPSIS
    1Password CLI の host-side PATH 設定ハンドラー

.DESCRIPTION
    VS Code Dev Containers の initializeCommand は Windows 側の cmd.exe から
    `op` を解決する。op.exe は winget パッケージ内の実体名とコマンド名が
    一致しているため、実体ディレクトリを USER PATH に追加する。
    既に起動している VS Code が古い PATH を保持している場合に備えて、
    USER PATH またはプロセス PATH ですでに使われている WinGet Links shim のみ維持する。
    WindowsApps は OS 管理領域のため変更しない。

.NOTES
    Order = 9 (Winget/Bun の後、Chezmoi の前)
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
        $needsPathUpdate = -not $this.IsPathFirstInUserPath($packageDir)

        $compatibilityShims = @(
            @{
                Directory = $this.GetLinksPath()
                LinkPath  = Join-Path $this.GetLinksPath() "op.exe"
            }
        )

        $needsShimUpdate = $false
        foreach ($shim in $compatibilityShims) {
            if (
                $this.NeedsCompatibilityShim($shim.Directory, $shim.LinkPath) -and
                $this.IsManagedCompatibilityShim($shim.LinkPath, $opExe) -and
                -not $this.IsCompatibilityShimCurrent($shim.LinkPath, $opExe)
            ) {
                $needsShimUpdate = $true
                break
            }
        }

        if ($needsPathUpdate -or $needsShimUpdate) {
            return $true
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
            $this.EnsureCompatibilityShim($this.GetLinksPath(), "op.exe", $opExe, "WinGet Links")
            $this.EnsureUserPathEntry($packageDir, "1Password CLI package directory")

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

        if ($this.IsCompatibilityShimCurrent($linkPath, $targetExe)) {
            if (-not $this.IsPortableLinkCurrent($linkPath, $targetExe)) {
                $this.WriteCompatibilityCopyMarker($linkPath)
            }
            $this.Log("$label の op.exe shim は最新です", "Gray")
            return
        }

        if (Test-Path -LiteralPath $linkPath) {
            if (-not $this.IsManagedCompatibilityShim($linkPath, $targetExe)) {
                $this.LogWarning("既存の $label op.exe は所有元を確認できないため変更しません: $linkPath")
                return
            }
        }

        $hadManagedCopyMarker = $this.IsManagedCompatibilityCopy($linkPath)
        try {
            $this.CreatePortableLink($linkPath, $targetExe)
            $markerPath = $this.GetCompatibilityCopyMarkerPath($linkPath)
            if ($hadManagedCopyMarker) {
                Remove-Item -LiteralPath $markerPath -Force -ErrorAction SilentlyContinue
            }
            $this.Log("$label の op.exe shim を現行 exe への symlink に更新しました", "Green")
        }
        catch {
            $this.LogWarning("symlink を作成できないため $label の op.exe shim をコピーで更新します")
            $this.CreateCompatibilityCopy($linkPath, $targetExe)
            $this.Log("$label の op.exe shim を現行 exe のコピーに更新しました", "Green")
        }
    }

    hidden [bool] IsCompatibilityShimCurrent([string]$linkPath, [string]$targetExe) {
        return (
            $this.IsPortableLinkCurrent($linkPath, $targetExe) -or
            $this.IsPortableCopyCurrent($linkPath, $targetExe)
        )
    }

    hidden [bool] IsManagedCompatibilityShim([string]$linkPath, [string]$currentExe) {
        if (-not (Test-Path -LiteralPath $linkPath)) {
            return $false
        }

        try {
            $link = Get-Item -LiteralPath $linkPath -Force -ErrorAction Stop
            if ($link.LinkType -ne "SymbolicLink") {
                return (
                    $this.IsManagedCompatibilityCopy($linkPath) -or
                    $this.IsPortableCopyCurrent($linkPath, $currentExe)
                )
            }

            $target = [string]@($link.Target)[0]
            return $target -match '(?i)\\Microsoft\\WinGet\\Packages\\AgileBits\.1Password\.CLI_[^\\]+\\op\.exe$'
        }
        catch {
            return $false
        }
    }

    hidden [string] GetCompatibilityCopyMarkerPath([string]$linkPath) {
        return "$linkPath.dotfiles-managed"
    }

    hidden [bool] IsManagedCompatibilityCopy([string]$linkPath) {
        $markerPath = $this.GetCompatibilityCopyMarkerPath($linkPath)
        if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
            return $false
        }

        try {
            $link = Get-Item -LiteralPath $linkPath -Force -ErrorAction Stop
            if ($link.LinkType -eq "SymbolicLink") {
                return $false
            }

            $marker = [System.IO.File]::ReadAllText($markerPath) | ConvertFrom-Json -ErrorAction Stop
            if ($marker.owner -ne "dotfiles.OnePasswordCli" -or $marker.sha256 -notmatch '^[A-Fa-f0-9]{64}$') {
                return $false
            }

            $linkHash = (Get-FileHash -LiteralPath $linkPath -Algorithm SHA256 -ErrorAction Stop).Hash
            return $linkHash -eq $marker.sha256
        }
        catch {
            return $false
        }
    }

    hidden [void] WriteCompatibilityCopyMarker([string]$linkPath) {
        $markerPath = $this.GetCompatibilityCopyMarkerPath($linkPath)
        $parentDir = Split-Path -Parent $linkPath
        $suffix = [System.Guid]::NewGuid().ToString("N")
        $markerName = Split-Path -Leaf $markerPath
        $tempMarkerPath = Join-Path $parentDir ".$markerName.$suffix.tmp"
        $backupMarkerPath = Join-Path $parentDir ".$markerName.$suffix.backup"
        $oldMarkerMoved = $false

        try {
            $linkHash = (Get-FileHash -LiteralPath $linkPath -Algorithm SHA256 -ErrorAction Stop).Hash
            $markerJson = @{ owner = "dotfiles.OnePasswordCli"; sha256 = $linkHash } | ConvertTo-Json -Compress
            [System.IO.File]::WriteAllText($tempMarkerPath, $markerJson, [System.Text.Encoding]::ASCII)

            if (Test-Path -LiteralPath $markerPath) {
                Move-Item -LiteralPath $markerPath -Destination $backupMarkerPath -Force -ErrorAction Stop
                $oldMarkerMoved = $true
            }

            Move-Item -LiteralPath $tempMarkerPath -Destination $markerPath -Force -ErrorAction Stop
            if ($oldMarkerMoved) {
                Remove-Item -LiteralPath $backupMarkerPath -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            $markerError = $_.Exception
            if ($oldMarkerMoved -and (Test-Path -LiteralPath $backupMarkerPath)) {
                try {
                    if (Test-Path -LiteralPath $markerPath) {
                        Remove-Item -LiteralPath $markerPath -Force -ErrorAction Stop
                    }
                    Move-Item -LiteralPath $backupMarkerPath -Destination $markerPath -Force -ErrorAction Stop
                }
                catch {
                    throw "shim copy ownership marker failed and the previous marker could not be restored. Backup: $backupMarkerPath. Marker error: $($markerError.Message). Restore error: $($_.Exception.Message)"
                }
            }
            if (Test-Path -LiteralPath $tempMarkerPath) {
                Remove-Item -LiteralPath $tempMarkerPath -Force -ErrorAction SilentlyContinue
            }
            throw $markerError
        }
    }

    hidden [void] CreateCompatibilityCopy([string]$linkPath, [string]$targetExe) {
        $parentDir = Split-Path -Parent $linkPath
        $linkName = Split-Path -Leaf $linkPath
        $suffix = [System.Guid]::NewGuid().ToString("N")
        $tempCopyPath = Join-Path $parentDir ".$linkName.$suffix.tmp"
        $backupPath = Join-Path $parentDir ".$linkName.$suffix.backup"
        $oldMoved = $false

        try {
            Copy-Item -LiteralPath $targetExe -Destination $tempCopyPath -Force -ErrorAction Stop
            if (-not $this.IsPortableCopyCurrent($tempCopyPath, $targetExe)) {
                throw "一時コピーの SHA-256 検証に失敗しました: $tempCopyPath"
            }

            if (Test-Path -LiteralPath $linkPath) {
                Move-Item -LiteralPath $linkPath -Destination $backupPath -Force -ErrorAction Stop
                $oldMoved = $true
            }

            Move-Item -LiteralPath $tempCopyPath -Destination $linkPath -Force -ErrorAction Stop
            $this.WriteCompatibilityCopyMarker($linkPath)
            if ($oldMoved) {
                Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            $copyError = $_.Exception
            if ($oldMoved -and (Test-Path -LiteralPath $backupPath)) {
                try {
                    if (Test-Path -LiteralPath $linkPath) {
                        Remove-Item -LiteralPath $linkPath -Force -ErrorAction Stop
                    }
                    Move-Item -LiteralPath $backupPath -Destination $linkPath -Force -ErrorAction Stop
                }
                catch {
                    throw "shim コピーに失敗し、以前の shim を復元できませんでした。退避先: $backupPath. Copy error: $($copyError.Message). Restore error: $($_.Exception.Message)"
                }
            }
            elseif (-not $oldMoved -and (Test-Path -LiteralPath $linkPath)) {
                Remove-Item -LiteralPath $linkPath -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path -LiteralPath $tempCopyPath) {
                Remove-Item -LiteralPath $tempCopyPath -Force -ErrorAction SilentlyContinue
            }
            throw $copyError
        }
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
