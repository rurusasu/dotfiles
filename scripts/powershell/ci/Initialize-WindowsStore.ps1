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

function Write-WindowsStoreDiagnostics {
    [CmdletBinding()]
    param()

    Assert-WindowsStoreHostedRunner
    # Postmortem diagnostics must not replace the installer failure with a missing
    # channel or an unavailable state reader. Preparation above remains strict.
    try { Write-WindowsStoreState -Label 'Diagnostics' }
    catch { Write-Warning "Windows Store state diagnostics unavailable: $($_.Exception.Message)" }
    $startTime = [datetime]::Now.AddMinutes(-60)
    foreach ($channel in @(
            'Microsoft-Windows-WindowsUpdateClient/Operational'
            'Microsoft-Windows-Store/Operational'
            'Microsoft-Windows-AppXDeploymentServer/Operational'
        )) {
        try {
            $events = @(Get-WinEvent -FilterHashtable @{ LogName = $channel; StartTime = $startTime } -MaxEvents 20 -ErrorAction Stop)
            Write-Host "WINDOWS_STORE_EVENTS: $channel Count=$($events.Count)"
            foreach ($event in $events) {
                $message = [string]$event.Message -replace '(?i)\bhttps?://\S+', '[URL redacted]'
                if ($message.Length -gt 4096) { $message = $message.Substring(0, 4096) + ' <truncated>' }
                Write-Host "WINDOWS_STORE_EVENT: Channel=$channel Time=$($event.TimeCreated) Id=$($event.Id) Level=$($event.LevelDisplayName) Message=$message"
            }
        }
        catch {
            if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { Write-Host "WINDOWS_STORE_EVENTS: $channel Count=0" }
            else { Write-Warning "Windows Store event channel unavailable ($channel): $($_.Exception.Message)" }
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference = 'Stop'
    if ($DiagnosticsOnly) { Write-WindowsStoreDiagnostics }
    else { Initialize-WindowsStore }
}
