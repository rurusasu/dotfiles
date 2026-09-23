<#
.SYNOPSIS
    Codex CLI ポータブルパッケージ設定ハンドラー

.DESCRIPTION
    winget の OpenAI.Codex パッケージは portable インストーラーで
    実行ファイル名が codex-x86_64-pc-windows-msvc.exe となっている。
    このハンドラーは WinGet\Links に codex.exe shim を作成する。
    また、Codex MCP から uv tool のエントリポイント（mempalace-mcp 等）を
    起動できるよう ~/.local/bin を USER PATH に追加する。

.NOTES
    Order = 6 (Winget の後、Bun の前)
#>

$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

function Resolve-CodexPackageExecutablePath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$LocalAppData = $env:LOCALAPPDATA
    )

    return [CodexHandler]::ResolveCodexPackageExecutablePath($LocalAppData)
}

class CodexHandler : SetupHandlerBase {
    CodexHandler() {
        $this.Name = "Codex"
        $this.Description = "Codex CLI shim と MCP PATH 設定"
        $this.Order = 6
        $this.RequiresAdmin = $false
        $this.Phase = 1
    }

    <#
    .SYNOPSIS
        実行可否を判定する
    .DESCRIPTION
        Codex パッケージがインストールされていて、Links\codex.exe が
        現行 exe を指していない（未作成 / winget upgrade 後の陳腐化）か、
        Links または ~/.local/bin が USER PATH に未登録の場合に適用する。
    #>
    [bool] CanApply([SetupContext]$ctx) {
        $codexExe = $this.GetCodexExecutablePath()
        if (-not $codexExe) {
            $this.Log("Codex パッケージがインストールされていません", "Gray")
            return $false
        }

        $linksPath = $this.GetLinksPath()
        $linkPath = Join-Path $linksPath "codex.exe"
        $shimHostPath = Join-Path $linksPath "codex-code-mode-host.exe"
        $localBin = $this.GetLocalBinPath()
        $codexHostPath = $this.GetCodexHostExecutablePath($codexExe)
        $codexHostAvailable = Test-Path -LiteralPath $codexHostPath -PathType Leaf
        $shimUsesCopy = $this.IsPortableCopyCurrent($linkPath, $codexExe)
        $adjacentShimHostAvailable = -not $shimUsesCopy -or
            (Test-Path -LiteralPath $shimHostPath -PathType Leaf)

        # リンクが最新でも PATH 設定が欠けていれば適用する。
        # WinGet upgrade 後の陳腐化、copy fallback、host欠落などの部分実行を想定。
        if (
            $this.IsPortableLinkCurrent($linkPath, $codexExe) -and
            $codexHostAvailable -and
            $adjacentShimHostAvailable -and
            $this.IsPathInUserPath($linksPath) -and
            $this.IsPathInUserPath($localBin)
        ) {
            $this.Log("codex.exe shim と PATH 設定は既に完了しています", "Gray")
            return $false
        }

        return $true
    }

    <#
    .SYNOPSIS
        codex.exe shim を作成する
    #>
    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            $codexExe = $this.GetCodexExecutablePath()
            if (-not $codexExe) {
                return $this.CreateFailureResult("Codex 実行ファイルが見つかりません")
            }

            $codexHostPath = $this.GetCodexHostExecutablePath($codexExe)
            if (-not (Test-Path -LiteralPath $codexHostPath -PathType Leaf)) {
                throw "Codex CLI package is missing its adjacent code-mode host executable: $codexHostPath"
            }

            $linksPath = $this.GetLinksPath()
            if (-not (Test-Path $linksPath)) {
                New-Item -ItemType Directory -Path $linksPath -Force | Out-Null
            }

            $linkPath = Join-Path $linksPath "codex.exe"

            # リンクが陳腐化している（旧バージョンを指すコピー等）場合のみ貼り直す。
            # 既存リンクは、現行 exe への symlink 作成に成功してから置き換える。
            $linkIsCurrent = $this.IsPortableLinkCurrent($linkPath, $codexExe)
            $copyIsCurrent = $this.IsPortableCopyCurrent($linkPath, $codexExe)
            $shimIsCopy = $copyIsCurrent
            if (-not $linkIsCurrent -and -not $copyIsCurrent) {
                try {
                    $this.CreatePortableLink($linkPath, $codexExe)
                }
                catch {
                    # Windows PowerShell without Developer Mode cannot create
                    # symlinks from a user phase. A content-checked copy keeps
                    # Codex usable without requiring elevation.
                    $this.LogWarning("シンボリックリンクを作成できないため codex.exe をコピーで作成します")
                    if (Test-Path -LiteralPath $linkPath) {
                        Remove-Item -LiteralPath $linkPath -Force -ErrorAction Stop
                    }
                    Copy-Item -LiteralPath $codexExe -Destination $linkPath -Force -ErrorAction Stop
                    $shimIsCopy = $true
                    $this.Log("codex.exe shim をコピーで作成しました", "Green")
                }
            }
            else {
                $shimType = if ($linkIsCurrent) { "シンボリックリンク" } else { "コピー" }
                $this.Log("codex.exe shim は最新です ($shimType)", "Gray")
            }

            # Codex canonicalizes symlink targets and resolves the helper from
            # the WinGet package root. A copied shim loses that relationship.
            if ($shimIsCopy) {
                $this.SyncCodexHostExecutable($linksPath, $codexExe)
            }

            # PATH は常に冪等チェック。リンクが既存でも PATH 未設定なら追加する。
            $this.EnsureUserPathEntry($linksPath, $false, "WinGet Links")

            # Codex MCP の stdio サーバーは Codex プロセスの PATH を継承する。
            # uv tool が作成する mempalace-mcp.exe 等を解決できるようにする。
            $this.EnsureUserPathEntry($this.GetLocalBinPath(), $true, "~/.local/bin")

            return $this.CreateSuccessResult("codex.exe shim と MCP PATH を設定しました")
        }
        catch {
            return $this.CreateFailureResult("Codex 設定に失敗しました", $_.Exception)
        }
    }

    <#
    .SYNOPSIS
        Codex パッケージの実行ファイルパスを取得する
    #>
    static [string] ResolveCodexPackageExecutablePath([string]$localAppData) {
        if ([string]::IsNullOrWhiteSpace($localAppData)) {
            $profilePath = if ($env:USERPROFILE) { $env:USERPROFILE } else { [Environment]::GetFolderPath("UserProfile") }
            $localAppData = Join-Path $profilePath "AppData\Local"
        }

        $packagesPath = Join-Path $localAppData "Microsoft\WinGet\Packages"
        $codexDirectories = @(
            Get-ChildItem -Path $packagesPath -Directory -Filter "OpenAI.Codex_*" -ErrorAction SilentlyContinue
        )
        $programsCodexPath = Join-Path $localAppData "Programs\Codex"
        if (Test-Path -LiteralPath $programsCodexPath -PathType Container) {
            $codexDirectories += [System.IO.DirectoryInfo]$programsCodexPath
        }

        $relativeExecutablePaths = @(
            "bin\codex.exe"
            "codex-x86_64-pc-windows-msvc.exe"
            "codex.exe"
        )
        $firstExecutablePath = $null
        foreach ($codexDirectory in $codexDirectories) {
            if (-not $codexDirectory) {
                continue
            }
            foreach ($relativePath in $relativeExecutablePaths) {
                $executablePath = Join-Path $codexDirectory.FullName $relativePath
                if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
                    continue
                }

                if (-not $firstExecutablePath) {
                    $firstExecutablePath = $executablePath
                }
                $hostPath = Join-Path (Split-Path -Parent $executablePath) "codex-code-mode-host.exe"
                if (Test-Path -LiteralPath $hostPath -PathType Leaf) {
                    return $executablePath
                }
            }
        }

        # Keep CLI-only candidates visible so Apply reports a missing adjacent host.
        return $firstExecutablePath
    }

    hidden [string] GetCodexExecutablePath() {
        return [CodexHandler]::ResolveCodexPackageExecutablePath($this.GetLocalAppDataPath())
    }

    hidden [string] GetCodexHostExecutablePath([string]$codexExe) {
        return Join-Path (Split-Path -Parent $codexExe) "codex-code-mode-host.exe"
    }

    hidden [void] SyncCodexHostExecutable([string]$linksPath, [string]$codexExe) {
        $sourcePath = $this.GetCodexHostExecutablePath($codexExe)
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Codex CLI package is missing its adjacent code-mode host executable: $sourcePath"
        }

        $shimPath = Join-Path $linksPath "codex-code-mode-host.exe"
        if (-not $this.IsPortableCopyCurrent($shimPath, $sourcePath)) {
            Copy-Item -LiteralPath $sourcePath -Destination $shimPath -Force -ErrorAction Stop
            $this.Log("codex-code-mode-host.exe を shim の隣に同期しました", "Green")
        }
    }

    <#
    .SYNOPSIS
        WinGet Links フォルダパスを取得する
    #>
    hidden [string] GetLinksPath() {
        return Join-Path $this.GetLocalAppDataPath() "Microsoft\WinGet\Links"
    }

    <#
    .SYNOPSIS
        LOCALAPPDATA パスを取得する
    #>
    hidden [string] GetLocalAppDataPath() {
        if ($env:LOCALAPPDATA) {
            return $env:LOCALAPPDATA
        }

        $homeDir = $this.GetHomeDir()
        return Join-Path $homeDir "AppData\Local"
    }

    <#
    .SYNOPSIS
        ~/.local/bin パスを取得する
    #>
    hidden [string] GetLocalBinPath() {
        return Join-Path $this.GetHomeDir() ".local\bin"
    }

    <#
    .SYNOPSIS
        ユーザーホームパスを取得する
    #>
    hidden [string] GetHomeDir() {
        $homeDir = if ($env:USERPROFILE) {
            $env:USERPROFILE
        }
        elseif ($env:HOME) {
            $env:HOME
        }
        else {
            [Environment]::GetFolderPath("UserProfile")
        }
        return $homeDir
    }

    <#
    .SYNOPSIS
        指定パスが USER PATH に登録済みか判定する
    #>
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

    <#
    .SYNOPSIS
        USER PATH と現在のプロセス PATH に指定パスを追加する
    #>
    hidden [void] EnsureUserPathEntry([string]$targetPath, [bool]$prepend, [string]$label) {
        $normalizedTarget = $this.NormalizePathForComparison($targetPath)
        $userPath = Get-UserEnvironmentPath
        $userItems = if ($userPath) { @($userPath -split ";" | Where-Object { $_ }) } else { @() }

        $hasUserEntry = $false
        foreach ($item in $userItems) {
            if ($this.NormalizePathForComparison($item) -eq $normalizedTarget) {
                $hasUserEntry = $true
                break
            }
        }

        if (-not $hasUserEntry) {
            $newItems = if ($prepend) { @($targetPath) + $userItems } else { $userItems + @($targetPath) }
            Set-UserEnvironmentPath -Path ($newItems -join ";")
            $this.Log("USER PATH に $label を追加しました: $targetPath", "Green")
        }
        else {
            $this.Log("$label は既に USER PATH に含まれています", "Gray")
        }

        $processItems = if ($env:PATH) { @($env:PATH -split ";" | Where-Object { $_ }) } else { @() }
        $hasProcessEntry = $false
        foreach ($item in $processItems) {
            if ($this.NormalizePathForComparison($item) -eq $normalizedTarget) {
                $hasProcessEntry = $true
                break
            }
        }

        if (-not $hasProcessEntry) {
            $env:PATH = if ($prepend) { "$targetPath;$env:PATH" } else { "$env:PATH;$targetPath" }
        }
    }

    <#
    .SYNOPSIS
        PATH 比較用に大小文字と末尾区切り文字を正規化する
    #>
    hidden [string] NormalizePathForComparison([string]$path) {
        if (-not $path) { return "" }
        $trimChars = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        return $path.Trim('"').TrimEnd($trimChars).ToLowerInvariant()
    }
}
