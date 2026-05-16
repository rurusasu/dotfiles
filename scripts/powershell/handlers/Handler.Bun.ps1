<#
.SYNOPSIS
    Bun ポータブルパッケージ設定ハンドラー

.DESCRIPTION
    winget の Oven-sh.Bun パッケージは portable archive 形式で、
    実行ファイルが bun-windows-x64\bun.exe というサブディレクトリに配置される。
    winget は自動で PATH も Links shim も作らないため、このハンドラーで
    WinGet\Links に bun.exe シンボリックリンクを作成し、Links を USER PATH に追加する。

.NOTES
    Order = 8 (Codex の後、Docker の前)
#>

$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class BunHandler : SetupHandlerBase {
    BunHandler() {
        $this.Name = "Bun"
        $this.Description = "Bun シンボリックリンク作成"
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

        $linksPath = $this.GetLinksPath()
        $linkPath = Join-Path $linksPath "bun.exe"

        if (Test-Path $linkPath) {
            $this.Log("bun.exe リンクは既に存在します", "Gray")
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

            $linksPath = $this.GetLinksPath()
            if (-not (Test-Path $linksPath)) {
                New-Item -ItemType Directory -Path $linksPath -Force | Out-Null
            }

            $linkPath = Join-Path $linksPath "bun.exe"
            $this.Log("シンボリックリンクを作成しています: $linkPath -> $bunExe")

            # Windows ではシンボリックリンク作成に管理者権限または開発者モードが必要
            # 失敗した場合はハードリンクまたはコピーにフォールバック
            $linkCreated = $false

            try {
                New-Item -ItemType SymbolicLink -Path $linkPath -Target $bunExe -Force -ErrorAction Stop | Out-Null
                $this.Log("シンボリックリンクを作成しました", "Green")
                $linkCreated = $true
            }
            catch {
                $this.LogWarning("シンボリックリンク作成失敗: $($_.Exception.Message)")
            }

            if (-not $linkCreated) {
                try {
                    New-Item -ItemType HardLink -Path $linkPath -Target $bunExe -Force -ErrorAction Stop | Out-Null
                    $this.Log("ハードリンクを作成しました", "Green")
                    $linkCreated = $true
                }
                catch {
                    $this.LogWarning("ハードリンク作成失敗: $($_.Exception.Message)")
                }
            }

            if (-not $linkCreated) {
                Copy-Item -Path $bunExe -Destination $linkPath -Force
                $this.Log("ファイルをコピーしました", "Green")
            }

            $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
            if ($userPath -notlike "*$linksPath*") {
                $this.Log("PATH に Links フォルダを追加しています...")
                $newPath = "$userPath;$linksPath"
                [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
                $env:Path = "$env:Path;$linksPath"
                $this.Log("PATH を更新しました", "Green")
            }

            return $this.CreateSuccessResult("bun.exe リンクを作成しました")
        }
        catch {
            return $this.CreateFailureResult("Bun 設定に失敗しました", $_)
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
}
