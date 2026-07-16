<#
.SYNOPSIS
    Hermes Agent Docker コンテナの初期セットアップと起動ハンドラー

.DESCRIPTION
    - docker/hermes-agent/compose.yml を使って Hermes gateway/dashboard を起動
    - ~/.hermes/config.yaml の model provider/default を初期化
    - 1Password の保存済み credential を優先して ~/.hermes/.env に dashboard Basic Auth と Slack 接続情報を初期化
    - 1Password が使えない場合は credential を生成し、password を ~/.hermes/dashboard-basic-auth-password.txt に保存
#>

$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class HermesAgentHandler : SetupHandlerBase {
    [string]$Image = "nousresearch/hermes-agent:latest"
    [int]$DockerCheckTimeoutSeconds = 15
    [int]$DockerRunTimeoutSeconds = 600
    [int]$DockerComposeTimeoutSeconds = 180

    HermesAgentHandler() {
        $this.Name = "HermesAgent"
        $this.Description = "Hermes Agent Docker コンテナのセットアップ"
        $this.Order = 56
        $this.RequiresAdmin = $false
        $this.Phase = 2
    }

    [bool] CanApply([SetupContext]$ctx) {
        if ($this.IsSkipped($ctx)) {
            $this.Log("Hermes Agent セットアップはオプションで無効化されています", "Gray")
            return $false
        }

        $composeFile = $this.GetComposeFilePath($ctx)
        if (-not (Test-Path -LiteralPath $composeFile)) {
            $this.Log("Hermes compose file が見つかりません: $composeFile", "Gray")
            return $false
        }

        if (-not (Get-Command -Name "docker" -ErrorAction SilentlyContinue)) {
            $this.Log("docker コマンドが見つかりません", "Gray")
            return $false
        }

        if (-not (Test-DockerDaemon -TimeoutSeconds $this.DockerCheckTimeoutSeconds)) {
            $this.Log("Docker daemon が応答しないため Hermes Agent をスキップします", "Gray")
            return $false
        }

        if (-not (Test-WslAvailable)) {
            $this.Log("WSL が利用できないため Hermes Agent をスキップします", "Gray")
            return $false
        }

        if (-not $this.TestNixOsReady($ctx.DistroName)) {
            $this.Log("$($ctx.DistroName) が実行できないため Hermes Agent をスキップします", "Gray")
            return $false
        }

        if (-not $this.IsTruthy($ctx.GetOption("NixRebuildApplied", $false))) {
            $this.Log("NixOS 設定適用が完了していないため Hermes Agent をスキップします", "Gray")
            return $false
        }

        return $true
    }

    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            $composeFile = $this.GetComposeFilePath($ctx)
            if (-not (Test-Path -LiteralPath $composeFile)) {
                return $this.CreateFailureResult("Hermes compose file が見つかりません: $composeFile")
            }

            $dataDir = $this.GetDataDir()
            $this.EnsureDirectory($dataDir)
            $this.EnsureDirectory((Join-Path $dataDir ".xurl"))
            $this.EnsureDirectory($this.GetBrowserDataDir())
            $homeRepositoryResult = $this.EnsureHomeRepositoryLayout($ctx, $dataDir)
            $lifelogCoreResult = $this.EnsureLifelogCore($ctx, $dataDir)
            $modelResult = $this.EnsureModelConfiguration($ctx, $dataDir)
            $null = $this.EnsureTerminalEnvironmentPassthroughConfiguration($ctx, $dataDir)

            $envPath = Join-Path $dataDir ".env"
            $infoFilePath = Join-Path $dataDir "dashboard-basic-auth-password.txt"
            $authResult = $this.EnsureDashboardAuth($ctx, $envPath, $infoFilePath)
            $profileDashboardAuthResult = $this.SyncDashboardAuthToManagedProfileEnvironments($ctx, $dataDir, $envPath)
            $slackResult = $this.EnsureSlackEnvironment($ctx, $envPath)
            $profileSlackResult = $this.EnsureManagedProfileSlackEnvironments($ctx, $dataDir)
            $githubResult = $this.EnsureGitHubEnvironment($ctx, $envPath)
            $mcpResult = $this.EnsureMcpConfiguration($ctx, $dataDir)
            $slackMentionResult = $this.EnsureSlackMentionConfiguration($ctx, $dataDir)

            $composeArgs = @("compose", "-f", $composeFile, "up", "-d", "--build", "--force-recreate", "--remove-orphans")
            $output = @(Invoke-Docker -Arguments $composeArgs -TimeoutSeconds $this.DockerComposeTimeoutSeconds)
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0) {
                $message = ($output -join "`n").Trim()
                if ([string]::IsNullOrWhiteSpace($message)) {
                    $message = "exit code $exitCode"
                }
                return $this.CreateFailureResult("Hermes Agent コンテナの起動に失敗しました: $message")
            }

            $lifelogBootstrapResult = $this.InvokeLifelogCoreBootstrap($ctx)
            if (-not $lifelogBootstrapResult.Success) {
                return $this.CreateFailureResult($lifelogBootstrapResult.Message)
            }

            if ($authResult.Changed -and $authResult.Source -eq "1Password") {
                $this.Log("Dashboard Basic Auth を 1Password から設定しました", "Green")
            }
            elseif ($authResult.Changed) {
                $this.Log("Dashboard Basic Auth を生成しました: $infoFilePath", "Green")
            }
            else {
                $this.Log("Dashboard Basic Auth は既に設定済みです", "Gray")
            }

            if ($profileDashboardAuthResult.Changed -and $profileDashboardAuthResult.Count -gt 0) {
                $this.Log("Managed profile dashboard Basic Auth を同期しました ($($profileDashboardAuthResult.Count) profiles)", "Green")
            }

            if ($modelResult.Changed) {
                $this.Log("Hermes model 設定を $($modelResult.Provider)/$($modelResult.Model) に設定しました", "Green")
            }
            elseif ($modelResult.Source -eq "Config") {
                $this.Log("Hermes model 設定は既に設定済みです", "Gray")
            }

            if ($slackResult.Changed -and $slackResult.Source -eq "1Password") {
                $this.Log("Slack 接続情報を 1Password から設定しました", "Green")
            }
            elseif (-not $slackResult.Changed -and $slackResult.Source -eq "Existing") {
                $this.Log("Slack 接続情報は既に設定済みです", "Gray")
            }

            if ($profileSlackResult.Changed -and $profileSlackResult.Count -gt 0) {
                $this.Log("Managed profile Slack 接続情報を 1Password から設定しました ($($profileSlackResult.Count) profiles)", "Green")
            }

            if ($githubResult.Changed -and $githubResult.Source -eq "1Password") {
                $this.Log("Hermes lifelog sync 用 GitHub token を 1Password から設定しました", "Green")
            }
            elseif (-not $githubResult.Changed -and $githubResult.Source -eq "Existing") {
                $this.Log("Hermes lifelog sync 用 GitHub token は既に設定済みです", "Gray")
            }

            if ($homeRepositoryResult.Changed) {
                $this.Log("Hermes home/profile Git 管理ポリシーを更新しました", "Green")
            }

            if ($lifelogCoreResult.Changed) {
                $this.Log("Hermes lifelog core 設定を更新しました", "Green")
            }
            if ($lifelogBootstrapResult.Changed) {
                $this.Log("Hermes lifelog core を同期しました", "Green")
            }

            if ($mcpResult.Changed) {
                $this.Log("Hermes MCP server 設定を更新しました", "Green")
            }

            if ($slackMentionResult.Changed -and $slackMentionResult.Count -gt 0) {
                $this.Log("Slack 無メンション応答設定を更新しました ($($slackMentionResult.Count) configs)", "Green")
            }

            return $this.CreateSuccessResult("Hermes Agent を起動しました: http://127.0.0.1:9119 / browser: $($this.GetBrowserViewUrl())")
        }
        catch {
            return $this.CreateFailureResult("Hermes Agent セットアップに失敗しました: $($_.Exception.Message)", $_.Exception)
        }
    }

    hidden [bool] IsSkipped([SetupContext]$ctx) {
        $skip = $ctx.GetOption("SkipHermesAgent", $false)
        if ($this.IsTruthy($skip)) {
            return $true
        }

        $enabled = $ctx.GetOption("HermesAgentEnabled", $true)
        return -not $this.IsTruthy($enabled)
    }

    hidden [bool] IsTruthy([object]$value) {
        if ($null -eq $value) {
            return $false
        }
        if ($value -is [bool]) {
            return [bool]$value
        }

        $text = ([string]$value).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) {
            return $false
        }

        return $text -in @("1", "true", "TRUE", "True", "yes", "YES", "Yes", "on", "ON", "On")
    }

    hidden [string] GetComposeFilePath([SetupContext]$ctx) {
        return Join-Path $ctx.DotfilesPath "docker\hermes-agent\compose.yml"
    }

    hidden [bool] TestNixOsReady([string]$distroName) {
        if ([string]::IsNullOrWhiteSpace($distroName)) {
            return $false
        }

        try {
            Invoke-Wsl -TimeoutSeconds (Get-WslCheckTimeoutSecond) -Arguments @(
                "-d",
                $distroName,
                "-u",
                "root",
                "--",
                "true"
            ) | Out-Null
            return $LASTEXITCODE -eq 0
        }
        catch {
            return $false
        }
    }

    hidden [string] GetDataDir() {
        if (-not [string]::IsNullOrWhiteSpace($env:HERMES_DATA_DIR)) {
            return $env:HERMES_DATA_DIR
        }

        return Join-Path $this.GetHomeDir() ".hermes"
    }

    hidden [string] GetBrowserDataDir() {
        if (-not [string]::IsNullOrWhiteSpace($env:HERMES_BROWSER_DATA_DIR)) {
            return $env:HERMES_BROWSER_DATA_DIR
        }

        return Join-Path (Join-Path $this.GetHomeDir() ".hermes") ".browser"
    }

    hidden [string] GetBrowserViewUrl() {
        $port = "6080"
        if (-not [string]::IsNullOrWhiteSpace($env:HERMES_BROWSER_VIEW_PORT)) {
            $port = $env:HERMES_BROWSER_VIEW_PORT
        }

        return "http://127.0.0.1:$port"
    }

    hidden [string] GetHomeDir() {
        if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
            return $env:USERPROFILE
        }
        if (-not [string]::IsNullOrWhiteSpace($env:HOME)) {
            return $env:HOME
        }
        return [Environment]::GetFolderPath("UserProfile")
    }

    hidden [void] EnsureDirectory([string]$path) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    hidden [pscustomobject] EnsureHomeRepositoryLayout([SetupContext]$ctx, [string]$dataDir) {
        if (-not $this.IsTruthy($ctx.GetOption("HermesAgentHomeRepositoryLayoutEnabled", $true))) {
            return [PSCustomObject]@{ Changed = $false; Source = "Disabled" }
        }

        $changed = $false
        $changed = $this.EnsureGitignoreEntry(
            (Join-Path $dataDir ".gitignore"),
            "profiles/",
            "Profile homes are separate Git repositories/distributions."
        ) -or $changed

        $docsDir = Join-Path $dataDir "docs"
        $this.EnsureDirectory($docsDir)
        $changed = $this.EnsureFileLines(
            (Join-Path $docsDir "profile-home-layout.md"),
            $this.GetSharedHomeLayoutDocLines()
        ) -or $changed
        $changed = $this.EnsureFileLines(
            (Join-Path $docsDir "slack-app-registration.md"),
            $this.GetSlackAppRegistrationDocLines()
        ) -or $changed

        $changed = $this.EnsureManagedBlock(
            (Join-Path $dataDir "SOUL.md"),
            "HERMES_HOME_REPOSITORY_POLICY",
            @(
                "## Home Repository Policy",
                "",
                "Before changing Hermes home/profile layout, read /opt/data/docs/profile-home-layout.md.",
                "Runtime state such as .env, auth.json, memories/, sessions/, logs/, and state.db* stays out of Git."
            )
        ) -or $changed
        $changed = $this.EnsureManagedBlock(
            (Join-Path $dataDir "SOUL.md"),
            "HERMES_SLACK_APP_REGISTRATION_POLICY",
            $this.GetSlackAppRegistrationPolicyBlockLines()
        ) -or $changed

        foreach ($profileName in $this.GetManagedProfileNames($ctx)) {
            $changed = $this.EnsureProfileRepositoryLayout($dataDir, $profileName) -or $changed
            $profileDir = Join-Path (Join-Path $dataDir "profiles") $profileName
            if (Test-Path -LiteralPath $profileDir -PathType Container) {
                $changed = $this.EnsureManagedBlock(
                    (Join-Path $profileDir "SOUL.md"),
                    "HERMES_SLACK_APP_REGISTRATION_POLICY",
                    $this.GetSlackAppRegistrationPolicyBlockLines()
                ) -or $changed
            }
        }

        return [PSCustomObject]@{ Changed = $changed; Source = "Config" }
    }

    hidden [pscustomobject] EnsureLifelogCore([SetupContext]$ctx, [string]$dataDir) {
        if (-not $this.IsTruthy($ctx.GetOption("HermesAgentLifelogCoreEnabled", $true))) {
            return [PSCustomObject]@{ Changed = $false; Source = "Disabled" }
        }

        $changed = $false
        $coreDir = Join-Path $dataDir "core"
        $this.EnsureDirectory($coreDir)

        $changed = $this.EnsureGitignoreEntry(
            (Join-Path $dataDir ".gitignore"),
            "core/",
            "Shared lifelog core is a separate Git repository cloned at runtime."
        ) -or $changed

        $scriptsDir = Join-Path $dataDir "scripts"
        $this.EnsureDirectory($scriptsDir)
        $changed = $this.EnsureFileLinesLf(
            (Join-Path $scriptsDir "lifelog_sync.sh"),
            $this.GetLifelogCoreSyncScriptLines()
        ) -or $changed

        $changed = $this.EnsureFileLinesLf(
            (Join-Path $scriptsDir "article_news_slack.sh"),
            $this.GetArticleNewsSlackScriptLines()
        ) -or $changed

        $changed = $this.EnsureLifelogCronJob($dataDir) -or $changed

        $changed = $this.EnsureManagedBlock(
            (Join-Path $dataDir "SOUL.md"),
            "HERMES_LIFELOG_CORE_POLICY",
            $this.GetLifelogCorePolicyBlockLines()
        ) -or $changed

        foreach ($profileName in $this.GetManagedProfileNames($ctx)) {
            $profileDir = Join-Path (Join-Path $dataDir "profiles") $profileName
            if (-not (Test-Path -LiteralPath $profileDir -PathType Container)) {
                continue
            }
            $changed = $this.EnsureManagedBlock(
                (Join-Path $profileDir "SOUL.md"),
                "HERMES_LIFELOG_CORE_POLICY",
                $this.GetLifelogCorePolicyBlockLines()
            ) -or $changed
        }

        return [PSCustomObject]@{ Changed = $changed; Source = "Config" }
    }

    hidden [bool] EnsureFileLinesLf([string]$path, [string[]]$desiredLines) {
        $desiredContent = ($desiredLines -join "`n") + "`n"
        $existingContent = ""
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $existingContent = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        }

        if ($existingContent -eq $desiredContent) {
            return $false
        }

        $this.EnsureDirectory((Split-Path -Parent $path))
        Set-Content -LiteralPath $path -Encoding UTF8 -NoNewline -Value $desiredContent
        return $true
    }

    hidden [pscustomobject] InvokeLifelogCoreBootstrap([SetupContext]$ctx) {
        if (-not $this.IsTruthy($ctx.GetOption("HermesAgentLifelogCoreEnabled", $true))) {
            return [PSCustomObject]@{ Success = $true; Changed = $false; Source = "Disabled"; Message = "" }
        }
        if (-not $this.IsTruthy($ctx.GetOption("HermesAgentLifelogCoreBootstrapEnabled", $true))) {
            return [PSCustomObject]@{ Success = $true; Changed = $false; Source = "Disabled"; Message = "" }
        }

        $repairOutput = @(Invoke-Docker -Arguments @(
                "exec",
                "hermes",
                "bash",
                "-lc",
                "mkdir -p /opt/data/core && chown -R hermes:hermes /opt/data/core"
            ) -TimeoutSeconds $this.DockerRunTimeoutSeconds)
        $repairExitCode = $LASTEXITCODE
        if ($repairExitCode -ne 0) {
            $message = ($repairOutput -join "`n").Trim()
            if ([string]::IsNullOrWhiteSpace($message)) {
                $message = "exit code $repairExitCode"
            }
            return [PSCustomObject]@{
                Success = $false
                Changed = $false
                Source  = "Docker"
                Message = "Hermes lifelog core ownership repair failed: $message"
            }
        }

        $output = @(Invoke-Docker -Arguments @(
                "exec",
                "--user",
                "hermes",
                "hermes",
                "bash",
                "-lc",
                "bash /opt/data/scripts/lifelog_sync.sh --bootstrap"
            ) -TimeoutSeconds $this.DockerRunTimeoutSeconds)
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            $message = ($output -join "`n").Trim()
            if ([string]::IsNullOrWhiteSpace($message)) {
                $message = "exit code $exitCode"
            }
            return [PSCustomObject]@{
                Success = $false
                Changed = $false
                Source  = "Docker"
                Message = "Hermes lifelog core の初回同期に失敗しました: $message"
            }
        }

        return [PSCustomObject]@{
            Success = $true
            Changed = $true
            Source  = "Docker"
            Message = ""
        }
    }

    hidden [string[]] GetLifelogCorePolicyBlockLines() {
        return @(
            "## Lifelog Core Policy",
            "",
            "Before making user-context decisions, read /opt/data/core/lifelog/AGENTS.md and the relevant notes under /opt/data/core/lifelog.",
            "Treat /opt/data/core/lifelog as the shared source of truth for durable cross-agent user context.",
            "Write durable shared context to /opt/data/core/lifelog according to its AGENTS.md; do not use profile memories/ as the shared source of truth."
        )
    }

    hidden [bool] EnsureLifelogCronJob([string]$dataDir) {
        $cronDir = Join-Path $dataDir "cron"
        $this.EnsureDirectory($cronDir)
        $cronPath = Join-Path $cronDir "jobs.json"

        $cron = $null
        if (Test-Path -LiteralPath $cronPath -PathType Leaf) {
            try {
                $cron = Get-Content -LiteralPath $cronPath -Raw -ErrorAction Stop | ConvertFrom-Json
            }
            catch {
                $cron = $null
            }
        }
        if ($null -eq $cron) {
            $cron = [PSCustomObject]@{
                jobs       = @()
                updated_at = $null
            }
        }

        $jobs = @()
        if ($null -ne $cron.jobs) {
            $jobs = @($cron.jobs)
        }

        $desiredJobs = @(
            $this.GetLifelogCronJob(),
            $this.GetArticleNewsSlackCronJob()
        )
        $desiredJobsById = @{}
        foreach ($desiredJob in $desiredJobs) {
            $desiredJobsById[$desiredJob.id] = $desiredJob
        }

        $changed = $false
        $updatedJobs = @()
        $foundJobIds = @{}
        foreach ($job in $jobs) {
            if ($desiredJobsById.ContainsKey($job.id)) {
                $desiredJob = $desiredJobsById[$job.id]
                $foundJobIds[$desiredJob.id] = $true
                $mergedJob = $this.MergeLifelogCronJob($job, $desiredJob)
                if ((ConvertTo-Json -InputObject $job -Depth 10 -Compress) -ne (ConvertTo-Json -InputObject $mergedJob -Depth 10 -Compress)) {
                    $changed = $true
                }
                $updatedJobs += $mergedJob
                continue
            }
            $updatedJobs += $job
        }

        foreach ($desiredJob in $desiredJobs) {
            if (-not $foundJobIds.ContainsKey($desiredJob.id)) {
                $updatedJobs += $desiredJob
                $changed = $true
            }
        }

        if (-not $changed) {
            return $false
        }

        $cron.jobs = @($updatedJobs)
        $cron.updated_at = (Get-Date).ToUniversalTime().ToString("o")
        $json = ConvertTo-Json -InputObject $cron -Depth 10
        Set-Content -LiteralPath $cronPath -Encoding UTF8 -Value $json
        return $true
    }

    hidden [pscustomobject] MergeLifelogCronJob([object]$existingJob, [pscustomobject]$desiredJob) {
        $mergedJob = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $existingJob -Depth 10)
        foreach ($propertyName in @(
                "name",
                "prompt",
                "skills",
                "skill",
                "model",
                "provider",
                "provider_snapshot",
                "model_snapshot",
                "base_url",
                "script",
                "no_agent",
                "context_from",
                "schedule",
                "schedule_display",
                "enabled",
                "workdir"
            )) {
            $mergedJob | Add-Member -MemberType NoteProperty -Name $propertyName -Value $desiredJob.$propertyName -Force
        }

        return $mergedJob
    }

    hidden [pscustomobject] GetLifelogCronJob() {
        return [PSCustomObject]@{
            id                  = "lifelog-core-sync"
            name                = "Daily Lifelog core GitHub sync"
            prompt              = "Run the Hermes lifelog core GitHub sync script. It clones or updates /opt/data/core/lifelog, commits non-secret lifelog changes, rebases from origin/main, and pushes back to GitHub."
            skills              = @()
            skill               = $null
            model               = $null
            provider            = $null
            provider_snapshot   = $null
            model_snapshot      = $null
            base_url            = $null
            script              = "lifelog_sync.sh"
            no_agent            = $true
            context_from        = $null
            schedule            = [PSCustomObject]@{
                kind    = "cron"
                expr    = "20 4 * * *"
                display = "20 4 * * *"
            }
            schedule_display    = "20 4 * * *"
            repeat              = [PSCustomObject]@{
                times     = $null
                completed = 0
            }
            enabled             = $true
            state               = "scheduled"
            paused_at           = $null
            paused_reason       = $null
            last_run_at         = $null
            last_status         = $null
            last_error          = $null
            last_delivery_error = $null
            enabled_toolsets    = $null
            workdir             = $null
        }
    }

    hidden [pscustomobject] GetArticleNewsSlackCronJob() {
        return [PSCustomObject]@{
            id                  = "article-news-slack-post"
            name                = "Article collector translated news Slack post"
            prompt              = "Run the article collector translated news Slack post script. It collects recommended articles, translates them, saves translated Markdown into the lifelog inbox, and posts it to Slack channel C0AJVDKGN6A."
            skills              = @()
            skill               = $null
            model               = $null
            provider            = $null
            provider_snapshot   = $null
            model_snapshot      = $null
            base_url            = $null
            script              = "article_news_slack.sh"
            no_agent            = $true
            context_from        = $null
            schedule            = [PSCustomObject]@{
                kind    = "cron"
                expr    = "0 */2 * * *"
                display = "0 */2 * * *"
            }
            schedule_display    = "0 */2 * * *"
            repeat              = [PSCustomObject]@{
                times     = $null
                completed = 0
            }
            enabled             = $true
            state               = "scheduled"
            paused_at           = $null
            paused_reason       = $null
            last_run_at         = $null
            last_status         = $null
            last_error          = $null
            last_delivery_error = $null
            enabled_toolsets    = $null
            workdir             = $null
        }
    }

    hidden [string[]] GetArticleNewsSlackScriptLines() {
        return @(
            "#!/usr/bin/env bash",
            "set -euo pipefail",
            "",
            'HERMES_HOME_DIR="/opt/data"',
            'LIFELOG_INBOX_DIR="${ARTICLE_NEWS_LIFELOG_INBOX_DIR:-/opt/data/core/lifelog/0_inbox/article-news}"',
            'RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"',
            'WORK_ROOT="$HERMES_HOME_DIR/cron/output/article-news/$RUN_ID"',
            'STATE_DIR="$HERMES_HOME_DIR/cron/state/article-news"',
            'CONFIG_PATH="$WORK_ROOT/article-collector.toml"',
            'SLACK_CHANNEL="${ARTICLE_NEWS_SLACK_CHANNEL:-C0AJVDKGN6A}"',
            'ARTICLE_NEWS_LIMIT="${ARTICLE_NEWS_LIMIT:-2}"',
            "",
            'case "$ARTICLE_NEWS_LIMIT" in',
            '  ""|*[!0-9]*) echo "ARTICLE_NEWS_LIMIT must be a positive integer" >&2; exit 1 ;;',
            'esac',
            "",
            'mkdir -p "$WORK_ROOT" "$STATE_DIR" "$LIFELOG_INBOX_DIR"',
            "",
            'if [ -z "${SLACK_BOT_TOKEN:-}" ]; then',
            '  echo "SLACK_BOT_TOKEN is required" >&2',
            "  exit 1",
            "fi",
            "",
            'if ! command -v article-collector >/dev/null 2>&1; then',
            '  echo "article-collector is required" >&2',
            "  exit 1",
            "fi",
            "",
            'cat > "$CONFIG_PATH" <<CONFIG',
            "[recommend]",
            'sources = ["hackernews", "zenn", "qiita", "devto", "github-advisory", "aws-whatsnew", "kubernetes", "cncf", "infoq", "martinfowler", "github-search"]',
            'limit = $ARTICLE_NEWS_LIMIT',
            "fetch_articles = true",
            "create_pr = false",
            'history_path = "$STATE_DIR/recommend-history.sqlite"',
            "",
            "[recommend.source.qiita]",
            'query = "AI OR Rust OR security"',
            "",
            "[recommend.source.github-search]",
            'query = "stars:>1000 pushed:>2026-01-01 archived:false"',
            "CONFIG",
            "",
            'export ACP_AGENT="${ARTICLE_NEWS_ACP_AGENT:-codex}"',
            'export TRANSLATE_LANG="${ARTICLE_NEWS_TRANSLATE_LANG:-ja}"',
            'export ARTICLE_COLLECTOR_TEMP_DIR="$WORK_ROOT"',
            "",
            "set +e",
            'collector_output="$(article-collector recommend all --config "$CONFIG_PATH" 2>&1)"',
            'collector_status=$?',
            "set -e",
            'printf "%s\n" "$collector_output" > "$WORK_ROOT/article-collector.log"',
            "",
            'if [ "$collector_status" -ne 0 ]; then',
            '  if printf "%s\n" "$collector_output" | grep -Eq "No (new )?recommended articles found"; then',
            '    echo "No new recommended articles; skipping Slack post."',
            "    exit 0",
            "  fi",
            '  printf "%s\n" "$collector_output" >&2',
            '  exit "$collector_status"',
            "fi",
            "",
            'translated_path="$WORK_ROOT/translated.md"',
            'if [ ! -s "$translated_path" ]; then',
            '  echo "translated.md was not created" >&2',
            "  exit 1",
            "fi",
            "",
            'saved_path="$LIFELOG_INBOX_DIR/$RUN_ID.md"',
            'cp "$translated_path" "$saved_path"',
            "",
            'PYTHON_BIN="${PYTHON_BIN:-/opt/hermes/.venv/bin/python}"',
            'if [ ! -x "$PYTHON_BIN" ]; then',
            '  PYTHON_BIN="python3"',
            "fi",
            "",
            '$PYTHON_BIN - "$translated_path" "$SLACK_CHANNEL" <<''PY''',
            "import json",
            "import os",
            "import sys",
            "import urllib.error",
            "import urllib.request",
            "",
            "translated_path = sys.argv[1]",
            "channel = sys.argv[2]",
            'token = os.environ["SLACK_BOT_TOKEN"]',
            'with open(translated_path, "r", encoding="utf-8") as handle:',
            "    text = handle.read()",
            'payload = json.dumps({"channel": channel, "text": text, "mrkdwn": True}).encode("utf-8")',
            "request = urllib.request.Request(",
            '    "https://slack.com/api/chat.postMessage",',
            "    data=payload,",
            '    headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json; charset=utf-8"},',
            '    method="POST",',
            ")",
            "try:",
            "    with urllib.request.urlopen(request, timeout=30) as response:",
            '        body = response.read().decode("utf-8")',
            "except urllib.error.HTTPError as exc:",
            '    body = exc.read().decode("utf-8", errors="replace")',
            '    raise SystemExit(f"Slack HTTP error {exc.code}: {body}")',
            "result = json.loads(body)",
            'if not result.get("ok"):',
            '    raise SystemExit(f"Slack API error: {body}")',
            "PY",
            "",
            'echo "Saved translated news to $saved_path and posted to Slack channel $SLACK_CHANNEL."'
        )
    }

    hidden [string[]] GetLifelogCoreSyncScriptLines() {
        return @(
            "#!/usr/bin/env bash",
            "set -euo pipefail",
            "",
            'LIFELOG_DIR="${LIFELOG_ROOT:-/opt/data/core/lifelog}"',
            'LIFELOG_REMOTE_URL="${LIFELOG_REMOTE_URL:-https://github.com/rurusasu/lifelog.git}"',
            'LIFELOG_BRANCH="${LIFELOG_BRANCH:-main}"',
            'HERMES_HOME_DIR="/opt/data"',
            "",
            'load_github_token() {',
            '  if [ -f "$HERMES_HOME_DIR/.env" ]; then',
            '    while IFS="=" read -r key value || [ -n "$key" ]; do',
            '      key="${key#export }"',
            '      key="${key%$''\r''}"',
            '      value="${value%$''\r''}"',
            '      value="${value%\"}"; value="${value#\"}"',
            '      case "$key" in',
            '        GH_TOKEN|GITHUB_TOKEN) [ -z "${GH_TOKEN:-}" ] && export GH_TOKEN="$value" ;;',
            '        GITHUB_PERSONAL_ACCESS_TOKEN) [ -z "${GH_TOKEN:-}" ] && export GH_TOKEN="$value" ;;',
            '      esac',
            '    done < "$HERMES_HOME_DIR/.env"',
            '  fi',
            '}',
            "",
            'setup_git_auth() {',
            '  export GIT_TERMINAL_PROMPT=0',
            '  if [ -z "${GH_TOKEN:-}" ]; then',
            '    return',
            '  fi',
            '  GIT_ASKPASS_FILE="$(mktemp)"',
            '  export GIT_ASKPASS_FILE',
            '  cat > "$GIT_ASKPASS_FILE" <<''ASKPASS''',
            "#!/bin/sh",
            'case "$1" in',
            '  *Username*) printf "%s\n" "x-access-token" ;;',
            '  *Password*) printf "%s\n" "$GH_TOKEN" ;;',
            '  *) printf "\n" ;;',
            'esac',
            "ASKPASS",
            '  chmod 700 "$GIT_ASKPASS_FILE"',
            '  export GIT_ASKPASS="$GIT_ASKPASS_FILE"',
            '}',
            "",
            'cleanup() {',
            '  if [ -n "${GIT_ASKPASS_FILE:-}" ] && [ -f "$GIT_ASKPASS_FILE" ]; then',
            '    rm -f "$GIT_ASKPASS_FILE"',
            '  fi',
            '}',
            'trap cleanup EXIT',
            "",
            'refuse_secret_changes() {',
            '  if git -c safe.directory="$LIFELOG_DIR" diff --cached --name-only | grep -E ''(^|/)(\.direnv/|\.env|\.env\..*|auth\.json|.*token.*|.*secret.*|.*password.*|state\.db|.*\.sqlite3?|.*\.db|.*-shm|.*-wal|logs/|sessions/|cache/)'' >/dev/null 2>&1; then',
            '    echo "Hermes lifelog sync refused: secret/state/runtime file would be committed"',
            '    git -c safe.directory="$LIFELOG_DIR" reset --mixed >/dev/null',
            '    exit 1',
            '  fi',
            '}',
            "",
            'restore_runtime_paths() {',
            '  git -c safe.directory="$LIFELOG_DIR" restore --staged --worktree -- .direnv >/dev/null 2>&1 || true',
            '}',
            "",
            'load_github_token',
            'setup_git_auth',
            'mkdir -p "$(dirname "$LIFELOG_DIR")"',
            "",
            'if [ ! -d "$LIFELOG_DIR/.git" ]; then',
            '  if [ -e "$LIFELOG_DIR" ] && [ "$(find "$LIFELOG_DIR" -mindepth 1 -maxdepth 1 2>/dev/null | head -n 1)" != "" ]; then',
            '    echo "Hermes lifelog sync failed: $LIFELOG_DIR exists but is not an empty git repository"',
            '    exit 1',
            '  fi',
            '  rm -rf "$LIFELOG_DIR"',
            '  git clone --branch "$LIFELOG_BRANCH" "$LIFELOG_REMOTE_URL" "$LIFELOG_DIR"',
            'fi',
            "",
            'cd "$LIFELOG_DIR"',
            'if ! git -c safe.directory="$LIFELOG_DIR" config user.name >/dev/null; then',
            '  git -c safe.directory="$LIFELOG_DIR" config user.name "Hermes Lifelog Sync"',
            'fi',
            'if ! git -c safe.directory="$LIFELOG_DIR" config user.email >/dev/null; then',
            '  git -c safe.directory="$LIFELOG_DIR" config user.email "hermes-lifelog-sync@users.noreply.github.com"',
            'fi',
            'current_branch="$(git -c safe.directory="$LIFELOG_DIR" branch --show-current)"',
            'if [ "$current_branch" != "$LIFELOG_BRANCH" ]; then',
            '  echo "Hermes lifelog sync failed: expected branch $LIFELOG_BRANCH but found $current_branch"',
            '  exit 1',
            'fi',
            "",
            'restore_runtime_paths',
            'git -c safe.directory="$LIFELOG_DIR" add -A -- .',
            'refuse_secret_changes',
            'if ! git -c safe.directory="$LIFELOG_DIR" diff --cached --quiet; then',
            '  git -c safe.directory="$LIFELOG_DIR" commit -m "chore: sync lifelog $(date -u +%Y-%m-%d)" >/dev/null',
            '  echo "Hermes lifelog committed local changes."',
            'fi',
            "",
            'git -c safe.directory="$LIFELOG_DIR" pull --rebase origin "$LIFELOG_BRANCH"',
            'git -c safe.directory="$LIFELOG_DIR" push origin "$LIFELOG_BRANCH"',
            'if [ "${1:-}" = "--bootstrap" ]; then',
            '  echo "Hermes lifelog bootstrap completed."',
            'fi'
        )
    }

    hidden [bool] EnsureProfileRepositoryLayout([string]$dataDir, [string]$profileName) {
        $profileDir = Join-Path (Join-Path $dataDir "profiles") $profileName
        if (-not (Test-Path -LiteralPath $profileDir -PathType Container)) {
            return $false
        }

        $changed = $false
        $changed = $this.EnsureFileLines(
            (Join-Path $profileDir ".gitignore"),
            $this.GetProfileGitignoreLines()
        ) -or $changed

        $profileDocsDir = Join-Path $profileDir "docs"
        $this.EnsureDirectory($profileDocsDir)
        $changed = $this.RemoveDuplicatedProfileLayoutDoc($profileDir) -or $changed

        $changed = $this.EnsureManagedBlock(
            (Join-Path $profileDir "SOUL.md"),
            "HERMES_PROFILE_REPOSITORY_POLICY",
            @(
                "## Profile Repository Policy",
                "",
                "Before changing this profile home, read /opt/data/docs/profile-home-layout.md.",
                "Keep Hermes' standard filesystem layout intact; use Git ignore rules to keep runtime state and secrets out of the profile distribution."
            )
        ) -or $changed

        return $changed
    }

    hidden [bool] RemoveDuplicatedProfileLayoutDoc([string]$profileDir) {
        $profileLayoutDocPath = Join-Path (Join-Path $profileDir "docs") "profile-home-layout.md"
        if (-not (Test-Path -LiteralPath $profileLayoutDocPath -PathType Leaf)) {
            return $false
        }

        $existingLines = @(Get-Content -LiteralPath $profileLayoutDocPath -ErrorAction Stop)
        if (-not $this.LinesEqual($existingLines, $this.GetSharedHomeLayoutDocLines())) {
            return $false
        }

        Remove-Item -LiteralPath $profileLayoutDocPath -Force
        return $true
    }

    hidden [string[]] GetManagedProfileNames([SetupContext]$ctx) {
        $value = $ctx.GetOption("HermesAgentManagedProfiles", "rick,hoffman,risarisa")
        if ($value -is [array]) {
            return @($value | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }

        return @(
            ([string]$value).Split(",") |
                ForEach-Object { $_.Trim() } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
    }

    hidden [pscustomobject] SyncDashboardAuthToManagedProfileEnvironments(
        [SetupContext]$ctx,
        [string]$dataDir,
        [string]$sourceEnvPath
    ) {
        if (-not $this.IsTruthy($ctx.GetOption("HermesAgentSyncDashboardAuthToProfiles", $true))) {
            return [PSCustomObject]@{ Changed = $false; Source = "Disabled"; Count = 0; Profiles = @() }
        }

        if (-not (Test-Path -LiteralPath $sourceEnvPath -PathType Leaf)) {
            return [PSCustomObject]@{ Changed = $false; Source = "MissingSource"; Count = 0; Profiles = @() }
        }

        $sourceLines = @(Get-Content -LiteralPath $sourceEnvPath -ErrorAction Stop)
        $dashboardAuthLines = $this.GetDashboardAuthEnvLines($sourceLines)
        if (-not $this.HasDashboardAuth($dashboardAuthLines)) {
            return [PSCustomObject]@{ Changed = $false; Source = "MissingAuth"; Count = 0; Profiles = @() }
        }

        $profilesDir = Join-Path $dataDir "profiles"
        $changedProfiles = @()
        foreach ($profileName in $this.GetManagedProfileNames($ctx)) {
            $profileDir = Join-Path $profilesDir $profileName
            if (-not (Test-Path -LiteralPath $profileDir -PathType Container)) {
                continue
            }

            $profileEnvPath = Join-Path $profileDir ".env"
            $profileLines = @()
            if (Test-Path -LiteralPath $profileEnvPath -PathType Leaf) {
                $profileLines = @(Get-Content -LiteralPath $profileEnvPath -ErrorAction Stop)
            }

            $updatedLines = $this.SetDashboardAuthEnvLines($profileLines, $dashboardAuthLines)
            if (-not $this.LinesEqual($profileLines, $updatedLines)) {
                Set-Content -LiteralPath $profileEnvPath -Encoding UTF8 -Value $updatedLines
                $changedProfiles += $profileName
            }
        }

        return [PSCustomObject]@{
            Changed  = $changedProfiles.Count -gt 0
            Source   = "Synced"
            Count    = $changedProfiles.Count
            Profiles = $changedProfiles
        }
    }

    hidden [string[]] GetDashboardAuthEnvLines([string[]]$lines) {
        return @(
            $lines | Where-Object {
                $_ -match '^\s*HERMES_DASHBOARD_BASIC_AUTH_(USERNAME|PASSWORD_HASH|SECRET)\s*='
            }
        )
    }

    hidden [string[]] SetDashboardAuthEnvLines([string[]]$lines, [string[]]$dashboardAuthLines) {
        $filteredLines = @(
            $lines | Where-Object {
                $_ -notmatch '^\s*HERMES_DASHBOARD_BASIC_AUTH_(USERNAME|PASSWORD|PASSWORD_HASH|SECRET)\s*='
            }
        )

        if ($filteredLines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($filteredLines[-1])) {
            $filteredLines += ""
        }

        $filteredLines += $dashboardAuthLines
        return $filteredLines
    }

    hidden [bool] EnsureGitignoreEntry([string]$path, [string]$entry, [string]$comment) {
        $lines = @()
        if (Test-Path -LiteralPath $path) {
            $lines = @(Get-Content -LiteralPath $path -ErrorAction Stop)
        }

        if ($lines -contains $entry) {
            return $false
        }

        if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[-1])) {
            $lines += ""
        }
        $lines += "# $comment"
        $lines += $entry
        $this.EnsureDirectory((Split-Path -Parent $path))
        Set-Content -LiteralPath $path -Encoding UTF8 -Value $lines
        return $true
    }

    hidden [bool] EnsureFileLines([string]$path, [string[]]$desiredLines) {
        $existingLines = @()
        if (Test-Path -LiteralPath $path) {
            $existingLines = @(Get-Content -LiteralPath $path -ErrorAction Stop)
        }

        if ($this.LinesEqual($existingLines, $desiredLines)) {
            return $false
        }

        $this.EnsureDirectory((Split-Path -Parent $path))
        Set-Content -LiteralPath $path -Encoding UTF8 -Value $desiredLines
        return $true
    }

    hidden [bool] EnsureManagedBlock([string]$path, [string]$name, [string[]]$blockLines) {
        $begin = "<!-- BEGIN $name -->"
        $end = "<!-- END $name -->"
        $existingLines = @()
        if (Test-Path -LiteralPath $path) {
            $existingLines = @(Get-Content -LiteralPath $path -ErrorAction Stop)
        }

        $desiredBlock = @($begin) + $blockLines + @($end)
        $updatedLines = @()
        $index = 0
        $found = $false
        while ($index -lt $existingLines.Count) {
            if ($existingLines[$index] -eq $begin) {
                $found = $true
                $updatedLines += $desiredBlock
                $index++
                while ($index -lt $existingLines.Count -and $existingLines[$index] -ne $end) {
                    $index++
                }
                if ($index -lt $existingLines.Count) {
                    $index++
                }
                continue
            }

            $updatedLines += $existingLines[$index]
            $index++
        }

        if (-not $found) {
            if ($updatedLines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($updatedLines[-1])) {
                $updatedLines += ""
            }
            $updatedLines += $desiredBlock
        }

        if ($this.LinesEqual($existingLines, $updatedLines)) {
            return $false
        }

        $this.EnsureDirectory((Split-Path -Parent $path))
        Set-Content -LiteralPath $path -Encoding UTF8 -Value $updatedLines
        return $true
    }

    hidden [string[]] GetSlackAppRegistrationPolicyBlockLines() {
        return @(
            "## Slack App Registration Policy",
            "",
            "Before creating or updating a Slack App for a Hermes profile, read /opt/data/docs/slack-app-registration.md.",
            "Use Browser MCP for Slack UI automation and ask the user to complete login, 2FA, workspace selection, or consent in the visible noVNC browser when needed.",
            "Do not read generated Slack token values back through Browser MCP or tool output, shell arguments, Slack messages, or logs. Pause before token reveal or extraction and ask the user to capture and store secrets through noVNC or another approved non-logged secret channel. If no non-logging secret write path is available, leave the profile .env unchanged and report the blocked step."
        )
    }

    hidden [string[]] GetSlackAppRegistrationDocLines() {
        return @(
            "# Hermes Slack App Registration",
            "",
            "Use this guide when registering a Hermes managed profile as a Slack App through Browser MCP.",
            "",
            "## Visible Browser",
            "",
            "The host-visible browser viewer is:",
            "",
            '```text',
            $this.GetBrowserViewUrl(),
            '```',
            "",
            "This is the same browser session controlled by Hermes Browser MCP. Ask the user to open this URL when Slack requires login, 2FA, workspace selection, or consent.",
            "",
            "## Registration Flow",
            "",
            '1. Locate the profile directory, for example `/opt/data/profiles/nancy`.',
            '2. Read the profile''s `slack-manifest.json`.',
            '3. Open `https://api.slack.com/apps?new_app=1` with Browser MCP.',
            "4. Create the app from an app manifest and paste the manifest content.",
            "5. Review the Slack app settings and create the app.",
            '6. In Basic Information, generate an app-level token with `connections:write` for Socket Mode.',
            "7. Install the app to the workspace to obtain the bot token.",
            '8. Pause before token reveal or extraction and ask the user to capture and store values through noVNC or another approved non-logged secret channel.',
            '9. Write runtime credentials to the profile `.env` only after all values are available through that non-logging path.',
            "",
            "## Required Environment",
            "",
            '```text',
            "SLACK_BOT_TOKEN=xoxb-redacted",
            "SLACK_APP_TOKEN=xapp-redacted",
            "SLACK_ALLOWED_USERS=U04BDJU87KJ",
            '```',
            "",
            'If `.env` already has Slack credentials, ask before replacing them.',
            "",
            "## 1Password",
            "",
            'When the user wants persistent secret storage and 1Password is available, store the same fields in the matching `SlackBot-<ProfileTitle>` item. The install handler reads managed profile Slack credentials from that item naming convention.',
            "",
            "## Secret Safety",
            "",
            "- Do not read generated Slack token values back through Browser MCP or tool output.",
            "- Do not pass generated Slack token values through shell arguments, Slack messages, or logs.",
            "- Do not send generated Slack token values back into Slack.",
            '- Do not commit `.env`, `auth.json`, tokens, secrets, sessions, logs, or database files.',
            '- If no approved non-logged secret channel is available, leave the profile `.env` unchanged and report the exact blocked step.'
        )
    }

    hidden [string[]] GetSharedHomeLayoutDocLines() {
        return @(
            '# Hermes Agent Home/Profile Layout',
            '',
            'Hermes profile homes should keep the filesystem layout that Hermes expects, while Git tracks only the declarative distribution files.',
            '',
            '## Runtime Mounts',
            '',
            '- The Hermes Docker service mounts `~/.hermes` as `/opt/data`.',
            '- Inside the official Docker image, s6 supervises profile gateways as `/run/service/gateway-<profile>` within that same container.',
            '- Profile homes stay visible under `/opt/data/profiles/<profile>` and keep their own `.env`, config, cron, memory, sessions, and gateway state.',
            '- Do not run another Hermes gateway container against `~/.hermes` or any `~/.hermes/profiles/<profile>` directory while the root container can see that profile.',
            '- `HERMES_DATA_DIR` remains the Hermes home. Do not point it at lifelog; lifelog is restored under `~/.hermes/core/lifelog`.',
            '',
            '## Standard Profile Filesystem',
            '',
            '`hermes profile create <name>` scaffolds a usable profile home. Depending on flags and runtime activity, a profile home may contain files and directories such as:',
            '',
            '```text',
            '~/.hermes/profiles/<profile>/',
            '  .env',
            '  .gitignore',
            '  .no-bundled-skills',
            '  config.yaml',
            '  SOUL.md',
            '  profile.yaml',
            '  slack-manifest.json',
            '  assets/',
            '  docs/',
            '  cron/',
            '  home/',
            '  logs/',
            '  memories/',
            '  plans/',
            '  sessions/',
            '  skills/',
            '  skins/',
            '  workspace/',
            '  state.db*',
            '```',
            '',
            'Do not delete or flatten this physical layout just to make Git status smaller. Hermes and its gateway may recreate runtime directories as needed.',
            '',
            '## Git-Tracked Distribution',
            '',
            'Track durable, declarative profile content:',
            '',
            '- `config.yaml`',
            '- `SOUL.md`',
            '- `profile.yaml`',
            '- `.gitignore`',
            '- `.no-bundled-skills` when the profile intentionally has no bundled skills',
            '- `slack-manifest.json` when the profile has a Slack app',
            '- `assets/` for durable profile images and icons',
            '- `docs/` for profile-specific docs only; do not copy the shared root layout doc into each profile',
            '- curated profile-specific `skills/`, if intentionally maintained',
            '- declarative `cron/` definitions only, not cron output, locks, or tick files',
            '',
            '## Profile Gateway Runtime Secrets',
            '',
            'A profile gateway still needs runtime credentials inside that profile home, even when s6 runs it inside the root Docker container. Put dashboard auth, Slack tokens, and other env-based secrets in the profile `.env`; put model-provider auth in the profile `auth.json` or provider-specific env vars. Provision these locally or from a secrets manager, and keep them out of Git.',
            '',
            '## Ignored Runtime State',
            '',
            'Ignore secrets and live state:',
            '',
            '- `.env`, `.env.*`, `auth.json`, tokens, and secrets',
            '- `memories/`, `sessions/`, `logs/`, `state.db*`, gateway state, channel directories, locks, pids, caches, generated usage files, local workspaces, and transient cron output',
            '- default profile state copied by `--clone-all` unless it has been intentionally curated into the profile distribution',
            '',
            '## Profile Creation Notes',
            '',
            '- `hermes profile create <name>` creates a standard scaffold.',
            '- `hermes profile create --clone <name>` copies `config.yaml`, `.env`, `SOUL.md`, and `skills` from the source profile.',
            '- `hermes profile create --clone-all <name>` copies broader state and is not recommended for clean Git-managed distributions.',
            '- If a profile does not need bundled skills, use or keep `.no-bundled-skills` instead of tracking an empty `skills/` tree.',
            '',
            '## Shared Knowledge',
            '',
            'Do not share profile `memories/` through Git. Put durable shared guidance in `docs/` or repository `AGENTS.md` files, and use Slack, Hermes Kanban, GitHub issues, or Linear for cross-agent work state. If a shared memory backend is introduced later, namespace it by user, app, and profile.',
            '',
            '## Lifelog Core',
            '',
            '`install.cmd` restores the shared lifelog core at:',
            '',
            '```text',
            '~/.hermes/core/lifelog',
            '```',
            '',
            'Hermes gateways see it at:',
            '',
            '```text',
            '/opt/data/core/lifelog',
            '```',
            '',
            'Every managed profile should treat `/opt/data/core/lifelog/AGENTS.md` and relevant lifelog notes as the shared source of truth before making user-context decisions. The Hermes home repository ignores `core/`; lifelog is its own Git repository and is synced by the `lifelog_sync.sh` cron job.'
        )
    }

    hidden [string[]] GetProfileGitignoreLines() {
        return @(
            "# Secrets and credentials",
            ".env",
            ".env.*",
            "!.env.example",
            "auth.json",
            "*.pem",
            "*.key",
            "*token*",
            "*secret*",
            "",
            "# Live memory and conversation state",
            "memories/",
            "sessions/",
            "logs/",
            "state.db*",
            "*.db",
            "*.sqlite",
            "*.sqlite3",
            "gateway_state.json",
            "gateway.pid",
            "gateway.lock",
            "channel_directory.json",
            "",
            "# Runtime locks and generated files",
            "*.lock",
            "*.pid",
            "*-shm",
            "*-wal",
            ".skills_prompt_snapshot.json",
            "context_length_cache.yaml",
            "models_dev_cache.json",
            "ollama_cloud_models_cache.json",
            "provider_models_cache.json",
            "config.yaml.bak*",
            "cron/output/",
            "cron/.jobs.lock",
            "cron/.tick.lock",
            "cron/ticker_*",
            "",
            "# Caches and generated dependencies",
            "cache/",
            "audio_cache/",
            "image_cache/",
            ".cache/",
            ".local/",
            ".npm/",
            "lazy-packages/",
            "node_modules/",
            "bin/",
            "lsp/",
            "__pycache__/",
            "*.pyc",
            "*.pyo",
            "*.log",
            "*.tmp",
            "*.bak",
            "*.bak-*",
            "",
            "# Local workspaces and transient user files",
            "home/",
            "workspace/",
            "plans/",
            "pairing/",
            "sandboxes/",
            "",
            "# Generated skill state; keep curated skill content tracked separately.",
            "skills/.usage.json*",
            "skills/.curator_state"
        )
    }

    hidden [pscustomobject] EnsureModelConfiguration([SetupContext]$ctx, [string]$dataDir) {
        if (-not $this.IsTruthy($ctx.GetOption("HermesAgentModelConfigEnabled", $true))) {
            return [PSCustomObject]@{ Changed = $false; Source = "Disabled"; Provider = ""; Model = "" }
        }

        $provider = ([string]$ctx.GetOption("HermesAgentModelProvider", "openai-codex")).Trim()
        if ([string]::IsNullOrWhiteSpace($provider)) {
            $provider = "openai-codex"
        }

        $model = ([string]$ctx.GetOption("HermesAgentModelDefault", "gpt-5.5")).Trim()
        if ([string]::IsNullOrWhiteSpace($model)) {
            $model = "gpt-5.5"
        }

        $configPath = Join-Path $dataDir "config.yaml"
        $existingLines = @()
        if (Test-Path -LiteralPath $configPath) {
            $existingLines = @(Get-Content -LiteralPath $configPath -ErrorAction Stop)
        }

        $desiredLines = @(
            "model:",
            "  provider: $provider",
            "  default: $model"
        )
        $updatedLines = $this.SetModelConfigLines($existingLines, $desiredLines)
        $changed = -not $this.LinesEqual($existingLines, $updatedLines)
        if ($changed) {
            Set-Content -LiteralPath $configPath -Encoding UTF8 -Value $updatedLines
        }

        return [PSCustomObject]@{ Changed = $changed; Source = "Config"; Provider = $provider; Model = $model }
    }

    hidden [pscustomobject] EnsureMcpConfiguration([SetupContext]$ctx, [string]$dataDir) {
        if (-not $this.IsTruthy($ctx.GetOption("HermesAgentMcpConfigEnabled", $true))) {
            return [PSCustomObject]@{ Changed = $false; Source = "Disabled" }
        }

        $configTargets = @(
            [PSCustomObject]@{
                ConfigPath = Join-Path $dataDir "config.yaml"
                DataDir    = $dataDir
            }
        )

        $profilesDir = Join-Path $dataDir "profiles"
        foreach ($profileName in $this.GetManagedProfileNames($ctx)) {
            $profileDir = Join-Path $profilesDir $profileName
            if (Test-Path -LiteralPath $profileDir -PathType Container) {
                $configTargets += [PSCustomObject]@{
                    ConfigPath = Join-Path $profileDir "config.yaml"
                    DataDir    = $profileDir
                }
            }
        }

        $changedPaths = @()
        foreach ($target in $configTargets) {
            $configPath = $target.ConfigPath
            $targetDataDir = $target.DataDir
            $existingLines = @()
            if (Test-Path -LiteralPath $configPath) {
                $existingLines = @(Get-Content -LiteralPath $configPath -ErrorAction Stop)
            }

            $envPath = Join-Path $targetDataDir ".env"
            $envLines = @()
            if (Test-Path -LiteralPath $envPath) {
                $envLines = @(Get-Content -LiteralPath $envPath -ErrorAction Stop)
            }

            $includeXApi = $this.HasXApiMcpAuthentication($targetDataDir, $envLines)
            $updatedLines = $this.SetMcpConfigLines($existingLines, $includeXApi)
            if (-not $this.LinesEqual($existingLines, $updatedLines)) {
                $this.EnsureDirectory((Split-Path -Parent $configPath))
                Set-Content -LiteralPath $configPath -Encoding UTF8 -Value $updatedLines
                $changedPaths += $configPath
            }
        }

        return [PSCustomObject]@{
            Changed = $changedPaths.Count -gt 0
            Source  = "Config"
            Count   = $changedPaths.Count
            Paths   = $changedPaths
        }
    }

    hidden [pscustomobject] EnsureTerminalEnvironmentPassthroughConfiguration([SetupContext]$ctx, [string]$dataDir) {
        if (-not $this.IsTruthy($ctx.GetOption("HermesAgentTerminalEnvPassthroughEnabled", $true))) {
            return [PSCustomObject]@{ Changed = $false; Source = "Disabled"; Count = 0; Paths = @() }
        }

        $configPaths = @((Join-Path $dataDir "config.yaml"))
        $profilesDir = Join-Path $dataDir "profiles"
        foreach ($profileName in $this.GetManagedProfileNames($ctx)) {
            $profileDir = Join-Path $profilesDir $profileName
            if (Test-Path -LiteralPath $profileDir -PathType Container) {
                $configPaths += (Join-Path $profileDir "config.yaml")
            }
        }

        $changedPaths = @()
        foreach ($configPath in $configPaths) {
            $existingLines = @()
            if (Test-Path -LiteralPath $configPath -PathType Leaf) {
                $existingLines = @(Get-Content -LiteralPath $configPath -ErrorAction Stop)
            }

            $updatedLines = $this.SetTerminalEnvPassthroughConfigLines($existingLines)
            if (-not $this.LinesEqual($existingLines, $updatedLines)) {
                $this.EnsureDirectory((Split-Path -Parent $configPath))
                Set-Content -LiteralPath $configPath -Encoding UTF8 -Value $updatedLines
                $changedPaths += $configPath
            }
        }

        return [PSCustomObject]@{
            Changed = $changedPaths.Count -gt 0
            Source  = "Config"
            Count   = $changedPaths.Count
            Paths   = $changedPaths
        }
    }

    hidden [pscustomobject] EnsureSlackMentionConfiguration([SetupContext]$ctx, [string]$dataDir) {
        if (-not $this.IsTruthy($ctx.GetOption("HermesAgentSlackRespondWithoutMention", $true))) {
            return [PSCustomObject]@{ Changed = $false; Source = "Disabled"; Count = 0; Paths = @() }
        }

        $configPaths = @((Join-Path $dataDir "config.yaml"))
        $profilesDir = Join-Path $dataDir "profiles"
        foreach ($profileName in $this.GetManagedProfileNames($ctx)) {
            $profileConfigPath = Join-Path (Join-Path $profilesDir $profileName) "config.yaml"
            if (Test-Path -LiteralPath $profileConfigPath -PathType Leaf) {
                $configPaths += $profileConfigPath
            }
        }

        $changedPaths = @()
        foreach ($configPath in $configPaths) {
            $existingLines = @()
            if (Test-Path -LiteralPath $configPath -PathType Leaf) {
                $existingLines = @(Get-Content -LiteralPath $configPath -ErrorAction Stop)
            }

            $updatedLines = $this.SetSlackMentionConfigLines($existingLines)
            if (-not $this.LinesEqual($existingLines, $updatedLines)) {
                $this.EnsureDirectory((Split-Path -Parent $configPath))
                Set-Content -LiteralPath $configPath -Encoding UTF8 -Value $updatedLines
                $changedPaths += $configPath
            }
        }

        return [PSCustomObject]@{
            Changed = $changedPaths.Count -gt 0
            Source  = "Config"
            Count   = $changedPaths.Count
            Paths   = $changedPaths
        }
    }

    hidden [string[]] SetTerminalEnvPassthroughConfigLines([string[]]$lines) {
        $managedEnvNames = @(
            "GITHUB_PERSONAL_ACCESS_TOKEN"
        )
        $removedEnvNames = @(
            "GH_TOKEN",
            "GITHUB_TOKEN"
        )
        $managedLines = @("  env_passthrough:") + @($managedEnvNames | ForEach-Object { "    - $_" })
        $desiredBlock = @("terminal:") + $managedLines

        if ($lines.Count -eq 0) {
            return $desiredBlock
        }

        $terminalStart = -1
        for ($index = 0; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -match '^terminal\s*:') {
                $terminalStart = $index
                break
            }
        }

        if ($terminalStart -lt 0) {
            $result = @($lines)
            if ($result.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($result[-1])) {
                $result += ""
            }
            $result += $desiredBlock
            return $result
        }

        $terminalEnd = $terminalStart + 1
        while ($terminalEnd -lt $lines.Count) {
            if ($lines[$terminalEnd] -match '^\S[^:]*\s*:') {
                break
            }
            $terminalEnd++
        }

        $existingBlock = @($lines[$terminalStart..($terminalEnd - 1)])
        $preservedChildLines = @()
        $preservedEnvNames = @()
        $childIndex = 1
        while ($childIndex -lt $existingBlock.Count) {
            if ($existingBlock[$childIndex] -match '^\s{2}env_passthrough\s*:') {
                $childIndex++
                while (
                    $childIndex -lt $existingBlock.Count `
                        -and $existingBlock[$childIndex] -notmatch '^\s{2}\S[^:]*\s*:' `
                        -and $existingBlock[$childIndex] -notmatch '^\S'
                ) {
                    if ($existingBlock[$childIndex] -match '^\s{4}-\s*(?<name>[^#\s]+)\s*(?:#.*)?$') {
                        $envName = $Matches["name"].Trim("'`"")
                        if (
                            $removedEnvNames -notcontains $envName `
                                -and $preservedEnvNames -notcontains $envName
                        ) {
                            $preservedEnvNames += $envName
                        }
                    }
                    $childIndex++
                }
                continue
            }

            $preservedChildLines += $existingBlock[$childIndex]
            $childIndex++
        }

        $envNames = @($preservedEnvNames)
        foreach ($managedEnvName in $managedEnvNames) {
            if ($envNames -notcontains $managedEnvName) {
                $envNames += $managedEnvName
            }
        }
        $envPassthroughLines = @("  env_passthrough:") + @($envNames | ForEach-Object { "    - $_" })
        $newBlock = @("terminal:") + $preservedChildLines + $envPassthroughLines
        $result = @()
        if ($terminalStart -gt 0) {
            $result += $lines[0..($terminalStart - 1)]
        }
        $result += $newBlock
        if ($terminalEnd -lt $lines.Count) {
            $result += $lines[$terminalEnd..($lines.Count - 1)]
        }
        return $result
    }

    hidden [string[]] SetSlackMentionConfigLines([string[]]$lines) {
        $managedLines = @(
            "  require_mention: true",
            "  strict_mention: false",
            "  allow_bots: mentions"
        )
        $desiredBlock = @("slack:") + $managedLines

        if ($lines.Count -eq 0) {
            return $desiredBlock
        }

        $slackStart = -1
        for ($index = 0; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -match '^slack\s*:') {
                $slackStart = $index
                break
            }
        }

        if ($slackStart -lt 0) {
            $result = @($lines)
            if ($result.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($result[-1])) {
                $result += ""
            }
            $result += $desiredBlock
            return $result
        }

        $slackEnd = $slackStart + 1
        while ($slackEnd -lt $lines.Count) {
            if ($lines[$slackEnd] -match '^\S[^:]*\s*:') {
                break
            }
            $slackEnd++
        }

        $existingBlock = @($lines[$slackStart..($slackEnd - 1)])
        $preservedChildLines = @(
            $existingBlock |
                Select-Object -Skip 1 |
                Where-Object { $_ -notmatch '^\s{2}(require_mention|strict_mention|allow_bots)\s*:' }
        )

        $newBlock = @("slack:") + $managedLines + $preservedChildLines
        $result = @()
        if ($slackStart -gt 0) {
            $result += $lines[0..($slackStart - 1)]
        }
        $result += $newBlock
        if ($slackEnd -lt $lines.Count) {
            $result += $lines[$slackEnd..($lines.Count - 1)]
        }
        return $result
    }

    hidden [string[]] SetMcpConfigLines([string[]]$lines, [bool]$includeXApi) {
        $managedServerNames = @("github", "xapi", "x-docs", "browser", "chrome")
        $desiredLines = @()
        if ($includeXApi) {
            $desiredLines += @(
                "  xapi:",
                "    command: /usr/local/bin/hermes-xapi-mcp",
                "    connect_timeout: 300",
                "    env:",
                '      X_API_CLIENT_ID: ${X_API_CLIENT_ID}',
                '      X_API_CLIENT_SECRET: ${X_API_CLIENT_SECRET}'
            )
        }

        $desiredLines += @(
            "  x-docs:",
            "    url: https://docs.x.com/mcp",
            "    connect_timeout: 60",
            "  chrome:",
            "    url: http://browser-mcp:8080/mcp",
            "    connect_timeout: 120"
        )
        $result = @()
        $index = 0
        $foundMcpServers = $false
        while ($index -lt $lines.Count) {
            if ($lines[$index] -match '^mcp_servers\s*:') {
                $foundMcpServers = $true
                $mcpHeader = $lines[$index]
                $mcpLines = @()
                $index++

                while ($index -lt $lines.Count -and $lines[$index] -notmatch '^\S') {
                    if ($lines[$index] -match '^\s{2}(\S[^:]*)\s*:') {
                        $serverName = $Matches[1]
                        if ($serverName -in $managedServerNames) {
                            $index++
                            while (
                                $index -lt $lines.Count `
                                    -and $lines[$index] -notmatch '^\S' `
                                    -and $lines[$index] -notmatch '^\s{2}\S[^:]*\s*:'
                            ) {
                                $index++
                            }
                            continue
                        }
                    }

                    $mcpLines += $lines[$index]
                    $index++
                }

                $result += $mcpHeader
                $result += $mcpLines
                $result += $desiredLines
                continue
            }

            $result += $lines[$index]
            $index++
        }

        if (-not $foundMcpServers) {
            if ($result.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($result[-1])) {
                $result += ""
            }
            $result += "mcp_servers:"
            $result += $desiredLines
        }

        return $result
    }

    hidden [bool] HasXApiMcpAuthentication([string]$dataDir, [string[]]$envLines) {
        $clientId = $this.GetEnvLineValue($envLines, "X_API_CLIENT_ID")
        $clientSecret = $this.GetEnvLineValue($envLines, "X_API_CLIENT_SECRET")
        if ($this.HasRealEnvValue($clientId) -and $this.HasRealEnvValue($clientSecret)) {
            return $true
        }

        $xurlDir = Join-Path $dataDir ".xurl"
        if (-not (Test-Path -LiteralPath $xurlDir -PathType Container)) {
            return $false
        }

        $cacheFile = Get-ChildItem -LiteralPath $xurlDir -Force -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        return $null -ne $cacheFile
    }

    hidden [string] GetEnvLineValue([string[]]$lines, [string]$name) {
        $escapedName = [regex]::Escape($name)
        foreach ($line in $lines) {
            if ($line -match "^\s*(?:export\s+)?$escapedName\s*=\s*(?<value>.*)\s*$") {
                return $Matches["value"]
            }
        }

        return $null
    }

    hidden [bool] HasRealEnvValue([string]$value) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            return $false
        }

        $trimmed = $value.Trim()
        if ($trimmed.Length -ge 2) {
            $first = $trimmed.Substring(0, 1)
            $last = $trimmed.Substring($trimmed.Length - 1, 1)
            if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
                $trimmed = $trimmed.Substring(1, $trimmed.Length - 2).Trim()
            }
        }

        return -not [string]::IsNullOrWhiteSpace($trimmed) -and $trimmed -notmatch '^\$\{[^}]+\}$'
    }

    hidden [string[]] RemoveGithubMcpConfigLines([string[]]$lines) {
        if ($lines.Count -eq 0) {
            return $lines
        }

        $result = @()
        $index = 0
        while ($index -lt $lines.Count) {
            if ($lines[$index] -match '^mcp_servers\s*:') {
                $mcpHeader = $lines[$index]
                $mcpLines = @()
                $index++

                while ($index -lt $lines.Count -and $lines[$index] -notmatch '^\S') {
                    if ($lines[$index] -match '^\s{2}github\s*:') {
                        $index++
                        while (
                            $index -lt $lines.Count `
                                -and $lines[$index] -notmatch '^\S' `
                                -and $lines[$index] -notmatch '^\s{2}\S[^:]*\s*:'
                        ) {
                            $index++
                        }
                        continue
                    }

                    $mcpLines += $lines[$index]
                    $index++
                }

                if ($mcpLines.Count -gt 0) {
                    $result += $mcpHeader
                    $result += $mcpLines
                }
                continue
            }

            $result += $lines[$index]
            $index++
        }

        return $result
    }

    hidden [string[]] SetModelConfigLines([string[]]$lines, [string[]]$desiredLines) {
        $cleanedLines = @(
            $lines | Where-Object {
                $_ -notmatch '^model\.(default|provider)\s*:'
            }
        )

        if ($cleanedLines.Count -eq 0) {
            return $desiredLines
        }

        $modelStart = -1
        for ($index = 0; $index -lt $cleanedLines.Count; $index++) {
            if ($cleanedLines[$index] -match '^model\s*:') {
                $modelStart = $index
                break
            }
        }

        if ($modelStart -lt 0) {
            $result = @()
            $result += $desiredLines
            if (-not [string]::IsNullOrWhiteSpace($cleanedLines[0])) {
                $result += ""
            }
            $result += $cleanedLines
            return $result
        }

        $modelEnd = $modelStart + 1
        while ($modelEnd -lt $cleanedLines.Count) {
            $line = $cleanedLines[$modelEnd]
            if ($line -match '^\S[^:]*\s*:') {
                break
            }
            $modelEnd++
        }

        $result = @()
        if ($modelStart -gt 0) {
            $result += $cleanedLines[0..($modelStart - 1)]
        }
        $result += $desiredLines
        if ($modelEnd -lt $cleanedLines.Count) {
            $result += $cleanedLines[$modelEnd..($cleanedLines.Count - 1)]
        }
        return $result
    }

    hidden [bool] LinesEqual([string[]]$left, [string[]]$right) {
        if ($left.Count -ne $right.Count) {
            return $false
        }

        for ($index = 0; $index -lt $left.Count; $index++) {
            if ($left[$index] -ne $right[$index]) {
                return $false
            }
        }
        return $true
    }

    hidden [pscustomobject] EnsureDashboardAuth([SetupContext]$ctx, [string]$envPath, [string]$infoFilePath) {
        $lines = @()
        if (Test-Path -LiteralPath $envPath) {
            $lines = @(Get-Content -LiteralPath $envPath -ErrorAction Stop)
        }

        $onePasswordCredentials = $this.GetOnePasswordDashboardCredentials($ctx)
        if ($null -ne $onePasswordCredentials) {
            $secureSecret = $this.NewSecureString([string]$onePasswordCredentials.Password)
            $dashboardCredential = [System.Management.Automation.PSCredential]::new(
                [string]$onePasswordCredentials.Username,
                $secureSecret
            )
            $credentials = $this.NewDashboardCredentialsFromCredential($dashboardCredential)
            $this.WriteDashboardAuth($envPath, $lines, $credentials)
            if (Test-Path -LiteralPath $infoFilePath) {
                Remove-Item -LiteralPath $infoFilePath -Force
            }
            return [PSCustomObject]@{ Changed = $true; Source = "1Password" }
        }

        if ($this.HasDashboardAuth($lines)) {
            return [PSCustomObject]@{ Changed = $false; Source = "Existing" }
        }

        $credentials = $this.NewDashboardCredentials()
        $this.WriteDashboardAuth($envPath, $lines, $credentials)
        Set-Content -LiteralPath $infoFilePath -Encoding UTF8 -Value @(
            "url=http://127.0.0.1:9119",
            "username=$($credentials.Username)",
            "password=$($credentials.Password)"
        )
        return [PSCustomObject]@{ Changed = $true; Source = "Generated" }
    }

    hidden [pscustomobject] EnsureSlackEnvironment([SetupContext]$ctx, [string]$envPath) {
        $lines = @()
        if (Test-Path -LiteralPath $envPath) {
            $lines = @(Get-Content -LiteralPath $envPath -ErrorAction Stop)
        }

        $slackEnvironment = $this.GetOnePasswordSlackEnvironment($ctx)
        if ($null -ne $slackEnvironment) {
            $this.WriteSlackEnvironment($envPath, $lines, $slackEnvironment)
            return [PSCustomObject]@{ Changed = $true; Source = "1Password" }
        }

        if ($this.HasSlackEnvironment($lines)) {
            return [PSCustomObject]@{ Changed = $false; Source = "Existing" }
        }

        return [PSCustomObject]@{ Changed = $false; Source = "Missing" }
    }

    hidden [pscustomobject] EnsureGitHubEnvironment([SetupContext]$ctx, [string]$envPath) {
        $lines = @()
        if (Test-Path -LiteralPath $envPath) {
            $lines = @(Get-Content -LiteralPath $envPath -ErrorAction Stop)
        }

        $existingToken = $null
        foreach ($name in @("GITHUB_PERSONAL_ACCESS_TOKEN", "GITHUB_PAT_TOKEN", "GH_TOKEN", "GITHUB_TOKEN")) {
            $candidate = $this.GetEnvLineValue($lines, $name)
            if ($this.HasRealEnvValue($candidate)) {
                $existingToken = $candidate.Trim().Trim('"').Trim("'")
                break
            }
        }

        if ([string]::IsNullOrWhiteSpace($existingToken)) {
            $existingToken = $this.GetOnePasswordGitHubToken($ctx)
        }

        if ([string]::IsNullOrWhiteSpace($existingToken)) {
            return [PSCustomObject]@{ Changed = $false; Source = "Missing" }
        }

        $environment = @{
            GITHUB_PERSONAL_ACCESS_TOKEN = $existingToken
            GH_TOKEN                     = $existingToken
            GITHUB_TOKEN                 = $existingToken
        }
        $updatedLines = $this.SetNamedEnvironmentLines($lines, $environment)
        $changed = -not $this.LinesEqual($lines, $updatedLines)
        if ($changed) {
            Set-Content -LiteralPath $envPath -Encoding UTF8 -Value $updatedLines
        }

        $source = if ($this.HasRealEnvValue($this.GetEnvLineValue($lines, "GITHUB_PERSONAL_ACCESS_TOKEN"))) {
            "Existing"
        }
        else {
            "1Password"
        }
        return [PSCustomObject]@{ Changed = $changed; Source = $source }
    }

    hidden [pscustomobject] EnsureManagedProfileSlackEnvironments([SetupContext]$ctx, [string]$dataDir) {
        $defaultEnabled = $this.IsTruthy($ctx.GetOption("HermesAgentSlack1PasswordEnabled", $true))
        $profilesDir = Join-Path $dataDir "profiles"
        $changedProfiles = @()
        $existingProfiles = @()
        $missingProfiles = @()

        foreach ($profileName in $this.GetManagedProfileNames($ctx)) {
            $profileDir = Join-Path $profilesDir $profileName
            $envPath = Join-Path $profileDir ".env"
            if (-not (Test-Path -LiteralPath $profileDir -PathType Container)) {
                continue
            }

            $profileTitle = $this.GetManagedProfileTitle($profileName)
            $lines = @()
            if (Test-Path -LiteralPath $envPath -PathType Leaf) {
                $lines = @(Get-Content -LiteralPath $envPath -ErrorAction Stop)
            }
            $slackEnvironment = $this.GetOnePasswordSlackEnvironmentForItem(
                $ctx,
                "HermesAgent$($profileTitle)Slack1PasswordEnabled",
                $defaultEnabled,
                "HermesAgentRequire$($profileTitle)Slack",
                "HermesAgent$($profileTitle)Slack1PasswordAccount",
                "HermesAgent$($profileTitle)Slack1PasswordVault",
                "HermesAgent$($profileTitle)Slack1PasswordItem",
                "SlackBot-$profileTitle"
            )
            if ($null -ne $slackEnvironment) {
                $this.WriteSlackEnvironment($envPath, $lines, $slackEnvironment, $true)
                $changedProfiles += $profileName
                continue
            }

            if ($this.HasSlackEnvironment($lines)) {
                $existingProfiles += $profileName
                continue
            }

            $missingProfiles += $profileName
        }

        return [PSCustomObject]@{
            Changed  = $changedProfiles.Count -gt 0
            Source   = "1Password"
            Count    = $changedProfiles.Count
            Profiles = $changedProfiles
            Existing = $existingProfiles
            Missing  = $missingProfiles
        }
    }

    hidden [string] GetManagedProfileTitle([string]$profileName) {
        if ([string]::IsNullOrWhiteSpace($profileName)) {
            return ""
        }

        $textInfo = [System.Globalization.CultureInfo]::InvariantCulture.TextInfo
        return $textInfo.ToTitleCase($profileName.ToLowerInvariant())
    }

    hidden [void] WriteDashboardAuth([string]$envPath, [string[]]$lines, [pscustomobject]$credentials) {
        $filteredLines = @(
            $lines | Where-Object {
                $_ -notmatch '^\s*HERMES_DASHBOARD_BASIC_AUTH_(USERNAME|PASSWORD|PASSWORD_HASH|SECRET)\s*='
            }
        )

        if ($filteredLines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($filteredLines[-1])) {
            $filteredLines += ""
        }

        $filteredLines += "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=$($credentials.Username)"
        $filteredLines += "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=$($credentials.PasswordHash)"
        $filteredLines += "HERMES_DASHBOARD_BASIC_AUTH_SECRET=$($credentials.Secret)"

        Set-Content -LiteralPath $envPath -Value $filteredLines -Encoding UTF8
    }

    hidden [void] WriteSlackEnvironment([string]$envPath, [string[]]$lines, [pscustomobject]$environment) {
        $this.WriteSlackEnvironment($envPath, $lines, $environment, $false)
    }

    hidden [void] WriteSlackEnvironment([string]$envPath, [string[]]$lines, [pscustomobject]$environment, [bool]$removeSharedPlatformSecrets) {
        $filteredLines = @(
            $lines | Where-Object {
                $_ -notmatch '^\s*SLACK_(BOT_TOKEN|APP_TOKEN|ALLOWED_USERS)\s*=' -and
                (-not $removeSharedPlatformSecrets -or -not $this.IsSharedPlatformSecretLine($_))
            }
        )

        if ($filteredLines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($filteredLines[-1])) {
            $filteredLines += ""
        }

        $filteredLines += "SLACK_BOT_TOKEN=$($environment.BotToken)"
        $filteredLines += "SLACK_APP_TOKEN=$($environment.AppToken)"
        $filteredLines += "SLACK_ALLOWED_USERS=$($environment.AllowedUsers)"

        Set-Content -LiteralPath $envPath -Value $filteredLines -Encoding UTF8
    }

    hidden [string[]] SetNamedEnvironmentLines([string[]]$lines, [hashtable]$environment) {
        $keys = @($environment.Keys | Sort-Object)
        if ($keys.Count -eq 0) {
            return $lines
        }

        $escapedKeys = @($keys | ForEach-Object { [regex]::Escape([string]$_) })
        $pattern = '^\s*(?:export\s+)?(' + ($escapedKeys -join '|') + ')\s*='
        $filteredLines = @(
            $lines | Where-Object { $_ -notmatch $pattern }
        )

        if ($filteredLines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($filteredLines[-1])) {
            $filteredLines += ""
        }

        foreach ($key in $keys) {
            $filteredLines += "$key=$($environment[$key])"
        }

        return $filteredLines
    }

    hidden [bool] IsSharedPlatformSecretLine([string]$line) {
        if ($line -notmatch '^\s*(?:export\s+)?(?<name>[A-Z0-9_]+)\s*=') {
            return $false
        }

        return $this.IsSharedPlatformSecretName($Matches["name"])
    }

    hidden [bool] IsSharedPlatformSecretName([string]$name) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            return $false
        }

        return $name.Trim() -match '^(TELEGRAM_BOT_TOKEN|DISCORD_BOT_TOKEN|DISCORD_TOKEN|WHATSAPP_[A-Z0-9_]+|SIGNAL_[A-Z0-9_]+|TEAMS_[A-Z0-9_]+|QQBOT_[A-Z0-9_]+|YUANBAO_[A-Z0-9_]+|HOMEASSISTANT_[A-Z0-9_]+)$'
    }

    hidden [bool] HasDashboardAuth([string[]]$lines) {
        $required = @{
            HERMES_DASHBOARD_BASIC_AUTH_USERNAME      = $false
            HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH = $false
            HERMES_DASHBOARD_BASIC_AUTH_SECRET        = $false
        }

        foreach ($line in $lines) {
            if ($line -match '^\s*([^#=\s]+)\s*=(.*)$') {
                $key = $Matches[1]
                $value = $Matches[2]
                if ($required.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace($value)) {
                    $required[$key] = $true
                }
            }
        }

        foreach ($key in $required.Keys) {
            if (-not $required[$key]) {
                return $false
            }
        }
        return $true
    }

    hidden [bool] HasSlackEnvironment([string[]]$lines) {
        $required = @{
            SLACK_BOT_TOKEN     = $false
            SLACK_APP_TOKEN     = $false
            SLACK_ALLOWED_USERS = $false
        }

        foreach ($line in $lines) {
            if ($line -match '^\s*([^#=\s]+)\s*=(.*)$') {
                $key = $Matches[1]
                $value = $Matches[2]
                if ($required.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace($value)) {
                    $required[$key] = $true
                }
            }
        }

        foreach ($key in $required.Keys) {
            if (-not $required[$key]) {
                return $false
            }
        }
        return $true
    }

    hidden [pscustomobject] GetOnePasswordDashboardCredentials([SetupContext]$ctx) {
        if (-not $this.IsTruthy($ctx.GetOption("HermesAgent1PasswordEnabled", $true))) {
            return $null
        }

        $required = $this.IsTruthy($ctx.GetOption("HermesAgentRequire1Password", $false))
        $opCommand = @(Get-Command -Name "op" -ErrorAction SilentlyContinue | Select-Object -First 1)
        if (-not $opCommand) {
            if ($required) {
                throw "1Password CLI (op) が見つかりません"
            }
            $this.Log("1Password CLI が見つからないため Hermes dashboard credential の自動取得をスキップします", "Gray")
            return $null
        }

        $opExe = [string]$opCommand.Source
        if ([string]::IsNullOrWhiteSpace($opExe) -and $opCommand.PSObject.Properties.Name -contains "Path") {
            $opExe = [string]$opCommand.Path
        }
        if ([string]::IsNullOrWhiteSpace($opExe)) {
            $opExe = "op"
        }

        $account = [string]$ctx.GetOption("HermesAgent1PasswordAccount", "my.1password.com")
        $vault = [string]$ctx.GetOption("HermesAgent1PasswordVault", "Private")
        $item = [string]$ctx.GetOption("HermesAgent1PasswordItem", "Hermes Agent Dashboard")
        $arguments = @("item", "get", $item, "--account", $account, "--vault", $vault, "--format", "json")
        $result = Invoke-OpCommand -OpExe $opExe -Arguments $arguments
        if ($result.ExitCode -ne 0) {
            if ($required) {
                throw "1Password から Hermes dashboard credential を取得できません"
            }
            $this.Log("1Password から Hermes dashboard credential を取得できないためローカル生成にフォールバックします", "Gray")
            return $null
        }

        try {
            $itemJson = ($result.Output -join "`n") | ConvertFrom-Json -ErrorAction Stop
            $username = $this.GetOnePasswordFieldValue($itemJson, "USERNAME", @("username", "user name"))
            $password = $this.GetOnePasswordFieldValue($itemJson, "PASSWORD", @("password"))
            if ([string]::IsNullOrWhiteSpace($username) -or [string]::IsNullOrWhiteSpace($password)) {
                if ($required) {
                    throw "1Password item に username/password がありません"
                }
                $this.Log("1Password item に username/password がないためローカル生成にフォールバックします", "Gray")
                return $null
            }

            return [PSCustomObject]@{
                Username = $username
                Password = $password
            }
        }
        catch {
            if ($required) {
                throw
            }
            $this.Log("1Password item を読めないためローカル生成にフォールバックします", "Gray")
            return $null
        }
    }

    hidden [string] GetOnePasswordGitHubToken([SetupContext]$ctx) {
        if (-not $this.IsTruthy($ctx.GetOption("HermesAgentGitHub1PasswordEnabled", $true))) {
            return $null
        }

        $required = $this.IsTruthy($ctx.GetOption("HermesAgentRequireGitHub", $false))
        $opCommand = @(Get-Command -Name "op" -ErrorAction SilentlyContinue | Select-Object -First 1)
        if (-not $opCommand) {
            if ($required) {
                throw "Hermes lifelog sync 用の 1Password CLI (op) が見つかりません"
            }
            return $null
        }

        $opExe = [string]$opCommand.Source
        if ([string]::IsNullOrWhiteSpace($opExe) -and $opCommand.PSObject.Properties.Name -contains "Path") {
            $opExe = [string]$opCommand.Path
        }
        if ([string]::IsNullOrWhiteSpace($opExe)) {
            $opExe = "op"
        }

        $account = [string]$ctx.GetOption("HermesAgentGitHub1PasswordAccount", "my.1password.com")
        $vault = [string]$ctx.GetOption("HermesAgentGitHub1PasswordVault", "Private")
        $item = [string]$ctx.GetOption("HermesAgentGitHub1PasswordItem", "GitHubUsedUserPAT")
        $result = Invoke-OpCommand -OpExe $opExe -Arguments @(
            "item", "get", $item, "--account", $account, "--vault", $vault, "--format", "json"
        )
        if ($result.ExitCode -ne 0) {
            if ($required) {
                throw "1Password から Hermes lifelog sync 用 GitHub token を取得できません: $item"
            }
            return $null
        }

        try {
            $itemJson = ($result.Output -join "`n") | ConvertFrom-Json -ErrorAction Stop
            $token = $this.GetOnePasswordFieldValue($itemJson, "", @("credential", "token", "PAT", "password"))
            if ([string]::IsNullOrWhiteSpace($token) -and $required) {
                throw "1Password item に GitHub token がありません: $item"
            }
            return $token
        }
        catch {
            if ($required) {
                throw
            }
            return $null
        }
    }

    hidden [pscustomobject] GetOnePasswordSlackEnvironment([SetupContext]$ctx) {
        return $this.GetOnePasswordSlackEnvironmentForItem(
            $ctx,
            "HermesAgentSlack1PasswordEnabled",
            $true,
            "HermesAgentRequireSlack",
            "HermesAgentSlack1PasswordAccount",
            "HermesAgentSlack1PasswordVault",
            "HermesAgentSlack1PasswordItem",
            "SlackBot-Hermes"
        )
    }

    hidden [pscustomobject] GetOnePasswordSlackEnvironmentForItem(
        [SetupContext]$ctx,
        [string]$enabledOption,
        [bool]$enabledDefault,
        [string]$requiredOption,
        [string]$accountOption,
        [string]$vaultOption,
        [string]$itemOption,
        [string]$defaultItem
    ) {
        if (-not $this.IsTruthy($ctx.GetOption($enabledOption, $enabledDefault))) {
            return $null
        }

        $required = $this.IsTruthy($ctx.GetOption($requiredOption, $true))
        $opCommand = @(Get-Command -Name "op" -ErrorAction SilentlyContinue | Select-Object -First 1)
        if (-not $opCommand) {
            if ($required) {
                throw "Slack 接続用の 1Password CLI (op) が見つかりません"
            }
            $this.Log("1Password CLI が見つからないため Hermes Slack 接続情報の自動取得をスキップします", "Gray")
            return $null
        }

        $opExe = [string]$opCommand.Source
        if ([string]::IsNullOrWhiteSpace($opExe) -and $opCommand.PSObject.Properties.Name -contains "Path") {
            $opExe = [string]$opCommand.Path
        }
        if ([string]::IsNullOrWhiteSpace($opExe)) {
            $opExe = "op"
        }

        $account = [string]$ctx.GetOption($accountOption, "my.1password.com")
        $vault = [string]$ctx.GetOption($vaultOption, "Private")
        $item = [string]$ctx.GetOption($itemOption, $defaultItem)
        $arguments = @("item", "get", $item, "--account", $account, "--vault", $vault, "--format", "json")
        $result = Invoke-OpCommand -OpExe $opExe -Arguments $arguments
        if ($result.ExitCode -ne 0) {
            if ($required) {
                throw "1Password から Hermes Slack 接続情報を取得できません: $item"
            }
            $this.Log("1Password から Hermes Slack 接続情報を取得できないため Slack 自動設定をスキップします: $item", "Gray")
            return $null
        }

        try {
            $itemJson = ($result.Output -join "`n") | ConvertFrom-Json -ErrorAction Stop
            $botToken = $this.GetOnePasswordFieldValue($itemJson, "", @("SLACK_BOT_TOKEN", "bot_token", "bot token"))
            $appToken = $this.GetOnePasswordFieldValue($itemJson, "", @("SLACK_APP_TOKEN", "app_level_token", "app token", "app-level token"))
            $allowedUsers = $this.GetOnePasswordFieldValue($itemJson, "", @("SLACK_ALLOWED_USERS", "allowed_users", "allowed users", "allowFrom", "allow_from"))
            if (
                [string]::IsNullOrWhiteSpace($botToken) -or
                [string]::IsNullOrWhiteSpace($appToken) -or
                [string]::IsNullOrWhiteSpace($allowedUsers)
            ) {
                if ($required) {
                    throw "1Password item に Slack token または allowed users がありません: $item"
                }
                $this.Log("1Password item に Slack token または allowed users がないため Slack 自動設定をスキップします: $item", "Gray")
                return $null
            }

            return [PSCustomObject]@{
                BotToken     = $botToken
                AppToken     = $appToken
                AllowedUsers = $allowedUsers
            }
        }
        catch {
            if ($required) {
                throw
            }
            $this.Log("1Password item を読めないため Slack 自動設定をスキップします: $item", "Gray")
            return $null
        }
    }

    hidden [string] GetOnePasswordFieldValue([pscustomobject]$item, [string]$purpose, [string[]]$names) {
        $fields = @($item.fields)
        if (-not [string]::IsNullOrWhiteSpace($purpose)) {
            foreach ($field in $fields) {
                $fieldPurpose = ([string]$field.purpose).Trim()
                if ($fieldPurpose -eq $purpose -and -not [string]::IsNullOrWhiteSpace([string]$field.value)) {
                    return [string]$field.value
                }
            }
        }

        $normalizedNames = @($names | ForEach-Object { $_.ToLowerInvariant() })
        foreach ($field in $fields) {
            $candidates = @([string]$field.id, [string]$field.label) |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                ForEach-Object { $_.Trim().ToLowerInvariant() }
            foreach ($candidate in $candidates) {
                if ($candidate -in $normalizedNames -and -not [string]::IsNullOrWhiteSpace([string]$field.value)) {
                    return [string]$field.value
                }
            }
        }

        return $null
    }

    hidden [securestring] NewSecureString([string]$value) {
        $secure = [securestring]::new()
        foreach ($char in $value.ToCharArray()) {
            $secure.AppendChar($char)
        }
        $secure.MakeReadOnly()
        return $secure
    }

    hidden [pscustomobject] NewDashboardCredentials() {
        $python = @'
import secrets
from plugins.dashboard_auth.basic import hash_password

password = secrets.token_urlsafe(32)
print(password)
print(hash_password(password))
'@

        $runArgs = @(
            "run",
            "--rm",
            "--entrypoint",
            "/opt/hermes/.venv/bin/python",
            "-w",
            "/opt/hermes",
            $this.Image,
            "-c",
            $python
        )
        $output = @(Invoke-Docker -Arguments $runArgs -TimeoutSeconds $this.DockerRunTimeoutSeconds)
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            throw "dashboard password hash generation failed (exit code $exitCode): $(($output -join "`n").Trim())"
        }

        $nonEmpty = @($output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($nonEmpty.Count -lt 2) {
            throw "dashboard password hash generation returned incomplete output"
        }

        return [PSCustomObject]@{
            Username     = "admin"
            Password     = [string]$nonEmpty[0]
            PasswordHash = [string]$nonEmpty[1]
            Secret       = $this.NewTokenSecret()
        }
    }

    hidden [pscustomobject] NewDashboardCredentialsFromCredential([System.Management.Automation.PSCredential]$credential) {
        return [PSCustomObject]@{
            Username     = $credential.UserName
            PasswordHash = $this.NewDashboardAuthHash($credential.Password)
            Secret       = $this.NewTokenSecret()
        }
    }

    hidden [string] NewDashboardAuthHash([securestring]$secret) {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "hermes-dashboard-auth-$([guid]::NewGuid().ToString('N'))"
        $passwordPath = Join-Path $tempDir "password"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        $plainSecret = [System.Net.NetworkCredential]::new("", $secret).Password
        Set-Content -LiteralPath $passwordPath -Value $plainSecret -NoNewline -Encoding UTF8

        try {
            $python = @'
from pathlib import Path
from plugins.dashboard_auth.basic import hash_password

password = Path("/run/secrets/hermes_dashboard_password").read_text(encoding="utf-8")
print(hash_password(password))
'@
            $runArgs = @(
                "run",
                "--rm",
                "--mount",
                "type=bind,source=$passwordPath,target=/run/secrets/hermes_dashboard_password,readonly",
                "--entrypoint",
                "/opt/hermes/.venv/bin/python",
                "-w",
                "/opt/hermes",
                $this.Image,
                "-c",
                $python
            )
            $output = @(Invoke-Docker -Arguments $runArgs -TimeoutSeconds $this.DockerRunTimeoutSeconds)
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0) {
                throw "dashboard password hash generation failed (exit code $exitCode): $(($output -join "`n").Trim())"
            }

            $hash = @($output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) | Select-Object -First 1
            if ([string]::IsNullOrWhiteSpace([string]$hash)) {
                throw "dashboard password hash generation returned incomplete output"
            }
            return [string]$hash
        }
        finally {
            $plainSecret = $null
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    hidden [string] NewTokenSecret() {
        [byte[]]$bytes = New-Object byte[] 32
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try {
            $rng.GetBytes($bytes)
        }
        finally {
            $rng.Dispose()
        }

        return [Convert]::ToBase64String($bytes).TrimEnd("=").Replace("+", "-").Replace("/", "_")
    }
}
