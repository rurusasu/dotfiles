<#
.SYNOPSIS
    VS Code Server のキャッシュ削除と事前インストールを管理するハンドラー

.DESCRIPTION
    - WSL 内の VS Code Server キャッシュを削除
    - Windows 側の VS Code からコミットハッシュを取得
    - VS Code Server を事前インストール

.NOTES
    Order = 40 (WSL 依存処理)
    Docker の後に実行
#>

# 依存ファイルの読み込み
# 注: SetupHandler.ps1 は install.ps1 またはテストフレームワークによって事前にロードされている前提
# クラスキャッシュ問題を防ぐため、ここでは読み込まない
$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class VscodeServerHandler : SetupHandlerBase {
    VscodeServerHandler() {
        $this.Name = "VscodeServer"
        $this.Description = "VS Code Server のキャッシュ削除と事前インストール"
        $this.Order = 40
        $this.RequiresAdmin = $false
    }

    <#
    .SYNOPSIS
        実行可否を判定する
    .DESCRIPTION
        以下の条件をチェック:
        - SkipVscodeServerClean と SkipVscodeServerPreinstall が両方 true でないか
        - VS Code (Stable または Insiders) がインストールされているか
    #>
    [bool] CanApply([SetupContext]$ctx) {
        $skipClean = $ctx.GetOption("SkipVscodeServerClean", $false)
        $skipPreinstall = $ctx.GetOption("SkipVscodeServerPreinstall", $false)

        # 両方スキップなら実行不要
        if ($skipClean -and $skipPreinstall) {
            $this.Log("すべての処理がスキップされているためスキップします", "Gray")
            return $false
        }

        # WSL が利用可能か確認
        if (-not (Test-WslAvailable)) {
            $this.Log("WSL が利用できないためスキップします", "Gray")
            return $false
        }

        # VS Code のインストール確認（preinstall が有効な場合のみ）
        if (-not $skipPreinstall) {
            try {
                $stableProduct = $this.GetVscodeProductInfo("stable")
                $insidersProduct = $this.GetVscodeProductInfo("insider")
            } catch {
                $this.LogWarning("VS Code product.json の読み取りに失敗しました: $($_.Exception.Message)")
                $stableProduct = $null
                $insidersProduct = $null
            }

            if (-not $stableProduct -and -not $insidersProduct) {
                $this.Log("VS Code がインストールされていません", "Gray")
                # clean のみ実行可能
                if ($skipClean) {
                    return $false
                }
            }
        }

        return $true
    }

    <#
    .SYNOPSIS
        VS Code Server のキャッシュ削除と事前インストールを実行する
    #>
    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            $distroName = $ctx.DistroName
            $user = $this.GetWslDefaultUser($distroName)

            $skipClean = $ctx.GetOption("SkipVscodeServerClean", $false)
            $skipPreinstall = $ctx.GetOption("SkipVscodeServerPreinstall", $false)

            # キャッシュ削除
            if (-not $skipClean) {
                $this.CleanupVscodeServer($distroName, $user)
            } else {
                $this.Log("SkipVscodeServerClean が設定されているためキャッシュ削除をスキップします", "Gray")
            }

            # 事前インストール
            if (-not $skipPreinstall) {
                $didPreinstall = $this.PreinstallVscodeServer($distroName, $user)
                if (-not $didPreinstall) {
                    $this.LogWarning("VS Code の product.json が見つからないため、事前インストールをスキップします")
                }
            } else {
                $this.Log("SkipVscodeServerPreinstall が設定されているため事前インストールをスキップします", "Gray")
            }

            return $this.CreateSuccessResult("VS Code Server の処理を完了しました")
        } catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }

    <#
    .SYNOPSIS
        VS Code Server のキャッシュを削除する
    #>
    hidden [void] CleanupVscodeServer([string]$distroName, [string]$user) {
        $this.Log("VS Code Server キャッシュを削除します")

        $safeUser = $this.EscapeForShell($user)
        $userHome = "/home/$safeUser"
        $cleanup = "rm -rf '$userHome/.vscode-server' '$userHome/.vscode-server-insiders' && " +
            "rm -rf '$userHome/.vscode-remote-containers' '$userHome/.vscode-remote-wsl' && " +
            "rm -rf /root/.vscode-server /root/.vscode-server-insiders && " +
            "rm -rf /root/.vscode-remote-containers /root/.vscode-remote-wsl"

        Invoke-Wsl "-d" $distroName "-u" "root" "--" "sh" "-lc" $cleanup
        $this.Log("VS Code Server キャッシュを削除しました", "Green")
    }

    <#
    .SYNOPSIS
        VS Code Server を事前インストールする
    #>
    hidden [bool] PreinstallVscodeServer([string]$distroName, [string]$user) {
        $didPreinstall = $false

        # Insiders
        $insidersProduct = $this.GetVscodeProductInfo("insider")
        if ($insidersProduct -and $insidersProduct.commit) {
            $this.Log("VS Code Server (Insiders) を事前インストールします")
            $this.InstallVscodeServer($distroName, "insider", $insidersProduct.commit, $user)
            $didPreinstall = $true
        }

        # Stable
        $stableProduct = $this.GetVscodeProductInfo("stable")
        if ($stableProduct -and $stableProduct.commit) {
            $this.Log("VS Code Server (Stable) を事前インストールします")
            $this.InstallVscodeServer($distroName, "stable", $stableProduct.commit, $user)
            $didPreinstall = $true
        }

        return $didPreinstall
    }

    <#
    .SYNOPSIS
        VS Code Server をインストールする
    #>
    hidden [void] InstallVscodeServer([string]$distroName, [string]$channel, [string]$commit, [string]$user) {
        $serverRoot = if ($channel -eq "insider") {
            "/home/$user/.vscode-server-insiders"
        } else {
            "/home/$user/.vscode-server"
        }

        $serverDir = "$serverRoot/bin/$commit"
        $url = "https://update.code.visualstudio.com/commit:$commit/server-linux-x64/$channel"

        # シェルインジェクション防止: PowerShell 変数を直接展開するが、
        # シェルメタ文字（', ", $, `, \）をエスケープする。
        # 注: シェル変数参照方式は PowerShell → wsl.exe の引数渡しで
        # ダブルクォートが正しく伝達されないため使用しない。
        $safeUser = $this.EscapeForShell($user)
        $safeRoot = $this.EscapeForShell($serverRoot)
        $safeDir = $this.EscapeForShell($serverDir)
        $safeUrl = $this.EscapeForShell($url)
        $chownOwner = "${safeUser}:" + '$(id -gn ''' + $safeUser + ''' 2>/dev/null || echo ''' + $safeUser + ''')'

        $cmd = "set -e && " +
        "mkdir -p '$safeDir' && " +
        "if [ ! -f '$safeDir/.nixos-patched' ]; then curl -fsSL '$safeUrl' | tar -xz -C '$safeDir' --strip-components=1; fi && " +
        "if [ -x '$safeDir/bin/code-server-insiders' ] && [ ! -e '$safeDir/bin/code-server' ]; then ln -s code-server-insiders '$safeDir/bin/code-server'; fi && " +
        "chown -R '$chownOwner' '$safeRoot'"

        Invoke-Wsl "-d" $distroName "-u" "root" "--" "sh" "-lc" $cmd
    }

    <#
    .SYNOPSIS
        シェルのシングルクォート文脈で安全に使える文字列にエスケープする
    #>
    hidden [string] EscapeForShell([string]$value) {
        # シングルクォート内では ' のみ特殊。' → '\'' に変換
        return $value.Replace("'", "'\''")
    }

    <#
    .SYNOPSIS
        WSL のデフォルトユーザーを取得する
    #>
    hidden [string] GetWslDefaultUser([string]$distroName) {
        $user = Invoke-Wsl "-d" $distroName "--" "sh" "-lc" "whoami" | Select-Object -First 1
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($user)) {
            return "nixos"
        }
        return $user.Trim()
    }

    <#
    .SYNOPSIS
        VS Code の product.json から情報を取得する
    #>
    hidden [object] GetVscodeProductInfo([string]$channel) {
        $roots = if ($channel -eq "insider") {
            @((Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code Insiders"))
        } else {
            @((Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code"))
        }

        $pattern = if ($channel -eq "insider") {
            "C:\Users\*\AppData\Local\Programs\Microsoft VS Code Insiders\*\resources\app\product.json"
        } else {
            "C:\Users\*\AppData\Local\Programs\Microsoft VS Code\*\resources\app\product.json"
        }

        $productFile = $this.FindVscodeProductJson($roots, $pattern)
        if (-not $productFile) {
            return $null
        }

        try {
            return Get-JsonContent -Path $productFile.FullName
        } catch {
            return $null
        }
    }

    <#
    .SYNOPSIS
        VS Code の product.json ファイルを検索する
    #>
    hidden [object] FindVscodeProductJson([string[]]$roots, [string]$pattern) {
        $candidates = @()

        foreach ($root in $roots) {
            if ([string]::IsNullOrWhiteSpace($root)) {
                continue
            }
            if (Test-PathExist -Path $root) {
                $found = Get-ChildItemSafe -Path $root -Filter "product.json" -Recurse
                if ($found) {
                    $candidates += $found
                }
            }
        }

        if ($pattern) {
            try {
                $patternFiles = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue
                if ($patternFiles) {
                    $candidates += $patternFiles
                }
            } catch [System.Management.Automation.ItemNotFoundException] {
                # グロブパターン展開時のエラーを無視（VS Code 未インストール時など）
                Write-Verbose "パターン検索でファイルが見つかりません: $pattern"
            }
        }

        $filtered = @($candidates | Where-Object { $_ -ne $null })
        if ($filtered.Count -eq 0) {
            return $null
        }

        return $filtered | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }
}
