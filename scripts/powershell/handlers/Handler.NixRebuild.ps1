<#
.SYNOPSIS
    NixOS-WSL の nixos-rebuild switch を実行するハンドラー

.DESCRIPTION
    - NixOS ディストリビューションの存在確認
    - nixos-rebuild switch の実行

.NOTES
    Order = 55 (NixOSWSL=17 の後に実行)
#>

$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class NixRebuildHandler : SetupHandlerBase {
    hidden [string] $NixOsUser = 'nixos'
    hidden [string] $NixOsHome = '/home/nixos'

    NixRebuildHandler() {
        $this.Name = "NixRebuild"
        $this.Description = "nixos-rebuild switch の実行"
        $this.Order = 55
        $this.RequiresAdmin = $false
    }

    hidden [void] ResolveNixOsIdentity([string]$distroName) {
        $identityCommand = 'user=$(cat /var/lib/dotfiles/user 2>/dev/null || true); if [ -z "$user" ]; then user=$(awk -F= ''/^\[user\]/{in_user=1; next} /^\[/{in_user=0} in_user && $1=="default" {gsub(/[[:space:]]/,"",$2); print $2; exit}'' /etc/wsl.conf 2>/dev/null || true); fi; if [ -z "$user" ]; then user=$(getent passwd 1000 | cut -d: -f1); fi; if [ -n "$user" ]; then home=$(getent passwd "$user" | cut -d: -f6); printf "%s\t%s" "$user" "$home"; fi'
        $identityOutput = Invoke-Wsl -Arguments @(
            "-d", $distroName, "-u", "root", "--", "bash", "-lc", $identityCommand
        )
        $identityText = if ($identityOutput) { ([string]($identityOutput | Select-Object -First 1)).Trim() } else { "" }
        if ($identityText -match '^(?<user>[a-z_][a-z0-9_-]*[$]?)\s+(?<home>/\S+)$') {
            $this.NixOsUser = $Matches.user
            $this.NixOsHome = $Matches.home
        }
        else {
            $this.NixOsUser = 'nixos'
            $this.NixOsHome = '/home/nixos'
        }
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
            # リポジトリの local 設定だけを解除する。global は Home Manager が所有する。
            Invoke-Wsl -Arguments @(
                "-d", $distroName, "-u", $this.NixOsUser, "--",
                "bash", "-lc", "cd ~/.dotfiles && git config --unset-all core.hooksPath 2>/dev/null; true"
            )

            $output = Invoke-Wsl -Arguments @(
                "-d", $distroName, "-u", $this.NixOsUser, "--",
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

    hidden [string] QuoteShellArg([string]$value) {
        return "'" + ($value -replace "'", "'\\''") + "'"
    }

    hidden [void] EnsureDotfilesAvailable([string]$distroName, [string]$dotfilesPath) {
        # Windows パス (D:\ruru\dotfiles) を WSL マウントパス (/mnt/d/ruru/dotfiles) に変換
        $driveLetter = $dotfilesPath.Substring(0, 1).ToLower()
        $wslMountPath = '/mnt/' + $driveLetter + ($dotfilesPath.Substring(2) -replace '\\', '/')

        $dotfilesLinkPath = "$($this.NixOsHome)/.dotfiles"
        $existingTarget = Invoke-Wsl -Arguments @(
            "-d", $distroName, "-u", $this.NixOsUser, "--",
            "bash", "-lc", "if [ -L $dotfilesLinkPath ]; then readlink -f $dotfilesLinkPath 2>/dev/null; elif [ -e $dotfilesLinkPath ]; then printf '__non_symlink__'; fi"
        )
        $existingTargetText = if ($existingTarget) { ([string]($existingTarget | Select-Object -First 1)).Trim() } else { "" }
        if ($existingTargetText -eq $wslMountPath) {
            return
        }
        if ($existingTargetText -eq "__non_symlink__") {
            return
        }

        # Windows dotfiles が WSL からアクセスできるか確認
        Invoke-Wsl -Arguments @("-d", $distroName, "-u", $this.NixOsUser, "--", "bash", "-lc", "test -d `"$wslMountPath`"") | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $this.Log("dotfiles を WSL マウント経由でリンクします: $wslMountPath")
            Invoke-Wsl -Arguments @("-d", $distroName, "-u", $this.NixOsUser, "--", "bash", "-lc", "ln -sfn `"$wslMountPath`" $dotfilesLinkPath")
            if ($LASTEXITCODE -ne 0) {
                throw "dotfiles のシンボリックリンク作成に失敗しました"
            }
            $this.Log("dotfiles リンク完了: $dotfilesLinkPath -> $wslMountPath", "Green")
        }
        else {
            throw "dotfiles が見つかりません。Windows パス '$dotfilesPath' が WSL から '$wslMountPath' としてアクセスできません"
        }
    }

    [SetupResult] Apply([SetupContext]$ctx) {
        if ($ctx.Options.ContainsKey("NixRebuildApplied")) {
            $ctx.Options.Remove("NixRebuildApplied")
        }
        try {
            $distroName = $ctx.DistroName
            $this.ResolveNixOsIdentity($distroName)

            # dotfiles が NixOS 内に存在しなければ Windows マウント経由でリンク
            $this.EnsureDotfilesAvailable($distroName, $ctx.DotfilesPath)

            $this.Log("nix flake update を実行しています...")
            $flakePath = "$($this.NixOsHome)/.dotfiles"
            $quotedFlakePath = $this.QuoteShellArg($flakePath)
            $flakeUpdateCommand = "cd $quotedFlakePath && nix --accept-flake-config --extra-experimental-features 'nix-command flakes' flake update --flake . 2>&1"
            $flakeUpdateOutput = Invoke-Wsl -Arguments @("-d", $distroName, "-u", $this.NixOsUser, "--", "bash", "-lc", $flakeUpdateCommand)
            $flakeUpdateExitCode = $LASTEXITCODE
            $flakeUpdateErrors = [System.Collections.Generic.List[string]]::new()
            $flakeUpdateOutput | ForEach-Object {
                if ($_ -notmatch '^\s*$') {
                    if ($_ -match '^error:') {
                        $this.LogError("  $_")
                        $flakeUpdateErrors.Add([string]$_)
                    }
                    else {
                        $this.Log("  $_", "Gray")
                    }
                }
            }
            if ($flakeUpdateExitCode -ne 0) {
                $errorDetail = if ($flakeUpdateErrors.Count -gt 0) { ": $($flakeUpdateErrors[0])" } else { "" }
                throw "nix flake update が失敗しました (exit code: $flakeUpdateExitCode)$errorDetail"
            }

            $this.Log("nixos-rebuild switch を実行しています...")

            # ホスト情報は Nix が /etc/nixos/dotfiles.json から取得する。
            # 2>&1 で stderr も捕捉しエラー詳細をログに残す。
            # This repository pins its binary-cache URL and signing key in flake.nix.
            # Accept that checked-in flake config only for this rebuild invocation;
            # do not persist trust in the user's or machine's Nix configuration.
            $rebuildCommand = "cd $($this.QuoteShellArg("$($this.NixOsHome)/.dotfiles")) && nixos-rebuild switch --flake .#nixos --impure --option accept-flake-config true --option experimental-features 'nix-command flakes' 2>&1"
            $nixRebuildTimeoutSeconds = [int]$ctx.GetOption("NixRebuildTimeoutSeconds", 5400)
            $output = Invoke-Wsl -TimeoutSeconds $nixRebuildTimeoutSeconds -Arguments @("-d", $distroName, "-u", "root", "--", "bash", "-lc", $rebuildCommand)
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
                $rebuildFailure = "nixos-rebuild switch が失敗しました (exit code: $nixosExitCode)$errorDetail"
                throw $rebuildFailure
            }

            $this.Log("nixos-rebuild switch 完了", "Green")

            # pre-commit hooks をインストール
            $this.InstallPreCommitHooks($distroName)

            # Home Manager installs Hermes natively in NixOS. Validate it as
            # the resolved Linux user, without a Windows Hermes installation.
            $hermesCommand = 'export XDG_RUNTIME_DIR=/run/user/$(id -u); export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus; systemctl --user is-active --quiet hermes-agent.service && command -v hermes >/dev/null && hermes --version'
            $hermesOutput = Invoke-Wsl -TimeoutSeconds 60 -Arguments @(
                '-d', $distroName, '-u', $this.NixOsUser, '--', 'bash', '-lc', $hermesCommand
            )
            if ($LASTEXITCODE -ne 0) {
                throw "NixOS 上の Hermes service/CLI 検証に失敗しました: $($hermesOutput -join '; ')"
            }

            $ctx.Options["NixRebuildApplied"] = $true
            return $this.CreateSuccessResult("NixOS 設定を適用しました")
        }
        catch {
            $failureMessage = $_.Exception.Message
            return $this.CreateFailureResult($failureMessage, $_.Exception)
        }
    }
}
