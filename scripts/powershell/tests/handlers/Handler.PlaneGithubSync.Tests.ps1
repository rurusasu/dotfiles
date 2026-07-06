#Requires -Module Pester

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../handlers/Handler.PlaneGithubSync.ps1
}

Describe 'PlaneGithubSyncHandler' {
    BeforeEach {
        $script:handler = [PlaneGithubSyncHandler]::new()
        $script:ctx = [SetupContext]::new($TestDrive)
        $script:syncScript = Join-Path $TestDrive "scripts\powershell\sync-plane-github.ps1"
        $script:configPath = Join-Path $TestDrive ".config\plane-github-sync\config.json"
        $script:registeredTask = $null

        New-Item -ItemType Directory -Path (Split-Path -Parent $script:syncScript) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $script:configPath) -Force | Out-Null
        Set-Content -LiteralPath $script:syncScript -Encoding UTF8 -Value "Write-Output sync"
        Set-Content -LiteralPath $script:configPath -Encoding UTF8 -Value @'
{
  "planeBaseUrl": "http://127.0.0.1:18080",
  "planeWorkspaceSlug": "team",
  "projectMappings": [
    {
      "planeProject": "dotfiles",
      "githubRepository": "rurusasu/dotfiles"
    }
  ]
}
'@
        $script:ctx.Options["PlaneGithubSyncConfigPath"] = $script:configPath

        Mock Write-Host { }
        Mock Get-Command {
            return [pscustomobject]@{ Name = $Name; Source = "C:\tools\$Name.exe"; Path = "C:\tools\$Name.exe" }
        } -ParameterFilter { $Name -in @("gh", "pwsh") }
        Mock Get-PlaneGithubSyncCurrentUser { return "USER\Kohei" }
        Mock New-PlaneGithubSyncScheduledTaskAction {
            param([string]$Execute, [string]$Argument)
            return [pscustomobject]@{ Execute = $Execute; Argument = $Argument }
        }
        Mock New-PlaneGithubSyncScheduledTaskTrigger {
            param([datetime]$At, [timespan]$RepetitionInterval, [timespan]$RepetitionDuration)
            return [pscustomobject]@{
                At = $At
                RepetitionInterval = $RepetitionInterval
                RepetitionDuration = $RepetitionDuration
            }
        }
        Mock New-PlaneGithubSyncScheduledTaskSetting {
            return [pscustomobject]@{ Settings = $true }
        }
        Mock New-PlaneGithubSyncScheduledTaskPrincipal {
            param([string]$UserId)
            return [pscustomobject]@{ UserId = $UserId }
        }
        Mock Register-PlaneGithubSyncScheduledTask {
            param(
                [string]$TaskName,
                [object]$Action,
                [object]$Trigger,
                [object]$Settings,
                [object]$Principal,
                [string]$Description
            )
            $script:registeredTask = [pscustomobject]@{
                TaskName = $TaskName
                Action = $Action
                Trigger = $Trigger
                Settings = $Settings
                Principal = $Principal
                Description = $Description
                Force = $true
            }
            return $script:registeredTask
        }
    }

    Context 'Constructor' {
        It 'should set installer metadata' {
            $script:handler.Name | Should -Be "PlaneGithubSync"
            $script:handler.Description | Should -Be "Plane と GitHub Issues の同期タスク"
            $script:handler.Order | Should -Be 58
            $script:handler.RequiresAdmin | Should -Be $false
            $script:handler.Phase | Should -Be 2
        }
    }

    Context 'CanApply' {
        It 'should return false when skipped by option' {
            $script:ctx.Options["SkipPlaneGithubSync"] = $true

            $script:handler.CanApply($script:ctx) | Should -Be $false
        }

        It 'should return false when the sync config has an unresolved workspace slug placeholder' {
            Set-Content -LiteralPath $script:configPath -Encoding UTF8 -Value @'
{
  "planeBaseUrl": "http://127.0.0.1:18080",
  "planeWorkspaceSlug": "${PLANE_WORKSPACE_SLUG}",
  "projectMappings": []
}
'@

            $script:handler.CanApply($script:ctx) | Should -Be $false
        }

        It 'should return false when gh is unavailable' {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "gh" }

            $script:handler.CanApply($script:ctx) | Should -Be $false
        }

        It 'should return true when the script, config, gh, and PowerShell are ready' {
            $script:handler.CanApply($script:ctx) | Should -Be $true
        }
    }

    Context 'Apply' {
        It 'should register a recurring scheduled task for Plane GitHub sync' {
            $result = $script:handler.Apply($script:ctx)

            $result.Success | Should -Be $true
            $script:registeredTask.TaskName | Should -Be "Dotfiles Plane GitHub Sync"
            $script:registeredTask.Action.Execute | Should -Be "C:\tools\pwsh.exe"
            $script:registeredTask.Action.Argument | Should -Match ([regex]::Escape($script:syncScript))
            $script:registeredTask.Action.Argument | Should -Match ([regex]::Escape($script:configPath))
            $script:registeredTask.Trigger.RepetitionInterval.TotalMinutes | Should -Be 5
            $script:registeredTask.Principal.UserId | Should -Be "USER\Kohei"
            $script:registeredTask.Force | Should -Be $true
        }
    }
}
