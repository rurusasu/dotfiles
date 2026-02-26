<#
.SYNOPSIS
    NixOS-WSL の nixos-rebuild switch を実行するハンドラー

.DESCRIPTION
    - NixOS ディストリビューションの存在確認
    - nixos-rebuild switch の実行

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
        $distroExists = $distros | Where-Object { $_ -eq $distroName }
        if (-not $distroExists) {
            $this.Log("$distroName が見つからないためスキップします")
            return $false
        }

        return $true
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

            # bun install を実行（package.json がある場合）
            $this.Log("bun install を実行しています...")
            $bunOutput = Invoke-Wsl -Arguments @("-d", $distroName, "--", "bash", "-lc", "cd ~/.dotfiles && bun install")

            $bunOutput | ForEach-Object {
                if ($_ -notmatch '^\s*$') {
                    $this.Log("  $_", "Gray")
                }
            }

            if ($LASTEXITCODE -ne 0) {
                $this.LogWarning("bun install が失敗しました (exit code: $LASTEXITCODE)")
            }
            else {
                $this.Log("bun install 完了", "Green")
            }

            return $this.CreateSuccessResult("NixOS 設定を適用しました")
        }
        catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }
}
