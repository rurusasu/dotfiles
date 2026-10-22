[CmdletBinding()]
param([switch]$DiagnosticsOnly)

function Assert-WindowsStoreHostedRunner {
    if ($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or $env:RUNNER_OS -cne 'Windows') {
        throw 'Windows Store CI preparation requires a GitHub-hosted Windows runner.'
    }
}

function Test-WindowsStoreAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    finally { $identity.Dispose() }
}

function Get-WindowsStorePolicyState {
    $windowsUpdate = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $policies = @{}
    $urlConfigured = @{}
    foreach ($definition in @(
            @{ Path = $windowsUpdate; Names = @('DoNotConnectToWindowsUpdateInternetLocations', 'DisableWindowsUpdateAccess') }
            @{ Path = $windowsUpdate + '\AU'; Names = @('NoAutoUpdate', 'AUOptions', 'UseWUServer') }
        )) {
        $key = $null
        try { $key = Get-ItemProperty -LiteralPath $definition.Path -ErrorAction Stop }
        catch [Management.Automation.ItemNotFoundException] { }
        foreach ($name in $definition.Names) {
            $property = if ($key) { $key.PSObject.Properties[$name] } else { $null }
            $policies[$name] = [pscustomobject]@{ Path = $definition.Path; Present = ($null -ne $property); Value = $(if ($property) { $property.Value } else { $null }) }
        }
        if ($definition.Path -eq $windowsUpdate) {
            foreach ($name in @('WUServer', 'WUStatusServer', 'UpdateServiceUrlAlternate')) {
                $property = if ($key) { $key.PSObject.Properties[$name] } else { $null }
                # Record applicability without disclosing server addresses or credentials.
                $urlConfigured[$name] = ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value))
            }
        }
    }
    return [pscustomobject]@{ Policies = $policies; UrlConfigured = $urlConfigured }
}

function Write-WindowsStoreState {
    param([string]$Label = 'Current', [object]$PolicyState)

    if (-not $PolicyState) { $PolicyState = Get-WindowsStorePolicyState }
    Write-Host "WINDOWS_STORE_STATE: $Label"
    foreach ($name in @('DoNotConnectToWindowsUpdateInternetLocations', 'DisableWindowsUpdateAccess', 'NoAutoUpdate', 'AUOptions', 'UseWUServer')) {
        $policy = $PolicyState.Policies[$name]
        $value = '<absent>'
        if ($policy.Present) {
            # These are integer policies. Do not echo an unexpected string value.
            $value = if ([string]$policy.Value -match '^\d+$') { [string]$policy.Value } else { '<non-integer>' }
        }
        Write-Host "WINDOWS_STORE_POLICY: $name=$value"
    }
    foreach ($name in @('WUServer', 'WUStatusServer', 'UpdateServiceUrlAlternate')) {
        Write-Host "WINDOWS_STORE_POLICY: $($name)Configured=$($PolicyState.UrlConfigured[$name])"
    }
    foreach ($name in @('wuauserv', 'BITS', 'InstallService', 'DoSvc', 'ClipSVC', 'AppXSvc')) {
        $service = Get-Service -Name $name -ErrorAction Stop
        Write-Host "WINDOWS_STORE_SERVICE: $name StartType=$($service.StartType) Status=$($service.Status)"
    }
    foreach ($name in @('Microsoft.WindowsStore', 'Microsoft.DesktopAppInstaller')) {
        $packages = @(Get-AppxPackage -Name $name -ErrorAction Stop)
        if ($packages.Count -eq 0) { Write-Host "WINDOWS_STORE_APPX: $name <absent>" }
        foreach ($package in $packages) { Write-Host "WINDOWS_STORE_APPX: $name Version=$($package.Version)" }
    }
}

function Initialize-WindowsStore {
    [CmdletBinding()]
    param()

    # Keep this before every registry or service operation, including diagnostics.
    Assert-WindowsStoreHostedRunner
    if (-not (Test-WindowsStoreAdministrator)) { throw 'Windows Store CI preparation requires administrator rights.' }
    $before = Get-WindowsStorePolicyState
    Write-WindowsStoreState -Label 'Before' -PolicyState $before
    foreach ($name in @('DoNotConnectToWindowsUpdateInternetLocations', 'DisableWindowsUpdateAccess')) {
        $policy = $before.Policies[$name]
        if ($policy.Present) {
            Remove-ItemProperty -LiteralPath $policy.Path -Name $name -ErrorAction Stop
        }
    }

    $service = Get-Service -Name 'wuauserv' -ErrorAction Stop
    if ($service.StartType -eq 'Disabled') {
        Set-Service -Name 'wuauserv' -StartupType Manual -ErrorAction Stop
    }
    if ($service.Status -ne 'Running') {
        # Start-Service waits internally for Running; send the start request
        # directly so the explicit timeout below owns the status wait.
        $service.Start()
        $service.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds(30))
        $service.Refresh()
        if ($service.Status -ne 'Running') { throw 'wuauserv did not reach Running within 30 seconds.' }
    }

    $after = Get-WindowsStorePolicyState
    Write-WindowsStoreState -Label 'After' -PolicyState $after
    foreach ($name in @('NoAutoUpdate', 'AUOptions')) {
        $previous = $before.Policies[$name]
        $current = $after.Policies[$name]
        if ($previous.Present -ne $current.Present -or -not [object]::Equals($previous.Value, $current.Value)) {
            throw "$name changed during Windows Store CI preparation."
        }
    }
    foreach ($name in @('DoNotConnectToWindowsUpdateInternetLocations', 'DisableWindowsUpdateAccess')) {
        if ($after.Policies[$name].Present) { throw "$name remains set after Windows Store CI preparation." }
    }
    Write-Host 'WINDOWS_STORE_PREREQUISITES_READY'
}

function ConvertTo-WindowsStoreDiagnosticText {
    param([AllowNull()][string]$Text, [string]$FieldName, [int]$MaximumLength = 4096)

    $sensitive = 'token|cookie|password|secret|authorization|credential|ticket'
    if ($FieldName -match $sensitive) { return '<redacted>' }
    # Consume the rest of a labeled secret's line, including bearer tokens,
    # quoted values, and cookies containing spaces or semicolons.
    $safe = [string]$Text -replace ('(?im)(?<!\w)["'']?[\w.-]*(?:' + $sensitive + ')[\w.-]*["'']?\s*[:=][^\r\n]*'), '<redacted>'
    $safe = $safe -replace '(?i)\b[a-z][a-z0-9+.-]*://[^\s<>"'']+', '[URL redacted]'
    $marker = '<truncated>'
    if ($safe.Length -gt $MaximumLength) { $safe = $safe.Substring(0, $MaximumLength - $marker.Length) + $marker }
    return $safe
}

function Get-WindowsStoreEventData {
    param([Parameter(Mandatory)][object]$Event)

    $result = [pscustomobject]@{ Text = '<unavailable>'; ActivityId = $null; StoreFailure = $false }
    # Keep raw classification text private. Only the boolean and sanitized,
    # bounded display data leave this function.
    $classificationText = ''
    try { $classificationText = [string]$Event.Message } catch { }
    if ($Event.PSObject.Methods['ToXml']) {
        try {
            $xml = New-Object System.Xml.XmlDocument
            $xml.XmlResolver = $null
            $xml.LoadXml($Event.ToXml())
            $correlation = $xml.SelectSingleNode('/*[local-name()="Event"]/*[local-name()="System"]/*[local-name()="Correlation"]')
            if ($correlation) {
                $activity = $correlation.GetAttribute('ActivityID')
                $parsedActivity = [guid]::Empty
                if ([guid]::TryParse($activity, [ref]$parsedActivity)) { $result.ActivityId = $activity }
            }
            $nodes = @($xml.SelectNodes('/*[local-name()="Event"]/*[local-name()="EventData"]/*[local-name()="Data"][@Name]'))
            if ($nodes.Count -eq 0) { $nodes = @($xml.SelectNodes('/*[local-name()="Event"]/*[local-name()="UserData"]//*[not(*)]')) }
            foreach ($node in $nodes) {
                $name = if ($node.HasAttribute('Name')) { $node.GetAttribute('Name') } else { $node.LocalName }
                $classificationText += ' ' + $name + '=' + $node.InnerText
            }
            $fields = [Collections.Generic.List[string]]::new()
            foreach ($node in ($nodes | Select-Object -First 64)) {
                $name = if ($node.HasAttribute('Name')) { $node.GetAttribute('Name') } else { $node.LocalName }
                $value = ConvertTo-WindowsStoreDiagnosticText -Text $node.InnerText -FieldName $name -MaximumLength 2048
                $name = ConvertTo-WindowsStoreDiagnosticText -Text $name -MaximumLength 128
                $fields.Add($name + '=' + $value)
            }
            $result.Text = $fields -join '; '
            $marker = '<truncated>'
            if ($nodes.Count -gt 64) { $result.Text += '; ' + $marker }
            if ($result.Text.Length -gt 8192) { $result.Text = $result.Text.Substring(0, 8192 - $marker.Length) + $marker }
        }
        catch { $result.Text = '<unavailable>' } # Never print XML or its exception.
    }
    $excluded = $classificationText -match '(?i)\bcancel\w*|\bclean(?:up|ing\s*up)\b'
    $errorLevel = ($null -ne $Event.Level -and [int]$Event.Level -le 2)
    $result.StoreFailure = -not $excluded -and ($errorLevel -or $classificationText -match '(?i)80244007|-2145107961|\binto\s+Error\b|\bNewState=Error\b|SOAP\s*fault|download\w*\s*fail\w*|\bDiagError\b')
    return $result
}

function Get-WindowsStoreEventMessage {
    param([object]$Event)
    try { return ConvertTo-WindowsStoreDiagnosticText -Text ([string]$Event.Message) }
    catch { return '<unavailable>' }
}

function Write-WindowsStoreDiagnosticEvent {
    param([object]$Event, [string]$Channel, [string]$Bucket, [object]$EventData)

    if (-not $EventData) { $EventData = Get-WindowsStoreEventData -Event $Event }
    $activity = $EventData.ActivityId
    if ($Event.ActivityId) { $activity = ConvertTo-WindowsStoreDiagnosticText -Text ([string]$Event.ActivityId) -MaximumLength 128 }
    $time = if ($Event.TimeCreated) { ([datetime]$Event.TimeCreated).ToUniversalTime().ToString('o') } else { '<unavailable>' }
    $message = Get-WindowsStoreEventMessage -Event $Event
    Write-Host "WINDOWS_STORE_EVENT: Bucket=$Bucket Channel=$Channel Id=$($Event.Id) RecordId=$($Event.RecordId) TimeUtc=$time ActivityId=$activity Level=$($Event.LevelDisplayName) Message=$message EventData=$($EventData.Text)"
}

function Write-WindowsStoreDiagnostics {
    [CmdletBinding()]
    param()

    Assert-WindowsStoreHostedRunner
    # Postmortem diagnostics must not replace the installer failure with a missing
    # channel or an unavailable state reader. Preparation above remains strict.
    try { Write-WindowsStoreState -Label 'Diagnostics' }
    catch { Write-Warning ('Windows Store state diagnostics unavailable: ' + (ConvertTo-WindowsStoreDiagnosticText -Text $_.Exception.Message)) }
    $startTime = [datetime]::Now.AddMinutes(-60)
    $windowsUpdate = 'Microsoft-Windows-WindowsUpdateClient/Operational'
    $store = 'Microsoft-Windows-Store/Operational'
    foreach ($query in @(
            @{ Channel = $windowsUpdate; Bucket = 'Recent'; ReadLimit = 20; OutputLimit = 20 }
            @{ Channel = $store; Bucket = 'Recent'; ReadLimit = 20; OutputLimit = 20 }
            @{ Channel = 'Microsoft-Windows-AppXDeploymentServer/Operational'; Bucket = 'Recent'; ReadLimit = 20; OutputLimit = 20 }
            @{ Channel = $windowsUpdate; Bucket = 'WindowsUpdateFailure'; ReadLimit = 30; OutputLimit = 30; Id = @(20, 24, 25, 31) }
            @{ Channel = $store; Bucket = 'StoreFailure'; ReadLimit = 500; OutputLimit = 20 }
        )) {
        $channel = $query.Channel
        try {
            $filter = @{ LogName = $channel; StartTime = $startTime }
            if ($query.ContainsKey('Id')) { $filter.Id = $query.Id }
            $events = @(Get-WinEvent -FilterHashtable $filter -MaxEvents $query.ReadLimit -ErrorAction Stop)
            $candidates = @(
                foreach ($event in $events) {
                    $data = Get-WindowsStoreEventData -Event $event
                    if ($query.Bucket -eq 'StoreFailure' -and -not $data.StoreFailure) { continue }
                    [pscustomobject]@{ Event = $event; Data = $data }
                }
            )
            if ($query.Bucket -eq 'StoreFailure') {
                $candidates = @($candidates | Sort-Object @{ Expression = { $_.Event.RecordId } }, @{ Expression = { $_.Event.TimeCreated } })
            }
            $readLimitReached = $events.Count -ge $query.ReadLimit
            $outputLimitReached = $candidates.Count -gt $query.OutputLimit
            Write-Host "WINDOWS_STORE_EVENTS: Bucket=$($query.Bucket) Channel=$channel ReadCount=$($events.Count) MatchedFailureCount=$($candidates.Count) ReadLimitReached=$readLimitReached OutputLimitReached=$outputLimitReached"
            foreach ($match in ($candidates | Select-Object -First $query.OutputLimit)) {
                Write-WindowsStoreDiagnosticEvent -Event $match.Event -Channel $channel -Bucket $query.Bucket -EventData $match.Data
            }
        }
        catch {
            if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') {
                Write-Host "WINDOWS_STORE_EVENTS: Bucket=$($query.Bucket) Channel=$channel ReadCount=0 MatchedFailureCount=0 ReadLimitReached=False OutputLimitReached=False"
            }
            else { Write-Warning ("Windows Store event channel unavailable ($channel): " + (ConvertTo-WindowsStoreDiagnosticText -Text $_.Exception.Message)) }
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference = 'Stop'
    if ($DiagnosticsOnly) { Write-WindowsStoreDiagnostics }
    else { Initialize-WindowsStore }
}
