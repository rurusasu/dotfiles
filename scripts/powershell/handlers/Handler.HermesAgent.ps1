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
            $homeRepositoryResult = $this.EnsureHomeRepositoryLayout($ctx, $dataDir)
            $modelResult = $this.EnsureModelConfiguration($ctx, $dataDir)

            $envPath = Join-Path $dataDir ".env"
            $infoFilePath = Join-Path $dataDir "dashboard-basic-auth-password.txt"
            $authResult = $this.EnsureDashboardAuth($ctx, $envPath, $infoFilePath)
            $profileDashboardAuthResult = $this.SyncDashboardAuthToManagedProfileEnvironments($ctx, $dataDir, $envPath)
            $slackResult = $this.EnsureSlackEnvironment($ctx, $envPath)
            $researcherSlackResult = $this.EnsureResearcherSlackEnvironment($ctx, $dataDir)
            $openClawApiResult = $this.EnsureOpenClawApiEnvironment($ctx, $envPath)
            $mcpResult = $this.EnsureMcpConfiguration($ctx, $dataDir)
            $slackMentionResult = $this.EnsureSlackMentionConfiguration($ctx, $dataDir)

            $composeArgs = @("compose", "-f", $composeFile, "up", "-d", "--build")
            $output = @(Invoke-Docker -Arguments $composeArgs -TimeoutSeconds $this.DockerComposeTimeoutSeconds)
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0) {
                $message = ($output -join "`n").Trim()
                if ([string]::IsNullOrWhiteSpace($message)) {
                    $message = "exit code $exitCode"
                }
                return $this.CreateFailureResult("Hermes Agent コンテナの起動に失敗しました: $message")
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

            if ($researcherSlackResult.Changed -and $researcherSlackResult.Source -eq "1Password") {
                $this.Log("researcher Slack 接続情報を 1Password から設定しました", "Green")
            }

            if ($homeRepositoryResult.Changed) {
                $this.Log("Hermes home/profile Git 管理ポリシーを更新しました", "Green")
            }

            if ($openClawApiResult.Changed -and $openClawApiResult.Count -gt 0) {
                $this.Log("OpenClaw API token を Hermes .env に設定しました ($($openClawApiResult.Count) keys)", "Green")
            }
            elseif (-not $openClawApiResult.Changed -and $openClawApiResult.Source -eq "Disabled") {
                $this.Log("OpenClaw API token の自動設定は無効化されています", "Gray")
            }

            if ($mcpResult.Changed) {
                $this.Log("Hermes MCP server 設定を更新しました", "Green")
            }

            if ($slackMentionResult.Changed -and $slackMentionResult.Count -gt 0) {
                $this.Log("Slack 無メンション応答設定を更新しました ($($slackMentionResult.Count) configs)", "Green")
            }

            return $this.CreateSuccessResult("Hermes Agent を起動しました: http://127.0.0.1:9119")
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

        foreach ($profileName in $this.GetManagedProfileNames($ctx)) {
            $changed = $this.EnsureProfileRepositoryLayout($dataDir, $profileName) -or $changed
        }

        return [PSCustomObject]@{ Changed = $changed; Source = "Config" }
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
        $value = $ctx.GetOption("HermesAgentManagedProfiles", "researcher,rick,hoffman")
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

    hidden [string[]] GetSharedHomeLayoutDocLines() {
        return @(
            '# Hermes Agent Home/Profile Layout',
            '',
            'Hermes profile homes should keep the filesystem layout that Hermes expects, while Git tracks only the declarative distribution files.',
            '',
            '## Runtime Mounts',
            '',
            '- The default gateway mounts `~/.hermes` as `/opt/data`.',
            '- A dedicated profile gateway mounts `~/.hermes/profiles/<profile>` as `/opt/data`.',
            '- A dedicated profile gateway mounts the root shared docs directory `~/.hermes/docs` onto `/opt/data/docs` read-only.',
            '- From the default gateway, profile homes are visible under `/opt/data/profiles/<profile>`.',
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
            '## Dedicated Gateway Runtime Secrets',
            '',
            'A profile that runs its own gateway still needs runtime credentials inside that profile home. Put dashboard auth, Slack tokens, and other env-based secrets in the profile `.env`; put model-provider auth in the profile `auth.json` or provider-specific env vars. Provision these locally or from a secrets manager, and keep them out of Git.',
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
            'Do not share profile `memories/` through Git. Put durable shared guidance in `docs/` or repository `AGENTS.md` files, and use Slack, Hermes Kanban, GitHub issues, or Linear for cross-agent work state. If a shared memory backend is introduced later, namespace it by user, app, and profile.'
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

        $configPath = Join-Path $dataDir "config.yaml"
        $existingLines = @()
        if (Test-Path -LiteralPath $configPath) {
            $existingLines = @(Get-Content -LiteralPath $configPath -ErrorAction Stop)
        }

        $updatedLines = $this.SetMcpConfigLines($existingLines)
        $changed = -not $this.LinesEqual($existingLines, $updatedLines)
        if ($changed) {
            Set-Content -LiteralPath $configPath -Encoding UTF8 -Value $updatedLines
        }

        return [PSCustomObject]@{ Changed = $changed; Source = "Config" }
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

    hidden [string[]] SetSlackMentionConfigLines([string[]]$lines) {
        $managedLines = @(
            "  require_mention: false",
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
                Where-Object { $_ -notmatch '^\s{2}(require_mention|allow_bots)\s*:' }
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

    hidden [string[]] SetMcpConfigLines([string[]]$lines) {
        $managedServerNames = @("github", "xapi", "x-docs")
        $desiredLines = @(
            "  xapi:",
            "    command: /usr/local/bin/hermes-xapi-mcp",
            "    connect_timeout: 300",
            "    env:",
            '      X_API_CLIENT_ID: ${X_API_CLIENT_ID}',
            '      X_API_CLIENT_SECRET: ${X_API_CLIENT_SECRET}',
            "  x-docs:",
            "    url: https://docs.x.com/mcp",
            "    connect_timeout: 60"
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

    hidden [pscustomobject] EnsureResearcherSlackEnvironment([SetupContext]$ctx, [string]$dataDir) {
        $defaultEnabled = $this.IsTruthy($ctx.GetOption("HermesAgentSlack1PasswordEnabled", $true))
        if (-not $this.IsTruthy($ctx.GetOption("HermesAgentResearcherSlack1PasswordEnabled", $defaultEnabled))) {
            return [PSCustomObject]@{ Changed = $false; Source = "Disabled" }
        }

        $envPath = Join-Path $dataDir "profiles\researcher\.env"
        if (-not (Test-Path -LiteralPath $envPath)) {
            return [PSCustomObject]@{ Changed = $false; Source = "MissingProfile" }
        }

        $lines = @(Get-Content -LiteralPath $envPath -ErrorAction Stop)
        $slackEnvironment = $this.GetOnePasswordSlackEnvironmentForItem(
            $ctx,
            "HermesAgentResearcherSlack1PasswordEnabled",
            $true,
            "HermesAgentRequireResearcherSlack",
            "HermesAgentResearcherSlack1PasswordAccount",
            "HermesAgentResearcherSlack1PasswordVault",
            "HermesAgentResearcherSlack1PasswordItem",
            "SlackBot-Researcher"
        )
        if ($null -ne $slackEnvironment) {
            $this.WriteSlackEnvironment($envPath, $lines, $slackEnvironment, $true)
            return [PSCustomObject]@{ Changed = $true; Source = "1Password" }
        }

        if ($this.HasSlackEnvironment($lines)) {
            return [PSCustomObject]@{ Changed = $false; Source = "Existing" }
        }

        return [PSCustomObject]@{ Changed = $false; Source = "Missing" }
    }

    hidden [pscustomobject] EnsureOpenClawApiEnvironment([SetupContext]$ctx, [string]$envPath) {
        if (-not $this.IsTruthy($ctx.GetOption("HermesAgentOpenClawSecrets1PasswordEnabled", $true))) {
            return [PSCustomObject]@{ Changed = $false; Source = "Disabled"; Count = 0 }
        }

        $lines = @()
        if (Test-Path -LiteralPath $envPath) {
            $lines = @(Get-Content -LiteralPath $envPath -ErrorAction Stop)
        }

        $environment = $this.GetOnePasswordOpenClawApiEnvironment($ctx)
        if ($environment.Count -eq 0) {
            return [PSCustomObject]@{ Changed = $false; Source = "Missing"; Count = 0 }
        }

        $this.WriteNamedEnvironment($envPath, $lines, $environment)
        return [PSCustomObject]@{ Changed = $true; Source = "1Password"; Count = $environment.Count }
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

    hidden [bool] IsSharedPlatformSecretLine([string]$line) {
        return $line -match '^\s*(TELEGRAM_BOT_TOKEN|DISCORD_BOT_TOKEN|DISCORD_TOKEN|WHATSAPP_[A-Z0-9_]+|SIGNAL_[A-Z0-9_]+|TEAMS_[A-Z0-9_]+|QQBOT_[A-Z0-9_]+|YUANBAO_[A-Z0-9_]+|HOMEASSISTANT_[A-Z0-9_]+)\s*='
    }

    hidden [void] WriteNamedEnvironment([string]$envPath, [string[]]$lines, [hashtable]$environment) {
        $keys = @($environment.Keys | Sort-Object)
        if ($keys.Count -eq 0) {
            return
        }

        $escapedKeys = @($keys | ForEach-Object { [regex]::Escape([string]$_) })
        $pattern = '^\s*(' + ($escapedKeys -join '|') + ')\s*='
        $filteredLines = @(
            $lines | Where-Object {
                $_ -notmatch $pattern
            }
        )

        if ($filteredLines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($filteredLines[-1])) {
            $filteredLines += ""
        }

        foreach ($key in $keys) {
            $filteredLines += "$key=$($environment[$key])"
        }

        Set-Content -LiteralPath $envPath -Value $filteredLines -Encoding UTF8
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
        $vault = [string]$ctx.GetOption("HermesAgent1PasswordVault", "openclaw")
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

    hidden [pscustomobject] GetOnePasswordSlackEnvironment([SetupContext]$ctx) {
        return $this.GetOnePasswordSlackEnvironmentForItem(
            $ctx,
            "HermesAgentSlack1PasswordEnabled",
            $true,
            "HermesAgentRequireSlack",
            "HermesAgentSlack1PasswordAccount",
            "HermesAgentSlack1PasswordVault",
            "HermesAgentSlack1PasswordItem",
            "SlackBot-OpenClaw"
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

        $required = $this.IsTruthy($ctx.GetOption($requiredOption, $false))
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
        $vault = [string]$ctx.GetOption($vaultOption, "openclaw")
        $item = [string]$ctx.GetOption($itemOption, $defaultItem)
        $arguments = @("item", "get", $item, "--account", $account, "--vault", $vault, "--format", "json")
        $result = Invoke-OpCommand -OpExe $opExe -Arguments $arguments
        if ($result.ExitCode -ne 0) {
            if ($required) {
                throw "1Password から Hermes Slack 接続情報を取得できません"
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
                    throw "1Password item に Slack token または allowed users がありません"
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

    hidden [hashtable] GetOnePasswordOpenClawApiEnvironment([SetupContext]$ctx) {
        $required = $this.IsTruthy($ctx.GetOption("HermesAgentRequireOpenClawSecrets", $false))
        $environment = @{}
        $opCommand = @(Get-Command -Name "op" -ErrorAction SilentlyContinue | Select-Object -First 1)
        if (-not $opCommand) {
            if ($required) {
                throw "OpenClaw API token 用の 1Password CLI (op) が見つかりません"
            }
            $this.Log("1Password CLI が見つからないため OpenClaw API token の自動取得をスキップします", "Gray")
            return $environment
        }

        $opExe = [string]$opCommand.Source
        if ([string]::IsNullOrWhiteSpace($opExe) -and $opCommand.PSObject.Properties.Name -contains "Path") {
            $opExe = [string]$opCommand.Path
        }
        if ([string]::IsNullOrWhiteSpace($opExe)) {
            $opExe = "op"
        }

        $account = [string]$ctx.GetOption("HermesAgentOpenClawSecrets1PasswordAccount", "my.1password.com")
        $vault = [string]$ctx.GetOption("HermesAgentOpenClawSecrets1PasswordVault", "openclaw")
        $specs = @(
            [PSCustomObject]@{
                Item     = [string]$ctx.GetOption("HermesAgentGitHub1PasswordItem", "GitHubUsedOpenClawPAT")
                Field    = @("credential", "認証情報", "token", "PAT")
                EnvNames = @("GITHUB_TOKEN", "GH_TOKEN", "GITHUB_PERSONAL_ACCESS_TOKEN")
            },
            [PSCustomObject]@{
                Item     = [string]$ctx.GetOption("HermesAgentOpenClawGateway1PasswordItem", "openclaw")
                Field    = @("password", "gateway token", "credential", "認証情報", "token")
                EnvNames = @("OPENCLAW_GATEWAY_TOKEN")
            },
            [PSCustomObject]@{
                Item     = [string]$ctx.GetOption("HermesAgentExa1PasswordItem", "ExaUsedOpenclawPAT")
                Field    = @("credential", "認証情報", "api key", "api_key", "token")
                EnvNames = @("EXA_API_KEY")
            },
            [PSCustomObject]@{
                Item     = [string]$ctx.GetOption("HermesAgentTavily1PasswordItem", "TavilyUsedOpenclawPAT")
                Field    = @("credential", "認証情報", "api key", "api_key", "token")
                EnvNames = @("TAVILY_API_KEY")
            },
            [PSCustomObject]@{
                Item     = [string]$ctx.GetOption("HermesAgentFirecrawl1PasswordItem", "FirecrawlUsedOpenclawPAT")
                Field    = @("credential", "認証情報", "api key", "api_key", "token")
                EnvNames = @("FIRECRAWL_API_KEY")
            },
            [PSCustomObject]@{
                Item     = [string]$ctx.GetOption("HermesAgentGemini1PasswordItem", "OpenClawGeminiAPI")
                Field    = @("credential", "認証情報", "api key", "api_key", "token")
                EnvNames = @("GEMINI_API_KEY", "GOOGLE_API_KEY")
            },
            [PSCustomObject]@{
                Item     = [string]$ctx.GetOption("HermesAgentHuggingFace1PasswordItem", "HuggingFace")
                Field    = @("PAT", "credential", "認証情報", "api key", "api_key", "token")
                EnvNames = @("HF_TOKEN", "HUGGINGFACEHUB_API_TOKEN")
            },
            [PSCustomObject]@{
                Item     = [string]$ctx.GetOption("HermesAgentTelegram1PasswordItem", "TelegramBot")
                Field    = @("credential", "認証情報", "bot token", "bot_token", "token")
                EnvNames = @("TELEGRAM_BOT_TOKEN")
            },
            [PSCustomObject]@{
                Item     = [string]$ctx.GetOption("HermesAgentXai1PasswordItem", "XUsedOpenClaw")
                Field    = @("credential", "認証情報", "api key", "api_key", "token")
                EnvNames = @("XAI_API_KEY")
            },
            [PSCustomObject]@{
                Item     = [string]$ctx.GetOption("HermesAgentAutoCli1PasswordItem", "AutoCLI")
                Field    = @("credential", "認証情報", "api key", "api_key", "token")
                EnvNames = @("AUTOCLI_API_KEY")
            },
            [PSCustomObject]@{
                Item     = [string]$ctx.GetOption("HermesAgentXApiMcp1PasswordItem", "XApiMcp")
                Field    = @("CLIENT_ID", "client_id", "client id", "oauth client id", "OAuth 2.0 Client ID")
                EnvNames = @("X_API_CLIENT_ID")
                Required = $false
            },
            [PSCustomObject]@{
                Item     = [string]$ctx.GetOption("HermesAgentXApiMcp1PasswordItem", "XApiMcp")
                Field    = @("CLIENT_SECRET", "client_secret", "client secret", "oauth client secret", "OAuth 2.0 Client Secret")
                EnvNames = @("X_API_CLIENT_SECRET")
                Required = $false
            }
        )

        foreach ($spec in $specs) {
            if ([string]::IsNullOrWhiteSpace($spec.Item)) {
                continue
            }

            $arguments = @("item", "get", $spec.Item, "--account", $account, "--vault", $vault, "--format", "json")
            $result = Invoke-OpCommand -OpExe $opExe -Arguments $arguments
            if ($result.ExitCode -ne 0) {
                if ($required -and $spec.Required -ne $false) {
                    throw "1Password から OpenClaw API token を取得できません: $($spec.Item)"
                }
                $this.Log("1Password item が読めないため OpenClaw API token をスキップします: $($spec.Item)", "Gray")
                continue
            }

            try {
                $itemJson = ($result.Output -join "`n") | ConvertFrom-Json -ErrorAction Stop
                $value = $this.GetOnePasswordFieldValue($itemJson, "", $spec.Field)
                if ([string]::IsNullOrWhiteSpace($value)) {
                    if ($required -and $spec.Required -ne $false) {
                        throw "1Password item に OpenClaw API token がありません: $($spec.Item)"
                    }
                    $this.Log("1Password item に OpenClaw API token がないためスキップします: $($spec.Item)", "Gray")
                    continue
                }

                foreach ($envName in $spec.EnvNames) {
                    $environment[$envName] = $value
                }
            }
            catch {
                if ($required -and $spec.Required -ne $false) {
                    throw
                }
                $this.Log("1Password item を読めないため OpenClaw API token をスキップします: $($spec.Item)", "Gray")
            }
        }

        return $environment
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
