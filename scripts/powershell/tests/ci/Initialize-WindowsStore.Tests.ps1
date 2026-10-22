BeforeAll {
    $script:storeScript = Join-Path $PSScriptRoot '../../ci/Initialize-WindowsStore.ps1'
    if (Test-Path -LiteralPath $script:storeScript) { . $script:storeScript }
}

Describe 'Hosted Windows Store prerequisites' {
    BeforeEach {
        $script:originalStoreEnvironment = @{}
        foreach ($name in @('GITHUB_ACTIONS', 'RUNNER_ENVIRONMENT', 'RUNNER_OS')) {
            $script:originalStoreEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        }
        $env:GITHUB_ACTIONS = 'true'
        $env:RUNNER_ENVIRONMENT = 'github-hosted'
        $env:RUNNER_OS = 'Windows'
        $script:wuPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
        $script:auPath = $script:wuPath + '\AU'
        $script:policyValues = @{
            $script:wuPath = @{ UnrelatedPolicy = 7 }
            $script:auPath = @{ NoAutoUpdate = 1; AUOptions = 2; UseWUServer = 0 }
        }
        $script:changes = [Collections.Generic.List[string]]::new()
        $script:messages = [Collections.Generic.List[string]]::new()
        $script:warnings = [Collections.Generic.List[string]]::new()
        $script:eventQueries = [Collections.Generic.List[object]]::new()
        $script:service = [pscustomobject]@{
            Name = 'wuauserv'; StartType = 'Manual'; Status = 'Running'
            Starts = 0; StartError = $null; Actions = $script:changes
            Waits = 0; WaitSeconds = 0; RemainStopped = $false
        }
        $script:service | Add-Member -MemberType ScriptMethod -Name Start -Value {
            if ($this.StartError) { throw $this.StartError }
            $this.Starts++
            $this.Actions.Add('start:wuauserv')
        }
        $script:service | Add-Member -MemberType ScriptMethod -Name WaitForStatus -Value {
            param($Status, $Timeout)
            $this.Waits++
            $this.Actions.Add('wait:wuauserv')
            $this.WaitSeconds = $Timeout.TotalSeconds
            if (-not $this.RemainStopped) { $this.Status = [string]$Status }
        }
        $script:service | Add-Member -MemberType ScriptMethod -Name Refresh -Value {}

        # Deny every system boundary unless a test explicitly supplies a fixture.
        Mock Get-ItemProperty { throw 'Unexpected registry read' }
        Mock Remove-ItemProperty { throw 'Unexpected registry write' }
        Mock Set-Service { throw 'Unexpected service configuration' }
        Mock Start-Service { throw 'Unexpected service start' }
        Mock Get-Service { throw 'Unexpected service read' }
        Mock Get-AppxPackage { throw 'Unexpected AppX read' }
        Mock Get-WinEvent { throw 'Unexpected event read' }
        Mock Write-Host { param($Object) $script:messages.Add([string]$Object) }
        Mock Write-Warning { param($Message) $script:warnings.Add([string]$Message) }
        if (Get-Command Test-WindowsStoreAdministrator -ErrorAction SilentlyContinue) {
            Mock Test-WindowsStoreAdministrator { $true }
        }
        Mock Get-ItemProperty {
            param([string]$LiteralPath)
            [pscustomobject]$script:policyValues[$LiteralPath].Clone()
        } -ParameterFilter { $LiteralPath -eq $script:wuPath -or $LiteralPath -eq $script:auPath }
        Mock Get-Service {
            param($Name)
            if ($Name -eq 'wuauserv') { return $script:service }
            [pscustomobject]@{ Name = $Name; StartType = 'Manual'; Status = 'Stopped' }
        } -ParameterFilter { $Name -in @('wuauserv', 'BITS', 'InstallService', 'DoSvc', 'ClipSVC', 'AppXSvc') }
        Mock Get-AppxPackage {
            param($Name)
            [pscustomobject]@{ Name = $Name; Version = '1.2.3.4' }
        } -ParameterFilter { $Name -in @('Microsoft.WindowsStore', 'Microsoft.DesktopAppInstaller') }
    }

    AfterEach {
        foreach ($name in $script:originalStoreEnvironment.Keys) {
            [Environment]::SetEnvironmentVariable($name, $script:originalStoreEnvironment[$name], 'Process')
        }
    }

    It 'should remove only the two Store blocking policies and preserve update scheduling' {
        $script:policyValues[$script:wuPath]['DoNotConnectToWindowsUpdateInternetLocations'] = 1
        $script:policyValues[$script:wuPath]['DisableWindowsUpdateAccess'] = 1
        Mock Remove-ItemProperty {
            param([string]$LiteralPath, [string]$Name)
            $script:changes.Add('remove:' + $Name)
            $script:policyValues[$LiteralPath].Remove($Name)
        } -ParameterFilter { $LiteralPath -eq $script:wuPath -and $Name -in @('DoNotConnectToWindowsUpdateInternetLocations', 'DisableWindowsUpdateAccess') }

        Initialize-WindowsStore

        $script:policyValues[$script:wuPath].ContainsKey('DoNotConnectToWindowsUpdateInternetLocations') | Should -BeFalse
        $script:policyValues[$script:wuPath].ContainsKey('DisableWindowsUpdateAccess') | Should -BeFalse
        $script:policyValues[$script:wuPath]['UnrelatedPolicy'] | Should -Be 7
        $script:policyValues[$script:auPath]['NoAutoUpdate'] | Should -Be 1
        $script:policyValues[$script:auPath]['AUOptions'] | Should -Be 2
        $script:policyValues[$script:auPath]['UseWUServer'] | Should -Be 0
        @($script:changes).Count | Should -Be 2
        ($script:messages -join "`n") | Should -Match 'Before'
        ($script:messages -join "`n") | Should -Match 'After'
    }

    It 'should enable only a disabled Windows Update service and wait for running with a timeout' {
        $script:service.StartType = 'Disabled'
        $script:service.Status = 'Stopped'
        Mock Set-Service {
            $script:changes.Add('manual:wuauserv')
            $script:service.StartType = 'Manual'
        } -ParameterFilter { $Name -eq 'wuauserv' -and $StartupType -eq 'Manual' }
        Initialize-WindowsStore

        $script:service.StartType | Should -Be 'Manual'
        $script:service.Status | Should -Be 'Running'
        $script:service.Starts | Should -Be 1
        $script:service.Waits | Should -Be 1
        $script:service.WaitSeconds | Should -BeGreaterThan 0
        $script:service.WaitSeconds | Should -BeLessOrEqual 60
        ($script:changes -join '|') | Should -BeExactly 'manual:wuauserv|start:wuauserv|wait:wuauserv'
    }

    It 'should leave an already ready runner unchanged on repeated initialization' {
        Initialize-WindowsStore
        Initialize-WindowsStore

        $script:changes.Count | Should -Be 0
        $script:service.Waits | Should -Be 0
        $script:policyValues[$script:auPath]['NoAutoUpdate'] | Should -Be 1
    }

    It 'should refuse initialization before any writes outside the hosted Windows runner boundary' -TestCases @(
        @{ Variable = 'GITHUB_ACTIONS'; Value = 'false' }
        @{ Variable = 'RUNNER_ENVIRONMENT'; Value = 'self-hosted' }
        @{ Variable = 'RUNNER_OS'; Value = 'Linux' }
        @{ Variable = 'GITHUB_ACTIONS'; Value = '' }
    ) {
        param($Variable, $Value)
        [Environment]::SetEnvironmentVariable($Variable, $Value, 'Process')

        { Initialize-WindowsStore } | Should -Throw '*GitHub-hosted Windows*'
        $script:changes.Count | Should -Be 0
        $script:messages.Count | Should -Be 0
    }

    It 'should refuse initialization without administrator rights' {
        Mock Test-WindowsStoreAdministrator { $false }

        { Initialize-WindowsStore } | Should -Throw '*administrator*'
        $script:changes.Count | Should -Be 0
    }

    It 'should propagate a required policy repair failure' {
        $script:policyValues[$script:wuPath]['DisableWindowsUpdateAccess'] = 1
        Mock Remove-ItemProperty { throw 'fixture access denied' } -ParameterFilter { $LiteralPath -eq $script:wuPath -and $Name -eq 'DisableWindowsUpdateAccess' }

        { Initialize-WindowsStore } | Should -Throw '*fixture access denied*'
        $script:policyValues[$script:wuPath]['DisableWindowsUpdateAccess'] | Should -Be 1
    }

    It 'should reject an update scheduling change during initialization' {
        $script:policyValues[$script:wuPath]['DisableWindowsUpdateAccess'] = 1
        Mock Remove-ItemProperty {
            $script:policyValues[$script:wuPath].Remove('DisableWindowsUpdateAccess')
            $script:policyValues[$script:auPath]['NoAutoUpdate'] = 0
        } -ParameterFilter { $LiteralPath -eq $script:wuPath -and $Name -eq 'DisableWindowsUpdateAccess' }

        { Initialize-WindowsStore } | Should -Throw '*NoAutoUpdate*changed*'
    }

    It 'should reject a service that never reaches running' {
        $script:service.Status = 'Stopped'
        $script:service.RemainStopped = $true

        { Initialize-WindowsStore } | Should -Throw '*wuauserv*Running*'
    }

    It 'should propagate a rejected service start request without waiting' {
        $script:service.Status = 'Stopped'
        $script:service.StartError = 'fixture service start rejected'

        { Initialize-WindowsStore } | Should -Throw '*fixture service start rejected*'
        $script:service.Waits | Should -Be 0
        $script:changes.Count | Should -Be 0
    }

    It 'should report configured update service flags without exposing URLs or unrelated policy values' {
        $script:policyValues[$script:wuPath]['WUServer'] = 'https://user:secret@example.invalid/path?token=secret'
        $script:policyValues[$script:wuPath]['WUStatusServer'] = ''
        $script:policyValues[$script:wuPath]['UpdateServiceUrlAlternate'] = 'https://private.invalid'
        $script:policyValues[$script:wuPath]['UnrelatedSecret'] = 'must-not-appear'

        Initialize-WindowsStore

        $output = $script:messages -join "`n"
        $output | Should -Match 'WUServerConfigured=True'
        $output | Should -Match 'WUStatusServerConfigured=False'
        $output | Should -Match 'UpdateServiceUrlAlternateConfigured=True'
        $output | Should -Match 'UseWUServer=0'
        $output | Should -Match 'ClipSVC'
        $output | Should -Match 'AppXSvc'
        $output | Should -Match 'Microsoft.WindowsStore.*1.2.3.4'
        $output | Should -Match 'Microsoft.DesktopAppInstaller.*1.2.3.4'
        $output | Should -Not -Match 'secret|example.invalid|private.invalid|must-not-appear|UnrelatedSecret'
    }

    It 'should keep diagnostics read only and bound every event query' {
        $script:policyValues[$script:wuPath]['DisableWindowsUpdateAccess'] = 1
        Mock Get-WinEvent {
            param($FilterHashtable, $MaxEvents)
            $script:eventQueries.Add([pscustomobject]@{ Filter = $FilterHashtable; Limit = $MaxEvents })
            [pscustomobject]@{ TimeCreated = [datetime]'2026-10-23T09:00:00'; Id = 42; LevelDisplayName = 'Error'; Message = 'fixture update event' }
        }

        & ([scriptblock]::Create([IO.File]::ReadAllText($script:storeScript))) -DiagnosticsOnly

        $script:changes.Count | Should -Be 0
        $script:policyValues[$script:wuPath]['DisableWindowsUpdateAccess'] | Should -Be 1
        $script:eventQueries.Count | Should -Be 3
        foreach ($query in $script:eventQueries) {
            $query.Limit | Should -BeGreaterThan 0
            $query.Limit | Should -BeLessOrEqual 20
            $query.Filter.StartTime | Should -BeGreaterThan ([datetime]::Now.AddMinutes(-61))
            $query.Filter.LogName | Should -BeIn @('Microsoft-Windows-WindowsUpdateClient/Operational', 'Microsoft-Windows-Store/Operational', 'Microsoft-Windows-AppXDeploymentServer/Operational')
        }
        ($script:messages -join "`n") | Should -Match 'fixture update event'
    }

    It 'should warn about unavailable diagnostic channels without failing the diagnostic step' {
        Mock Get-WinEvent { throw 'fixture channel unavailable' }

        { & ([scriptblock]::Create([IO.File]::ReadAllText($script:storeScript))) -DiagnosticsOnly } | Should -Not -Throw

        $script:changes.Count | Should -Be 0
        $script:warnings.Count | Should -Be 3
        ($script:warnings -join "`n") | Should -Match 'channel unavailable'
    }
}
