<#
.SYNOPSIS
    Hermes Agent Docker コンテナの初期セットアップと起動ハンドラー

.DESCRIPTION
    - docker/hermes-agent/compose.yml を使って Hermes gateway/dashboard を起動
    - ~/.hermes/.env に dashboard Basic Auth を初期化
    - 生成した dashboard password は ~/.hermes/dashboard-basic-auth-password.txt に保存
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

            $envPath = Join-Path $dataDir ".env"
            $infoFilePath = Join-Path $dataDir "dashboard-basic-auth-password.txt"
            $authCreated = $this.EnsureDashboardAuth($envPath, $infoFilePath)

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

            if ($authCreated) {
                $this.Log("Dashboard Basic Auth を生成しました: $infoFilePath", "Green")
            }
            else {
                $this.Log("Dashboard Basic Auth は既に設定済みです", "Gray")
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

    hidden [bool] EnsureDashboardAuth([string]$envPath, [string]$infoFilePath) {
        $lines = @()
        if (Test-Path -LiteralPath $envPath) {
            $lines = @(Get-Content -LiteralPath $envPath -ErrorAction Stop)
        }

        if ($this.HasDashboardAuth($lines)) {
            return $false
        }

        $credentials = $this.NewDashboardCredentials()
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
        Set-Content -LiteralPath $infoFilePath -Encoding UTF8 -Value @(
            "url=http://127.0.0.1:9119",
            "username=$($credentials.Username)",
            "password=$($credentials.Password)"
        )
        return $true
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
