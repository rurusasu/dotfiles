<#
.SYNOPSIS
    OpenClaw Docker コンテナを管理するハンドラー

.DESCRIPTION
    - chezmoi で生成された設定ファイルの確認
    - .env ファイルの自動生成（存在しない場合）
    - docker compose で OpenClaw コンテナをビルド・起動
    - コンテナの起動確認

.NOTES
    Order = 120 (Chezmoi の後に実行)
    前提: docker が利用可能であること
#>

$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class OpenClawHandler : SetupHandlerBase {
    # コンテナ起動待機設定
    [int]$StartupRetries = 12
    [int]$StartupRetryDelaySeconds = 5
    # docker compose up リトライ設定（Docker 起動直後の一時的な失敗への対策）
    [int]$ComposeRetries = 2
    [int]$ComposeRetryDelaySeconds = 10

    OpenClawHandler() {
        $this.Name = "OpenClaw"
        $this.Description = "OpenClaw Telegram AI ゲートウェイの起動"
        $this.Order = 120
        $this.RequiresAdmin = $false
    }

    <#
    .SYNOPSIS
        実行可否を判定する
    .DESCRIPTION
        以下の条件をチェック:
        - docker コマンドが利用可能か
        - docker-compose.yml が存在するか
    #>
    [bool] CanApply([SetupContext]$ctx) {
        $this.StartupRetries = $ctx.GetOption("OpenClawStartupRetries", 12)
        $this.StartupRetryDelaySeconds = $ctx.GetOption("OpenClawStartupRetryDelaySeconds", 5)
        $this.ComposeRetries = $ctx.GetOption("OpenClawComposeRetries", 2)
        $this.ComposeRetryDelaySeconds = $ctx.GetOption("OpenClawComposeRetryDelaySeconds", 10)

        $dockerCmd = Get-ExternalCommand -Name "docker"
        if (-not $dockerCmd) {
            $this.Log("docker が見つかりません", "Gray")
            return $false
        }

        $composeFile = $this.GetComposeFilePath($ctx)
        if (-not (Test-PathExist -Path $composeFile)) {
            $this.Log("docker-compose.yml が見つかりません: $composeFile", "Gray")
            return $false
        }

        # op (1Password CLI) が必要（openclaw.docker.json の生成に使用）
        $opCmd = Get-ExternalCommand -Name "op"
        if (-not $opCmd) {
            $this.Log("op (1Password CLI) が見つかりません。OpenClaw をスキップします", "Gray")
            return $false
        }

        return $true
    }

    <#
    .SYNOPSIS
        OpenClaw コンテナを起動する
    #>
    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            # .env ファイルの確認・生成
            $this.EnsureEnvFile($ctx)

            # 設定ファイルの存在確認
            $configFile = $this.GetConfigFilePath()
            if (-not (Test-PathExist -Path $configFile)) {
                $this.LogWarning("openclaw.docker.json が見つかりません: $configFile")
                $this.Log("chezmoi apply を実行して設定ファイルを生成します")
                Invoke-Chezmoi "apply" "--source" (Join-Path $ctx.DotfilesPath "chezmoi")
                if ($LASTEXITCODE -ne 0) {
                    return $this.CreateFailureResult("chezmoi apply に失敗しました")
                }
            }

            # コンテナを起動（--build で最新イメージを使用）
            # docker compose はビルド進捗を stderr に出力するため NativeCommandError が発生するが
            # 終了コードが 0 であれば成功として扱う
            # Docker 起動直後の一時的な失敗に備えてリトライする
            $composeFile = $this.GetComposeFilePath($ctx)
            $this.Log("OpenClaw コンテナを起動します (--build)")
            for ($attempt = 1; $attempt -le $this.ComposeRetries; $attempt++) {
                try {
                    Invoke-Docker "compose" "-f" $composeFile "up" "-d" "--build"
                } catch {
                    # NativeCommandError (docker compose build progress → stderr) は無視
                }
                if ($LASTEXITCODE -eq 0) { break }
                if ($attempt -lt $this.ComposeRetries) {
                    $this.LogWarning("docker compose up に失敗しました (exit: $LASTEXITCODE)、再試行します... ($attempt/$($this.ComposeRetries))")
                    Start-SleepSafe -Seconds $this.ComposeRetryDelaySeconds
                }
            }
            if ($LASTEXITCODE -ne 0) {
                return $this.CreateFailureResult("docker compose up に失敗しました (exit: $LASTEXITCODE)")
            }

            # コンテナ起動の確認
            if ($this.WaitForContainer()) {
                return $this.CreateSuccessResult("OpenClaw コンテナを起動しました")
            } else {
                return $this.CreateFailureResult("コンテナの起動確認がタイムアウトしました ($($this.StartupRetries * $this.StartupRetryDelaySeconds)秒)")
            }
        } catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }

    <#
    .SYNOPSIS
        .env ファイルを確認・生成する
    .DESCRIPTION
        .env が存在しない場合、USERPROFILE パスを使ったデフォルト値で生成する
    #>
    hidden [void] EnsureEnvFile([SetupContext]$ctx) {
        $composeDir = $this.GetComposeDir($ctx)
        $envFile = Join-Path $composeDir ".env"

        if (Test-PathExist -Path $envFile) {
            $this.Log(".env ファイルが存在します: $envFile", "Gray")
            return
        }

        # 1Password から GITHUB_TOKEN を取得（未設定・サインアウト時は空文字）
        $githubToken = ""
        $opCmd = Get-ExternalCommand -Name "op"
        if ($opCmd) {
            try {
                $result = & op read "op://Personal/GitHubUsedOpenClawPAT/credential" 2>&1
                if ($LASTEXITCODE -eq 0) { $githubToken = ($result | Out-String).Trim() }
            } catch { }
        }

        $configPath = ($this.GetConfigFilePath() -replace '\\', '/')
        $envContent = @"
OPENCLAW_PORT=18789
OPENCLAW_UID=1000
OPENCLAW_GID=1000
OPENCLAW_CONFIG_FILE=$configPath
TZ=Asia/Tokyo
GITHUB_TOKEN=$githubToken
"@
        $this.Log(".env ファイルを生成します: $envFile")
        Set-ContentNoNewline -Path $envFile -Value $envContent
    }

    <#
    .SYNOPSIS
        コンテナが起動するまで待機する
    #>
    hidden [bool] WaitForContainer() {
        for ($i = 1; $i -le $this.StartupRetries; $i++) {
            $this.Log("コンテナ起動を確認中... ($i/$($this.StartupRetries))")
            $status = Invoke-Docker "ps" "--filter" "name=openclaw" "--filter" "status=running" "--format" "{{.Names}}"
            if ($status -match "openclaw") {
                $this.Log("コンテナが起動しました", "Green")
                return $true
            }
            Start-SleepSafe -Seconds $this.StartupRetryDelaySeconds
        }
        return $false
    }

    <#
    .SYNOPSIS
        docker-compose.yml のパスを返す
    #>
    hidden [string] GetComposeFilePath([SetupContext]$ctx) {
        return Join-Path $ctx.DotfilesPath "docker\openclaw\docker-compose.yml"
    }

    <#
    .SYNOPSIS
        docker-compose.yml の親ディレクトリを返す
    #>
    hidden [string] GetComposeDir([SetupContext]$ctx) {
        return Join-Path $ctx.DotfilesPath "docker\openclaw"
    }

    <#
    .SYNOPSIS
        openclaw.docker.json のパスを返す
    #>
    hidden [string] GetConfigFilePath() {
        $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
        return Join-Path $homeDir ".openclaw\openclaw.docker.json"
    }
}
