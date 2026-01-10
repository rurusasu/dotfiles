<#
.SYNOPSIS
    Docker Desktop と WSL の連携を管理するハンドラー

.DESCRIPTION
    - Docker Desktop のインストール確認
    - docker-desktop / docker-desktop-data ディストリビューションの作成
    - WSL ディストリビューションとの連携確認
    - docker グループへのユーザー追加

.NOTES
    Order = 20 (WSL 依存処理)
    WslConfig の後、VscodeServer の前に実行
#>

# 依存ファイルの読み込み
$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\SetupHandler.ps1")
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class DockerHandler : SetupHandlerBase {
    # リトライ設定
    [int]$Retries = 5
    [int]$RetryDelaySeconds = 5

    DockerHandler() {
        $this.Name = "Docker"
        $this.Description = "Docker Desktop との WSL 連携"
        $this.Order = 20
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

        if ($this.Retries -le 0) {
            $this.Log("リトライ回数が 0 のためスキップします", "Gray")
            return $false
        }

        # Docker Desktop のインストール確認
        $dockerExe = $this.GetDockerDesktopPath()
        if (-not (Test-PathExists -Path $dockerExe)) {
            $this.Log("Docker Desktop がインストールされていません", "Gray")
            return $false
        }

        return $true
    }

    <#
    .SYNOPSIS
        Docker Desktop 連携を設定する
    #>
    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            $distroName = $ctx.DistroName

            # WSL が書き込み可能かチェック
            if (-not $this.TestWslWritable($distroName)) {
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
        $writableCheck = "touch /tmp/.wsl-write-test 2>/dev/null && rm -f /tmp/.wsl-write-test"
        Invoke-Wsl -d $distroName -u root -- sh -lc $writableCheck
        return $LASTEXITCODE -eq 0
    }

    <#
    .SYNOPSIS
        WSL の空き容量をチェックする
    #>
    hidden [bool] TestWslFreeSpace([string]$distroName) {
        $freeCheck = 'df -Pk / | awk ''NR==2 {print $4}'''
        $freeBlocks = Invoke-Wsl -d $distroName -u root -- sh -lc $freeCheck | Select-Object -First 1

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
        if (-not (Test-PathExists -Path $dockerExe)) {
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

        if (-not (Test-PathExists -Path $vhdTemplate) -or -not (Test-PathExists -Path $dataTar)) {
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
        Invoke-Wsl -d $distroName -u root -- sh -lc "( groupadd docker || true ) && usermod -aG docker $user"
    }

    <#
    .SYNOPSIS
        WSL のデフォルトユーザーを取得する
    #>
    hidden [string] GetWslDefaultUser([string]$distroName) {
        $user = Invoke-Wsl -d $distroName -- sh -lc "whoami" | Select-Object -First 1
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
        if (-not (Test-PathExists -Path $dockerExe)) {
            return
        }

        $this.Log("Docker Desktop を起動します")
        Start-ProcessSafe -FilePath $dockerExe
        Start-SleepSafe -Seconds 5
    }

    <#
    .SYNOPSIS
        Docker Desktop を再起動する
    #>
    hidden [void] RestartDockerDesktop() {
        $running = Get-ProcessSafe -Name "Docker Desktop"
        $backend = Get-ProcessSafe -Name "com.docker.backend"

        if (-not $running -and -not $backend) {
            return
        }

        $this.Log("Docker Desktop を再起動します")
        Stop-ProcessSafe -Name "Docker Desktop"
        Stop-ProcessSafe -Name "com.docker.backend"
        Start-SleepSafe -Seconds 5

        $this.StartDockerDesktopIfNeeded()
        Start-SleepSafe -Seconds 10
    }

    <#
    .SYNOPSIS
        Docker Desktop の健全性をチェックする
    #>
    hidden [bool] TestDockerDesktopHealth() {
        Invoke-Wsl -d docker-desktop -u root -- sh -lc "test -f /opt/docker-desktop/componentsVersion.json"
        return $LASTEXITCODE -eq 0
    }

    <#
    .SYNOPSIS
        Docker Desktop プロキシの接続をテストする
    #>
    hidden [bool] TestDockerDesktopProxy([string]$distroName) {
        $existsCmd = "[ -x /mnt/wsl/docker-desktop/docker-desktop-user-distro ]"
        Invoke-Wsl -d $distroName -u root -- sh -lc $existsCmd
        if ($LASTEXITCODE -ne 0) {
            return $false
        }

        $proxyCmd = "timeout 3 /mnt/wsl/docker-desktop/docker-desktop-user-distro proxy --distro-name nixos --docker-desktop-root /mnt/wsl/docker-desktop 'C:\Program Files\Docker\Docker\resources'"
        Invoke-Wsl -d $distroName -u root -- sh -lc $proxyCmd

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
                $this.RestartDockerDesktop()
                $restarted = $true
            }

            Invoke-Wsl --shutdown
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
