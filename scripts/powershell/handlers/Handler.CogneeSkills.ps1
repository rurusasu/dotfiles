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

        # ── Layer 1: 対話確認（永続フラグ） ──
        # chezmoi.toml の cognee_skills_enabled で過去の選択を確認する。
        # 未設定（$null）なら対話的に確認し、結果を chezmoi.toml に永続化する。
        # 非対話環境（バックグラウンド実行等）では Read-Host がハングするためスキップする。
        $enabled = $this.ReadCogneeSkillsEnabled()
        if ($null -eq $enabled) {
            if (-not (Test-InteractiveEnvironment)) {
                $this.Log("非対話環境のためスキップします (対話モードで install.cmd を実行してください)", "Yellow")
                return $false
            }
            # 初回: ユーザーに確認
            Write-Host ""
            Write-Host "  CogneeSkills (スキルサーバー) を検出しました。" -ForegroundColor Yellow
            Write-Host "  この PC で CogneeSkills をセットアップしますか？" -ForegroundColor Yellow
            Write-Host "  (Docker コンテナのビルド・起動を行います)" -ForegroundColor Gray
            $answer = Read-Host "  [y/N]"
            $enabled = ($answer -match '^[yY]')
            $this.WriteCogneeSkillsEnabled($enabled)
            $this.Log("選択を chezmoi.toml に記録しました (cognee_skills_enabled = $($enabled.ToString().ToLower()))")
            if (-not $enabled) {
                return $false
            }
        } elseif (-not $enabled) {
            $this.Log("CogneeSkills は無効です (chezmoi.toml)", "Gray")
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

    # ────────────────────────────────────────────────────────
    # chezmoi.toml フラグ管理
    # ────────────────────────────────────────────────────────

    <#
    .SYNOPSIS
        chezmoi.toml から cognee_skills_enabled フラグを読み取る
    .OUTPUTS
        $true  — 有効化済み（過去にユーザーが承認）
        $false — 無効化済み（過去にユーザーが拒否）
        $null  — 未設定（初回、ユーザーに確認が必要）
    #>
    hidden [object] ReadCogneeSkillsEnabled() {
        $tomlPath = $this.GetChezmoiTomlPath()
        if (-not (Test-Path $tomlPath)) { return $null }
        $content = Get-Content $tomlPath -Raw -ErrorAction SilentlyContinue
        if (-not $content) { return $null }
        if ($content -match 'cognee_skills_enabled\s*=\s*(true|false)') {
            return ($Matches[1] -eq 'true')
        }
        return $null
    }

    <#
    .SYNOPSIS
        chezmoi.toml に cognee_skills_enabled フラグを永続化する
    .DESCRIPTION
        ファイルが存在しない場合は作成する。
        [data] セクションがない場合は追加する。
        既存の値がある場合は更新する。
    #>
    hidden [void] WriteCogneeSkillsEnabled([bool]$enabled) {
        $tomlPath = $this.GetChezmoiTomlPath()
        $value = if ($enabled) { "true" } else { "false" }
        $nl = [Environment]::NewLine

        $dir = Split-Path $tomlPath
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        if (-not (Test-Path $tomlPath)) {
            [System.IO.File]::WriteAllText($tomlPath, "[data]${nl}cognee_skills_enabled = ${value}${nl}")
            return
        }

        $content = Get-Content $tomlPath -Raw
        if ($content -match 'cognee_skills_enabled\s*=') {
            # 既存の値を更新
            $content = $content -replace '(cognee_skills_enabled\s*=\s*)\w+', "`${1}${value}"
        } elseif ($content -match '\[data\]') {
            # [data] セクションの直後に追記
            $content = $content -replace '(\[data\]\s*\r?\n)', "`$1cognee_skills_enabled = ${value}${nl}"
        } else {
            # [data] セクションごと追加
            $content = "${content}${nl}[data]${nl}cognee_skills_enabled = ${value}${nl}"
        }
        [System.IO.File]::WriteAllText($tomlPath, $content)
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
