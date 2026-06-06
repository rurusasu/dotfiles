<#
.SYNOPSIS
    NixOS-WSL の nixos-rebuild switch を実行するハンドラー

.DESCRIPTION
    - NixOS ディストリビューションの存在確認
    - nixos-rebuild switch の実行
    - pnpm グローバルパッケージのインストール (windows/pnpm/packages.json)

.NOTES
    Order = 55 (NixOSWSL=50 の後に実行)
#>

$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class NixRebuildHandler : SetupHandlerBase {
    hidden [string] $PnpmHomePath = '$HOME/.local/share/pnpm'

    hidden [string] GetPnpmShellPrefix() {
        return "export PNPM_HOME=$($this.PnpmHomePath); export PATH=`"`$PNPM_HOME/bin:`$PNPM_HOME:`$HOME/.npm-global/bin:`$PATH`""
    }

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
        try {
            $distros = Invoke-Wsl -TimeoutSeconds (Get-WslCheckTimeoutSecond) -Arguments @("-l", "-q")
            if ($LASTEXITCODE -ne 0) {
                $this.LogWarning("WSL が利用できません")
                return $false
            }
        }
        catch {
            $this.LogWarning("WSL が利用できません: $($_.Exception.Message)")
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
            $preCommitExitCode = $LASTEXITCODE

            $output | ForEach-Object {
                if ($_ -notmatch '^\s*$') {
                    $this.Log("  $_", "Gray")
                }
            }

            if ($preCommitExitCode -ne 0) {
                $this.LogWarning("pre-commit hooks のインストールが失敗しました (exit code: $preCommitExitCode)")
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
        # WSL interop 経由で Windows 版 pnpm が /mnt/ 配下に見えることがある。
        # Linux ネイティブの pnpm のみを有効とみなすため /mnt/ 配下を除外して確認する。
        Invoke-Wsl -Arguments @(
            "-d", $distroName, "-u", "nixos", "--",
            "bash", "-lc", "$($this.GetPnpmShellPrefix()); command -v pnpm 2>/dev/null | grep -qv '^/mnt/'"
        ) | Out-Null
        if ($LASTEXITCODE -ne 0) {
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
            "bash", "-lc", "$($this.GetPnpmShellPrefix()); [ -d `"`$PNPM_HOME`" ] && [ -d `"`$PNPM_HOME/bin`" ] && echo exists"
        )
        if (-not $pnpmHomeCheck -or $pnpmHomeCheck -notmatch 'exists') {
            $this.Log("PNPM_HOME を設定しています...")
            Invoke-Wsl -Arguments @(
                "-d", $distroName, "-u", "nixos", "--",
                "bash", "-lc", "$($this.GetPnpmShellPrefix()); mkdir -p `"`$PNPM_HOME`" `"`$PNPM_HOME/bin`"; pnpm setup 2>/dev/null || true"
            )
        }
        # .bashrc に PNPM_HOME/bin が無ければ追加
        Invoke-Wsl -Arguments @(
            "-d", $distroName, "-u", "nixos", "--",
            "bash", "-lc", "grep -q 'PNPM_HOME/bin' ~/.bashrc || echo 'export PNPM_HOME=$($this.PnpmHomePath); export PATH=`$PNPM_HOME/bin:`$PNPM_HOME:`$PATH' >> ~/.bashrc"
        )
    }

    hidden [bool] InstallPnpmGlobalPackages([string]$distroName, [string]$packagesJsonPath) {
        try {
            if (-not (Test-Path -LiteralPath $packagesJsonPath -PathType Leaf)) {
                $this.Log("pnpm パッケージ設定が見つかりません。スキップ: $packagesJsonPath", "Gray")
                return $true
            }

            $json = Get-JsonContent -Path $packagesJsonPath
            $packages = $json.globalPackages
            if (-not $packages -or $packages.Count -eq 0) {
                $this.Log("インストールする pnpm パッケージがありません", "Gray")
                return $true
            }

            # pnpm が利用可能か確認し、なければ corepack で有効化
            $this.EnsurePnpmAvailable($distroName)

            # インストール済みパッケージを取得してフィルタリング
            $installedOutput = Invoke-Wsl -Arguments @(
                "-d", $distroName, "-u", "nixos", "--",
                "bash", "-lc", "$($this.GetPnpmShellPrefix()); pnpm ls -g --depth=0 2>/dev/null"
            )
            $toInstall = @()
            $skipped = 0
            $verified = 0
            foreach ($pkg in $packages) {
                $pkgSpec = if ($pkg -is [string]) { $pkg } else { $pkg.name }
                $pkgName = $pkgSpec -replace '@[\d\.]+$', ''
                $verifyCmd = if ($pkg -is [string]) { $null } else { $pkg.verifyCommand }
                $installArgs = @()
                if ($pkg -isnot [string]) {
                    if ($pkg -is [System.Collections.IDictionary] -and $pkg.Contains("installArgs")) {
                        foreach ($arg in @($pkg["installArgs"])) {
                            if (-not [string]::IsNullOrWhiteSpace([string]$arg)) {
                                $installArgs += [string]$arg
                            }
                        }
                    }
                    elseif ($pkg.PSObject.Properties.Name -contains "installArgs") {
                        foreach ($arg in @($pkg.installArgs)) {
                            if (-not [string]::IsNullOrWhiteSpace([string]$arg)) {
                                $installArgs += [string]$arg
                            }
                        }
                    }
                }
                if ($installedOutput -and ($installedOutput | Where-Object { $_ -match [regex]::Escape($pkgName) })) {
                    if ($verifyCmd) {
                        if ($this.TestPnpmPackageVerificationInWsl($distroName, $verifyCmd)) {
                            $this.Log("スキップ (検証済み): $pkgName", "Gray")
                            $verified++
                            continue
                        }

                        $this.LogWarning("インストール済みですが検証に失敗しました。再インストールします: $pkgName")
                    }
                    else {
                        $this.Log("スキップ (インストール済み): $pkgName", "Gray")
                        $skipped++
                        continue
                    }
                }

                $toInstall += [PSCustomObject]@{
                    Spec          = $pkgSpec
                    VerifyCommand = $verifyCmd
                    InstallArgs   = $installArgs
                }
            }

            if ($toInstall.Count -eq 0) {
                $parts = @()
                if ($verified -gt 0) { $parts += "$verified 個検証済み" }
                $parts += "$skipped 個スキップ"
                $this.Log("pnpm グローバルパッケージはすべてインストール済みで、検証対象も正常です ($($parts -join ', '))", "Gray")
                return $true
            }

            # シェルメタ文字を含むパッケージ名（@scope/pkg 等）を安全に渡すためクォート
            $packageSpecs = @($toInstall | ForEach-Object { $_.Spec })
            $installArgs = @($toInstall | ForEach-Object { @($_.InstallArgs) } | Where-Object { $_ } | Select-Object -Unique)
            $quotedInstallArgs = ($installArgs | ForEach-Object { $this.QuoteShellArg([string]$_) }) -join " "
            $quotedPkgs = ($packageSpecs | ForEach-Object { $this.QuoteShellArg($_) }) -join " "
            $this.Log("pnpm グローバルパッケージをインストールしています: $($packageSpecs -join ', ')")

            # PNPM_HOME と ~/.npm-global/bin を PATH に追加
            $pnpmExitCode = $this.InvokeWslPnpmInstall(@(
                    "-d", $distroName, "-u", "nixos", "--",
                    "bash", "-lc", "$($this.GetPnpmShellPrefix()); pnpm add -g --reporter=append-only --yes $quotedInstallArgs $quotedPkgs"
                ))

            if ($pnpmExitCode -ne 0) {
                $this.LogWarning("pnpm グローバルパッケージのインストールが失敗しました (exit code: $pnpmExitCode)")
                return $false
            }
            else {
                $verifyFailed = 0
                foreach ($pkg in $toInstall) {
                    if ($pkg.VerifyCommand -and -not $this.TestPnpmPackageVerificationInWsl($distroName, $pkg.VerifyCommand)) {
                        $verifyFailed++
                        $this.LogWarning("✗ $($pkg.Spec) のインストールは成功しましたが検証に失敗しました")
                    }
                }

                $parts = @("$($toInstall.Count) 個インストール")
                if ($verifyFailed -gt 0) { $parts += "$verifyFailed 個検証失敗" }
                if ($verified -gt 0) { $parts += "$verified 個検証済み" }
                $parts += "$skipped 個スキップ"
                if ($verifyFailed -gt 0) {
                    $this.LogWarning("pnpm グローバルパッケージの検証に失敗しました ($($parts -join ', '))")
                    return $false
                }
                $this.Log("pnpm グローバルパッケージのインストール完了 ($($parts -join ', '))", "Green")
                return $true
            }
        }
        catch {
            $this.LogWarning("pnpm パッケージインストール中にエラーが発生しました: $_")
            return $false
        }
    }

    hidden [int] InvokeWslPnpmInstall([string[]]$arguments) {
        Invoke-Wsl -Arguments $arguments | ForEach-Object {
            if ($_ -notmatch '^\s*$') {
                $this.Log("  $_", "Gray")
            }
        }
        return $LASTEXITCODE
    }

    hidden [bool] TestPnpmPackageVerificationInWsl([string]$distroName, [object]$verifyCmd) {
        if (-not $verifyCmd) {
            return $false
        }

        try {
            $command = $null
            $arguments = @()
            $timeoutSeconds = 30
            $verifyType = "command"
            if ($verifyCmd -is [hashtable]) {
                if (-not $verifyCmd.ContainsKey("command")) { return $false }
                $command = [string]$verifyCmd["command"]
                if ($verifyCmd.ContainsKey("args")) { $arguments = @($verifyCmd["args"]) }
                if ($verifyCmd.ContainsKey("timeoutSeconds")) { $timeoutSeconds = [int]$verifyCmd["timeoutSeconds"] }
                if ($verifyCmd.ContainsKey("type")) { $verifyType = [string]$verifyCmd["type"] }
            }
            else {
                if (-not ($verifyCmd.PSObject.Properties.Name -contains "command")) { return $false }
                $command = [string]$verifyCmd.command
                if ($verifyCmd.PSObject.Properties.Name -contains "args") { $arguments = @($verifyCmd.args) }
                if ($verifyCmd.PSObject.Properties.Name -contains "timeoutSeconds") { $timeoutSeconds = [int]$verifyCmd.timeoutSeconds }
                if ($verifyCmd.PSObject.Properties.Name -contains "type") { $verifyType = [string]$verifyCmd.type }
            }
            if ($timeoutSeconds -le 0) { $timeoutSeconds = 30 }

            if ($verifyType -eq "commandExists") {
                $commandExistsLine = "command -v $($this.QuoteShellArg($command))"
                $cmdLine = "bash -lc $($this.QuoteShellArg($commandExistsLine))"
                $this.Log("検証中: command -v $command", "Gray")
            }
            else {
                $cmdLine = (@($command) + $arguments | ForEach-Object { $this.QuoteShellArg([string]$_) }) -join " "
                $this.Log("検証中: $command $($arguments -join ' ')", "Gray")
            }

            Invoke-Wsl -Arguments @(
                "-d", $distroName, "-u", "nixos", "--",
                "bash", "-lc", "$($this.GetPnpmShellPrefix()); timeout ${timeoutSeconds}s $cmdLine"
            ) | ForEach-Object {
                if ($_ -notmatch '^\s*$') {
                    $this.Log("  $_", "Gray")
                }
            }
            if ($LASTEXITCODE -eq 124) {
                $this.Log("検証コマンドがタイムアウトしました (${timeoutSeconds}s): $command $($arguments -join ' ')", "Yellow")
            }
            return $LASTEXITCODE -eq 0
        }
        catch {
            $this.Log("検証コマンド実行エラー: $($_.Exception.Message)", "Yellow")
            return $false
        }
    }

    hidden [string] QuoteShellArg([string]$value) {
        return "'" + ($value -replace "'", "'\\''") + "'"
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
        }
        else {
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
            # git が利用できない場合は直接 gitconfig を書き込む。
            # 既存エントリがなければ追記（>> で上書き回避, 冪等）。
            Invoke-Wsl -Arguments @(
                "-d", $distroName, "-u", "root", "--",
                "bash", "-lc", "grep -qs 'directory = \*' /root/.gitconfig 2>/dev/null || printf '[safe]\n\tdirectory = *\n' >> /root/.gitconfig"
            ) | Out-Null

            # root で nixos-rebuild switch を実行。2>&1 で stderr も捕捉しエラー詳細をログに残す。
            $output = Invoke-Wsl -Arguments @("-d", $distroName, "-u", "root", "--", "bash", "-lc", "cd /home/nixos/.dotfiles && nixos-rebuild switch --flake .#nixos 2>&1")
            $nixosExitCode = $LASTEXITCODE

            # error: で始まる行は LogError（赤）、それ以外は Gray で表示
            $errorLines = [System.Collections.Generic.List[string]]::new()
            $output | ForEach-Object {
                if ($_ -notmatch '^\s*$') {
                    if ($_ -match '^error:') {
                        $this.LogError("  $_")
                        $errorLines.Add([string]$_)
                    }
                    else {
                        $this.Log("  $_", "Gray")
                    }
                }
            }

            if ($nixosExitCode -ne 0) {
                $errorDetail = if ($errorLines.Count -gt 0) { ": $($errorLines[0])" } else { "" }
                throw "nixos-rebuild switch が失敗しました (exit code: $nixosExitCode)$errorDetail"
            }

            $this.Log("nixos-rebuild switch 完了", "Green")

            # pnpm グローバルパッケージをインストール（SSOT: all.nix → windows/pnpm/packages.json）
            $packagesJsonPath = Join-Path $ctx.DotfilesPath "windows\pnpm\packages.json"
            if (-not $this.InstallPnpmGlobalPackages($distroName, $packagesJsonPath)) {
                throw "pnpm グローバルパッケージのインストールまたは検証に失敗しました"
            }

            # pre-commit hooks をインストール
            $this.InstallPreCommitHooks($distroName)

            return $this.CreateSuccessResult("NixOS 設定を適用しました")
        }
        catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }
}
