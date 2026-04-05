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
    # NixOS-WSL (systemd) は wsl --terminate 後の再起動に 20-120 秒かかるため
    # デフォルト 15 回 (最大待機: 3+6+9+...+42 = 315 秒)
    [int]$WslWritableMaxAttempts = 15

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
        $this.WslWritableMaxAttempts = $ctx.GetOption("WslWritableMaxAttempts", 15)

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

        # WSL が利用可能か確認
        if (-not (Test-WslAvailable)) {
            $this.Log("WSL が利用できないためスキップします", "Gray")
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

            # Docker プロセス停止前に WSL が安定している状態で確認する。
            # StopLingeringDockerProcesses の後では WSL が一時的に不安定になり
            # wsl -l -q が空を返してディストリビューションを見逃すことがある。
            $nixosRegistered = $this.TestWslDistroExists($distroName)

            # 残留プロセスをクリーンアップ（Lingering processes対策）
            $hadLingering = $this.StopLingeringDockerProcesses()

            if ($hadLingering) {
                # Docker プロセス強制終了後、WSL の接続が安定するまで待機する。
                # Docker backend が WSL との接続を保持していた場合、
                # 強制終了直後は WSL が不安定な状態になる可能性がある。
                $this.Log("Docker プロセス終了後、WSL が安定するまで待機します...", "Gray")
                Start-SleepSafe -Seconds 30
            }

            if ($nixosRegistered) {
                # NixOS への操作は Docker Desktop 起動より先に行う。
                # Docker Desktop の初期化が wsl --shutdown を呼ぶ場合があり、
                # その後に書き込みチェックをすると NixOS 再起動待ちになるため。
                if (-not $this.WaitForWslWritable($distroName)) {
                    $this.LogWarning("WSL が書き込み不可のため、NixOS 連携をスキップします")
                    $this.StartDockerDesktopIfNeeded()
                    $this.EnsureDockerDesktopDistros()
                    $this.StartDockerDesktopIfNeeded()
                    return $this.CreateSuccessResult("WSL が書き込み不可のため NixOS 連携をスキップしました")
                }

                # 空き容量チェック
                if (-not $this.TestWslFreeSpace($distroName)) {
                    $this.LogWarning("WSL の空き容量が不足しているため、NixOS 連携をスキップします")
                    $this.StartDockerDesktopIfNeeded()
                    $this.EnsureDockerDesktopDistros()
                    $this.StartDockerDesktopIfNeeded()
                    return $this.CreateSuccessResult("WSL の空き容量不足のため NixOS 連携をスキップしました")
                }

                # docker グループにユーザーを追加（NixOS が起動している今のうちに実施）
                $this.EnsureDockerGroup($distroName)
            } else {
                $this.Log("$distroName が WSL に登録されていません。NixOS 連携をスキップします", "Gray")
            }

            # NixOS の有無に関わらず Docker Desktop を起動する
            $this.StartDockerDesktopIfNeeded()

            # Docker Desktop のディストリビューション確認・作成
            $this.EnsureDockerDesktopDistros()

            # Docker Desktop を起動（必要に応じて）
            $this.StartDockerDesktopIfNeeded()

            if (-not $nixosRegistered) {
                return $this.CreateSuccessResult("Docker Desktop を起動しました（NixOS 連携なし）")
            }

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
        指定された WSL ディストリビューションが登録されているか確認する
    .DESCRIPTION
        wsl -l -q の出力を解析する。
        Windows WSL の出力は null バイトを含む場合があるため除去する。
    #>
    hidden [bool] TestWslDistroExists([string]$distroName) {
        $distros = Invoke-Wsl "-l" "-q" 2>$null
        if (-not $distros) { return $false }
        $distroExists = $distros | Where-Object {
            ($_ -replace "`0", '' -replace [char]0xFEFF, '').Trim() -eq $distroName
        }
        return [bool]$distroExists
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

        # 全試行失敗後の診断: ディストリビューションが起動しているか確認
        Invoke-Wsl "-d" $distroName "-u" "root" "--" "true" | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $this.Log("診断: '$distroName' は起動していますが /tmp が書き込み不可です。NixOS の systemd 設定を確認してください", "Yellow")
        } else {
            $this.Log("診断: '$distroName' が起動しないか、コマンドを受け付けません (終了コード: $LASTEXITCODE)", "Yellow")
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
        # WSL の出力は null バイトを含む場合があるため TestWslDistroExists と同様に除去する
        $list = Invoke-Wsl -l -q 2>$null
        $names = @()
        if ($list) {
            $names = $list | ForEach-Object { ($_ -replace "`0", '' -replace [char]0xFEFF, '').Trim() } | Where-Object { $_ }
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

        # StopLingeringDockerProcesses による強制終了後、Docker Desktop が
        # WSL cross-distro 共有の docker-desktop-user-distro を 0 バイトで
        # 残すことがある。修復しないと NixOS WSL integration が永続的に失敗する。
        $this.RepairWslProxyBinary()
    }

    <#
    .SYNOPSIS
        WSL cross-distro 共有の docker-desktop-user-distro バイナリを修復する
    .DESCRIPTION
        /mnt/wsl/docker-desktop/docker-desktop-user-distro が 0 バイトの場合、
        docker-desktop distro 内のオリジナルバイナリからコピーして修復する。
    #>
    hidden [void] RepairWslProxyBinary() {
        $proxyPath = "/mnt/wsl/docker-desktop/docker-desktop-user-distro"
        $checkResult = Invoke-Wsl -d "docker-desktop" "--" "stat" "-c" "%s" $proxyPath 2>$null
        if ($LASTEXITCODE -ne 0) { return }

        $size = 0
        if ($checkResult -and [int]::TryParse($checkResult.Trim(), [ref]$size) -and $size -gt 0) {
            return
        }

        $this.LogWarning("docker-desktop-user-distro が 0 バイトです。修復します")
        $sharedPath = "/mnt/host/wsl/docker-desktop/docker-desktop-user-distro"
        Invoke-Wsl -d "docker-desktop" "--" "cp" "/docker-desktop-user-distro" $sharedPath 2>$null
        Invoke-Wsl -d "docker-desktop" "--" "chmod" "+x" $sharedPath 2>$null

        if ($LASTEXITCODE -eq 0) {
            $this.Log("docker-desktop-user-distro を修復しました", "Green")
        } else {
            $this.LogWarning("docker-desktop-user-distro の修復に失敗しました")
        }
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
    hidden [bool] StopLingeringDockerProcesses() {
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
            return $false
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
        return $true
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
        if (-not $this.TestWslDistroExists("docker-desktop")) {
            return $false
        }
        # Docker Desktop のリソースは Windows 側にマウントされている
        # docker-desktop distro では Windows C: ドライブが
        # /tmp/docker-desktop-root/mnt/host/<drive>/ にマウントされている（実機確認済み）
        $dockerPath = $this.GetDockerDesktopPath()
        $driveLetter = $dockerPath.Substring(0, 1).ToLower()
        if (-not [char]::IsLetter($driveLetter)) {
            $this.Log("Docker Desktop パスからドライブレターを取得できません: $dockerPath", "Gray")
            return $false
        }
        $checkCmd = "test -f '/tmp/docker-desktop-root/mnt/host/$driveLetter/Program Files/Docker/Docker/resources/componentsVersion.json'"
        Invoke-Wsl "-d" "docker-desktop" "-u" "root" "--" "sh" "-c" $checkCmd
        return $LASTEXITCODE -eq 0
    }

    <#
    .SYNOPSIS
        docker-desktop distro から共有 /mnt/wsl/ へ bind mount を設定する
    .DESCRIPTION
        Docker Desktop の Windows backend が NixOS の systemd mount namespace に
        bind mount できない場合の workaround。
        docker-desktop distro の /mnt/host/wsl は NixOS の /mnt/wsl と同じ
        shared:1 peer group なので、docker-desktop 側で bind mount すると NixOS に伝播する。
    #>
    hidden [void] SetupDockerBindMounts() {
        if (-not $this.TestWslDistroExists("docker-desktop")) {
            $this.Log("docker-desktop distro が見つからないため bind mount をスキップします", "Gray")
            return
        }

        # バイナリが実行可能かつソケットディレクトリが bind mount 済みか確認
        # ソケットファイル自体は Docker Desktop 初期化タイミングで現れるため、
        # ディレクトリが mountpoint かどうかで判定する
        $checkCmd = "[ -x /mnt/host/wsl/docker-desktop/docker-desktop-user-distro ] && mountpoint -q /mnt/host/wsl/docker-desktop/shared-sockets/guest-services"
        Invoke-Wsl "-d" "docker-desktop" "-u" "root" "--" "sh" "-c" $checkCmd 2>$null
        if ($LASTEXITCODE -eq 0) {
            $this.Log("docker-desktop bind mount は既に設定済みです", "Gray")
            return
        }

        $this.Log("docker-desktop bind mount を設定します...")
        # マウント先ディレクトリが存在しない場合に備えて mkdir -p を先行実行する
        # docker-desktop-user-distro はファイルの bind mount なので touch でマウント先を確保する
        $mountCmd = @(
            "mkdir -p /mnt/host/wsl/docker-desktop/shared-sockets/guest-services",
            "touch /mnt/host/wsl/docker-desktop/docker-desktop-user-distro 2>/dev/null",
            "mount --bind /docker-desktop-user-distro /mnt/host/wsl/docker-desktop/docker-desktop-user-distro 2>/dev/null",
            "mount --bind /run/guest-services /mnt/host/wsl/docker-desktop/shared-sockets/guest-services 2>/dev/null"
        ) -join " ; "
        Invoke-Wsl "-d" "docker-desktop" "-u" "root" "--" "sh" "-c" $mountCmd 2>$null

        # ソースファイルの実行ビット有無に依らず bind mount の有無で成否を判定する
        $verifyCmd = "mountpoint -q /mnt/host/wsl/docker-desktop/docker-desktop-user-distro"
        Invoke-Wsl "-d" "docker-desktop" "-u" "root" "--" "sh" "-c" $verifyCmd 2>$null
        if ($LASTEXITCODE -eq 0) {
            $this.Log("docker-desktop bind mount を設定しました", "Green")
        }
        else {
            $this.Log("docker-desktop bind mount の設定に失敗しました（Docker Desktop が管理する可能性あり）", "Gray")
        }
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

        $proxyCmd = "timeout 3 /mnt/wsl/docker-desktop/docker-desktop-user-distro proxy --distro-name $distroName --docker-desktop-root /mnt/wsl/docker-desktop 'C:\Program Files\Docker\Docker\resources'"
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

            # docker-desktop distro の bind mount を確認・設定する
            # Docker Desktop の Windows backend が NixOS に bind mount できない場合の workaround
            # 初回・再起動後ともに Docker Desktop の初期化と競合しないよう RetryDelaySeconds 待機する
            Start-SleepSafe -Seconds $this.RetryDelaySeconds
            $this.SetupDockerBindMounts()

            if ($this.TestDockerDesktopProxy($distroName)) {
                $this.Log("Docker Desktop 連携の確認に成功しました", "Green")
                return $true
            }

            if (-not $restarted) {
                $this.LogWarning("Docker Desktop 連携の確認に失敗しました。WSL を再起動して再試行します")
                # wsl --shutdown は Docker Desktop 以外のディストリビューション（NixOS 等）を
                # 破壊する可能性があるため、docker-desktop のみ terminate する
                Invoke-Wsl --terminate docker-desktop 2>$null
                $this.RestartDockerDesktop()
                $restarted = $true
                # RestartDockerDesktop 内の sleep 後、次のループ先頭で RetryDelaySeconds 待機する
            }
            elseif ($i -lt $this.Retries) {
                # 再起動後の再試行: ループ先頭の sleep 前にログのみ出力
                $this.LogWarning("Docker Desktop 連携の確認に失敗しました。再試行します")
            }
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
