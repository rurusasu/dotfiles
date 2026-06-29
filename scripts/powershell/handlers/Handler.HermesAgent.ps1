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
            $modelResult = $this.EnsureModelConfiguration($ctx, $dataDir)

            $envPath = Join-Path $dataDir ".env"
            $infoFilePath = Join-Path $dataDir "dashboard-basic-auth-password.txt"
            $authResult = $this.EnsureDashboardAuth($ctx, $envPath, $infoFilePath)
            $slackResult = $this.EnsureSlackEnvironment($ctx, $envPath)

            $composeArgs = @("compose", "-f", $composeFile, "up", "-d")
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
        $filteredLines = @(
            $lines | Where-Object {
                $_ -notmatch '^\s*SLACK_(BOT_TOKEN|APP_TOKEN|ALLOWED_USERS)\s*='
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
        if (-not $this.IsTruthy($ctx.GetOption("HermesAgentSlack1PasswordEnabled", $true))) {
            return $null
        }

        $required = $this.IsTruthy($ctx.GetOption("HermesAgentRequireSlack", $false))
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

        $account = [string]$ctx.GetOption("HermesAgentSlack1PasswordAccount", "my.1password.com")
        $vault = [string]$ctx.GetOption("HermesAgentSlack1PasswordVault", "openclaw")
        $item = [string]$ctx.GetOption("HermesAgentSlack1PasswordItem", "SlackBot-OpenClaw")
        $arguments = @("item", "get", $item, "--account", $account, "--vault", $vault, "--format", "json")
        $result = Invoke-OpCommand -OpExe $opExe -Arguments $arguments
        if ($result.ExitCode -ne 0) {
            if ($required) {
                throw "1Password から Hermes Slack 接続情報を取得できません"
            }
            $this.Log("1Password から Hermes Slack 接続情報を取得できないため Slack 自動設定をスキップします", "Gray")
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
                $this.Log("1Password item に Slack token または allowed users がないため Slack 自動設定をスキップします", "Gray")
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
            $this.Log("1Password item を読めないため Slack 自動設定をスキップします", "Gray")
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
