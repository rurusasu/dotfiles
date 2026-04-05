<#
.SYNOPSIS
    chezmoi による dotfiles 適用を管理するハンドラー

.DESCRIPTION
    - chezmoi コマンドの検出（PATH、WinGet Links、WinGet Packages）
    - chezmoi apply の実行

.NOTES
    Order = 10 (WSL 非依存処理)
    WSL 関連の処理とは独立して実行可能
#>

# 依存ファイルの読み込み
# 注: SetupHandler.ps1 は install.ps1 またはテストフレームワークによって事前にロードされている前提
# クラスキャッシュ問題を防ぐため、ここでは読み込まない
$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class ChezmoiHandler : SetupHandlerBase {
    # 検出された chezmoi 実行ファイルのパス
    hidden [string]$ChezmoiExePath

    ChezmoiHandler() {
        $this.Name = "Chezmoi"
        $this.Description = "chezmoi による dotfiles 適用"
        $this.Order = 10
        $this.RequiresAdmin = $false
    }

    <#
    .SYNOPSIS
        実行可否を判定する
    .DESCRIPTION
        以下の条件をチェック:
        - chezmoi コマンドが利用可能か
        - chezmoi ソースディレクトリが存在するか
    #>
    [bool] CanApply([SetupContext]$ctx) {
        # chezmoi の検出
        $this.ChezmoiExePath = $this.FindChezmoiExe()
        if (-not $this.ChezmoiExePath) {
            $this.ShowChezmoiInstallInstructions($ctx)
            return $false
        }

        # chezmoi が実際に動作するか確認（DLL不足などを検出）
        if (-not $this.TestChezmoiExecutable()) {
            $this.LogWarning("chezmoi が正常に動作しません（Visual C++ Redistributable が必要な可能性があります）")
            $this.Log("修正方法: winget install -e --id Microsoft.VCRedist.2015+.x64", "Yellow")
            return $false
        }

        # ソースディレクトリの確認
        $sourcePath = $this.GetChezmoiSourcePath($ctx)
        if (-not (Test-PathExist -Path $sourcePath)) {
            $this.LogWarning("chezmoi ソースディレクトリが見つかりません: $sourcePath")
            return $false
        }

        return $true
    }

    <#
    .SYNOPSIS
        chezmoi apply を実行する
    #>
    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            $sourcePath = $this.GetChezmoiSourcePath($ctx)
            $runtimeRoot = $this.GetChezmoiRuntimeRoot()
            $persistentStatePath = Join-Path $runtimeRoot "chezmoistate.boltdb"
            $cachePath = Join-Path $runtimeRoot "cache"

            # winget で同セッション内に新規インストールされたツール（op 等）を検出できるよう
            # レジストリから最新の PATH を読み直す
            $machinePath = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine')
            $userPath    = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
            $env:PATH    = (@($machinePath, $userPath) | Where-Object { $_ }) -join ";"

            # 1Password CLI のセットアップ確認（chezmoi テンプレートで op を使用するため）
            $this.EnsureOnePasswordAvailable()

            $this.Log("chezmoi でターミナル設定を適用します: $sourcePath")
            New-DirectorySafe -Path $runtimeRoot
            New-DirectorySafe -Path $cachePath

            # config file テンプレートが変更された場合、init で config を再生成する
            # git データは .chezmoidata/personal.yaml から供給されるためプロンプトは発生しない
            $this.Log("chezmoi init を実行中...")
            Invoke-Chezmoi `
                -ExePath $this.ChezmoiExePath `
                -MergeStderr `
                "--persistent-state" $persistentStatePath `
                "--cache" $cachePath `
                "--no-tty" "init" "--source" $sourcePath "-v"

            # --force: コンフリクト時のプロンプトをスキップして上書き（非対話実行に必須）
            # -MergeStderr: run_after_ スクリプトの stdout/stderr を合流してコンソール表示
            $this.Log("chezmoi apply を実行中...")
            Invoke-Chezmoi `
                -ExePath $this.ChezmoiExePath `
                -MergeStderr `
                "--persistent-state" $persistentStatePath `
                "--cache" $cachePath `
                "--no-tty" "apply" "--source" $sourcePath "--force" "-v"

            # chezmoi apply の終了コードを保存（後続処理で上書きされるのを防ぐ）
            $chezmoiExitCode = $LASTEXITCODE

            # 管理者昇格セッション対応: Windows Terminal の elevate: true により
            # 別ユーザーのプロファイルが読まれるケースがある。
            # 管理者権限がある場合のみ実行（非管理者では他ユーザーの Documents にアクセス不可）
            if (Test-IsAdminSession) {
                $this.DeployProfileToOtherUsers($sourcePath)
            }

            if ($chezmoiExitCode -eq 0) {
                $this.Log("chezmoi apply 完了", "Green")
                $this.Log("Windows Terminal を起動中なら、再起動すると確実に反映されます", "Gray")
                return $this.CreateSuccessResult("dotfiles を適用しました")
            } else {
                $this.LogError("chezmoi apply が失敗しました (exit=$chezmoiExitCode)")
                $this.Log("手動で実行してください: chezmoi --source `"$sourcePath`" apply", "Yellow")
                return $this.CreateFailureResult("chezmoi apply が失敗しました (exit=$chezmoiExitCode)")
            }
        } catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }

    <#
    .SYNOPSIS
        chezmoi 実行ファイルを検索する
    .DESCRIPTION
        以下の順序で検索:
        1. PATH 内の chezmoi
        2. WinGet Links ディレクトリ
        3. WinGet Packages ディレクトリ
    #>
    hidden [string] FindChezmoiExe() {
        # 1. PATH から検索
        $cmd = Get-ExternalCommand -Name "chezmoi"
        if ($cmd) {
            return $cmd.Source
        }

        # 2. WinGet Links ディレクトリ
        $linksPath = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\chezmoi.exe"
        if (Test-PathExist -Path $linksPath) {
            return $linksPath
        }

        # 3. WinGet Packages ディレクトリ
        $packagesRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
        if (Test-PathExist -Path $packagesRoot) {
            $pkgDir = Get-ChildItemSafe -Path $packagesRoot -Directory |
            Where-Object { $_.Name -like 'twpayne.chezmoi*' } |
            Select-Object -First 1

            if ($pkgDir) {
                $exe = Join-Path $pkgDir.FullName "chezmoi.exe"
                if (Test-PathExist -Path $exe) {
                    return $exe
                }
            }
        }

        # 4. Programs ディレクトリ（カスタムインストール）
        $programsPath = Join-Path $env:LOCALAPPDATA "Programs\chezmoi\chezmoi.exe"
        if (Test-PathExist -Path $programsPath) {
            return $programsPath
        }

        return $null
    }

    <#
    .SYNOPSIS
        chezmoi が実際に動作するか確認する
    .DESCRIPTION
        chezmoi --version を実行して、DLL不足などのエラーがないか確認
    #>
    hidden [bool] TestChezmoiExecutable() {
        try {
            $output = Invoke-Chezmoi -ExePath $this.ChezmoiExePath -Arguments @("--version")
            # exit code 0 かつ出力にバージョン情報が含まれているか確認
            if ($LASTEXITCODE -eq 0 -and $output -match '\d+\.\d+') {
                return $true
            }
            return $false
        } catch {
            # 例外が発生した場合（DLL不足など）
            return $false
        }
    }

    <#
    .SYNOPSIS
        chezmoi インストール手順を表示する
    #>
    hidden [void] ShowChezmoiInstallInstructions([SetupContext]$ctx) {
        $sourcePath = $this.GetChezmoiSourcePath($ctx)

        Write-Host ""
        Write-Host "========================================" -ForegroundColor Yellow
        Write-Host "chezmoi がインストールされていません" -ForegroundColor Yellow
        Write-Host "========================================" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Windows Terminal / WezTerm 設定を適用するには、以下のいずれかを実行してください:" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  # 方法1: winget で chezmoi をインストールして適用"
        Write-Host "  winget install -e --id twpayne.chezmoi"
        Write-Host "  chezmoi init --source `"$sourcePath`""
        Write-Host "  chezmoi apply"
        Write-Host ""
        Write-Host "  # 方法2: GitHub から直接取得（ローカル source を使わない場合）"
        Write-Host "  winget install -e --id twpayne.chezmoi"
        Write-Host "  chezmoi init rurusasu/dotfiles"
        Write-Host "  chezmoi apply"
        Write-Host ""
    }

    <#
    .SYNOPSIS
        chezmoi ソースディレクトリのパスを取得する
    #>
    hidden [string] GetChezmoiSourcePath([SetupContext]$ctx) {
        return Join-Path $ctx.DotfilesPath "chezmoi"
    }

    hidden [string] GetChezmoiRuntimeRoot() {
        return Join-Path $env:LOCALAPPDATA "chezmoi"
    }

    <#
    .SYNOPSIS
        1Password CLI のサインイン状態を確認し、未設定なら案内して待つ
    .DESCRIPTION
        chezmoi テンプレートが onepasswordRead を使用するため、
        op CLI がサインイン済みである必要がある。
        デスクトップアプリ連携が有効なら自動で通過する。
    #>
    hidden [void] EnsureOnePasswordAvailable() {
        $opExe = $this.FindOpExe()
        if (-not $opExe) {
            $this.LogWarning("1Password CLI (op) が見つかりません。chezmoi テンプレートが失敗する可能性があります")
            return
        }

        # サインイン済みか確認
        # op whoami はデスクトップアプリ連携環境（特に -File モード）で
        # "account is not signed in" を返す場合がある。
        # op vault list は認証済みなら exit 0 を返し、より信頼性が高い。
        $result = Invoke-OpVaultList -OpExe $opExe
        if ($result.ExitCode -eq 0) {
            $this.Log("1Password CLI: サインイン済み", "Gray")
            return
        }

        # 原因を診断して具体的なエラーメッセージを構築
        $diagnosis = $this.DiagnoseOpAuthFailure($opExe)

        # 非対話環境では Read-Host がハングするため対話的サインインをスキップ
        # ただし chezmoi apply は確実に失敗するため、例外で停止する
        if (-not (Test-InteractiveEnvironment)) {
            throw $diagnosis
        }

        # 1Password CLI が未認証 → ログイン画面を表示して待機
        Write-Host ""
        Write-Host "========================================"  -ForegroundColor Yellow
        Write-Host "[Chezmoi] 1Password CLI の認証が必要です" -ForegroundColor Yellow
        Write-Host "========================================"  -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  $diagnosis" -ForegroundColor Cyan
        Write-Host ""
        if (Test-IsAdminSession) {
            Write-Host "  管理者昇格プロセスでは 1Password デスクトップアプリ連携が使えないため、" -ForegroundColor Cyan
            Write-Host "  op signin による対話認証を試みます。"                                     -ForegroundColor Cyan
        } else {
            Write-Host "  ヒント: 1Password デスクトップアプリが起動・サインイン済みなら"           -ForegroundColor Gray
            Write-Host "  自動的に認証される場合があります。アプリを確認してください。"             -ForegroundColor Gray
        }
        Write-Host ""

        $maxRetries = 3
        for ($i = 1; $i -le $maxRetries; $i++) {
            $this.Log("1Password CLI: サインインを試行中 ($i/$maxRetries)...")
            Invoke-OpSignIn -OpExe $opExe | Out-Null

            # signin 後に whoami で確認
            $result = Invoke-OpVaultList -OpExe $opExe
            if ($result.ExitCode -eq 0) {
                $this.Log("1Password CLI: サインイン完了", "Green")
                return
            }

            if ($i -lt $maxRetries) {
                $this.LogWarning("1Password CLI のサインインを確認できませんでした")
                Write-Host ""
                Write-Host "  1Password デスクトップアプリでサインインしてから Enter を押してください ($i/$maxRetries)..." -ForegroundColor Yellow -NoNewline
                Read-Host | Out-Null

                # デスクトップアプリ連携が有効になった可能性があるため whoami で再確認
                $result = Invoke-OpVaultList -OpExe $opExe
                if ($result.ExitCode -eq 0) {
                    $this.Log("1Password CLI: サインイン完了（デスクトップアプリ連携）", "Green")
                    return
                }
            }
        }

        # 全リトライ失敗 → chezmoi apply に進んでも確実に失敗するため例外で停止
        throw "1Password CLI のサインインに失敗しました。1Password デスクトップアプリでサインインしてから再実行してください。"
    }

    <#
    .SYNOPSIS
        op whoami 失敗の原因を診断し、具体的な対処法を返す
    .DESCRIPTION
        以下の順序で原因を特定する:
        1. op account list が空 → CLI にアカウント未登録（デスクトップアプリ連携が無効）
        2. それ以外 → 一般的な認証エラー
    #>
    hidden [string] DiagnoseOpAuthFailure([string]$opExe) {
        $accountResult = Invoke-OpAccountList -OpExe $opExe
        $outputStr = if ($accountResult.Output) { ($accountResult.Output | Out-String).Trim() } else { '' }

        # op account list 自体が失敗 → デスクトップアプリに接続できない
        if ($accountResult.ExitCode -ne 0) {
            $isConnectError = $outputStr -match 'cannot connect|make sure it is running'
            if ($isConnectError) {
                return @(
                    "1Password デスクトップアプリに接続できません。"
                    "CLI 連携を有効にした後、アプリの再起動が必要な場合があります:"
                    "  1. タスクトレイの 1Password を右クリック → 「Quit 1Password」で完全終了"
                    "  2. 1Password デスクトップアプリを再起動"
                    "  3. アプリでロック解除（パスワード or 生体認証）"
                    "  4. install.cmd を再実行する"
                ) -join "`n"
            }
            return @(
                "1Password CLI がデスクトップアプリと通信できません。"
                "1Password デスクトップアプリが起動・ロック解除されていることを確認してください。"
            ) -join "`n"
        }

        # account list は成功したがアカウントが空 → CLI連携が無効
        $hasAccounts = $outputStr -and $outputStr -ne '[]' -and $outputStr -ne ''
        if (-not $hasAccounts) {
            return @(
                "1Password CLI にアカウントが登録されていません。"
                "1Password デスクトップアプリで CLI 連携を有効にしてください:"
                "  1. 1Password デスクトップアプリを開く"
                "  2. Settings > Developer を開く"
                "  3. 「Biometric unlock for 1Password CLI」をオンにする"
                "  4. 1Password デスクトップアプリを再起動する"
                "  5. install.cmd を再実行する"
                ""
                "  参考: https://developer.1password.com/docs/cli/app-integration/"
            ) -join "`n"
        }

        # アカウントはあるが未認証
        return @(
            "1Password CLI が未認証です。"
            "1Password デスクトップアプリでロック解除してから再実行してください。"
        ) -join "`n"
    }

    <#
    .SYNOPSIS
        op.exe を探す（PATH または WinGet Packages）
    #>
    hidden [string] FindOpExe() {
        # 1. PATH から検索
        $cmd = Get-ExternalCommand -Name "op"
        if ($cmd) {
            return $cmd.Source
        }

        # 2. 全ユーザーの WinGet Packages を検索（管理者昇格セッション対応）
        return Find-WinGetExe -PackagePattern 'AgileBits.1Password.CLI*' -ExeFilter 'op.exe'
    }

    <#
    .SYNOPSIS
        他ユーザーの Documents にも PowerShell プロファイルをデプロイする
    .DESCRIPTION
        Windows Terminal の elevate: true 設定により、管理者昇格セッションでは
        別ユーザーのプロファイルが読み込まれることがある。
        管理者権限で実行されるこのハンドラーから、他ユーザーの Documents にも
        プロファイルをコピーすることで昇格セッションでもプロファイルが有効になる。
    #>
    hidden [void] DeployProfileToOtherUsers([string]$sourcePath) {
        $profileSource = Join-Path $sourcePath "shells\Microsoft.PowerShell_profile.ps1"
        if (-not (Test-Path -LiteralPath $profileSource -PathType Leaf)) { return }

        $usersDir = Split-Path $env:USERPROFILE
        Get-ChildItemSafe -Path $usersDir -Directory |
            Where-Object { $_.Name -notin @("Public", "Default", "Default User", "All Users", $env:USERNAME) } |
            ForEach-Object {
                $userDir = $_
                try {
                    $docs = Join-Path $userDir.FullName "Documents"
                    if (Test-Path -LiteralPath $docs) {
                        foreach ($subDir in @("PowerShell", "WindowsPowerShell")) {
                            $dest = Join-Path $docs "$subDir\Microsoft.PowerShell_profile.ps1"
                            $destDir = Split-Path -Parent $dest
                            if (-not (Test-Path -LiteralPath $destDir)) {
                                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                            }
                            Copy-Item -LiteralPath $profileSource -Destination $dest -Force
                            $this.Log("プロファイルをデプロイ: $dest", "Green")
                        }
                    }
                } catch {
                    $this.Log("スキップ: $($userDir.FullName) ($($_.Exception.Message))", "Gray")
                }
            }
    }
}
