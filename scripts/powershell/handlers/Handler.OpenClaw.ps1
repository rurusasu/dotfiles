<#
.SYNOPSIS
    OpenClaw Docker コンテナを管理するハンドラー（対話確認 + インフラチェックの 2 層ゲート）

.DESCRIPTION
    install.cmd 実行時の 2 層ゲート:
      1. 対話確認 — 初回実行時にユーザーへ [y/N] で確認し、
         結果を ~/.config/chezmoi/chezmoi.toml [data].openclaw_enabled に永続化。
         承認済みならプロンプトをスキップ、拒否済みならサイレントスキップ。
         承認時は chezmoi apply を自動実行して .openclaw/ 設定を展開する。
      2. インフラチェック — docker コマンド / docker-compose.yml / 設定ファイルの存在確認。
    両方をパスした場合のみセットアップを実行する。

    chezmoi apply 側は .chezmoidata/personal.yaml の openclaw_enabled (default: false) と
    .chezmoiignore.tmpl で制御されるため、フラグが true でない PC には
    .openclaw/ ディレクトリ自体が展開されない。

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
    }

    <#
    .SYNOPSIS
        実行可否を判定する（2 層ゲート）
    .DESCRIPTION
        以下を順にチェックし、すべてパスした場合のみ $true を返す:
        1. 対話確認 — chezmoi.toml のフラグを確認。未設定なら対話的に問い、結果を永続化。
        2. インフラチェック — 設定ファイル / docker / docker-compose.yml の存在。
    #>
    [bool] CanApply([SetupContext]$ctx) {
        $this.StartupRetries = $ctx.GetOption("OpenClawStartupRetries", 12)
        $this.StartupRetryDelaySeconds = $ctx.GetOption("OpenClawStartupRetryDelaySeconds", 5)
        $this.ComposeRetries = $ctx.GetOption("OpenClawComposeRetries", 2)
        $this.ComposeRetryDelaySeconds = $ctx.GetOption("OpenClawComposeRetryDelaySeconds", 10)

        # ── Layer 1: 対話確認（永続フラグ） ──
        # chezmoi.toml の openclaw_enabled で過去の選択を確認する。
        # 未設定（$null）なら対話的に確認し、結果を chezmoi.toml に永続化する。
        # 非対話環境（バックグラウンド実行等）では Read-Host がハングするためスキップする。
        $enabled = $this.ReadOpenClawEnabled()
        if ($null -eq $enabled) {
            if (-not (Test-InteractiveEnvironment)) {
                $this.Log("非対話環境のためスキップします (対話モードで install.cmd を実行してください)", "Yellow")
                return $false
            }
            # 初回: ユーザーに確認
            Write-Host ""
            Write-Host "  OpenClaw (Telegram AI ゲートウェイ) を検出しました。" -ForegroundColor Yellow
            Write-Host "  この PC で OpenClaw をセットアップしますか？" -ForegroundColor Yellow
            Write-Host "  (Docker コンテナのビルド・起動を行います)" -ForegroundColor Gray
            $answer = Read-Host "  [y/N]"
            $enabled = ($answer -match '^[yY]')
            $this.WriteOpenClawEnabled($enabled)
            $this.Log("選択を chezmoi.toml に記録しました (openclaw_enabled = $($enabled.ToString().ToLower()))")
            if (-not $enabled) {
                return $false
            }
            # フラグを有効化したので chezmoi apply で .openclaw/ 設定を展開
            $this.ApplyChezmoiConfig()
        } elseif (-not $enabled) {
            $this.Log("OpenClaw は無効です (chezmoi.toml)", "Gray")
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
    # chezmoi.toml フラグ管理
    # ────────────────────────────────────────────────────────

    <#
    .SYNOPSIS
        chezmoi.toml から openclaw_enabled フラグを読み取る
    .OUTPUTS
        $true  — 有効化済み（過去にユーザーが承認）
        $false — 無効化済み（過去にユーザーが拒否）
        $null  — 未設定（初回、ユーザーに確認が必要）
    #>
    hidden [object] ReadOpenClawEnabled() {
        $tomlPath = $this.GetChezmoiTomlPath()
        if (-not (Test-Path $tomlPath)) { return $null }
        $content = Get-Content $tomlPath -Raw -ErrorAction SilentlyContinue
        if (-not $content) { return $null }
        if ($content -match 'openclaw_enabled\s*=\s*(true|false)') {
            return ($Matches[1] -eq 'true')
        }
        return $null
    }

    <#
    .SYNOPSIS
        chezmoi.toml に openclaw_enabled フラグを永続化する
    .DESCRIPTION
        ファイルが存在しない場合は作成する。
        [data] セクションがない場合は追加する。
        既存の値がある場合は更新する。
    #>
    hidden [void] WriteOpenClawEnabled([bool]$enabled) {
        $tomlPath = $this.GetChezmoiTomlPath()
        $value = if ($enabled) { "true" } else { "false" }
        $nl = [Environment]::NewLine

        $dir = Split-Path $tomlPath
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        if (-not (Test-Path $tomlPath)) {
            [System.IO.File]::WriteAllText($tomlPath, "[data]${nl}openclaw_enabled = ${value}${nl}")
            return
        }

        $content = Get-Content $tomlPath -Raw
        if ($content -match 'openclaw_enabled\s*=') {
            # 既存の値を更新
            $content = $content -replace '(openclaw_enabled\s*=\s*)\w+', "`${1}${value}"
        } elseif ($content -match '\[data\]') {
            # [data] セクションの直後に追記
            $content = $content -replace '(\[data\]\s*\r?\n)', "`$1openclaw_enabled = ${value}${nl}"
        } else {
            # [data] セクションごと追加
            $content = "${content}${nl}[data]${nl}openclaw_enabled = ${value}${nl}"
        }
        [System.IO.File]::WriteAllText($tomlPath, $content)
    }

    <#
    .SYNOPSIS
        chezmoi apply を実行して .openclaw/ 設定ファイルを展開する
    .DESCRIPTION
        WriteOpenClawEnabled で openclaw_enabled = true を書き込んだ直後に呼ぶ。
        Chezmoi ハンドラーは既に実行済み (Order < 120) のため、
        フラグ変更後の再適用が必要。
    #>
    hidden [void] ApplyChezmoiConfig() {
        $chezmoiCmd = Get-ExternalCommand -Name "chezmoi"
        if (-not $chezmoiCmd) {
            $this.LogWarning("chezmoi が見つかりません — 設定ファイルの展開をスキップします")
            return
        }
        $this.Log("chezmoi apply で OpenClaw 設定を展開しています...")
        try {
            & chezmoi apply 2>&1 | Out-Null
        } catch {
            $this.LogWarning("chezmoi apply に失敗しました: $($_.Exception.Message)")
        }
    }

    <#
    .SYNOPSIS
        chezmoi.toml のパスを返す
    #>
    hidden [string] GetChezmoiTomlPath() {
        $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
        return Join-Path $homeDir ".config\chezmoi\chezmoi.toml"
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
            $this.Log(".env ファイルが存在します: $envFile", "Gray")
            return
        }

        $configPath = ($this.GetConfigFilePath() -replace '\\', '/')
        $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
        $geminiCredentialsDir = ((Join-Path $homeDir ".gemini") -replace '\\', '/')
        $claudeCredentialsDir = ((Join-Path $homeDir ".claude") -replace '\\', '/')
        $claudeConfigJson = ((Join-Path $homeDir ".claude.json") -replace '\\', '/')
        $secretDir = ($this.GetSecretDir() -replace '\\', '/')
        $workspaceHostDir = ((Join-Path $homeDir "openclaw-workspace") -replace '\\', '/')
        # Convert Windows path to Docker Desktop POSIX path: C:/Users/x -> /c/Users/x
        $workspacePosixDir = $workspaceHostDir -replace '^([A-Z]):', { '/' + $_.Groups[1].Value.ToLower() }
        $envContent = @"
OPENCLAW_PORT=18789
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
"@
        $this.Log(".env ファイルを生成します: $envFile")
        Set-ContentNoNewline -Path $envFile -Value $envContent
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
        $existing = Invoke-Docker "exec" "openclaw" "//bin/sh" "-c" "test -f //home/app/.openclaw/cron/jobs.json && echo exists"
        if ($existing -match "exists") {
            $this.Log("cron/jobs.json はすでに存在します。シードをスキップします", "Gray")
            return
        }

        $this.Log("cron/jobs.json が存在しません。シードファイルをコピーします")
        Invoke-Docker "exec" "openclaw" "//bin/sh" "-c" "mkdir -p //home/app/.openclaw/cron"
        Invoke-Docker "cp" ($seedFile -replace '\\', '/') "openclaw://home/app/.openclaw/cron/jobs.json"
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
