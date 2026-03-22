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
        Codex パッケージがインストールされていて、Links に codex.exe がない場合に適用
    #>
    [bool] CanApply([SetupContext]$ctx) {
        $codexExe = $this.GetCodexExecutablePath()
        if (-not $codexExe) {
            $this.Log("Codex パッケージがインストールされていません", "Gray")
            return $false
        }

        $linksPath = $this.GetLinksPath()
        $linkPath = Join-Path $linksPath "codex.exe"

        if (Test-Path $linkPath) {
            $this.Log("codex.exe リンクは既に存在します", "Gray")
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
            $this.Log("シンボリックリンクを作成しています: $linkPath -> $codexExe")

            # Windows ではシンボリックリンク作成に管理者権限または開発者モードが必要
            # 失敗した場合はハードリンクまたはコピーにフォールバック
            $linkCreated = $false

            # まずシンボリックリンクを試す
            try {
                New-Item -ItemType SymbolicLink -Path $linkPath -Target $codexExe -Force -ErrorAction Stop | Out-Null
                $this.Log("シンボリックリンクを作成しました", "Green")
                $linkCreated = $true
            }
            catch {
                $this.LogWarning("シンボリックリンク作成失敗: $($_.Exception.Message)")
            }

            # シンボリックリンクが失敗した場合、ハードリンクを試す
            if (-not $linkCreated) {
                try {
                    New-Item -ItemType HardLink -Path $linkPath -Target $codexExe -Force -ErrorAction Stop | Out-Null
                    $this.Log("ハードリンクを作成しました", "Green")
                    $linkCreated = $true
                }
                catch {
                    $this.LogWarning("ハードリンク作成失敗: $($_.Exception.Message)")
                }
            }

            # すべて失敗した場合はファイルをコピー
            if (-not $linkCreated) {
                Copy-Item -Path $codexExe -Destination $linkPath -Force
                $this.Log("ファイルをコピーしました", "Green")
            }

            # Links パスが PATH に登録されているか確認
            $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
            if ($userPath -notlike "*$linksPath*") {
                $this.Log("PATH に Links フォルダを追加しています...")
                $newPath = "$userPath;$linksPath"
                [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
                $env:Path = "$env:Path;$linksPath"
                $this.Log("PATH を更新しました", "Green")
            }

            return $this.CreateSuccessResult("codex.exe リンクを作成しました")
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
}
