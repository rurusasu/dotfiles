<#
.SYNOPSIS
    OpenClaw Docker コンテナを管理するハンドラー

.DESCRIPTION
    - chezmoi で生成された設定ファイルの確認
    - .env ファイルの自動生成（存在しない場合）
    - 1Password から GitHub PAT を取得して Docker secret 一時ファイルを生成
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

        return $true
    }

    <#
    .SYNOPSIS
        OpenClaw コンテナを起動する
    #>
    [SetupResult] Apply([SetupContext]$ctx) {
        $originalGitHubToken = $env:GITHUB_TOKEN
        $originalXaiApiKey = $env:XAI_API_KEY

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

            # GitHub token を環境変数で注入（ディスクに書き込まない）
            $env:GITHUB_TOKEN = $this.ResolveGitHubToken()

            # xAI API key を環境変数で注入（Grok x_search 用）
            $env:XAI_API_KEY = $this.ResolveOpSecret("op://Personal/xAI-Grok-Twitter/console/apikey", "XAI_API_KEY")

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
            if (-not $this.WaitForContainer()) {
                return $this.CreateFailureResult("コンテナの起動確認がタイムアウトしました ($($this.StartupRetries * $this.StartupRetryDelaySeconds)秒)")
            }

            # cron ジョブのシード（新規 volume の場合のみ）
            $this.SeedCronJobs()

            return $this.CreateSuccessResult("OpenClaw コンテナを起動しました")
        } catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        } finally {
            if ($null -ne $originalGitHubToken) {
                $env:GITHUB_TOKEN = $originalGitHubToken
            } else {
                Remove-Item -Path Env:\GITHUB_TOKEN -ErrorAction SilentlyContinue
            }
            if ($null -ne $originalXaiApiKey) {
                $env:XAI_API_KEY = $originalXaiApiKey
            } else {
                Remove-Item -Path Env:\XAI_API_KEY -ErrorAction SilentlyContinue
            }
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

        $configPath = ($this.GetConfigFilePath() -replace '\\', '/')
        $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
        $geminiCredentialsDir = ((Join-Path $homeDir ".gemini") -replace '\\', '/')
        $claudeCredentialsDir = ((Join-Path $homeDir ".claude") -replace '\\', '/')
        $claudeConfigJson = ((Join-Path $homeDir ".claude.json") -replace '\\', '/')
        $envContent = @"
OPENCLAW_PORT=18789
OPENCLAW_UID=1000
OPENCLAW_GID=1000
OPENCLAW_CONFIG_FILE=$configPath
TZ=Asia/Tokyo
GEMINI_CREDENTIALS_DIR=$geminiCredentialsDir
CLAUDE_CREDENTIALS_DIR=$claudeCredentialsDir
CLAUDE_CONFIG_JSON=$claudeConfigJson
"@
        $this.Log(".env ファイルを生成します: $envFile")
        Set-ContentNoNewline -Path $envFile -Value $envContent
    }

    <#
    .SYNOPSIS
        GitHub token を取得する（ディスクに書き込まない）
    .DESCRIPTION
        1Password が利用可能なら op read を優先し、未取得時は OPENCLAW_GITHUB_TOKEN 環境変数をフォールバックする。
        取得したトークンは呼び出し元で GITHUB_TOKEN 環境変数にセットし、docker compose が環境変数経由でコンテナに注入する。
    #>
    hidden [string] ResolveGitHubToken() {
        $githubToken = ""
        $opCmd = Get-ExternalCommand -Name "op"
        if ($opCmd) {
            try {
                $result = & op read "op://Personal/GitHubUsedOpenClawPAT/credential" 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $githubToken = ($result | Out-String).Trim()
                } else {
                    $this.Log("op read に失敗しました。OPENCLAW_GITHUB_TOKEN を確認します", "Yellow")
                }
            } catch {
                $this.Log("op read で例外が発生しました。OPENCLAW_GITHUB_TOKEN を確認します", "Yellow")
            }
        } else {
            $this.Log("op (1Password CLI) が見つかりません。OPENCLAW_GITHUB_TOKEN を確認します", "Yellow")
        }

        if ([string]::IsNullOrWhiteSpace($githubToken)) {
            $githubToken = [string]$env:OPENCLAW_GITHUB_TOKEN
        }
        if ([string]::IsNullOrWhiteSpace($githubToken)) {
            $this.LogWarning("GitHub token が未取得です。GitHub 連携が必要な操作は失敗する可能性があります")
        }

        return $githubToken
    }

    <#
    .SYNOPSIS
        1Password からシークレットを取得する（汎用）
    .DESCRIPTION
        op read でシークレットを取得する。失敗時は空文字を返し警告を出す。
    #>
    hidden [string] ResolveOpSecret([string]$opRef, [string]$label) {
        $opCmd = Get-ExternalCommand -Name "op"
        if ($opCmd) {
            try {
                $result = & op read $opRef 2>&1
                if ($LASTEXITCODE -eq 0) {
                    return ($result | Out-String).Trim()
                } else {
                    $this.LogWarning("$label の取得に失敗しました (op read)")
                }
            } catch {
                $this.LogWarning("$label の取得で例外が発生しました")
            }
        }
        return ""
    }

    <#
    .SYNOPSIS
        cron/jobs.json が存在しない場合にシードファイルをコピーする
    .DESCRIPTION
        新規セットアップや volume 再作成後、chezmoi が展開した
        ~/.openclaw/cron/jobs.seed.json をコンテナ内に投入してリスタートする。
        jobs.json がすでに存在する場合は何もしない。
    #>
    hidden [void] SeedCronJobs() {
        $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
        $seedFile = Join-Path $homeDir ".openclaw\cron\jobs.seed.json"

        if (-not (Test-PathExist -Path $seedFile)) {
            $this.Log("cron seed ファイルが見つかりません: $seedFile", "Gray")
            return
        }

        # コンテナ内に jobs.json がすでに存在するか確認
        $existing = Invoke-Docker "exec" "openclaw" "//bin/sh" "-c" "test -f //home/bun/.openclaw/cron/jobs.json && echo exists"
        if ($existing -match "exists") {
            $this.Log("cron/jobs.json はすでに存在します。シードをスキップします", "Gray")
            return
        }

        $this.Log("cron/jobs.json が存在しません。シードファイルをコピーします")
        Invoke-Docker "exec" "openclaw" "//bin/sh" "-c" "mkdir -p //home/bun/.openclaw/cron"
        Invoke-Docker "cp" ($seedFile -replace '\\', '/') "openclaw://home/bun/.openclaw/cron/jobs.json"
        if ($LASTEXITCODE -ne 0) {
            $this.LogWarning("cron seed のコピーに失敗しました")
            return
        }

        $this.Log("cron seed をコピーしました。コンテナを再起動します")
        Invoke-Docker "restart" "openclaw"
        $this.WaitForContainer() | Out-Null
        $this.Log("cron ジョブを復元しました", "Green")
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
