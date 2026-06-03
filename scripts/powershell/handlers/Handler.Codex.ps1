<#
.SYNOPSIS
    Codex CLI ポータブルパッケージ設定ハンドラー

.DESCRIPTION
    winget の OpenAI.Codex パッケージは portable インストーラーで
    実行ファイル名が codex-x86_64-pc-windows-msvc.exe となっている。
    このハンドラーは WinGet\Links に codex.exe シンボリックリンクを作成する。

.NOTES
    Order = 6 (Winget の後、Bun の前)
#>

$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class CodexHandler : SetupHandlerBase {
    CodexHandler() {
        $this.Name = "Codex"
        $this.Description = "Codex CLI シンボリックリンク作成"
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
        Links が USER PATH に未登録の場合に適用する。
    #>
    [bool] CanApply([SetupContext]$ctx) {
        $codexExe = $this.GetCodexExecutablePath()
        if (-not $codexExe) {
            $this.Log("Codex パッケージがインストールされていません", "Gray")
            return $false
        }

        $linksPath = $this.GetLinksPath()
        $linkPath = Join-Path $linksPath "codex.exe"

        # リンクが最新でも Links が PATH に無ければ適用する。
        # (winget upgrade 後の陳腐化, copy フォールバック後, 過去の部分実行を想定。)
        if ($this.IsPortableLinkCurrent($linkPath, $codexExe) -and $this.IsLinksInUserPath($linksPath)) {
            $this.Log("codex.exe リンクと PATH 設定は既に完了しています", "Gray")
            return $false
        }

        return $true
    }

    <#
    .SYNOPSIS
        codex.exe シンボリックリンクを作成する
    #>
    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            $codexExe = $this.GetCodexExecutablePath()
            if (-not $codexExe) {
                return $this.CreateFailureResult("Codex 実行ファイルが見つかりません")
            }

            $linksPath = $this.GetLinksPath()
            if (-not (Test-Path $linksPath)) {
                New-Item -ItemType Directory -Path $linksPath -Force | Out-Null
            }

            $linkPath = Join-Path $linksPath "codex.exe"

            # リンクが陳腐化している（旧バージョンを指すコピー等）場合のみ貼り直す。
            # winget upgrade 後に Links\codex.exe が旧バージョンを指す問題への対処。
            if (-not $this.IsPortableLinkCurrent($linkPath, $codexExe)) {
                $this.CreatePortableLink($linkPath, $codexExe)
            }
            else {
                $this.Log("codex.exe リンクは最新です", "Gray")
            }

            # PATH は常に冪等チェック。リンクが既存でも PATH 未設定なら追加する。
            if (-not $this.IsLinksInUserPath($linksPath)) {
                $this.Log("PATH に Links フォルダを追加しています...")
                $userPath = Get-UserEnvironmentPath
                $newPath = if ($userPath) { "$userPath;$linksPath" } else { $linksPath }
                Set-UserEnvironmentPath -Path $newPath
                $env:Path = "$env:Path;$linksPath"
                $this.Log("PATH を更新しました", "Green")
            }

            return $this.CreateSuccessResult("codex.exe リンクと PATH を設定しました")
        }
        catch {
            return $this.CreateFailureResult("Codex 設定に失敗しました", $_)
        }
    }

    <#
    .SYNOPSIS
        Codex パッケージの実行ファイルパスを取得する
    #>
    hidden [string] GetCodexExecutablePath() {
        $packagesBase = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
        $codexPattern = "OpenAI.Codex_*"

        $codexDir = Get-ChildItem -Path $packagesBase -Directory -Filter $codexPattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $codexDir) {
            return $null
        }

        # codex-x86_64-pc-windows-msvc.exe または codex.exe を探す
        $exePatterns = @("codex-x86_64-pc-windows-msvc.exe", "codex.exe")
        foreach ($pattern in $exePatterns) {
            $exePath = Join-Path $codexDir.FullName $pattern
            if (Test-Path $exePath) {
                return $exePath
            }
        }

        return $null
    }

    <#
    .SYNOPSIS
        WinGet Links フォルダパスを取得する
    #>
    hidden [string] GetLinksPath() {
        return Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"
    }

    <#
    .SYNOPSIS
        Links フォルダが USER PATH に登録済みか判定する
    #>
    hidden [bool] IsLinksInUserPath([string]$linksPath) {
        $userPath = Get-UserEnvironmentPath
        if (-not $userPath) { return $false }
        return $userPath -like "*$linksPath*"
    }
}
