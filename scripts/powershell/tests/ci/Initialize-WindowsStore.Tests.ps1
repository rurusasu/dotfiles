BeforeAll {
    $script:storeScript = Join-Path $PSScriptRoot '../../ci/Initialize-WindowsStore.ps1'
    if (Test-Path -LiteralPath $script:storeScript) { . $script:storeScript }
    function New-StoreDiagnosticEvent {
        param([int]$Id = 31, [long]$RecordId = 1, [string]$Message = 'fixture event', [int]$Level = 3, [string]$Xml = '<Event />')
        $event = [pscustomobject]@{
            Id = $Id; RecordId = $RecordId; TimeCreated = [datetime]'2026-10-23T00:01:00Z'
            ActivityId = $null; Level = $Level; LevelDisplayName = 'fixture level'; Message = $Message; Xml = $Xml
        }
        $event | Add-Member -MemberType ScriptMethod -Name ToXml -Value { $this.Xml }
        return $event
    }
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
        $script:eventQueries.Count | Should -Be 5
        $contextQueries = @($script:eventQueries | Where-Object { $_.Limit -eq 20 })
        $contextQueries.Count | Should -Be 3
        foreach ($query in $contextQueries) {
            $query.Limit | Should -BeLessOrEqual 20
            $query.Filter.ContainsKey('Id') | Should -BeFalse
        }
        foreach ($query in $script:eventQueries) {
            $query.Limit | Should -BeGreaterThan 0
            $query.Filter.StartTime | Should -BeGreaterThan ([datetime]::Now.AddMinutes(-61))
            $query.Filter.LogName | Should -BeIn @('Microsoft-Windows-WindowsUpdateClient/Operational', 'Microsoft-Windows-Store/Operational', 'Microsoft-Windows-AppXDeploymentServer/Operational')
        }
        $wuFailureQuery = @($script:eventQueries | Where-Object { $_.Limit -eq 30 })
        $wuFailureQuery.Count | Should -Be 1
        ($wuFailureQuery[0].Filter.Id -join ',') | Should -BeExactly '20,24,25,31'
        $wuFailureQuery[0].Filter.LogName | Should -Be 'Microsoft-Windows-WindowsUpdateClient/Operational'
        $storeFailureQuery = @($script:eventQueries | Where-Object { $_.Limit -eq 500 })
        $storeFailureQuery.Count | Should -Be 1
        $storeFailureQuery[0].Filter.LogName | Should -Be 'Microsoft-Windows-Store/Operational'
        ($script:messages -join "`n") | Should -Match 'fixture update event'
    }

    It 'should expose named Windows Update failure data and UTC correlation metadata behind a generic message' {
        $script:failureEvent = New-StoreDiagnosticEvent -RecordId 3001 -Message 'A generic Windows Update failure occurred.' -Xml @'
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event"><System><Correlation ActivityID="{12345678-1234-1234-1234-123456789abc}" /></System><EventData><Data Name="errorCode">0x80244007</Data><Data Name="updateGuid">update-fixture-guid</Data><Data Name="serviceGuid">service-fixture-guid</Data></EventData></Event>
'@
        Mock Get-WinEvent {
            param($FilterHashtable)
            if ($FilterHashtable.ContainsKey('Id')) { return $script:failureEvent }
        }

        Write-WindowsStoreDiagnostics

        $output = $script:messages -join "`n"
        $output | Should -Match 'Bucket=WindowsUpdateFailure.*RecordId=3001.*TimeUtc=2026-10-23T00:01:00.0000000Z'
        $output | Should -Match 'ActivityId=\{12345678-1234-1234-1234-123456789abc\}'
        $output | Should -Match 'errorCode=0x80244007'
        $output | Should -Match 'updateGuid=update-fixture-guid'
        $output | Should -Match 'serviceGuid=service-fixture-guid'
        $output | Should -Not -Match '<Event|<Data'
    }

    It 'should retain older originating Store failures when newer cleanup events fill the context window' {
        $script:origin = New-StoreDiagnosticEvent -Id 2006 -RecordId 10 -Message 'Transition INTO Error: -2145107961' -Xml '<Event><EventData><Data Name="NewState">Error</Data></EventData></Event>'
        $script:cleanup = @(11..40 | ForEach-Object { New-StoreDiagnosticEvent -Id 2007 -RecordId $_ -Level 2 -Message 'Cleanup after 0x80244007' })
        $script:nonFailures = @(
            (New-StoreDiagnosticEvent -RecordId 41 -Message 'Transition from Error INTO Cancel'),
            (New-StoreDiagnosticEvent -RecordId 42 -Message 'Transition from Error INTO Completed')
        )
        Mock Get-WinEvent {
            param($FilterHashtable, $MaxEvents)
            if ($FilterHashtable.LogName -eq 'Microsoft-Windows-Store/Operational') {
                if ($MaxEvents -eq 500) { return @($script:nonFailures) + @($script:cleanup) + @($script:origin) }
                return $script:cleanup | Select-Object -Last 20
            }
        }

        Write-WindowsStoreDiagnostics

        $priority = @($script:messages | Where-Object { $_ -like 'WINDOWS_STORE_EVENT:*Bucket=StoreFailure*' })
        $priority.Count | Should -Be 1
        $priority[0] | Should -Match 'Id=2006.*RecordId=10'
        $priority[0] | Should -Not -Match 'Cleanup|Cancel|Completed'
        @($script:messages | Where-Object { $_ -like 'WINDOWS_STORE_EVENT:*Bucket=Recent*' -and $_ -match 'Cleanup' }).Count | Should -Be 20
        ($script:messages -join "`n") | Should -Match 'Bucket=StoreFailure.*ReadCount=33.*MatchedFailureCount=1.*ReadLimitReached=False.*OutputLimitReached=False'
    }

    It 'should order and cap prioritized Store errors while reporting read and output limits' {
        $script:storeEvents = @(
            @(23..500 | ForEach-Object { New-StoreDiagnosticEvent -RecordId $_ -Message 'Cleaning up download failure' })
            @(22..1 | ForEach-Object { New-StoreDiagnosticEvent -RecordId $_ -Message 'DiagError: fixture method failed' })
        )
        Mock Get-WinEvent {
            param($FilterHashtable, $MaxEvents)
            if ($FilterHashtable.LogName -eq 'Microsoft-Windows-Store/Operational' -and $MaxEvents -eq 500) { return $script:storeEvents }
        }

        Write-WindowsStoreDiagnostics

        $priority = @($script:messages | Where-Object { $_ -like 'WINDOWS_STORE_EVENT:*Bucket=StoreFailure*' })
        $priority.Count | Should -Be 20
        $priority[0] | Should -Match 'RecordId=1 '
        $priority[19] | Should -Match 'RecordId=20 '
        ($script:messages -join "`n") | Should -Match 'Bucket=StoreFailure.*ReadCount=500.*MatchedFailureCount=22.*ReadLimitReached=True.*OutputLimitReached=True'
    }

    It 'should classify errors beyond display limits without returning or printing raw diagnostic text' {
        $script:tailEvents = @(
            (New-StoreDiagnosticEvent -RecordId 101 -Message (('m' * 4100) + ' 0x80244007 raw-message-tail-sentinel')),
            (New-StoreDiagnosticEvent -RecordId 102 -Xml ('<Event><EventData><Data Name="Details">' + ('v' * 2100) + ' -2145107961 raw-field-tail-sentinel</Data></EventData></Event>'))
        )
        Mock Get-WinEvent {
            param($FilterHashtable, $MaxEvents)
            if ($FilterHashtable.LogName -eq 'Microsoft-Windows-Store/Operational' -and $MaxEvents -eq 500) { return $script:tailEvents }
        }

        Write-WindowsStoreDiagnostics

        $priority = @($script:messages | Where-Object { $_ -like 'WINDOWS_STORE_EVENT:*Bucket=StoreFailure*' })
        $priority.Count | Should -Be 2
        $priority[0] | Should -Match 'RecordId=101 '
        $priority[1] | Should -Match 'RecordId=102 '
        ($script:messages -join "`n") | Should -Not -Match 'raw-message-tail-sentinel|raw-field-tail-sentinel'
        (Get-WindowsStoreEventData -Event $script:tailEvents[1] | ConvertTo-Json) | Should -Not -Match 'raw-field-tail-sentinel'
    }

    It 'should exclude cancellation and cleanup suffixes beyond display limits from priority output' {
        $script:tailEvents = @(
            (New-StoreDiagnosticEvent -RecordId 101 -Level 2 -Message ('0x80244007 ' + ('m' * 4100) + ' Cleanup')),
            (New-StoreDiagnosticEvent -RecordId 102 -Level 2 -Xml ('<Event><EventData><Data Name="Details">0x80244007 ' + ('v' * 2100) + ' Cancel</Data></EventData></Event>'))
        )
        Mock Get-WinEvent {
            param($FilterHashtable, $MaxEvents)
            if ($FilterHashtable.LogName -eq 'Microsoft-Windows-Store/Operational' -and $MaxEvents -eq 500) { return $script:tailEvents }
        }

        Write-WindowsStoreDiagnostics

        @($script:messages | Where-Object { $_ -like 'WINDOWS_STORE_EVENT:*Bucket=StoreFailure*' }).Count | Should -Be 0
        ($script:messages -join "`n") | Should -Match 'Bucket=StoreFailure.*ReadCount=2.*MatchedFailureCount=0'
    }

    It 'should redact sensitive names URLs and labeled secrets in event data and messages' {
        $script:sensitiveEvent = New-StoreDiagnosticEvent -Message 'failure at https://user:sentinel-url@example.invalid/path?token=sentinel-query password="sentinel-password"' -Xml @'
<Event><EventData><Data Name="AccessToken">sentinel-token</Data><Data Name="Cookie">sentinel-cookie</Data><Data Name="Password">sentinel-field-password</Data><Data Name="ClientSecret">sentinel-secret</Data><Data Name="Authorization">Bearer sentinel-bearer</Data><Data Name="Credential">sentinel-credential</Data><Data Name="Ticket">sentinel-ticket</Data><Data Name="ErrorMessage">failure token=sentinel-labeled</Data><Data Name="Details">Authorization: Bearer sentinel-authorization</Data><Data Name="Request">Cookie: a=sentinel-a; b=sentinel-b</Data><Data Name="Url">https://example.invalid/sentinel-path</Data></EventData></Event>
'@
        Mock Get-WinEvent { $script:sensitiveEvent }

        Write-WindowsStoreDiagnostics

        $output = $script:messages -join "`n"
        $output | Should -Match '<redacted>'
        $output | Should -Match '\[URL redacted\]'
        $output | Should -Not -Match 'sentinel-|example.invalid|https://|<Event'
    }

    It 'should cap event field count each value and total rendered data with truncation markers' {
        $event = New-StoreDiagnosticEvent -Xml ('<Event><EventData><Data Name="Details">' + ('a' * 3000) + '</Data></EventData></Event>')
        $data = Get-WindowsStoreEventData -Event $event
        $data.Text | Should -Match '<truncated>'
        ($data.Text -replace '^Details=', '').Length | Should -BeLessOrEqual 2048

        $fields = (1..65 | ForEach-Object { '<Data Name="Field' + $_ + '">value</Data>' }) -join ''
        $data = Get-WindowsStoreEventData -Event (New-StoreDiagnosticEvent -Xml ('<Event><EventData>' + $fields + '</EventData></Event>'))
        @([regex]::Matches($data.Text, 'Field\d+=')).Count | Should -Be 64
        $data.Text | Should -Not -Match 'Field65='
        $data.Text | Should -Match '<truncated>'

        $fields = (1..64 | ForEach-Object { '<Data Name="Field' + $_ + '">' + ('b' * 3000) + '</Data>' }) -join ''
        $data = Get-WindowsStoreEventData -Event (New-StoreDiagnosticEvent -Xml ('<Event><EventData>' + $fields + '</EventData></Event>'))
        $data.Text.Length | Should -BeLessOrEqual 8192
        $data.Text | Should -Match '<truncated>'
    }

    It 'should read UserData leaves and tolerate unavailable event XML without echoing its exception' {
        $event = New-StoreDiagnosticEvent -Xml '<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event"><UserData><Payload xmlns="fixture"><ErrorCode>0x80244007</ErrorCode><Nested><UpdateId>fixture-update</UpdateId></Nested></Payload></UserData></Event>'
        $data = Get-WindowsStoreEventData -Event $event
        $data.Text | Should -Match 'ErrorCode=0x80244007'
        $data.Text | Should -Match 'UpdateId=fixture-update'
        $event | Add-Member -MemberType ScriptMethod -Name ToXml -Force -Value { throw 'sentinel-xml-secret https://example.invalid' }

        { Get-WindowsStoreEventData -Event $event } | Should -Not -Throw
        (Get-WindowsStoreEventData -Event $event).Text | Should -Not -Match 'sentinel-|example.invalid'
    }

    It 'should report empty event queries without failing the diagnostic step' {
        Mock Get-WinEvent { Write-Error -Message 'No events' -ErrorId NoMatchingEventsFound -ErrorAction Stop }

        { Write-WindowsStoreDiagnostics } | Should -Not -Throw

        $script:warnings.Count | Should -Be 0
        @($script:messages | Where-Object { $_ -like 'WINDOWS_STORE_EVENTS:*ReadCount=0*' }).Count | Should -Be 5
    }

    It 'should warn about unavailable diagnostic channels without failing the diagnostic step' {
        Mock Get-WinEvent { throw 'fixture channel unavailable' }

        { & ([scriptblock]::Create([IO.File]::ReadAllText($script:storeScript))) -DiagnosticsOnly } | Should -Not -Throw

        $script:changes.Count | Should -Be 0
        $script:warnings.Count | Should -Be 5
        ($script:warnings -join "`n") | Should -Match 'channel unavailable'
    }
}
