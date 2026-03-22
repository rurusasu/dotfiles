<#
.SYNOPSIS
    NixOS-WSL の nixos-rebuild switch を実行するハンドラー

.DESCRIPTION
    - NixOS ディストリビューションの存在確認
    - nixos-rebuild switch の実行
    - pnpm グローバルパッケージのインストール (nix/pnpm/packages.json)

.NOTES
    Order = 15 (Chezmoi の後、WslConfig の前)
#>

$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class NixRebuildHandler : SetupHandlerBase {
    NixRebuildHandler() {
        $this.Name = "NixRebuild"
        $this.Description = "nixos-rebuild switch の実行"
        $this.Order = 15
        $this.RequiresAdmin = $false
    }

    [bool] CanApply([SetupContext]$ctx) {
        if ($ctx.GetOption("SkipNixRebuild", $false)) {
            $this.Log("SkipNixRebuild が設定されているためスキップします")
            return $false
        }

        # NixOS ディストリビューションが存在するか確認
        $distros = Invoke-Wsl -Arguments @("-l", "-q")
        if ($LASTEXITCODE -ne 0) {
            $this.LogWarning("WSL が利用できません")
            return $false
        }

        $distroName = $ctx.DistroName
        $distroExists = $distros | Where-Object { $_.Trim("`0", " ", "`r", "`n") -ieq $distroName }
        if (-not $distroExists) {
            $this.Log("$distroName が見つからないためスキップします")
            return $false
        }

        return $true
    }

    hidden [void] InstallPreCommitHooks([string]$distroName) {
        try {
            $this.Log("pre-commit hooks をインストールしています...")

            # core.hooksPath が設定されていると pre-commit install が拒否するため解除
            Invoke-Wsl -Arguments @(
                "-d", $distroName, "-u", "nixos", "--",
                "bash", "-lc", "cd ~/.dotfiles && git config --unset-all core.hooksPath 2>/dev/null; true"
            )

            $output = Invoke-Wsl -Arguments @(
                "-d", $distroName, "-u", "nixos", "--",
                "bash", "-lc", "cd ~/.dotfiles && pre-commit install --install-hooks"
            )

            $output | ForEach-Object {
                if ($_ -notmatch '^\s*$') {
                    $this.Log("  $_", "Gray")
                }
            }

            if ($LASTEXITCODE -ne 0) {
                $this.LogWarning("pre-commit hooks のインストールが失敗しました (exit code: $LASTEXITCODE)")
            }
            else {
                $this.Log("pre-commit hooks のインストール完了", "Green")
            }
        }
        catch {
            $this.LogWarning("pre-commit hooks インストール中にエラーが発生しました: $_")
        }
    }

    hidden [void] EnsurePnpmAvailable([string]$distroName) {
        $pnpmCheck = Invoke-Wsl -Arguments @(
            "-d", $distroName, "-u", "nixos", "--",
            "bash", "-lc", "command -v pnpm"
        )
        if ($LASTEXITCODE -ne 0 -or -not $pnpmCheck) {
            $this.Log("pnpm が見つかりません。corepack で有効化します...")
            Invoke-Wsl -Arguments @(
                "-d", $distroName, "-u", "nixos", "--",
                "bash", "-lc", "corepack enable && corepack prepare pnpm@latest --activate"
            )
            if ($LASTEXITCODE -ne 0) {
                throw "corepack による pnpm の有効化に失敗しました (exit code: $LASTEXITCODE)"
            }
            $this.Log("pnpm を有効化しました", "Green")
        }
    }

    hidden [void] InstallPnpmGlobalPackages([string]$distroName, [string]$packagesJsonPath) {
        try {
            if (-not (Test-Path -LiteralPath $packagesJsonPath -PathType Leaf)) {
                $this.Log("pnpm パッケージ設定が見つかりません。スキップ: $packagesJsonPath", "Gray")
                return
            }

            $json = Get-Content -LiteralPath $packagesJsonPath -Raw | ConvertFrom-Json
            $packages = $json.globalPackages
            if (-not $packages -or $packages.Count -eq 0) {
                $this.Log("インストールする pnpm パッケージがありません", "Gray")
                return
            }

            # pnpm が利用可能か確認し、なければ corepack で有効化
            $this.EnsurePnpmAvailable($distroName)

            # インストール済みパッケージを取得してフィルタリング
            $installedOutput = Invoke-Wsl -Arguments @(
                "-d", $distroName, "-u", "nixos", "--",
                "bash", "-lc", "pnpm ls -g --depth=0 2>/dev/null"
            )
            $toInstall = @()
            $skipped = 0
            foreach ($pkg in $packages) {
                $pkgName = $pkg -replace '@[\d\.]+$', ''
                if ($installedOutput -and ($installedOutput | Where-Object { $_ -match [regex]::Escape($pkgName) })) {
                    $this.Log("スキップ (インストール済み): $pkgName", "Gray")
                    $skipped++
                } else {
                    $toInstall += $pkg
                }
            }

            if ($toInstall.Count -eq 0) {
                $this.Log("pnpm グローバルパッケージはすべてインストール済みです ($skipped 個スキップ)", "Gray")
                return
            }

            $pkgList = $toInstall -join " "
            $this.Log("pnpm グローバルパッケージをインストールしています: $pkgList")

            $pnpmOutput = Invoke-Wsl -Arguments @(
                "-d", $distroName, "-u", "nixos", "--",
                "bash", "-lc", "pnpm add -g $pkgList"
            )

            $pnpmOutput | ForEach-Object {
                if ($_ -notmatch '^\s*$') {
                    $this.Log("  $_", "Gray")
                }
            }

            if ($LASTEXITCODE -ne 0) {
                $this.LogWarning("pnpm グローバルパッケージのインストールが失敗しました (exit code: $LASTEXITCODE)")
            }
            else {
                $this.Log("pnpm グローバルパッケージのインストール完了 ($($toInstall.Count) 個インストール, $skipped 個スキップ)", "Green")
            }
        }
        catch {
            $this.LogWarning("pnpm パッケージインストール中にエラーが発生しました: $_")
        }
    }

    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            $distroName = $ctx.DistroName
            $this.Log("nixos-rebuild switch を実行しています...")

            # root で nixos-rebuild switch を実行（nixos ユーザーの dotfiles を使用）
            $output = Invoke-Wsl -Arguments @("-d", $distroName, "-u", "root", "--", "bash", "-lc", "cd /home/nixos/.dotfiles && nixos-rebuild switch --flake .#nixos")

            # 出力をログに表示
            $output | ForEach-Object {
                if ($_ -notmatch '^\s*$') {
                    $this.Log("  $_", "Gray")
                }
            }

            if ($LASTEXITCODE -ne 0) {
                throw "nixos-rebuild switch が失敗しました (exit code: $LASTEXITCODE)"
            }

            $this.Log("nixos-rebuild switch 完了", "Green")

            # pnpm グローバルパッケージをインストール
            $packagesJsonPath = Join-Path $ctx.DotfilesPath "nix\pnpm\packages.json"
            $this.InstallPnpmGlobalPackages($distroName, $packagesJsonPath)

            # pre-commit hooks をインストール
            $this.InstallPreCommitHooks($distroName)

            return $this.CreateSuccessResult("NixOS 設定を適用しました")
        }
        catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }
}
