BeforeAll {
    $script:runtimePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-DesktopAction.ps1'
    . $script:runtimePath -Action '__test_load_only__'
}

Describe 'Desktop notification controls' {
    BeforeEach {
        $script:chords = [Collections.Generic.List[string]]::new()
        $script:findNames = @()
        $script:findIds = @()
        $script:window = [IntPtr]42
        $script:invocations = 0
        $script:proofEvents = [Collections.Generic.List[string]]::new()
        $script:control = [pscustomobject]@{ Id = 'notification-control' }
        $script:card = [pscustomobject]@{ Id = 'notification-card' }
        Mock Send-DesktopChord { param([uint16[]]$Keys, [IntPtr]$ExpectedWindow) $script:chords.Add(($Keys -join ',')); if ($ExpectedWindow -and $ExpectedWindow -ne [IntPtr]42) { throw 'Notification input changed windows' } }
        Mock Assert-DesktopShellPanel { [IntPtr]42 }
        Mock Get-DesktopForegroundWindow { $script:window }
        Mock Get-DesktopUiRoot { $null }
        Mock Get-DesktopUiControls { @() }
        Mock Start-Sleep { }
        Mock Write-DesktopActionEvidence { param($Name, $Details, $Status) $script:proofEvents.Add('evidence:' + $Name) }
        if (Get-Command Get-DesktopNotificationState -ErrorAction SilentlyContinue) {
            Mock Get-DesktopNotificationState { [pscustomobject]@{ Complete = $true; Controls = @($script:control); DismissTargets = @($script:control); DismissControls = @($script:control); ClearAllPresent = $true; ClearAllEnabled = $true } }
        }
        if (Get-Command Wait-DesktopNotificationRemoval -ErrorAction SilentlyContinue) {
            Mock Wait-DesktopNotificationRemoval { $script:proofEvents.Add('verified-removal') }
        }
        if (Get-Command Get-DesktopNotificationRemovalTarget -ErrorAction SilentlyContinue) { Mock Get-DesktopNotificationRemovalTarget { $script:card } }
        Mock Find-DesktopUiControl {
            param([IntPtr]$Window, [string[]]$Names, [string[]]$Ids)
            if ($Window -ne [IntPtr]42) { throw 'Notification lookup changed windows' }
            $script:findNames = $Names
            $script:findIds = $Ids
            $script:control
        }
        if (Get-Command Find-DesktopNotificationControl -ErrorAction SilentlyContinue) {
            Mock Find-DesktopNotificationControl {
                param([IntPtr]$Window, [string[]]$Names, [string[]]$Ids)
                if ($Window -ne [IntPtr]42) { throw 'Notification lookup changed windows' }
                $script:findNames = $Names
                $script:findIds = $Ids
                $script:control
            }
        }
        Mock Invoke-DesktopUiControl { $script:invocations++; $script:proofEvents.Add('activate') }
        if (Get-Command Invoke-DesktopNotificationDismissControl -ErrorAction SilentlyContinue) {
            Mock Invoke-DesktopNotificationDismissControl { $script:invocations++; $script:proofEvents.Add('activate') }
        }
    }

    It 'should support the Japanese individual notification clear labels' {
        Invoke-DesktopNotification 'dismiss'
        foreach ($escaped in @('\u901a\u77e5\u306e\u30af\u30ea\u30a2', '\u901a\u77e5\u3092\u30af\u30ea\u30a2', '\u3053\u306e\u901a\u77e5\u3092\u30af\u30ea\u30a2')) {
            $label = ('"' + $escaped + '"') | ConvertFrom-Json
            $script:findNames | Should -Contain $label
        }
        $script:invocations | Should -Be 1
    }

    It 'should find the actual notification-center ClearAllButton identity' {
        Invoke-DesktopNotification 'dismiss-all'
        $script:findIds | Should -Contain 'ClearAllButton'
        $script:invocations | Should -Be 1
    }

    It 'should close the same notification panel after a failed lookup or keyboard activation' -ForEach @(
        @{ Failure = 'find' }, @{ Failure = 'invoke' }
    ) {
        if ($Failure -eq 'find') {
            Mock Find-DesktopUiControl { throw 'isolated notification lookup failure' }
            if (Get-Command Find-DesktopNotificationControl -ErrorAction SilentlyContinue) { Mock Find-DesktopNotificationControl { throw 'isolated notification lookup failure' } }
        }
        else {
            Mock Invoke-DesktopUiControl { throw 'isolated notification invocation failure' }
            if (Get-Command Invoke-DesktopNotificationDismissControl -ErrorAction SilentlyContinue) { Mock Invoke-DesktopNotificationDismissControl { throw 'isolated notification activation failure' } }
        }
        { Invoke-DesktopNotification 'dismiss' } | Should -Throw '*notification*failure*'
        ($script:chords -join '|') | Should -Be '91,78|27'
    }

    It 'should avoid closing another window after panel focus changes' {
        Mock Find-DesktopUiControl { $script:window = [IntPtr]43; throw 'isolated notification focus failure' }
        if (Get-Command Find-DesktopNotificationControl -ErrorAction SilentlyContinue) { Mock Find-DesktopNotificationControl { $script:window = [IntPtr]43; throw 'isolated notification focus failure' } }
        { Invoke-DesktopNotification 'dismiss' } | Should -Throw '*notification*failure*'
        ($script:chords -join '|') | Should -Be '91,78'
    }

    It 'should leave notification history open without invoking a dismiss control' {
        Invoke-DesktopNotification 'history'
        ($script:chords -join '|') | Should -Be '91,78'
        $script:invocations | Should -Be 0
        @($script:findNames).Count | Should -Be 0
    }

    It 'should record a verified dismissal only after checking the refreshed panel' -ForEach @(
        @{ Operation = 'dismiss' }, @{ Operation = 'dismiss-all' }
    ) {
        Invoke-DesktopNotification $Operation
        ($script:proofEvents -join '|') | Should -Be ('activate|verified-removal|evidence:notification-' + $Operation)
        Should -Invoke Invoke-DesktopNotificationDismissControl -Times 1 -Exactly -ParameterFilter { $Window -eq [IntPtr]42 -and [object]::ReferenceEquals($Control, $script:control) }
        Should -Invoke Invoke-DesktopUiControl -Times 0 -Exactly
        Should -Invoke Write-DesktopActionEvidence -Times 1 -Exactly -ParameterFilter { $Name -eq ('notification-' + $Operation) -and ($Status -eq 'verified' -or [string]::IsNullOrEmpty($Status)) }
    }

    It 'should propagate an unverified dismissal without writing success evidence' {
        Mock Wait-DesktopNotificationRemoval { throw 'Notification removal was not verified' }
        { Invoke-DesktopNotification 'dismiss' } | Should -Throw '*not verified*'
        ($script:proofEvents -join '|') | Should -Be 'activate'
        Should -Invoke Write-DesktopActionEvidence -Times 0 -Exactly
        ($script:chords -join '|') | Should -Be '91,78|27'
    }

    It 'should activate the selected button but verify removal of its original notification card' {
        Invoke-DesktopNotification 'dismiss'
        Should -Invoke Get-DesktopNotificationRemovalTarget -Times 1 -Exactly -ParameterFilter { [object]::ReferenceEquals($Control, $script:control) }
        Should -Invoke Invoke-DesktopNotificationDismissControl -Times 1 -Exactly -ParameterFilter { [object]::ReferenceEquals($Control, $script:control) }
        Should -Invoke Wait-DesktopNotificationRemoval -Times 1 -Exactly -ParameterFilter { $Operation -eq 'dismiss' -and [object]::ReferenceEquals($Control, $script:card) }
    }

    It 'should reject an ambiguous original card before sending keyboard activation' {
        Mock Get-DesktopNotificationRemovalTarget { throw 'The closest notification card is ambiguous' }
        { Invoke-DesktopNotification 'dismiss' } | Should -Throw '*ambiguous*'
        Should -Invoke Invoke-DesktopNotificationDismissControl -Times 0 -Exactly
        Should -Invoke Wait-DesktopNotificationRemoval -Times 0 -Exactly
    }

    It 'should route each notification action through the scoped capability-aware finder' -ForEach @(
        @{ Operation = 'dismiss'; ToggleRequired = $false },
        @{ Operation = 'dismiss-all'; ToggleRequired = $false },
        @{ Operation = 'toggle'; ToggleRequired = $true }
    ) {
        Invoke-DesktopNotification $Operation
        Should -Invoke Find-DesktopNotificationControl -Times 1 -Exactly -ParameterFilter { $Window -eq [IntPtr]42 -and [bool]$Toggle -eq $ToggleRequired }
        Should -Invoke Find-DesktopUiControl -Times 0 -Exactly
        if ($ToggleRequired) {
            Should -Invoke Invoke-DesktopUiControl -Times 1 -Exactly -ParameterFilter { [bool]$Toggle }
            Should -Invoke Invoke-DesktopNotificationDismissControl -Times 0 -Exactly
        }
    }

    It 'should report control classes and IDs without copying private notification text into diagnostics' {
        Mock Get-DesktopUiControls {
            @(
                [pscustomobject]@{ Current = [pscustomobject]@{ ClassName = 'Button'; AutomationId = 'DismissButton'; Name = 'Dismiss: private account message' } },
                [pscustomobject]@{ Current = [pscustomobject]@{ ClassName = 'Button'; AutomationId = 'ClearAllButton'; Name = 'Clear all' } }
            )
        }
        $diagnostic = Get-DesktopNotificationDiagnostics -Window ([IntPtr]42) -ActionNames @('Dismiss', 'Clear all')
        $diagnostic | Should -Match 'ClearAllButton'
        $diagnostic | Should -Match 'Button'
        $diagnostic | Should -Not -Match 'private account message|Dismiss:'
    }
}

Describe 'Desktop notification keyboard activation' {
    BeforeEach {
        $script:events = [Collections.Generic.List[string]]::new()
        $script:focusSucceeds = $true
        $script:control = [pscustomobject]@{ Current = [pscustomobject]@{ HasKeyboardFocus = $false; IsKeyboardFocusable = $true; IsEnabled = $true } }
        $script:control | Add-Member -MemberType ScriptMethod -Name SetFocus -Value { $script:events.Add('set-focus'); $this.Current.HasKeyboardFocus = $script:focusSucceeds }
        Mock Assert-DesktopPanelFocus { param([IntPtr]$Window) if ($Window -ne [IntPtr]42) { throw 'Keyboard activation changed panels' }; $script:events.Add('assert-panel') }
        Mock Start-Sleep { }
        Mock Invoke-DesktopUiControl { throw 'Dismissal must not call the ineffective Invoke pattern' }
        Mock Write-DesktopActionEvidence { throw 'Keyboard input alone cannot prove notification removal' }
        Mock Send-DesktopChord { param([uint16[]]$Keys, [IntPtr]$ExpectedWindow, [object]$ExpectedControl) if ($ExpectedWindow -ne [IntPtr]42 -or ($Keys -join ',') -ne '32' -or -not [object]::ReferenceEquals($ExpectedControl, $script:control)) { throw 'Keyboard activation escaped its pinned control' }; $script:events.Add('space') }
    }

    It 'should focus the selected notification control and send Space once only after keyboard focus is proven' {
        Invoke-DesktopNotificationDismissControl -Control $script:control -Window ([IntPtr]42) -FocusTimeoutMilliseconds 0
        $script:events.IndexOf('set-focus') | Should -BeLessThan $script:events.IndexOf('space')
        $script:control.Current.HasKeyboardFocus | Should -BeTrue
        Should -Invoke Send-DesktopChord -Times 1 -Exactly
        Should -Invoke Invoke-DesktopUiControl -Times 0 -Exactly
    }

    It 'should not send a key when the requested control does not acquire keyboard focus' {
        $script:focusSucceeds = $false
        { Invoke-DesktopNotificationDismissControl -Control $script:control -Window ([IntPtr]42) -FocusTimeoutMilliseconds 0 } | Should -Throw '*focus*'
        Should -Invoke Send-DesktopChord -Times 0 -Exactly
    }

    It 'should propagate a stale focus target without sending Space' {
        $script:control | Add-Member -MemberType ScriptMethod -Name SetFocus -Force -Value { throw [Runtime.InteropServices.COMException]::new('stale notification focus target', -2147220991) }
        { Invoke-DesktopNotificationDismissControl -Control $script:control -Window ([IntPtr]42) -FocusTimeoutMilliseconds 0 } | Should -Throw '*stale notification*'
        Should -Invoke Send-DesktopChord -Times 0 -Exactly
    }

    It 'should stop without keyboard input after the notification panel loses foreground focus' {
        Mock Assert-DesktopPanelFocus { if ($script:control.Current.HasKeyboardFocus) { throw 'Notification panel focus changed' } }
        { Invoke-DesktopNotificationDismissControl -Control $script:control -Window ([IntPtr]42) -FocusTimeoutMilliseconds 0 } | Should -Throw '*focus changed*'
        Should -Invoke Send-DesktopChord -Times 0 -Exactly
    }

    It 'should recheck the original control after modifier release immediately before native input on Windows PowerShell 5.1' {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            Set-ItResult -Skipped -Because 'Windows PowerShell 5.1 requires Windows'
            return
        }
        $probe = @'
param([string]$RuntimePath)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System;
namespace DotfilesDesktop {
    public static class Native {
        public static bool Held = true;
        public static int ChordCalls = 0, KeyPolls = 0;
        public static short GetAsyncKeyState(int key) { KeyPolls++; return Held && key == 16 ? (short)-1 : (short)0; }
        public static IntPtr GetForegroundWindow() { return new IntPtr(42); }
        public static void Chord(ushort[] keys) { ChordCalls++; }
    }
}
"@
. $RuntimePath -Action '__test_load_only__'
$script:expectedControl = [pscustomobject]@{ Current = [pscustomobject]@{ HasKeyboardFocus = $true } }
function Start-Sleep { param([int]$Milliseconds) [DotfilesDesktop.Native]::Held = $false; $script:expectedControl.Current.HasKeyboardFocus = $false }
$rejected = $false
try { Send-DesktopChord @(32) -ExpectedWindow ([IntPtr]42) -ExpectedControl $script:expectedControl }
catch { if ($_.Exception.Message -notmatch 'focus') { throw }; $rejected = $true }
if (-not $rejected -or [DotfilesDesktop.Native]::ChordCalls -ne 0 -or [DotfilesDesktop.Native]::KeyPolls -le 5) { throw 'Control focus changed during modifier wait without preventing input' }
$rejected = $false
try { Send-DesktopChord @(32) -ExpectedWindow ([IntPtr]42) -ExpectedControl $script:expectedControl }
catch { if ($_.Exception.Message -notmatch 'focus') { throw }; $rejected = $true }
if (-not $rejected -or [DotfilesDesktop.Native]::ChordCalls -ne 0) { throw 'Unfocused control still received input' }
$script:expectedControl.Current.HasKeyboardFocus = $true
Send-DesktopChord @(32) -ExpectedWindow ([IntPtr]42) -ExpectedControl $script:expectedControl
if ([DotfilesDesktop.Native]::ChordCalls -ne 1) { throw 'Verified focused control did not receive exactly one chord' }
Send-DesktopChord @(17, 67)
if ([DotfilesDesktop.Native]::ChordCalls -ne 2) { throw 'Optional control guard affected ordinary clipboard input' }
Write-Output 'CONTROL_FOCUS_INPUT_GUARD_OK'
'@
        $probePath = Join-Path $TestDrive 'notification-control-input-probe.ps1'
        [IO.File]::WriteAllText($probePath, $probe, [Text.UTF8Encoding]::new($false))
        $exe = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $output = & $exe -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File $probePath -RuntimePath $script:runtimePath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
        $output -join [Environment]::NewLine | Should -Match 'CONTROL_FOCUS_INPUT_GUARD_OK'
    }
}

Describe 'Desktop notification removal verification' {
    BeforeEach {
        $script:original = [pscustomobject]@{ Id = 'original' }
        $script:other = [pscustomobject]@{ Id = 'other' }
        $script:root = [pscustomobject]@{ Id = 'root' }
        $script:state = [pscustomobject]@{
            Complete        = $true
            Controls        = @($script:root, $script:original, $script:other)
            DismissTargets  = @($script:original, $script:other)
            DismissControls = @($script:original, $script:other)
            ClearAllPresent = $true
            ClearAllEnabled = $true
        }
        Mock Assert-DesktopPanelFocus { }
        Mock Start-Sleep { }
        Mock Write-DesktopActionEvidence { throw 'Verification helpers must not write evidence themselves' }
        Mock Test-DesktopUiSameElement { param($First, $Second) [object]::ReferenceEquals($First, $Second) }
        if (Get-Command Get-DesktopNotificationState -ErrorAction SilentlyContinue) {
            Mock Get-DesktopNotificationState { $script:state }
        }
    }

    It 'should prove the original dismiss control disappeared in a complete refreshed tree' {
        $script:state.Controls = @($script:root, $script:other)
        # A new notification can keep the total count unchanged.
        $script:state.DismissTargets = @($script:other, [pscustomobject]@{ Id = 'new' })
        { Wait-DesktopNotificationRemoval -Window ([IntPtr]42) -Control $script:original -Operation dismiss -Names @('Dismiss') -BeforeCount 2 -TimeoutMilliseconds 1 } | Should -Not -Throw
    }

    It 'should reject an unchanged or merely disabled original target' -ForEach @(
        @{ Disabled = $false }, @{ Disabled = $true }
    ) {
        if ($Disabled) { $script:state.DismissControls = @($script:other) }
        { Wait-DesktopNotificationRemoval -Window ([IntPtr]42) -Control $script:original -Operation dismiss -Names @('Dismiss') -BeforeCount 2 -TimeoutMilliseconds 1 } | Should -Throw '*remov*'
    }

    It 'should reject a lower count when the original target is still present and another notification expired' {
        $script:state.Controls = @($script:root, $script:original)
        $script:state.DismissTargets = @($script:original)
        $script:state.DismissControls = @($script:original)
        { Wait-DesktopNotificationRemoval -Window ([IntPtr]42) -Control $script:original -Operation dismiss -Names @('Dismiss') -BeforeCount 2 -TimeoutMilliseconds 1 } | Should -Throw '*remov*'
    }

    It 'should not accept an incomplete empty accessibility snapshot as removal proof' -ForEach @(
        @{ Operation = 'dismiss' }, @{ Operation = 'dismiss-all' }
    ) {
        $script:state.Complete = $false
        $script:state.Controls = @()
        $script:state.DismissTargets = @()
        $script:state.DismissControls = @()
        $script:state.ClearAllPresent = $false
        $script:state.ClearAllEnabled = $false
        { Wait-DesktopNotificationRemoval -Window ([IntPtr]42) -Control $script:original -Operation $Operation -Names @('Dismiss') -BeforeCount 2 -TimeoutMilliseconds 1 } | Should -Throw '*remov*'
    }

    It 'should prove all notifications cleared only with no enabled dismiss controls and a disabled or absent ClearAllButton' -ForEach @(
        @{ ClearAllPresent = $true }, @{ ClearAllPresent = $false }
    ) {
        $script:state.Controls = @($script:root, $script:other)
        $script:state.DismissTargets = @()
        $script:state.DismissControls = @()
        $script:state.ClearAllPresent = $ClearAllPresent
        $script:state.ClearAllEnabled = $false
        { Wait-DesktopNotificationRemoval -Window ([IntPtr]42) -Control $script:original -Operation dismiss-all -Names @('Dismiss') -BeforeCount 2 -TimeoutMilliseconds 1 } | Should -Not -Throw
    }

    It 'should reject an enabled ClearAllButton or remaining enabled dismiss controls' -ForEach @(
        @{ Remaining = $false }, @{ Remaining = $true }
    ) {
        $script:state.DismissControls = if ($Remaining) { @($script:other) } else { @() }
        $script:state.ClearAllEnabled = -not $Remaining
        { Wait-DesktopNotificationRemoval -Window ([IntPtr]42) -Control $script:original -Operation dismiss-all -Names @('Dismiss') -BeforeCount 2 -TimeoutMilliseconds 1 } | Should -Throw '*remov*'
    }

    It 'should reject clear-all proof when the original enabled targets became disabled but remain in the tree' {
        $script:state.DismissControls = @()
        $script:state.ClearAllEnabled = $false
        { Wait-DesktopNotificationRemoval -Window ([IntPtr]42) -Control $script:original -Operation dismiss-all -Names @('Dismiss') -BeforeCount 2 -BeforeControls @($script:original, $script:other) -TimeoutMilliseconds 1 } | Should -Throw '*remov*'
    }

    It 'should stop verification if the pinned notification panel loses focus' {
        Mock Assert-DesktopPanelFocus { throw 'Notification panel focus changed' }
        { Wait-DesktopNotificationRemoval -Window ([IntPtr]42) -Control $script:original -Operation dismiss -Names @('Dismiss') -BeforeCount 2 -TimeoutMilliseconds 1 } | Should -Throw '*focus changed*'
    }

    It 'should retry a stale comparison without treating it as proof that every target vanished' {
        Mock Test-DesktopUiSameElement { throw [Runtime.InteropServices.COMException]::new('stale comparison', -2147220991) }
        { Wait-DesktopNotificationRemoval -Window ([IntPtr]42) -Control $script:original -Operation dismiss -Names @('Dismiss') -BeforeCount 2 -TimeoutMilliseconds 1 } | Should -Throw '*remov*'
    }

    It 'should verify original targets disappeared into a complete observed empty notification state' -ForEach @(
        @{ Operation = 'dismiss'; BeforeCount = 1 }, @{ Operation = 'dismiss-all'; BeforeCount = 2 }
    ) {
        $emptyMarker = [pscustomobject]@{ Current = [pscustomobject]@{ AutomationId = 'NoNotificationsTextBlock' } }
        $script:state.Complete = $true
        $script:state | Add-Member -MemberType NoteProperty -Name Empty -Value $true
        $script:state.Controls = @($script:root, $emptyMarker)
        $script:state.DismissTargets = @()
        $script:state.DismissControls = @()
        $script:state.ClearAllPresent = $false
        $script:state.ClearAllEnabled = $false
        $baseline = if ($Operation -eq 'dismiss-all') { @($script:original, $script:other) } else { @($script:original) }
        { Wait-DesktopNotificationRemoval -Window ([IntPtr]42) -Control $script:original -Operation $Operation -Names @('Dismiss') -BeforeCount $BeforeCount -BeforeControls $baseline -TimeoutMilliseconds 1 } | Should -Not -Throw
    }

    It 'should verify the old card disappeared despite a recycled button ID and unchanged visible button count' {
        $oldCard = [pscustomobject]@{ RuntimeId = '1340'; Current = [pscustomobject]@{ ClassName = 'ListViewItem' } }
        $newButton = [pscustomobject]@{ RuntimeId = '1329'; Current = [pscustomobject]@{ ClassName = 'Button' } }
        $newCard = [pscustomobject]@{ RuntimeId = '1360'; Current = [pscustomobject]@{ ClassName = 'ListViewItem' } }
        $anotherCard = [pscustomobject]@{ RuntimeId = '1361'; Current = [pscustomobject]@{ ClassName = 'ListViewItem' } }
        $script:state.Controls = @($script:root, $newButton, $newCard, $anotherCard)
        $script:state.DismissTargets = @($newButton)
        $script:state.DismissControls = @($newButton)
        Mock Test-DesktopUiSameElement { param($First, $Second) if ($First.RuntimeId -and $Second.RuntimeId) { $First.RuntimeId -eq $Second.RuntimeId } else { [object]::ReferenceEquals($First, $Second) } }
        { Wait-DesktopNotificationRemoval -Window ([IntPtr]42) -Control $oldCard -Operation dismiss -Names @('Dismiss') -BeforeCount 1 -TimeoutMilliseconds 1 } | Should -Not -Throw
    }

    It 'should reject removal proof when the original card remains while a different group disappears' {
        $oldCard = [pscustomobject]@{ RuntimeId = '1340'; Current = [pscustomobject]@{ ClassName = 'ListViewItem' } }
        $newButton = [pscustomobject]@{ RuntimeId = '1329'; Current = [pscustomobject]@{ ClassName = 'Button' } }
        $script:state.Controls = @($script:root, $oldCard, $newButton)
        $script:state.DismissTargets = @($newButton)
        $script:state.DismissControls = @($newButton)
        { Wait-DesktopNotificationRemoval -Window ([IntPtr]42) -Control $oldCard -Operation dismiss -Names @('Dismiss') -BeforeCount 2 -TimeoutMilliseconds 1 } | Should -Throw '*remov*'
    }
}

Describe 'Desktop notification state snapshots' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    BeforeAll {
        Add-Type -AssemblyName UIAutomationClient
        Add-Type -AssemblyName UIAutomationTypes
        function New-NotificationTestControl {
            param([string]$Name = '', [string]$Id = '', [bool]$Enabled = $true, [bool]$Invokable = $false)
            $control = [pscustomobject]@{ Current = [pscustomobject]@{ Name = $Name; AutomationId = $Id; ClassName = 'Button'; IsEnabled = $Enabled }; Invokable = $Invokable }
            $control | Add-Member -MemberType ScriptMethod -Name TryGetCurrentPattern -Value {
                param($PatternId, [ref]$Pattern)
                $Pattern.Value = [pscustomobject]@{}
                $this.Invokable -and $PatternId -eq [System.Windows.Automation.InvokePattern]::Pattern
            }
            $control
        }
    }

    BeforeEach {
        Mock Assert-DesktopPanelFocus { }
        $script:root = New-NotificationTestControl -Id 'NotificationCenterGrid'
        $script:enabled = New-NotificationTestControl -Name 'Dismiss: private notification body' -Invokable $true
        $script:disabled = New-NotificationTestControl -Name 'Dismiss' -Enabled $false -Invokable $true
        $script:clearAll = New-NotificationTestControl -Name 'Clear all' -Id 'ClearAllButton' -Invokable $true
        $script:controls = @($script:root, $script:enabled, $script:disabled, $script:clearAll)
        Mock Get-DesktopUiControls { $script:controls }
        if (Get-Command Get-DesktopNotificationControls -ErrorAction SilentlyContinue) { Mock Get-DesktopNotificationControls { $script:controls } }
    }

    It 'should count disabled dismiss targets separately from enabled actions' {
        $state = Get-DesktopNotificationState -Window ([IntPtr]42) -Names @('Dismiss')
        $state.Complete | Should -BeTrue
        @($state.Controls).Count | Should -Be 4
        @($state.DismissTargets).Count | Should -Be 2
        @($state.DismissControls).Count | Should -Be 1
        $state.ClearAllPresent | Should -BeTrue
        $state.ClearAllEnabled | Should -BeTrue
    }

    It 'should mark an empty or root-only tree incomplete' -ForEach @(
        @{ RootOnly = $false }, @{ RootOnly = $true }
    ) {
        $script:controls = if ($RootOnly) { @($script:root) } else { @() }
        $state = Get-DesktopNotificationState -Window ([IntPtr]42) -Names @('Dismiss')
        $state.Complete | Should -BeFalse
    }

    It 'should recognize the observed empty marker without requiring the removed ClearAllButton child' {
        $script:controls = @(
            $script:root,
            (New-NotificationTestControl -Id 'NoNotificationsTextBlock'),
            (New-NotificationTestControl -Id 'ClearAllButtonControl')
        )
        $state = Get-DesktopNotificationState -Window ([IntPtr]42) -Names @('Dismiss')
        $state.Complete | Should -BeTrue
        $state.Empty | Should -BeTrue
        @($state.DismissTargets).Count | Should -Be 0
        $state.ClearAllPresent | Should -BeFalse
        $state.ClearAllEnabled | Should -BeFalse
    }

    It 'should not treat a root or unrelated scaffold without the empty marker as a verified empty state' -ForEach @(
        @{ RootOnly = $true }, @{ RootOnly = $false }
    ) {
        $script:controls = if ($RootOnly) { @($script:root) } else { @($script:root, (New-NotificationTestControl -Id 'UnrelatedScaffold')) }
        $state = Get-DesktopNotificationState -Window ([IntPtr]42) -Names @('Dismiss')
        $state.Complete | Should -BeFalse
        $state.Empty | Should -BeFalse
    }

    It 'should reject contradictory empty markers when dismiss targets remain or ClearAllButton is enabled' -ForEach @(
        @{ Kind = 'remaining-target' }, @{ Kind = 'enabled-clear-all' }
    ) {
        $contradiction = if ($Kind -eq 'remaining-target') { $script:enabled } else { $script:clearAll }
        $script:controls = @($script:root, (New-NotificationTestControl -Id 'NoNotificationsTextBlock'), $contradiction)
        $state = Get-DesktopNotificationState -Window ([IntPtr]42) -Names @('Dismiss')
        $state.Empty | Should -BeFalse
    }

    It 'should mark a snapshot incomplete when an accessibility element becomes stale' {
        $script:enabled | Add-Member -MemberType ScriptMethod -Name TryGetCurrentPattern -Force -Value { param($PatternId, [ref]$Pattern) throw [Runtime.InteropServices.COMException]::new('stale snapshot', -2147220991) }
        $state = Get-DesktopNotificationState -Window ([IntPtr]42) -Names @('Dismiss')
        $state.Complete | Should -BeFalse
    }

    It 'should not treat an unrelated calendar scaffold as a complete notification tree' {
        $script:controls = @((New-NotificationTestControl -Id 'UnrelatedRoot'), (New-NotificationTestControl -Id 'CalendarGrid'))
        $state = Get-DesktopNotificationState -Window ([IntPtr]42) -Names @('Dismiss')
        $state.Complete | Should -BeFalse
    }
}

Describe 'Desktop notification subtree scope' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    BeforeAll {
        Add-Type -AssemblyName UIAutomationClient
        Add-Type -AssemblyName UIAutomationTypes
        function New-ScopedNotificationTestControl {
            param([string]$Name = '', [string]$Id = '', [string]$Capability = '', [bool]$Enabled = $true)
            $control = [pscustomobject]@{ Current = [pscustomobject]@{ Name = $Name; AutomationId = $Id; ClassName = 'Button'; IsEnabled = $Enabled }; Capability = $Capability }
            $control | Add-Member -MemberType ScriptMethod -Name TryGetCurrentPattern -Value {
                param($PatternId, [ref]$Pattern)
                $required = switch ($this.Capability) {
                    'invoke' { [System.Windows.Automation.InvokePattern]::Pattern }
                    'toggle' { [System.Windows.Automation.TogglePattern]::Pattern }
                    'selection' { [System.Windows.Automation.SelectionItemPattern]::Pattern }
                    default { $null }
                }
                if ($null -eq $required -or $PatternId -ne $required) { return $false }
                $Pattern.Value = [pscustomobject]@{}
                $true
            }
            $control
        }
    }

    BeforeEach {
        Mock Assert-DesktopPanelFocus { }
        Mock Start-Sleep { }
        $script:outside = New-ScopedNotificationTestControl -Name 'Close' -Id 'CalendarClose' -Capability invoke
        $script:inside = New-ScopedNotificationTestControl -Name 'Close' -Id 'NotificationClose' -Capability invoke
        $script:clearAll = New-ScopedNotificationTestControl -Name 'Clear all' -Id 'ClearAllButton' -Capability invoke
        $script:notificationGrid = New-ScopedNotificationTestControl -Id 'NotificationCenterGrid'
        $script:notificationGrid | Add-Member -MemberType NoteProperty -Name Children -Value @($script:inside, $script:clearAll)
        $script:notificationGrid | Add-Member -MemberType ScriptMethod -Name FindAll -Value { param($Scope, $Condition) $this.Children }
        $script:panelControls = @($script:outside, $script:notificationGrid, $script:inside, $script:clearAll)
        Mock Get-DesktopUiControls { $script:panelControls }
    }

    It 'should enumerate only the unique notification grid and its descendants' {
        $scoped = @(Get-DesktopNotificationControls -Window ([IntPtr]42))
        $scoped.Count | Should -Be 3
        [object]::ReferenceEquals($scoped[0], $script:notificationGrid) | Should -BeTrue
        @($scoped | Where-Object { [object]::ReferenceEquals($_, $script:outside) }).Count | Should -Be 0
        $scoped.Current.AutomationId | Should -Contain 'NotificationClose'
    }

    It 'should reject a missing or ambiguous notification grid instead of using the whole panel' -ForEach @(
        @{ Kind = 'missing' }, @{ Kind = 'ambiguous' }
    ) {
        if ($Kind -eq 'missing') { $script:panelControls = @($script:outside) }
        else { $script:panelControls += New-ScopedNotificationTestControl -Id 'NotificationCenterGrid' }
        @(Get-DesktopNotificationControls -Window ([IntPtr]42)).Count | Should -Be 0
    }

    It 'should return no scoped controls after stale enumeration but propagate unrelated COM failures' -ForEach @(
        @{ Stale = $true }, @{ Stale = $false }
    ) {
        $script:notificationGrid | Add-Member -MemberType NoteProperty -Name FailureCode -Value $(if ($Stale) { -2147220991 } else { -2147467259 })
        $script:notificationGrid | Add-Member -MemberType ScriptMethod -Name FindAll -Force -Value { param($Scope, $Condition) throw [Runtime.InteropServices.COMException]::new('isolated notification subtree enumeration failure', $this.FailureCode) }
        if ($Stale) { @(Get-DesktopNotificationControls -Window ([IntPtr]42)).Count | Should -Be 0 }
        else { { Get-DesktopNotificationControls -Window ([IntPtr]42) } | Should -Throw '*subtree enumeration failure*' }
    }

    It 'should choose the notification Close and exclude the earlier calendar Close from state and lookup' {
        $state = Get-DesktopNotificationState -Window ([IntPtr]42) -Names @('Close')
        @($state.DismissTargets).Count | Should -Be 1
        [object]::ReferenceEquals($state.DismissTargets[0], $script:inside) | Should -BeTrue
        $found = Find-DesktopNotificationControl -Window ([IntPtr]42) -Names @('Close') -TimeoutSeconds 0
        [object]::ReferenceEquals($found, $script:inside) | Should -BeTrue
    }

    It 'should exclude an application VerbButton named Close from dismissal targets and lookup' {
        $verb = New-ScopedNotificationTestControl -Name 'Close' -Id 'VerbButton' -Capability invoke
        $dismiss = New-ScopedNotificationTestControl -Name 'Close' -Id 'DismissButton' -Capability invoke
        $script:notificationGrid.Children = @($verb, $dismiss)
        $state = Get-DesktopNotificationState -Window ([IntPtr]42) -Names @('Close')
        @($state.DismissTargets).Count | Should -Be 1
        [object]::ReferenceEquals($state.DismissTargets[0], $dismiss) | Should -BeTrue
        $found = Find-DesktopNotificationControl -Window ([IntPtr]42) -Names @('Close') -TimeoutSeconds 0
        [object]::ReferenceEquals($found, $dismiss) | Should -BeTrue
    }

    It 'should require an invoke pattern for dismissal even if other same-name controls appear first' {
        $selection = New-ScopedNotificationTestControl -Name 'Close' -Capability selection
        $toggle = New-ScopedNotificationTestControl -Name 'Close' -Capability toggle
        $disabled = New-ScopedNotificationTestControl -Name 'Close' -Capability invoke -Enabled $false
        $script:notificationGrid.Children = @($selection, $toggle, $disabled, $script:inside)
        $found = Find-DesktopNotificationControl -Window ([IntPtr]42) -Names @('Close') -TimeoutSeconds 0
        [object]::ReferenceEquals($found, $script:inside) | Should -BeTrue
    }

    It 'should require a toggle pattern for notification mode instead of invoking a same-name button' {
        $invoke = New-ScopedNotificationTestControl -Name 'Do not disturb' -Capability invoke
        $toggle = New-ScopedNotificationTestControl -Name 'Do not disturb' -Capability toggle
        $script:notificationGrid.Children = @($invoke, $toggle)
        $found = Find-DesktopNotificationControl -Window ([IntPtr]42) -Names @('Do not disturb') -Toggle -TimeoutSeconds 0
        [object]::ReferenceEquals($found, $toggle) | Should -BeTrue
    }

    It 'should find the scoped ClearAllButton by ID and reject noninvokable same-name controls' {
        $script:notificationGrid.Children = @((New-ScopedNotificationTestControl -Name 'Clear all' -Id 'ClearAllButton' -Capability selection), $script:clearAll)
        $found = Find-DesktopNotificationControl -Window ([IntPtr]42) -Ids @('ClearAllButton') -TimeoutSeconds 0
        [object]::ReferenceEquals($found, $script:clearAll) | Should -BeTrue
    }

    It 'should reject a scoped matching control that has no required capability' {
        $script:notificationGrid.Children = @((New-ScopedNotificationTestControl -Name 'Close' -Capability selection))
        { Find-DesktopNotificationControl -Window ([IntPtr]42) -Names @('Close') -TimeoutSeconds 0 } | Should -Throw '*notification*'
    }
}

Describe 'Desktop notification original removal card' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    BeforeAll {
        Add-Type -AssemblyName UIAutomationClient
        Add-Type -AssemblyName UIAutomationTypes
        function New-NotificationRemovalTestCard {
            param([string]$Id, [object[]]$Children)
            $card = [pscustomobject]@{ Current = [pscustomobject]@{ ClassName = 'ListViewItem'; AutomationId = $Id }; Children = $Children }
            $card | Add-Member -MemberType ScriptMethod -Name FindAll -Value {
                param($Scope, $Condition)
                if ($Scope -ne [System.Windows.Automation.TreeScope]::Descendants) { throw 'Card lookup must inspect only descendants' }
                $this.Children
            }
            $card
        }
    }

    BeforeEach {
        $script:button = [pscustomobject]@{ Current = [pscustomobject]@{ ClassName = 'Button'; AutomationId = 'DismissButton' } }
        Mock Test-DesktopUiSameElement { param($First, $Second) [object]::ReferenceEquals($First, $Second) }
    }

    It 'should bind removal to the unique closest ListViewItem that contains the selected button' {
        $inner = New-NotificationRemovalTestCard -Id 'individual-card' -Children @($script:button)
        $outer = New-NotificationRemovalTestCard -Id 'group-card' -Children @($inner, $script:button)
        $target = Get-DesktopNotificationRemovalTarget -Control $script:button -Controls @($outer, $inner, $script:button)
        [object]::ReferenceEquals($target, $inner) | Should -BeTrue
    }

    It 'should preserve the selected control as fallback when no notification card contains it' {
        $otherButton = [pscustomobject]@{ Current = [pscustomobject]@{ ClassName = 'Button' } }
        $otherCard = New-NotificationRemovalTestCard -Id 'another-card' -Children @($otherButton)
        $target = Get-DesktopNotificationRemovalTarget -Control $script:button -Controls @($otherCard, $otherButton, $script:button)
        [object]::ReferenceEquals($target, $script:button) | Should -BeTrue
    }

    It 'should reject equally close matching cards before keyboard activation instead of choosing arbitrarily' {
        $first = New-NotificationRemovalTestCard -Id 'first-card' -Children @($script:button)
        $second = New-NotificationRemovalTestCard -Id 'second-card' -Children @($script:button)
        { Get-DesktopNotificationRemovalTarget -Control $script:button -Controls @($first, $second, $script:button) } | Should -Throw '*ambiguous*'
    }
}
