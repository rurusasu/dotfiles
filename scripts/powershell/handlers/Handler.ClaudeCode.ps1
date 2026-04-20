<#
.SYNOPSIS
    Claude Code スタンドアロンインストールハンドラー（Windows）

.DESCRIPTION
    Claude Code を公式スタンドアロンインストーラーで ~/.local/bin にインストールする。
    pnpm 経由でのインストールは .ps1 shim が .exe より優先されてしまうため、
    直接バイナリをダウンロードする方式を採用。

.NOTES
    Order = 7 (Winget の後)
    Phase = 1 (ユーザースコープ)
#>

$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class ClaudeCodeHandler : SetupHandlerBase {
    ClaudeCodeHandler() {
        $this.Name = "ClaudeCode"
        $this.Description = "Claude Code スタンドアロンインストール"
        $this.Order = 7
        $this.RequiresAdmin = $false
        $this.Phase = 1
    }

    [bool] CanApply([SetupContext]$ctx) {
        $localBin = $this.GetLocalBinPath()
        $claudeExe = Join-Path $localBin "claude.exe"

        if (Test-PathExist -Path $claudeExe) {
            $this.Log("Claude Code は既にインストール済みです: $claudeExe", "Gray")
            return $false
        }

        return $true
    }

    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            $localBin = $this.GetLocalBinPath()

            if (-not (Test-Path -LiteralPath $localBin)) {
                New-Item -ItemType Directory -Path $localBin -Force | Out-Null
                $this.Log("ディレクトリを作成しました: $localBin", "Gray")
            }

            # 公式インストーラースクリプトをダウンロードして実行
            $this.Log("Claude Code をインストールしています...")
            $installerUrl = "https://cli.claude.ai/install.ps1"
            $installerScript = Invoke-RestMethodSafe -Uri $installerUrl
            $this.Log("インストーラースクリプトをダウンロードしました")

            # インストーラースクリプトを一時ファイルに保存して実行
            $tempScript = Join-Path ([System.IO.Path]::GetTempPath()) "claude-install.ps1"
            [System.IO.File]::WriteAllText($tempScript, $installerScript)

            try {
                $output = & $tempScript 2>&1
                $this.Log("インストーラー出力: $output", "Gray")
            }
            finally {
                if (Test-Path -LiteralPath $tempScript) {
                    Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
                }
            }

            # インストール結果を確認
            $claudeExe = Join-Path $localBin "claude.exe"
            if (Test-PathExist -Path $claudeExe) {
                $this.EnsureLocalBinInPath($localBin)
                $this.Log("Claude Code をインストールしました: $claudeExe", "Green")
                return $this.CreateSuccessResult("Claude Code をインストールしました")
            }

            return $this.CreateFailureResult("インストール後に claude.exe が見つかりません")
        }
        catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }

    hidden [string] GetLocalBinPath() {
        $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
        return Join-Path $homeDir ".local\bin"
    }

    hidden [void] EnsureLocalBinInPath([string]$localBin) {
        $userPath = Get-UserEnvironmentPath
        $pathItems = if ($userPath) { @($userPath -split ";" | Where-Object { $_ }) } else { @() }

        if ($pathItems -notcontains $localBin) {
            # .local/bin を先頭に追加して pnpm 等より優先させる
            $newPath = (@($localBin) + $pathItems) -join ";"
            Set-UserEnvironmentPath -Path $newPath
            $this.Log("~/.local/bin を USER PATH の先頭に追加しました", "Green")
        }
        else {
            $this.Log("~/.local/bin は既に PATH に含まれています", "Gray")
        }

        # 現プロセスの PATH にも追加
        $processItems = if ($env:PATH) { @($env:PATH -split ";" | Where-Object { $_ }) } else { @() }
        if ($processItems -notcontains $localBin) {
            $env:PATH = "$localBin;$env:PATH"
        }
    }
}
