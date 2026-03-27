<#
.SYNOPSIS
    Docker Desktop と WSL の連携を管理するハンドラー

.DESCRIPTION
    - Docker Desktop のインストール確認
    - docker-desktop / docker-desktop-data ディストリビューションの作成
    - WSL ディストリビューションとの連携確認
    - docker グループへのユーザー追加

.NOTES
    Order = 18 (WslConfig の前に実行)
    WslConfig (Order=20) が wsl --terminate NixOS を実行するため、
    Docker の NixOS 接続チェックは WslConfig の前に行う必要がある。
#>

# 依存ファイルの読み込み
# 注: SetupHandler.ps1 は install.ps1 またはテストフレームワークによって事前にロードされている前提
# クラスキャッシュ問題を防ぐため、ここでは読み込まない
$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class DockerHandler : SetupHandlerBase {
    # リトライ設定
    [int]$Retries = 5
    [int]$RetryDelaySeconds = 5
    # WSL 書き込み可否チェックのリトライ設定
    # NixOS-WSL (systemd) は wsl --terminate 後の再起動に 20-60 秒かかるため
    # デフォルト 8 回 (最大待機: 3+6+9+12+15+18+21 = 84 秒)
    [int]$WslWritableMaxAttempts = 8

    DockerHandler() {
        $this.Name = "Docker"
        $this.Description = "Docker Desktop との WSL 連携"
        $this.Order = 18
        $this.RequiresAdmin = $false
    }

    <#
    .SYNOPSIS
        実行可否を判定する
    .DESCRIPTION
        以下の条件をチェック:
        - Docker Desktop がインストールされているか
        - リトライ回数が 0 より大きいか
    #>
    [bool] CanApply([SetupContext]$ctx) {
        # リトライ回数の取得
        $this.Retries = $ctx.GetOption("DockerIntegrationRetries", 5)
        $this.RetryDelaySeconds = $ctx.GetOption("DockerIntegrationRetryDelaySeconds", 5)
        $this.WslWritableMaxAttempts = $ctx.GetOption("WslWritableMaxAttempts", 8)

        if ($this.Retries -le 0) {
            $this.Log("リトライ回数が 0 のためスキップします", "Gray")
            return $false
        }

        # Docker Desktop のインストール確認
        $dockerExe = $this.GetDockerDesktopPath()
        if (-not (Test-PathExist -Path $dockerExe)) {
            $this.Log("Docker Desktop がインストールされていません", "Gray")
            return $false
        }

        # Docker Desktop が起動可能か確認
        if (-not $this.TestDockerDesktopExecutable($dockerExe)) {
            $this.LogWarning("Docker Desktop が正常に動作しません（インストールが不完全な可能性があります）")
            $this.Log("修正方法: Docker Desktop を再インストールしてください", "Yellow")
            return $false
        }

        return $true
    }

    <#
    .SYNOPSIS
        Docker Desktop が実際に起動可能か確認する
    .DESCRIPTION
        Docker Desktop.exe が存在し、実行可能ファイルとして有効かを確認
        （componentsVersion.json の存在で判定）
    #>
    hidden [bool] TestDockerDesktopExecutable([string]$dockerExe) {
        try {
            # componentsVersion.json が存在するか確認（Docker Desktop が正しくインストールされている証拠）
            $dockerDir = Split-Path -Parent $dockerExe
            $componentsFile = Join-Path $dockerDir "componentsVersion.json"
            if (Test-PathExist -Path $componentsFile) {
                return $true
            }

            # componentsVersion.json がなくても、exe が存在していれば OK（古いバージョン対応）
            # ファイルサイズが極端に小さい場合は壊れている可能性
            $fileInfo = Get-Item -LiteralPath $dockerExe -ErrorAction SilentlyContinue
            if ($fileInfo -and $fileInfo.Length -gt 1MB) {
                return $true
            }

            return $false
        } catch {
            return $false
        }
    }

    <#
    .SYNOPSIS
        Docker Desktop 連携を設定する
    #>
    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            $distroName = $ctx.DistroName

            # 最初に残留プロセスをクリーンアップ（Lingering processes対策）
            $this.StopLingeringDockerProcesses()

            # Docker Desktop を起動（WSL を正しく起動するために必要）
            $this.StartDockerDesktopIfNeeded()

            # WSL が書き込み可能になるまでリトライ
            if (-not $this.WaitForWslWritable($distroName)) {
                $this.LogWarning("WSL が書き込み不可のため、Docker Desktop 連携をスキップします")
                return $this.CreateSuccessResult("WSL が書き込み不可のためスキップしました")
            }

            # 空き容量チェック
            if (-not $this.TestWslFreeSpace($distroName)) {
                $this.LogWarning("WSL の空き容量が不足しているため、Docker Desktop 連携をスキップします")
                return $this.CreateSuccessResult("WSL の空き容量不足のためスキップしました")
            }

            # Docker Desktop のディストリビューション確認・作成
            $this.EnsureDockerDesktopDistros()

            # docker グループにユーザーを追加
            $this.EnsureDockerGroup($distroName)

            # Docker Desktop を起動（必要に応じて）
            $this.StartDockerDesktopIfNeeded()

            # Docker Desktop の健全性チェック
            if (-not $this.TestDockerDesktopHealth()) {
                $this.LogWarning("Docker Desktop 側の WSL ディストリビューションが壊れている可能性がありますが、連携の確認は続行します")
            }

            # 連携確認のリトライ
            $success = $this.RetryDockerIntegration($distroName)

            if ($success) {
                return $this.CreateSuccessResult("Docker Desktop 連携を確認しました")
            } else {
                return $this.CreateFailureResult("Docker Desktop 連携の確認に $($this.Retries) 回失敗しました")
            }
        } catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }

    <#
    .SYNOPSIS
        WSL が書き込み可能かテストする
    #>
    hidden [bool] TestWslWritable([string]$distroName) {
        # sh -c を使い NixOS の /etc/profile sourcing を避ける（Nix 環境初期化失敗対策）
        # `: > file` はシェルビルトインのみ使用、PATH 依存なし（NixOS-WSL 早期 boot 対応）
        # rm は PATH に無くても true でフォールバックするため cleanup 失敗でも exit 0 を維持
        $writableCheck = ': > /tmp/.wsl-write-test 2>/dev/null && { rm -f /tmp/.wsl-write-test 2>/dev/null; true; }'
        Invoke-Wsl "-d" $distroName "-u" "root" "--" "sh" "-c" $writableCheck
        return $LASTEXITCODE -eq 0
    }

    <#
    .SYNOPSIS
        WSL が書き込み可能になるまでバックオフ付きリトライする
    .DESCRIPTION
        以下のケースで WSL のファイルシステムが一時的に書き込み不可になることがある:
        - Docker プロセスの強制終了後
        - WslConfig による wsl --terminate 後 (NixOS-WSL は systemd 再起動に 20-60 秒かかる)
        段階的に待機時間を増やしながら最大 WslWritableMaxAttempts 回まで再試行する。
    #>
    hidden [bool] WaitForWslWritable([string]$distroName) {
        $maxAttempts = $this.WslWritableMaxAttempts
        $baseDelay = 3

        for ($i = 1; $i -le $maxAttempts; $i++) {
            if ($this.TestWslWritable($distroName)) {
                return $true
            }

            if ($i -lt $maxAttempts) {
                $delay = $baseDelay * $i
                $this.Log("WSL が書き込み不可。${delay} 秒後に再試行します ($i/$maxAttempts)")
                Start-SleepSafe -Seconds $delay
            }
        }

        return $false
    }

    <#
    .SYNOPSIS
        WSL の空き容量をチェックする
    #>
    hidden [bool] TestWslFreeSpace([string]$distroName) {
        $freeCheck = 'df -Pk / | awk ''NR==2 {print $4}'''
        $freeBlocks = Invoke-Wsl "-d" $distroName "-u" "root" "--" "sh" "-lc" $freeCheck | Select-Object -First 1

        if ($freeBlocks) {
            $freeBlocks = $freeBlocks.Trim()
            $freeValue = 0
            if ([int]::TryParse($freeBlocks, [ref]$freeValue) -and $freeValue -lt 10240) {
                return $false
            }
        }
        return $true
    }

    <#
    .SYNOPSIS
        Docker Desktop のディストリビューションを確認・作成する
    #>
    hidden [void] EnsureDockerDesktopDistros() {
        $dockerExe = $this.GetDockerDesktopPath()
        if (-not (Test-PathExist -Path $dockerExe)) {
            return
        }

        # 既存のディストリビューションを確認
        $list = Invoke-Wsl -l -q 2>$null
        $names = @()
        if ($list) {
            $names = $list | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        }

        if ($names -contains "docker-desktop" -and $names -contains "docker-desktop-data") {
            return
        }

        # Docker Desktop のリソースを確認
        $resourceRoot = Join-Path $env:ProgramFiles "Docker\Docker\resources\wsl"
        $vhdTemplate = Join-Path $resourceRoot "ext4.vhdx"
        $dataTar = Join-Path $resourceRoot "wsl-data.tar"

        if (-not (Test-PathExist -Path $vhdTemplate) -or -not (Test-PathExist -Path $dataTar)) {
            $this.LogWarning("Docker Desktop の WSL リソースが見つからないため、ディストリビューションの作成をスキップします")
            return
        }

        # ディレクトリ作成
        $root = Join-Path $env:LOCALAPPDATA "Docker\wsl"
        $distroDir = Join-Path $root "distro"
        $dataDir = Join-Path $root "data"
        New-DirectorySafe -Path $distroDir
        New-DirectorySafe -Path $dataDir

        # docker-desktop ディストリビューションを作成
        $distroVhd = Join-Path $distroDir "ext4.vhdx"
        Copy-FileSafe -Source $vhdTemplate -Destination $distroVhd -Force

        $this.Log("docker-desktop ディストリビューションを登録します")
        Invoke-Wsl --import-in-place docker-desktop $distroVhd

        # docker-desktop-data ディストリビューションを作成
        $this.Log("docker-desktop-data ディストリビューションを登録します")
        Invoke-Wsl --import docker-desktop-data $dataDir $dataTar --version 2
    }

    <#
    .SYNOPSIS
        ユーザーを docker グループに追加する
    #>
    hidden [void] EnsureDockerGroup([string]$distroName) {
        $user = $this.GetWslDefaultUser($distroName)
        Invoke-Wsl "-d" $distroName "-u" "root" "--" "sh" "-lc" "( groupadd docker 2>/dev/null || true ) && usermod -aG docker $user"
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
        Docker Desktop を起動する（まだ起動していない場合）
    #>
    hidden [void] StartDockerDesktopIfNeeded() {
        $running = Get-ProcessSafe -Name "Docker Desktop"
        if (-not $running) {
            $running = Get-ProcessSafe -Name "com.docker.backend"
        }

        if ($running) {
            return
        }

        $dockerExe = $this.GetDockerDesktopPath()
        if (-not (Test-PathExist -Path $dockerExe)) {
            return
        }

        # 起動前に残留プロセスをクリーンアップ（Lingering processes対策）
        $this.StopLingeringDockerProcesses()

        $this.Log("Docker Desktop を起動します")
        Start-ProcessSafe -FilePath $dockerExe
        Start-SleepSafe -Seconds 5
    }

    <#
    .SYNOPSIS
        Docker Desktop を再起動する
    #>
    hidden [void] RestartDockerDesktop() {
        # Docker 関連プロセスが1つでも動いているかチェック
        $anyRunning = $this.HasAnyDockerProcess()

        if (-not $anyRunning) {
            return
        }

        $this.Log("Docker Desktop を再起動します")

        # Docker 関連のすべてのプロセスを終了
        $this.StopAllDockerProcesses()

        Start-SleepSafe -Seconds 5

        $this.StartDockerDesktopIfNeeded()
        Start-SleepSafe -Seconds 10
    }

    <#
    .SYNOPSIS
        Docker 関連プロセスが1つでも動いているかチェックする
    #>
    hidden [bool] HasAnyDockerProcess() {
        $dockerProcessNames = @(
            "Docker Desktop",
            "com.docker.backend",
            "com.docker.build",
            "com.docker.dev-envs",
            "com.docker.extensions",
            "com.docker.proxy",
            "com.docker.service"
        )

        foreach ($processName in $dockerProcessNames) {
            $process = Get-ProcessSafe -Name $processName
            if ($process) {
                return $true
            }
        }
        return $false
    }

    <#
    .SYNOPSIS
        残留しているDockerプロセスを終了する（起動前のクリーンアップ）
    .DESCRIPTION
        Docker Desktop が不完全な状態で残っている場合、すべてのDockerプロセスを
        終了してクリーンな状態から起動できるようにする。
        「Lingering processes detected」エラーを防ぐため、残留プロセスだけでなく
        Docker Desktop本体も終了させて完全にリセットする。
    #>
    hidden [void] StopLingeringDockerProcesses() {
        # 残留プロセス（Docker Desktop本体なしで動いているプロセス）をチェック
        $lingeringProcessNames = @(
            "com.docker.build",
            "com.docker.dev-envs",
            "com.docker.extensions",
            "com.docker.proxy",
            "com.docker.service"
        )

        $hasLingering = $false
        foreach ($processName in $lingeringProcessNames) {
            $process = Get-ProcessSafe -Name $processName
            if ($process) {
                $hasLingering = $true
                break
            }
        }

        if (-not $hasLingering) {
            return
        }

        $this.Log("残留Dockerプロセスを検出しました。クリーンアップを実行します", "Yellow")

        # Docker関連のすべてのプロセスを終了（完全リセット）
        $allDockerProcessNames = @(
            "Docker Desktop",
            "com.docker.backend",
            "com.docker.build",
            "com.docker.dev-envs",
            "com.docker.extensions",
            "com.docker.proxy",
            "com.docker.service"
        )

        foreach ($processName in $allDockerProcessNames) {
            $process = Get-ProcessSafe -Name $processName
            if ($process) {
                $this.Log("プロセスを終了します: $processName", "Gray")
                Stop-Process -Name $processName -Force -ErrorAction SilentlyContinue
            }
        }

        # プロセス終了を待機
        Start-SleepSafe -Seconds 3

        # まだ残っているプロセスを再度強制終了
        foreach ($processName in $allDockerProcessNames) {
            $process = Get-ProcessSafe -Name $processName
            if ($process) {
                $this.Log("プロセスを強制終了します: $processName", "Yellow")
                Stop-Process -Name $processName -Force -ErrorAction SilentlyContinue
            }
        }

        Start-SleepSafe -Seconds 2
        $this.Log("Dockerプロセスのクリーンアップが完了しました", "Green")
    }

    <#
    .SYNOPSIS
        Docker 関連のすべてのプロセスを終了する
    #>
    hidden [void] StopAllDockerProcesses() {
        # Docker 関連のプロセス名リスト
        $dockerProcessNames = @(
            "Docker Desktop",
            "com.docker.backend",
            "com.docker.build",
            "com.docker.dev-envs",
            "com.docker.extensions",
            "com.docker.proxy",
            "com.docker.service"
        )

        foreach ($processName in $dockerProcessNames) {
            $process = Get-ProcessSafe -Name $processName
            if ($process) {
                $this.Log("プロセスを終了します: $processName", "Gray")
                Stop-ProcessSafe -Name $processName
            }
        }

        # 少し待ってからまだ残っているプロセスを強制終了
        Start-SleepSafe -Seconds 2

        foreach ($processName in $dockerProcessNames) {
            $process = Get-ProcessSafe -Name $processName
            if ($process) {
                $this.Log("プロセスを強制終了します: $processName", "Yellow")
                Stop-Process -Name $processName -Force -ErrorAction SilentlyContinue
            }
        }
    }

    <#
    .SYNOPSIS
        Docker Desktop の健全性をチェックする
    #>
    hidden [bool] TestDockerDesktopHealth() {
        Invoke-Wsl "-d" "docker-desktop" "-u" "root" "--" "sh" "-lc" "test -f /opt/docker-desktop/componentsVersion.json"
        return $LASTEXITCODE -eq 0
    }

    <#
    .SYNOPSIS
        Docker Desktop プロキシの接続をテストする
    #>
    hidden [bool] TestDockerDesktopProxy([string]$distroName) {
        $existsCmd = "[ -x /mnt/wsl/docker-desktop/docker-desktop-user-distro ]"
        Invoke-Wsl "-d" $distroName "-u" "root" "--" "sh" "-lc" $existsCmd
        if ($LASTEXITCODE -ne 0) {
            return $false
        }

        $proxyCmd = "timeout 3 /mnt/wsl/docker-desktop/docker-desktop-user-distro proxy --distro-name nixos --docker-desktop-root /mnt/wsl/docker-desktop 'C:\Program Files\Docker\Docker\resources'"
        Invoke-Wsl "-d" $distroName "-u" "root" "--" "sh" "-lc" $proxyCmd

        # exit code 0 (成功) または 124 (timeout) は OK
        return ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 124)
    }

    <#
    .SYNOPSIS
        Docker Desktop 連携をリトライする
    #>
    hidden [bool] RetryDockerIntegration([string]$distroName) {
        $restarted = $false

        for ($i = 1; $i -le $this.Retries; $i++) {
            $this.Log("Docker Desktop 連携の確認を試行します ($i/$($this.Retries))...")

            $this.StartDockerDesktopIfNeeded()

            if ($this.TestDockerDesktopProxy($distroName)) {
                $this.Log("Docker Desktop 連携の確認に成功しました", "Green")
                return $true
            }

            $this.LogWarning("Docker Desktop 連携の確認に失敗しました。WSL を再起動して再試行します")

            if (-not $restarted) {
                # wsl --shutdown は Docker Desktop 以外のディストリビューション（NixOS 等）を
                # 破壊する可能性があるため、docker-desktop のみ terminate する
                Invoke-Wsl --terminate docker-desktop 2>$null
                $this.RestartDockerDesktop()
                $restarted = $true
            }

            Start-SleepSafe -Seconds $this.RetryDelaySeconds
        }

        return $false
    }

    <#
    .SYNOPSIS
        Docker Desktop の実行ファイルパスを取得する
    #>
    hidden [string] GetDockerDesktopPath() {
        return Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe"
    }
}
