<#
.SYNOPSIS
    OpenClaw Docker コンテナを管理するハンドラー（対話確認 + インフラチェックの 2 層ゲート）

.DESCRIPTION
    install.cmd 実行時の 2 層ゲート:
      1. 対話確認 — 初回実行時にユーザーへ選択を求め、
         結果を ~/.config/dotfiles/consent.json に永続化。
         承認済みならプロンプトをスキップ、拒否済みならサイレントスキップ。
      2. インフラチェック — docker コマンド / docker-compose.yml / 設定ファイルの存在確認。
    両方をパスした場合のみセットアップを実行する。

    chezmoi apply 側は .chezmoidata/personal.yaml の openclaw_enabled と
    .chezmoiignore.tmpl で制御される（テンプレート展開用、consent とは独立）。

    処理内容:
    - .env ファイルの自動生成（存在しない場合）
    - 1Password からシークレットを取得して ~/.openclaw/secrets/ に永続化
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
        $this.Phase = 2
        $this.ConsentKey = "openclaw_enabled"
        $this.ConsentLabel = "OpenClaw — Telegram/Slack 連携 AI ボット"
    }

    <#
    .SYNOPSIS
        実行可否を判定する（2 層ゲート）
    .DESCRIPTION
        以下を順にチェックし、すべてパスした場合のみ $true を返す:
        1. 対話確認 — consent.json のフラグを確認。未設定ならスキップ。
        2. インフラチェック — 設定ファイル / docker / docker-compose.yml の存在。
    #>
    [bool] CanApply([SetupContext]$ctx) {
        $this.StartupRetries = $ctx.GetOption("OpenClawStartupRetries", 12)
        $this.StartupRetryDelaySeconds = $ctx.GetOption("OpenClawStartupRetryDelaySeconds", 5)
        $this.ComposeRetries = $ctx.GetOption("OpenClawComposeRetries", 2)
        $this.ComposeRetryDelaySeconds = $ctx.GetOption("OpenClawComposeRetryDelaySeconds", 10)

        # ── Layer 1: 同意フラグ確認 ──
        # Invoke-ConsentPrompt で事前に永続化済みのフラグを参照する
        $enabled = $this.ReadConsentFlag()
        if ($null -eq $enabled -or -not $enabled) {
            if ($null -eq $enabled) {
                $this.Log("未設定のためスキップします (install.cmd の同意プロンプトで有効化してください)", "Gray")
            } else {
                $this.Log("OpenClaw は無効です (consent.json)", "Gray")
            }
            return $false
        }

        # ── Layer 2: インフラチェック ──
        $configFile = $this.GetConfigFilePath()
        if (-not (Test-PathExist -Path $configFile)) {
            $this.Log("openclaw.docker.json が見つかりません — chezmoi apply を実行してください", "Yellow")
            return $false
        }

        $dockerCmd = Get-ExternalCommand -Name "docker"
        if (-not $dockerCmd) {
            $this.Log("docker が見つかりません", "Yellow")
            return $false
        }

        if (-not (Test-DockerDaemon)) {
            $this.Log("Docker デーモンに接続できません", "Yellow")
            return $false
        }

        $composeFile = $this.GetComposeFilePath($ctx)
        if (-not (Test-PathExist -Path $composeFile)) {
            $this.Log("docker-compose.yml が見つかりません: $composeFile", "Yellow")
            return $false
        }

        $this.Log("すべてのチェックをパスしました", "Green")
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

            # 設定ファイルの存在確認 (CanApply で検証済みだが念のため)
            $configFile = $this.GetConfigFilePath()
            if (-not (Test-PathExist -Path $configFile)) {
                return $this.CreateFailureResult("openclaw.docker.json が見つかりません。chezmoi apply を先に実行してください")
            }

            # 1Password からシークレットを取得し、永続ファイルに書き出す
            # ファイルは削除しない（docker compose が file: で参照し続けるため）
            $this.WriteSecretFile(
                "op://Personal/GitHubUsedOpenClawPAT/credential",
                "github_token",
                $true
            )
            $this.WriteSecretFile(
                "op://Personal/xAI-Grok-Twitter/console/apikey",
                "xai_api_key",
                $false
            )
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
                    $null = $_.Exception
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
        }
    }

    # ────────────────────────────────────────────────────────
    # .env / シークレット / Docker 操作
    # ────────────────────────────────────────────────────────

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
            # 既存 .env に必須変数が不足していれば追記
            $this.EnsureEnvVars($envFile, $ctx)
            return
        }

        $configPath = ($this.GetConfigFilePath() -replace '\\', '/')
        $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
        $geminiCredentialsDir = ((Join-Path $homeDir ".gemini") -replace '\\', '/')
        $claudeCredentialsDir = ((Join-Path $homeDir ".claude") -replace '\\', '/')
        $claudeConfigJson = ((Join-Path $homeDir ".claude.json") -replace '\\', '/')
        $secretDir = ($this.GetSecretDir() -replace '\\', '/')
        $codexAuthFile = ((Join-Path $homeDir ".codex" "auth.json") -replace '\\', '/')
        $skillsPath = (((Join-Path $ctx.DotfilesPath "chezmoi" "dot_claude" "skills") -replace '\\', '/'))
        $workspaceHostDir = ((Join-Path $homeDir "openclaw-workspace") -replace '\\', '/')
        # Convert Windows path to Docker Desktop POSIX path: C:/Users/x -> /c/Users/x
        $workspacePosixDir = $workspaceHostDir -replace '^([A-Z]):', { '/' + $_.Groups[1].Value.ToLower() }
        $envContent = @"
OPENCLAW_PORT=41789
OPENCLAW_UID=1000
OPENCLAW_GID=1000
OPENCLAW_CONFIG_FILE=$configPath
TZ=Asia/Tokyo
GEMINI_CREDENTIALS_DIR=$geminiCredentialsDir
CLAUDE_CREDENTIALS_DIR=$claudeCredentialsDir
CLAUDE_CONFIG_JSON=$claudeConfigJson
OPENCLAW_WORKSPACE_DIR=$workspaceHostDir
OPENCLAW_WORKSPACE_POSIX=$workspacePosixDir
OPENCLAW_GITHUB_TOKEN_FILE=$secretDir/github_token
OPENCLAW_XAI_API_KEY_FILE=$secretDir/xai_api_key
OPENCLAW_GEMINI_API_KEY_FILE=$secretDir/gemini_api_key
CODEX_AUTH_FILE=$codexAuthFile
SKILLS_PATH=$skillsPath
"@
        $this.Log(".env ファイルを生成します: $envFile")
        Set-ContentNoNewline -Path $envFile -Value $envContent
    }

    <#
    .SYNOPSIS
        既存 .env に必須変数が不足していれば追記する
    .DESCRIPTION
        .env のスキーマが変更された場合、既存ファイルに不足する変数を追記。
    #>
    hidden [void] EnsureEnvVars([string]$envFile, [SetupContext]$ctx) {
        $content = Get-Content $envFile -Raw -ErrorAction SilentlyContinue
        if (-not $content) { return }

        $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
        $secretDir = ($this.GetSecretDir() -replace '\\', '/')
        $workspaceHostDir = ((Join-Path $homeDir "openclaw-workspace") -replace '\\', '/')
        $workspacePosixDir = $workspaceHostDir -replace '^([A-Z]):', { '/' + $_.Groups[1].Value.ToLower() }

        $geminiCredentialsDir = ((Join-Path $homeDir ".gemini") -replace '\\', '/')
        $claudeCredentialsDir = ((Join-Path $homeDir ".claude") -replace '\\', '/')
        $claudeConfigJson = ((Join-Path $homeDir ".claude.json") -replace '\\', '/')
        $codexAuthFile = ((Join-Path $homeDir ".codex" "auth.json") -replace '\\', '/')
        $skillsPath = (((Join-Path $ctx.DotfilesPath "chezmoi" "dot_claude" "skills") -replace '\\', '/'))

        $requiredVars = [ordered]@{
            "GEMINI_CREDENTIALS_DIR"       = $geminiCredentialsDir
            "CLAUDE_CREDENTIALS_DIR"       = $claudeCredentialsDir
            "CLAUDE_CONFIG_JSON"           = $claudeConfigJson
            "CODEX_AUTH_FILE"              = $codexAuthFile
            "OPENCLAW_GITHUB_TOKEN_FILE"   = "$secretDir/github_token"
            "OPENCLAW_XAI_API_KEY_FILE"    = "$secretDir/xai_api_key"
            "OPENCLAW_GEMINI_API_KEY_FILE" = "$secretDir/gemini_api_key"
            "OPENCLAW_WORKSPACE_DIR"       = $workspaceHostDir
            "OPENCLAW_WORKSPACE_POSIX"     = $workspacePosixDir
            "SKILLS_PATH"                  = $skillsPath
        }

        $appended = @()
        $appendedKeys = @()
        foreach ($key in $requiredVars.Keys) {
            if ($content -notmatch "(?m)^$([regex]::Escape($key))=") {
                $appended += "$key=$($requiredVars[$key])"
                $appendedKeys += $key
            }
        }

        if ($appended.Count -gt 0) {
            $nl = [Environment]::NewLine
            $appendText = $nl + ($appended -join $nl) + $nl
            [System.IO.File]::AppendAllText($envFile, $appendText)
            $this.Log("$($appended.Count) 個の変数を .env に追記しました: $($appendedKeys -join ', ')")
        } else {
            $this.Log(".env ファイルが存在します: $envFile", "Gray")
        }
    }

    <#
    .SYNOPSIS
        1Password からシークレットを取得してファイルに永続化する
    .DESCRIPTION
        op read でシークレットを取得し、~/.openclaw/secrets/<name> に書き出す。
        ファイルは削除しない（docker compose の file: secret が参照し続けるため）。
        .env にファイルパスを OPENCLAW_<NAME>_FILE として追記する。
    #>
    hidden [void] WriteSecretFile([string]$opRef, [string]$name, [bool]$required) {
        $value = ""
        # PATH + 全ユーザーの WinGet Packages から op を検索（管理者昇格セッション対応）
        $opExe = Get-Command "op" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
        if (-not $opExe) {
            $opExe = Find-WinGetExe -PackagePattern 'AgileBits.1Password.CLI*' -ExeFilter 'op.exe'
        }
        if ($opExe) {
            try {
                $result = & $opExe read $opRef 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $value = ($result | Out-String).Trim()
                } else {
                    $this.LogWarning("$name の取得に失敗しました (op read)")
                }
            } catch {
                $this.LogWarning("$name の取得で例外が発生しました")
            }
        }

        if ([string]::IsNullOrWhiteSpace($value)) {
            $envName = "OPENCLAW_$($name.ToUpper())"
            $value = [string][Environment]::GetEnvironmentVariable($envName)
        }
        if ([string]::IsNullOrWhiteSpace($value) -and $required) {
            throw "$name が未取得です。1Password にサインインしているか確認してください (op read `"$opRef`")"
        }
        if ([string]::IsNullOrWhiteSpace($value)) {
            return
        }

        $secretDir = $this.GetSecretDir()
        if (-not (Test-Path $secretDir)) {
            New-Item -ItemType Directory -Path $secretDir -Force | Out-Null
        }
        $secretFile = Join-Path $secretDir $name
        Set-ContentNoNewline -Path $secretFile -Value $value
        $this.Log("$name を永続シークレットファイルに書き出しました", "Gray")
    }

    <#
    .SYNOPSIS
        シークレットディレクトリのパスを返す
    #>
    hidden [string] GetSecretDir() {
        return Join-Path (Split-Path $this.GetConfigFilePath()) "secrets"
    }

    <#
    .SYNOPSIS
        cron/jobs.json が存在しない場合にシードファイルをコピーする
    .DESCRIPTION
        新規セットアップや volume 再作成後、chezmoi が展開した
        ~/.openclaw/cron/jobs.seed.json をコンテナ内に投入してリスタートする。
        以下の場合はスキップする:
        - ホスト上にシードファイルが存在しない（chezmoi apply 未実行）
        - コンテナが起動していない
        - コンテナ内に jobs.json がすでに存在する
    #>
    hidden [void] SeedCronJobs() {
        $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
        $seedFile = Join-Path $homeDir ".openclaw\cron\jobs.seed.json"

        if (-not (Test-PathExist -Path $seedFile)) {
            $this.LogWarning("cron seed ファイルが見つかりません: $seedFile (chezmoi apply を実行してください)")
            return
        }

        # コンテナが起動中か確認
        $running = Invoke-Docker "ps" "--filter" "name=openclaw" "--filter" "status=running" "--format" "{{.Names}}"
        if ($running -notmatch "openclaw") {
            $this.LogWarning("cron seed: コンテナが起動していません。シードをスキップします")
            return
        }

        # コンテナ内に jobs.json がすでに存在するか確認
        $existing = Invoke-Docker "exec" "openclaw" "//bin/sh" "-c" "test -f //home/app/.openclaw/cron/jobs.json && echo exists"
        if ($existing -match "exists") {
            $this.Log("cron/jobs.json はすでに存在します。シードをスキップします", "Gray")
            return
        }

        $this.Log("cron/jobs.json が存在しません。シードファイルをコピーします")
        Invoke-Docker "exec" "openclaw" "//bin/sh" "-c" "mkdir -p //home/app/.openclaw/cron"
        if ($LASTEXITCODE -ne 0) {
            $this.LogWarning("cron seed: コンテナ内ディレクトリの作成に失敗しました")
            return
        }
        Invoke-Docker "cp" ($seedFile -replace '\\', '/') "openclaw:/home/app/.openclaw/cron/jobs.json"
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
            if ($i -lt $this.StartupRetries) {
                Start-SleepSafe -Seconds $this.StartupRetryDelaySeconds
            }
        }
        return $false
    }

    # ────────────────────────────────────────────────────────
    # パスヘルパー
    # ────────────────────────────────────────────────────────

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
