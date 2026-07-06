<#
.SYNOPSIS
    Plane and GitHub Issues sync scheduled task handler.

.DESCRIPTION
    Registers the local Plane <-> GitHub issue sync script as a per-user
    scheduled task once the non-secret Plane workspace slug is configured.
#>

function Get-PlaneGithubSyncCurrentUser {
    [CmdletBinding()]
    param()

    return [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
}

function New-PlaneGithubSyncScheduledTaskAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Execute,
        [Parameter(Mandatory)]
        [string]$Argument
    )

    return New-ScheduledTaskAction -Execute $Execute -Argument $Argument
}

function New-PlaneGithubSyncScheduledTaskTrigger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [datetime]$At,
        [Parameter(Mandatory)]
        [timespan]$RepetitionInterval,
        [Parameter(Mandatory)]
        [timespan]$RepetitionDuration
    )

    return New-ScheduledTaskTrigger -Once -At $At -RepetitionInterval $RepetitionInterval -RepetitionDuration $RepetitionDuration
}

function New-PlaneGithubSyncScheduledTaskSetting {
    [CmdletBinding()]
    param()

    return New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -MultipleInstances IgnoreNew
}

function New-PlaneGithubSyncScheduledTaskPrincipal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserId
    )

    return New-ScheduledTaskPrincipal -UserId $UserId -LogonType Interactive -RunLevel LeastPrivilege
}

function Register-PlaneGithubSyncScheduledTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TaskName,
        [Parameter(Mandatory)]
        [object]$Action,
        [Parameter(Mandatory)]
        [object]$Trigger,
        [Parameter(Mandatory)]
        [object]$Settings,
        [Parameter(Mandatory)]
        [object]$Principal,
        [Parameter(Mandatory)]
        [string]$Description
    )

    return Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $Action `
        -Trigger $Trigger `
        -Settings $Settings `
        -Principal $Principal `
        -Description $Description `
        -Force
}

class PlaneGithubSyncHandler : SetupHandlerBase {
    [int]$IntervalMinutes = 5
    [string]$TaskName = "Dotfiles Plane GitHub Sync"

    PlaneGithubSyncHandler() {
        $this.Name = "PlaneGithubSync"
        $this.Description = "Plane と GitHub Issues の同期タスク"
        $this.Order = 58
        $this.RequiresAdmin = $false
        $this.Phase = 2
    }

    [bool] CanApply([SetupContext]$ctx) {
        if ($this.IsSkipped($ctx)) {
            $this.Log("Plane GitHub sync はオプションで無効化されています", "Gray")
            return $false
        }

        $scriptPath = $this.GetSyncScriptPath($ctx)
        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
            $this.Log("Plane GitHub sync script が見つかりません: $scriptPath", "Gray")
            return $false
        }

        $configPath = $this.GetConfigPath($ctx)
        if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
            $this.Log("Plane GitHub sync config が見つかりません: $configPath", "Gray")
            return $false
        }

        if (-not $this.TestConfigReady($configPath)) {
            $this.Log("Plane workspace slug が未設定のため GitHub sync task 登録を保留します", "Gray")
            return $false
        }

        if (-not (Get-Command -Name "gh" -ErrorAction SilentlyContinue)) {
            $this.Log("gh コマンドが見つからないため Plane GitHub sync task をスキップします", "Gray")
            return $false
        }

        if ($this.TestConfigUsesOnePassword($configPath) -and -not (Get-Command -Name "op" -ErrorAction SilentlyContinue)) {
            $this.Log("op コマンドが見つからないため Plane API token を読めません", "Gray")
            return $false
        }

        if ([string]::IsNullOrWhiteSpace($this.GetPowerShellPath())) {
            $this.Log("pwsh または powershell が見つかりません", "Gray")
            return $false
        }

        return $true
    }

    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            $this.ConfigureFromOptions($ctx)

            $scriptPath = $this.GetSyncScriptPath($ctx)
            $configPath = $this.GetConfigPath($ctx)
            $powerShellPath = $this.GetPowerShellPath()
            if ([string]::IsNullOrWhiteSpace($powerShellPath)) {
                return $this.CreateFailureResult("pwsh または powershell が見つかりません")
            }

            if (-not $this.TestConfigReady($configPath)) {
                return $this.CreateFailureResult("Plane workspace slug が未設定です: $configPath")
            }

            $arguments = @(
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                $this.QuoteArgument($scriptPath),
                "-ConfigPath",
                $this.QuoteArgument($configPath)
            ) -join " "

            $action = New-PlaneGithubSyncScheduledTaskAction -Execute $powerShellPath -Argument $arguments
            $trigger = New-PlaneGithubSyncScheduledTaskTrigger `
                -At (Get-Date).AddMinutes(1) `
                -RepetitionInterval (New-TimeSpan -Minutes $this.IntervalMinutes) `
                -RepetitionDuration (New-TimeSpan -Days 3650)
            $settings = New-PlaneGithubSyncScheduledTaskSetting
            $principal = New-PlaneGithubSyncScheduledTaskPrincipal -UserId (Get-PlaneGithubSyncCurrentUser)

            Register-PlaneGithubSyncScheduledTask `
                -TaskName $this.TaskName `
                -Action $action `
                -Trigger $trigger `
                -Settings $settings `
                -Principal $principal `
                -Description "Sync Plane work items with GitHub Issues." | Out-Null

            $this.Log("Plane GitHub sync task を登録しました: $($this.TaskName)", "Green")
            return $this.CreateSuccessResult("Plane GitHub sync task を登録しました: $($this.TaskName)")
        }
        catch {
            return $this.CreateFailureResult("Plane GitHub sync task 登録に失敗しました: $($_.Exception.Message)", $_.Exception)
        }
    }

    hidden [void] ConfigureFromOptions([SetupContext]$ctx) {
        $this.IntervalMinutes = $this.GetIntOption($ctx, "PlaneGithubSyncIntervalMinutes", $this.IntervalMinutes)
        $configuredTaskName = [string]$ctx.GetOption("PlaneGithubSyncTaskName", $this.TaskName)
        if (-not [string]::IsNullOrWhiteSpace($configuredTaskName)) {
            $this.TaskName = $configuredTaskName
        }
    }

    hidden [bool] IsSkipped([SetupContext]$ctx) {
        if ($this.IsTruthy($ctx.GetOption("SkipPlaneGithubSync", $false))) {
            return $true
        }

        return -not $this.IsTruthy($ctx.GetOption("PlaneGithubSyncEnabled", $true))
    }

    hidden [bool] IsTruthy([object]$value) {
        if ($null -eq $value) { return $false }
        if ($value -is [bool]) { return [bool]$value }
        if ($value -is [int]) { return [int]$value -ne 0 }
        $text = ([string]$value).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { return $false }
        return $text -in @("1", "true", "yes", "y", "on", "enabled")
    }

    hidden [int] GetIntOption([SetupContext]$ctx, [string]$key, [int]$defaultValue) {
        $raw = $ctx.GetOption($key, $defaultValue)
        $parsed = 0
        if ([int]::TryParse([string]$raw, [ref]$parsed) -and $parsed -gt 0) {
            return $parsed
        }
        return $defaultValue
    }

    hidden [string] GetSyncScriptPath([SetupContext]$ctx) {
        return Join-Path $ctx.DotfilesPath "scripts\powershell\sync-plane-github.ps1"
    }

    hidden [string] GetConfigPath([SetupContext]$ctx) {
        $configured = [string]$ctx.GetOption("PlaneGithubSyncConfigPath", "")
        if (-not [string]::IsNullOrWhiteSpace($configured)) {
            return [Environment]::ExpandEnvironmentVariables($configured)
        }

        $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { "~" }
        return Join-Path (Join-Path $homeDir ".config") "plane-github-sync\config.json"
    }

    hidden [object] ReadConfig([string]$configPath) {
        return Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    }

    hidden [bool] TestConfigReady([string]$configPath) {
        try {
            $config = $this.ReadConfig($configPath)
            $slug = ([string]$config.planeWorkspaceSlug).Trim()
            if ([string]::IsNullOrWhiteSpace($slug)) {
                return $false
            }

            return -not ($slug -match '^\$\{[A-Za-z_][A-Za-z0-9_]*\}$')
        }
        catch {
            return $false
        }
    }

    hidden [bool] TestConfigUsesOnePassword([string]$configPath) {
        try {
            $config = $this.ReadConfig($configPath)
            return -not [string]::IsNullOrWhiteSpace([string]$config.planeApiTokenRef)
        }
        catch {
            return $false
        }
    }

    hidden [string] GetPowerShellPath() {
        foreach ($commandName in @("pwsh", "powershell")) {
            $command = Get-Command -Name $commandName -ErrorAction SilentlyContinue
            if ($null -eq $command) {
                continue
            }

            if ($command.Source) {
                return [string]$command.Source
            }

            if ($command.Path) {
                return [string]$command.Path
            }
        }

        return ""
    }

    hidden [string] QuoteArgument([string]$value) {
        return '"' + $value.Replace('"', '\"') + '"'
    }
}
