<#
.SYNOPSIS
    NixOS-WSL の nixos-rebuild switch を実行するハンドラー

.DESCRIPTION
    - NixOS ディストリビューションの存在確認
    - nixos-rebuild switch の実行
    - pnpm グローバルパッケージのインストール (nix/pnpm/packages.json)

.NOTES
    Order = 55 (NixOSWSL=50 の後に実行)
#>

$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class NixRebuildHandler : SetupHandlerBase {
    hidden [string] $PnpmHomePath = '$HOME/.local/share/pnpm'

    NixRebuildHandler() {
        $this.Name = "NixRebuild"
        $this.Description = "nixos-rebuild switch の実行"
        $this.Order = 55
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
        # wsl -l -q は UTF-16LE で出力するため、文字間にヌルバイトが挿入される
        # Trim では中間のヌルバイトを除去できないため、Replace で全て除去してから比較
        $distroExists = $distros | Where-Object {
            ($_ -replace "`0", '' -replace [char]0xFEFF, '').Trim() -match "^\s*$([regex]::Escape($distroName))\s*$"
        }
        if (-not $distroExists) {
            $this.Log("$distroName が見つからないためスキップします")
            return $false
        }

        return $true
    }

    hidden [void] InstallPreCommitHooks([string]$distroName) {
        try {
            $this.Log("pre-commit hooks をインストールしています...")

            # core.hooksPath が設定されていると pre-commit install が拒否するため
            # local/global/system すべてのレベルで解除する
            Invoke-Wsl -Arguments @(
                "-d", $distroName, "-u", "nixos", "--",
                "bash", "-lc", "cd ~/.dotfiles && git config --unset-all core.hooksPath 2>/dev/null; git config --global --unset-all core.hooksPath 2>/dev/null; true"
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
            "bash", "-lc", "export PATH=`"`$HOME/.npm-global/bin:`$PATH`"; command -v pnpm"
        )
        if ($LASTEXITCODE -ne 0 -or -not $pnpmCheck) {
            $this.Log("pnpm が見つかりません。npm 経由でインストールします...")
            # NixOS では npm のグローバルプレフィックスが read-only nix store を指すため
            # ~/.npm-global に変更してからインストールする
            Invoke-Wsl -Arguments @(
                "-d", $distroName, "-u", "nixos", "--",
                "bash", "-lc", "mkdir -p ~/.npm-global && npm config set prefix ~/.npm-global && npm install -g pnpm && grep -q npm-global ~/.bashrc || echo 'export PATH=~/.npm-global/bin:`$PATH' >> ~/.bashrc"
            )
            if ($LASTEXITCODE -ne 0) {
                throw "pnpm のインストールに失敗しました (exit code: $LASTEXITCODE)"
            }
            $this.Log("pnpm をインストールしました", "Green")
        }

        # PNPM_HOME が未設定なら pnpm setup を実行してグローバル bin ディレクトリを作成
        $pnpmHomeCheck = Invoke-Wsl -Arguments @(
            "-d", $distroName, "-u", "nixos", "--",
            "bash", "-lc", "export PATH=`"`$HOME/.npm-global/bin:`$PATH`"; export PNPM_HOME=$($this.PnpmHomePath); [ -d `"`$PNPM_HOME`" ] && echo exists"
        )
        if (-not $pnpmHomeCheck -or $pnpmHomeCheck -notmatch 'exists') {
            $this.Log("PNPM_HOME を設定しています...")
            Invoke-Wsl -Arguments @(
                "-d", $distroName, "-u", "nixos", "--",
                "bash", "-lc", "export PATH=`"`$HOME/.npm-global/bin:`$PATH`"; export PNPM_HOME=$($this.PnpmHomePath); mkdir -p `"`$PNPM_HOME`"; pnpm setup 2>/dev/null || true"
            )
            # .bashrc に PNPM_HOME が無ければ追加
            Invoke-Wsl -Arguments @(
                "-d", $distroName, "-u", "nixos", "--",
                "bash", "-lc", "grep -q PNPM_HOME ~/.bashrc || echo 'export PNPM_HOME=$($this.PnpmHomePath); export PATH=`$PNPM_HOME:`$PATH' >> ~/.bashrc"
            )
        }
    }

    hidden [void] InstallPnpmGlobalPackages([string]$distroName, [string]$packagesJsonPath) {
        try {
            if (-not (Test-Path -LiteralPath $packagesJsonPath -PathType Leaf)) {
                $this.Log("pnpm パッケージ設定が見つかりません。スキップ: $packagesJsonPath", "Gray")
                return
            }

            $json = Get-JsonContent -Path $packagesJsonPath
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
                "bash", "-lc", "export PNPM_HOME=$($this.PnpmHomePath); export PATH=`"`$PNPM_HOME:`$HOME/.npm-global/bin:`$PATH`"; pnpm ls -g --depth=0 2>/dev/null"
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

            # シェルメタ文字を含むパッケージ名（@scope/pkg 等）を安全に渡すためクォート
            $quotedPkgs = ($toInstall | ForEach-Object { "'$($_ -replace "'", "'\\''")'" }) -join " "
            $this.Log("pnpm グローバルパッケージをインストールしています: $($toInstall -join ', ')")

            # PNPM_HOME と ~/.npm-global/bin を PATH に追加
            $pnpmOutput = Invoke-Wsl -Arguments @(
                "-d", $distroName, "-u", "nixos", "--",
                "bash", "-lc", "export PNPM_HOME=$($this.PnpmHomePath); export PATH=`"`$PNPM_HOME:`$HOME/.npm-global/bin:`$PATH`"; pnpm add -g $quotedPkgs"
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

    hidden [void] EnsureDotfilesAvailable([string]$distroName, [string]$dotfilesPath) {
        # Windows パス (D:\ruru\dotfiles) を WSL マウントパス (/mnt/d/ruru/dotfiles) に変換
        $driveLetter = $dotfilesPath.Substring(0, 1).ToLower()
        $wslMountPath = '/mnt/' + $driveLetter + ($dotfilesPath.Substring(2) -replace '\\', '/')

        # /home/nixos/.dotfiles が存在するか確認
        Invoke-Wsl -Arguments @("-d", $distroName, "-u", "nixos", "--", "bash", "-lc", "test -e /home/nixos/.dotfiles") | Out-Null
        if ($LASTEXITCODE -eq 0) {
            return
        }

        # Windows dotfiles が WSL からアクセスできるか確認
        Invoke-Wsl -Arguments @("-d", $distroName, "-u", "nixos", "--", "bash", "-lc", "test -d `"$wslMountPath`"") | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $this.Log("dotfiles を WSL マウント経由でリンクします: $wslMountPath")
            Invoke-Wsl -Arguments @("-d", $distroName, "-u", "nixos", "--", "bash", "-lc", "ln -sf `"$wslMountPath`" /home/nixos/.dotfiles")
            if ($LASTEXITCODE -ne 0) {
                throw "dotfiles のシンボリックリンク作成に失敗しました"
            }
            $this.Log("dotfiles リンク完了: /home/nixos/.dotfiles -> $wslMountPath", "Green")
        } else {
            throw "dotfiles が見つかりません。Windows パス '$dotfilesPath' が WSL から '$wslMountPath' としてアクセスできません"
        }
    }

    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            $distroName = $ctx.DistroName

            # dotfiles が NixOS 内に存在しなければ Windows マウント経由でリンク
            $this.EnsureDotfilesAvailable($distroName, $ctx.DotfilesPath)

            $this.Log("nixos-rebuild switch を実行しています...")

            # /mnt/ 配下の dotfiles は Windows 側オーナーのため CVE-2022-24765 の ownership チェックで
            # nix (libgit2) がフレークの読み込みを拒否する。root の gitconfig で回避する。
            Invoke-Wsl -Arguments @(
                "-d", $distroName, "-u", "root", "--",
                "bash", "-lc", "git config --global safe.directory '*' 2>/dev/null || printf '[safe]\n\tdirectory = *\n' > /root/.gitconfig"
            ) | Out-Null

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
