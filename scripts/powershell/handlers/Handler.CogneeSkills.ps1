<#
.SYNOPSIS
    CogneeSkills Docker コンテナを管理するハンドラー（対話確認 + インフラチェックの 2 層ゲート）

.DESCRIPTION
    install.cmd 実行時の 2 層ゲート:
      1. 対話確認 — 初回実行時にユーザーへ [y/N] で確認し、
         結果を ~/.config/chezmoi/chezmoi.toml [data].cognee_skills_enabled に永続化。
         承認済みならプロンプトをスキップ、拒否済みならサイレントスキップ。
      2. インフラチェック — docker コマンド / docker-compose.yml の存在確認。
    両方をパスした場合のみセットアップを実行する。

    処理内容:
    - .env ファイルの自動生成（存在しない場合）
    - cognee-network Docker ネットワークの作成
    - docker compose で CogneeSkills コンテナをビルド・起動
    - コンテナの起動確認

.NOTES
    Order = 130 (OpenClaw の後に実行)
    前提: docker が利用可能であること
    シークレット: OpenClaw の gemini_api_key を再利用（独自のシークレット管理は不要）
#>

$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class CogneeSkillsHandler : SetupHandlerBase {
    # コンテナ起動待機設定
    [int]$StartupRetries = 12
    [int]$StartupRetryDelaySeconds = 5
    # docker compose up リトライ設定（Docker 起動直後の一時的な失敗への対策）
    [int]$ComposeRetries = 2
    [int]$ComposeRetryDelaySeconds = 10

    CogneeSkillsHandler() {
        $this.Name = "CogneeSkills"
        $this.Description = "CogneeSkills スキルサーバーの起動"
        $this.Order = 130
        $this.RequiresAdmin = $false
        $this.Phase = 1
        $this.ConsentKey = "cognee_skills_enabled"
        $this.ConsentLabel = "CogneeSkills — AI スキル学習・改善サーバー (cognee)"
    }

    <#
    .SYNOPSIS
        実行可否を判定する（2 層ゲート）
    .DESCRIPTION
        以下を順にチェックし、すべてパスした場合のみ $true を返す:
        1. 対話確認 — chezmoi.toml のフラグを確認。未設定なら対話的に問い、結果を永続化。
        2. インフラチェック — docker / docker-compose.yml の存在。
    #>
    [bool] CanApply([SetupContext]$ctx) {
        $this.StartupRetries = $ctx.GetOption("CogneeSkillsStartupRetries", 12)
        $this.StartupRetryDelaySeconds = $ctx.GetOption("CogneeSkillsStartupRetryDelaySeconds", 5)
        $this.ComposeRetries = $ctx.GetOption("CogneeSkillsComposeRetries", 2)
        $this.ComposeRetryDelaySeconds = $ctx.GetOption("CogneeSkillsComposeRetryDelaySeconds", 10)

        # ── Layer 1: 同意フラグ確認 ──
        # Invoke-ConsentPrompt で事前に永続化済みのフラグを参照する
        $enabled = $this.ReadConsentFlag()
        if ($null -eq $enabled -or -not $enabled) {
            if ($null -eq $enabled) {
                $this.Log("未設定のためスキップします (install.cmd の同意プロンプトで有効化してください)", "Gray")
            } else {
                $this.Log("CogneeSkills は無効です (chezmoi.toml)", "Gray")
            }
            return $false
        }

        # ── Layer 2: インフラチェック ──
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
        CogneeSkills コンテナを起動する
    #>
    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            # .env ファイルの確認・生成
            $this.EnsureEnvFile($ctx)

            # Gemini API キーのシークレットファイルを確認・作成
            $this.EnsureGeminiApiKey()

            # cognee-network を作成（存在しない場合のみ）
            $this.EnsureDockerNetwork()

            # コンテナを起動（--build で最新イメージを使用）
            # docker compose はビルド進捗を stderr に出力するため NativeCommandError が発生するが
            # 終了コードが 0 であれば成功として扱う
            # Docker 起動直後の一時的な失敗に備えてリトライする
            $composeFile = $this.GetComposeFilePath($ctx)
            $this.Log("CogneeSkills コンテナを起動します (--build)")
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

            return $this.CreateSuccessResult("CogneeSkills コンテナを起動しました")
        } catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }

    <#
    .SYNOPSIS
        Gemini API キーのシークレットファイルを確認・作成する
    .DESCRIPTION
        OpenClaw の secrets ディレクトリに gemini_api_key ファイルが存在しない場合、
        1Password (op read) または環境変数から取得して書き出す。
    #>
    hidden [void] EnsureGeminiApiKey() {
        $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
        $secretDir = Join-Path $homeDir ".openclaw\secrets"
        $secretFile = Join-Path $secretDir "gemini_api_key"

        if (Test-Path $secretFile) {
            $this.Log("gemini_api_key シークレットファイルが存在します", "Gray")
            return
        }

        $value = ""
        # 1. op read で取得
        $opExe = Get-Command "op" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
        if (-not $opExe) {
            $opExe = Find-WinGetExe -PackagePattern 'AgileBits.1Password.CLI*' -ExeFilter 'op.exe'
        }
        if ($opExe) {
            try {
                $result = & $opExe read "op://Personal/Gemini API/credential" 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $value = ($result | Out-String).Trim()
                }
            } catch { }
        }

        # 2. 環境変数フォールバック
        if ([string]::IsNullOrWhiteSpace($value)) {
            $value = [string][Environment]::GetEnvironmentVariable("GEMINI_API_KEY")
        }

        if ([string]::IsNullOrWhiteSpace($value)) {
            $this.LogWarning("Gemini API キーが取得できませんでした。CogneeSkills が起動しても LLM 呼び出しが失敗します")
            return
        }

        if (-not (Test-Path $secretDir)) {
            New-Item -ItemType Directory -Path $secretDir -Force | Out-Null
        }
        Set-ContentNoNewline -Path $secretFile -Value $value
        $this.Log("gemini_api_key を書き出しました", "Gray")
    }

    # ────────────────────────────────────────────────────────
    # .env / Docker ネットワーク / Docker 操作
    # ────────────────────────────────────────────────────────

    <#
    .SYNOPSIS
        .env ファイルを確認・生成する
    .DESCRIPTION
        .env が存在しない場合、デフォルト値で生成する。
        OpenClaw の gemini_api_key シークレットファイルを参照する。
    #>
    hidden [void] EnsureEnvFile([SetupContext]$ctx) {
        $composeDir = $this.GetComposeDir($ctx)
        $envFile = Join-Path $composeDir ".env"

        if (Test-PathExist -Path $envFile) {
            $this.Log(".env ファイルが存在します: $envFile", "Gray")
            return
        }

        $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
        $secretDir = ((Join-Path $homeDir ".openclaw\secrets") -replace '\\', '/')

        # chezmoi ソースディレクトリから dot_claude/skills パスを構築
        $chezmoiSourceDir = ((Join-Path $ctx.DotfilesPath "chezmoi") -replace '\\', '/')
        $skillsPath = "${chezmoiSourceDir}/dot_claude/skills"

        $envContent = @"
LLM_PROVIDER=gemini
EMBEDDING_PROVIDER=gemini
EMBEDDING_MODEL=gemini-embedding-2-preview
SKILLS_PATH=$skillsPath
OPENCLAW_GEMINI_API_KEY_FILE=$secretDir/gemini_api_key
SKILL_HEALTH_WINDOW=20
SKILL_HEALTH_THRESHOLD=0.7
SKILL_CORRECTION_PENALTY=0.05
"@
        $this.Log(".env ファイルを生成します: $envFile")
        Set-ContentNoNewline -Path $envFile -Value $envContent
    }

    <#
    .SYNOPSIS
        cognee-network Docker ネットワークを作成する（存在しない場合のみ）
    #>
    hidden [void] EnsureDockerNetwork() {
        $networkName = "cognee-network"
        $existing = Invoke-Docker "network" "ls" "--filter" "name=$networkName" "--format" "{{.Name}}"
        if ($existing -match $networkName) {
            $this.Log("Docker ネットワーク '$networkName' は既に存在します", "Gray")
            return
        }
        $this.Log("Docker ネットワーク '$networkName' を作成します")
        Invoke-Docker "network" "create" $networkName
        if ($LASTEXITCODE -ne 0) {
            throw "Docker ネットワーク '$networkName' の作成に失敗しました"
        }
        $this.Log("Docker ネットワーク '$networkName' を作成しました", "Green")
    }

    <#
    .SYNOPSIS
        コンテナが起動するまで待機する
    #>
    hidden [bool] WaitForContainer() {
        for ($i = 1; $i -le $this.StartupRetries; $i++) {
            $this.Log("コンテナ起動を確認中... ($i/$($this.StartupRetries))")
            $status = Invoke-Docker "ps" "--filter" "name=cognee-skills" "--filter" "status=running" "--format" "{{.Names}}"
            if ($status -match "cognee-skills") {
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
        return Join-Path $ctx.DotfilesPath "docker\cognee-skills\docker-compose.yml"
    }

    <#
    .SYNOPSIS
        docker-compose.yml の親ディレクトリを返す
    #>
    hidden [string] GetComposeDir([SetupContext]$ctx) {
        return Join-Path $ctx.DotfilesPath "docker\cognee-skills"
    }
}
