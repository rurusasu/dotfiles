BeforeAll {
    $script:runtimePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-DesktopAction.ps1'
    . $script:runtimePath -Action '__test_load_only__'
}

Describe 'Desktop virtualized Quick Settings search' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    BeforeAll {
        Add-Type -AssemblyName UIAutomationClient
        Add-Type -AssemblyName UIAutomationTypes
        function New-DesktopTestControl {
            param([string]$Name, [string]$Id, [bool]$Enabled = $true)
            $control = [pscustomobject]@{ Current = [pscustomobject]@{ Name = $Name; AutomationId = $Id; IsEnabled = $Enabled } }
            $control | Add-Member -MemberType ScriptMethod -Name TryGetCurrentPattern -Value {
                param($PatternId, [ref]$Pattern)
                $Pattern.Value = [pscustomobject]@{}
                $true
            }
            $control
        }
    }

    BeforeEach {
        $script:searchWindow = [IntPtr]42
        $script:scrollCalls = [Collections.Generic.List[string]]::new()
        $script:queriedWindows = [Collections.Generic.List[long]]::new()
        $script:targetControl = New-DesktopTestControl -Name 'Night light: On' -Id 'Microsoft.QuickAction.BlueLightReduction'
        Mock Assert-DesktopPanelFocus {
            param([IntPtr]$Window)
            if ($Window -ne $script:searchWindow) { throw 'Wrong shell panel window' }
        }
        Mock Start-Sleep { }
        $script:evidence = [Collections.Generic.List[object]]::new()
        Mock Write-DesktopActionEvidence {
            param([string]$Name, [hashtable]$Details, [string]$Status = 'verified')
            $script:evidence.Add([pscustomobject]@{ Name = $Name; Details = $Details; Status = $Status })
        }
        Mock Move-DesktopUiGrid {
            param([IntPtr]$Window, [switch]$Reset)
            $script:scrollCalls.Add(($Window.ToInt64().ToString() + ':' + $Reset.IsPresent.ToString()))
            $true
        }
    }

    It 'should realize a tile below the initial viewport after one reset and a large scroll' {
        Mock Get-DesktopUiControls {
            param([IntPtr]$Window)
            $script:queriedWindows.Add($Window.ToInt64())
            if ($script:scrollCalls.Count -ge 2) { return $script:targetControl }
            New-DesktopTestControl -Name 'Bluetooth' -Id 'Bluetooth'
        }
        $found = Find-DesktopUiControl -Window $script:searchWindow -Names @('Night light') -Scroll -TimeoutSeconds 1
        [object]::ReferenceEquals($found, $script:targetControl) | Should -BeTrue
        ($script:scrollCalls -join ',') | Should -Be '42:True,42:False'
        ($script:queriedWindows -join ',') | Should -Be '42,42,42'
    }

    It 'should return a visible matching tile without scrolling' {
        Mock Get-DesktopUiControls { $script:targetControl }
        $found = Find-DesktopUiControl -Window $script:searchWindow -Ids @('Microsoft.QuickAction.BlueLightReduction') -Scroll -TimeoutSeconds 1
        [object]::ReferenceEquals($found, $script:targetControl) | Should -BeTrue
        $script:scrollCalls.Count | Should -Be 0
    }

    It 'should avoid scrolling for callers that did not request virtualized grid search' {
        Mock Get-DesktopUiControls { @() }
        { Find-DesktopUiControl -Window $script:searchWindow -Names @('Missing') -TimeoutSeconds 0 } | Should -Throw '*required control*'
        $script:scrollCalls.Count | Should -Be 0
    }

    It 'should stop before reading another viewport when shell panel focus changes' {
        $script:focusChecks = 0
        Mock Assert-DesktopPanelFocus {
            param([IntPtr]$Window)
            $script:focusChecks++
            if ($script:focusChecks -gt 1) { throw 'Focus changed while operating the Windows panel' }
        }
        Mock Get-DesktopUiControls {
            param([IntPtr]$Window)
            $script:queriedWindows.Add($Window.ToInt64())
            @()
        }
        { Find-DesktopUiControl -Window $script:searchWindow -Names @('Night light') -Scroll -TimeoutSeconds 1 } | Should -Throw '*Focus changed*'
        $script:queriedWindows.Count | Should -Be 1
        $script:scrollCalls.Count | Should -Be 1
    }

    It 'should report an empty pinned COM tree without exposing control names in diagnostics' {
        $script:rootControl = [pscustomobject]@{ Current = [pscustomobject]@{ ClassName = 'ControlCenterWindow'; AutomationId = 'root'; ProcessId = 123; Name = 'private root name' } }
        $script:rootControl | Add-Member -MemberType ScriptMethod -Name FindAll -Value { param($Scope, $Condition) @() }
        Mock Get-DesktopUiRoot { $script:rootControl }
        $controls = @(Get-DesktopUiControls -Window $script:searchWindow)
        $controls.Count | Should -Be 1
        [object]::ReferenceEquals($controls[0], $script:rootControl) | Should -BeTrue
        $script:DesktopUiDiagnostics | Should -Match 'UIA view=com8;count=1'
        $script:DesktopUiDiagnostics | Should -Not -Match 'private root name|Night light'
    }

    It 'should keep standard discovery when the pinned root already exposes descendants' {
        $script:rootControl = [pscustomobject]@{ Current = [pscustomobject]@{ ClassName = 'ControlCenterWindow'; AutomationId = 'root'; ProcessId = 123 }; Child = $script:targetControl }
        $script:rootControl | Add-Member -MemberType ScriptMethod -Name FindAll -Value { param($Scope, $Condition) $this.Child }
        Mock Get-DesktopUiRoot { $script:rootControl }
        $controls = @(Get-DesktopUiControls -Window $script:searchWindow)
        $controls.Count | Should -Be 2
        [object]::ReferenceEquals($controls[1], $script:targetControl) | Should -BeTrue
        $script:DesktopUiDiagnostics | Should -Match 'UIA view=com8;count=2'
    }

    It 'should report an unavailable pinned root without traversing another window' {
        Mock Get-DesktopUiRoot { $null }
        @(Get-DesktopUiControls -Window $script:searchWindow).Count | Should -Be 0
        $script:DesktopUiDiagnostics | Should -Be 'UIA root unavailable for the pinned panel.'
    }

    It 'should verify the changed toggle state before recording success' -ForEach @(
        @{ Changes = $true }, @{ Changes = $false }
    ) {
        $pattern = [pscustomobject]@{ Current = [pscustomobject]@{ ToggleState = 0 }; Changes = $Changes; Calls = 0 }
        $pattern | Add-Member -MemberType ScriptMethod -Name Toggle -Value {
            $this.Calls++
            if ($this.Changes) { $this.Current.ToggleState = 1 }
        }
        $control = [pscustomobject]@{ Pattern = $pattern }
        $control | Add-Member -MemberType ScriptMethod -Name TryGetCurrentPattern -Value {
            param($PatternId, [ref]$Pattern)
            $Pattern.Value = $this.Pattern
            $true
        }
        if ($Changes) {
            Invoke-DesktopUiControl -Control $control -Window $script:searchWindow -Toggle -ActionName 'test-toggle' -ToggleTimeoutMilliseconds 1
            $script:evidence.Count | Should -Be 1
            $script:evidence[0].Name | Should -Be 'test-toggle'
            $script:evidence[0].Details.operation | Should -Be 'toggle'
            $script:evidence[0].Details.before | Should -Be 0
            $script:evidence[0].Details.after | Should -Be 1
            $script:evidence[0].Status | Should -Be 'verified'
        }
        else {
            { Invoke-DesktopUiControl -Control $control -Window $script:searchWindow -Toggle -ActionName 'test-toggle' -ToggleTimeoutMilliseconds 1 } | Should -Throw '*toggle state did not change*'
            $script:evidence.Count | Should -Be 0
        }
        $pattern.Calls | Should -Be 1
    }

    It 'should reject an unverifiable toggle without invoking another pattern or recording success' {
        $control = [pscustomobject]@{}
        $control | Add-Member -MemberType ScriptMethod -Name TryGetCurrentPattern -Value { param($PatternId, [ref]$Pattern) $false }
        { Invoke-DesktopUiControl -Control $control -Window $script:searchWindow -Toggle -ActionName 'test-toggle' -ToggleTimeoutMilliseconds 1 } | Should -Throw '*verifiable toggle state*'
        $script:evidence.Count | Should -Be 0
    }

    It 'should label a generic <Operation> request as submitted rather than verified completed' -ForEach @(
        @{ Operation = 'invoke' }, @{ Operation = 'select' }
    ) {
        $pattern = [pscustomobject]@{ Requests = 0 }
        $pattern | Add-Member -MemberType ScriptMethod -Name Invoke -Value { $this.Requests++ }
        $pattern | Add-Member -MemberType ScriptMethod -Name Select -Value { $this.Requests++ }
        $control = [pscustomobject]@{ Pattern = $pattern; Operation = $Operation }
        $control | Add-Member -MemberType ScriptMethod -Name TryGetCurrentPattern -Value {
            param($PatternId, [ref]$Pattern)
            $expectedPattern = if ($this.Operation -eq 'invoke') { [System.Windows.Automation.InvokePattern]::Pattern } else { [System.Windows.Automation.SelectionItemPattern]::Pattern }
            if ($PatternId -ne $expectedPattern) { return $false }
            $Pattern.Value = $this.Pattern
            $true
        }
        Invoke-DesktopUiControl -Control $control -Window $script:searchWindow -ActionName 'test-request'
        $pattern.Requests | Should -Be 1
        $script:evidence.Count | Should -Be 1
        $script:evidence[0].Status | Should -Be 'submitted'
        $script:evidence[0].Details.operation | Should -Be $Operation
        $script:evidence[0].Details.requestSubmitted | Should -BeTrue
        $script:evidence[0].Details.ContainsKey('completed') | Should -BeFalse
    }
}

Describe 'Desktop action runtime' {
    It 'should resolve keyboard parameter types in the production PowerShell runtime' {
        (Get-Command Send-DesktopChord).Parameters['Keys'].ParameterType | Should -Be ([uint16[]])
    }

    It 'should execute keyboard and clipboard argument binding on Windows PowerShell 5.1 without sending native input' {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            Set-ItResult -Skipped -Because 'Windows PowerShell 5.1 requires Windows'
            return
        }
        $probe = @'
param([string]$RuntimePath)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5) { throw 'Expected Windows PowerShell 5.1' }
# Supply the native boundary in this subprocess; no user32 input is possible.
Add-Type -TypeDefinition @"
using System;
namespace DotfilesDesktop {
    public static class Native {
        public static ushort[] LastChord;
        public static string WindowClass = "ControlCenterWindow";
        public static IntPtr GetForegroundWindow() { return new IntPtr(42); }
        public static short GetAsyncKeyState(int key) { return 0; }
        public static void Chord(ushort[] keys) { LastChord = keys; }
        public static int GetClassName(IntPtr window, System.Text.StringBuilder name, int maximum) { name.Append(WindowClass); return name.Length; }
    }
}
"@
. $RuntimePath -Action '__test_load_only__'
if ((Get-Command Send-DesktopChord).Parameters['Keys'].ParameterType -ne [uint16[]]) { throw 'Wrong keyboard parameter type' }
Send-DesktopChord @(91, 65)
if (([DotfilesDesktop.Native]::LastChord -join ',') -cne '91,65') { throw 'Quick Settings chord conversion failed' }
function Get-DesktopClipboardContext { param([IntPtr]$Window) 'ghostty' }
foreach ($operation in @('copy', 'cut', 'paste')) {
    Invoke-DesktopClipboard $operation
    $expected = if ($operation -eq 'paste') { '17,16,86' } else { '17,16,67' }
    if (([DotfilesDesktop.Native]::LastChord -join ',') -cne $expected) { throw ('Ghostty clipboard conversion failed: ' + $operation) }
}
function Get-DesktopClipboardContext { param([IntPtr]$Window) 'application' }
foreach ($operation in @('copy', 'cut', 'paste')) {
    Invoke-DesktopClipboard $operation
    $expected = switch ($operation) { 'copy' { '17,67' }; 'cut' { '17,88' }; 'paste' { '17,86' } }
    if (([DotfilesDesktop.Native]::LastChord -join ',') -cne $expected) { throw ('Application clipboard conversion failed: ' + $operation) }
}
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$script:scrollOperations = New-Object 'Collections.Generic.List[string]'
$script:scrollPattern = [pscustomobject]@{ Current = [pscustomobject]@{ VerticallyScrollable = $true; VerticalScrollPercent = 50 } }
$script:scrollPattern | Add-Member -MemberType ScriptMethod -Name SetScrollPercent -Value {
    param($Horizontal, $Vertical)
    if ($Horizontal -ne -1 -or $Vertical -ne 0) { throw 'Grid reset moved the wrong axis' }
    $script:scrollOperations.Add('reset')
    $this.Current.VerticalScrollPercent = 0
}
$script:scrollPattern | Add-Member -MemberType ScriptMethod -Name Scroll -Value {
    param($Horizontal, $Vertical)
    if ($Horizontal -ne [System.Windows.Automation.ScrollAmount]::NoAmount -or $Vertical -ne [System.Windows.Automation.ScrollAmount]::LargeIncrement) { throw 'Grid scroll used the wrong direction or amount' }
    $script:scrollOperations.Add('large-increment')
    $this.Current.VerticalScrollPercent = 100
}
$script:scrollControl = [pscustomobject]@{ Current = [pscustomobject]@{ ClassName = 'ScrollViewer'; AutomationId = 'QuickSettingsGrid' } }
$script:scrollControl | Add-Member -MemberType ScriptMethod -Name TryGetCurrentPattern -Value {
    param($PatternId, [ref]$Pattern)
    $Pattern.Value = $script:scrollPattern
    $true
}
function Get-DesktopUiControls { param([IntPtr]$Window) $script:scrollControl }
function Start-Sleep { param([int]$Milliseconds) }
if (-not (Move-DesktopUiGrid -Window ([IntPtr]42) -Reset)) { throw 'Grid reset did not report its changed position' }
if (-not (Move-DesktopUiGrid -Window ([IntPtr]42))) { throw 'Grid scroll did not report its changed position' }
if (Move-DesktopUiGrid -Window ([IntPtr]42)) { throw 'Grid scrolled beyond its last viewport' }
if (($script:scrollOperations -join ',') -cne 'reset,large-increment') { throw 'Grid reset/scroll sequence is incorrect' }
[DotfilesDesktop.Native]::WindowClass = 'UnrelatedWindow'
$guardRejected = $false
try { [void](Move-DesktopUiGrid -Window ([IntPtr]42) -Reset) }
catch { if ($_.Exception.Message -notmatch 'ControlCenterWindow') { throw }; $guardRejected = $true }
if (-not $guardRejected -or $script:scrollOperations.Count -ne 2) { throw 'Grid class guard allowed unrelated window scrolling' }
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne [Threading.ApartmentState]::STA) { throw 'Expected STA launch like PowerToys' }
$mtaResult = @(Invoke-DesktopMtaScript -ScriptBlock { param($Value) [Threading.Thread]::CurrentThread.GetApartmentState().ToString(); $Value } -Arguments @('argument with spaces'))
if (($mtaResult -join '|') -cne 'MTA|argument with spaces') { throw 'UI Automation worker apartment or argument forwarding is incorrect' }
function Invoke-DesktopMtaScript {
    param([scriptblock]$ScriptBlock, [object[]]$Arguments)
    if ($Arguments.Count -ne 2 -or $Arguments[0] -cne $RuntimePath -or $Arguments[1] -cne 'night-mode-toggle') { throw 'STA UI action delegation arguments are incorrect' }
    'UI_ACTION_DELEGATED'
}
if ((Invoke-DesktopUiAction -Name 'night-mode-toggle') -cne 'UI_ACTION_DELEGATED') { throw 'STA UI action did not delegate to its MTA boundary' }
Write-Output 'DESKTOP_KEYBOARD_BINDING_OK'
'@
        $probePath = Join-Path $TestDrive 'desktop-runtime-probe.ps1'
        [IO.File]::WriteAllText($probePath, $probe, [Text.UTF8Encoding]::new($false))
        $exe = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $output = & $exe -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File $probePath -RuntimePath $script:runtimePath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
        $output -join [Environment]::NewLine | Should -Match 'DESKTOP_KEYBOARD_BINDING_OK'
    }

    It 'should open Quick Settings for <Action> without injecting the managed clipboard chord' -ForEach @(
        @{ Action = 'night-mode-toggle' }, @{ Action = 'audio-output-cycle' }
    ) {
        $script:sentChords = [Collections.Generic.List[string]]::new()
        Mock Send-DesktopChord { param([uint16[]]$Keys) $script:sentChords.Add(($Keys -join ',')) }
        Mock Start-Sleep { }
        Mock Assert-DesktopShellPanel { throw 'stop at isolated shell panel boundary' }
        {
            if ($Action -eq 'night-mode-toggle') { Switch-DesktopNightMode }
            else { Switch-DesktopAudioOutput }
        } | Should -Throw '*isolated shell panel boundary*'
        @($script:sentChords).Count | Should -Be 1
        $script:sentChords[0] | Should -Be '91,65'
    }

    It 'should compile the native boundary on Windows PowerShell 5.1 from a directory containing a Core System facade' {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $PSVersionTable.PSVersion.Major -lt 7) {
            Set-ItResult -Skipped -Because 'The regression fixture requires Windows PowerShell 5.1 and the PowerShell 7 Core facade'
            return
        }
        $fixture = Join-Path $TestDrive 'PowerToys-like-working-directory'
        [IO.Directory]::CreateDirectory($fixture) | Out-Null
        # PowerToys ships the same .NET Core facade filename. Windows
        # PowerShell CodeDom otherwise finds it before Framework System.dll.
        Copy-Item -LiteralPath (Join-Path $PSHOME 'System.dll') -Destination (Join-Path $fixture 'System.dll')
        $probe = @'
param([string]$RuntimePath)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5) { throw 'Expected Windows PowerShell 5.1' }
. $RuntimePath -Action '__test_load_only__'
Initialize-DesktopNative
if (-not ('DotfilesDesktop.Native' -as [type])) { throw 'Native boundary was not compiled' }
Write-Output 'DESKTOP_FRAMEWORK_COMPILATION_OK'
'@
        $probePath = Join-Path $TestDrive 'desktop-compiler-probe.ps1'
        [IO.File]::WriteAllText($probePath, $probe, [Text.UTF8Encoding]::new($false))
        $exe = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $stdout = Join-Path $TestDrive 'desktop-compiler-probe.stdout'
        $stderr = Join-Path $TestDrive 'desktop-compiler-probe.stderr'
        $arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $probePath + '" -RuntimePath "' + $script:runtimePath + '"'
        $process = Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $fixture -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $output = @([IO.File]::ReadAllText($stdout), [IO.File]::ReadAllText($stderr)) -join [Environment]::NewLine
        $process.ExitCode | Should -Be 0 -Because $output
        $output | Should -Match 'DESKTOP_FRAMEWORK_COMPILATION_OK'
    }

    It 'should route copy cut and paste to the context-aware clipboard function' -ForEach @(
        @{ Action = 'copy' }, @{ Action = 'cut' }, @{ Action = 'paste' }
    ) {
        $script:clipboardOperation = $null
        Mock Invoke-DesktopClipboard { param([string]$Operation) $script:clipboardOperation = $Operation }
        Invoke-DesktopAction $Action
        $script:clipboardOperation | Should -BeExactly $Action
    }

    It 'should route <Action> through the UI Automation apartment boundary' -ForEach @(
        @{ Action = 'notification-dismiss' }, @{ Action = 'notification-dismiss-all' },
        @{ Action = 'notification-toggle' }, @{ Action = 'notification-history' },
        @{ Action = 'night-mode-toggle' }, @{ Action = 'audio-output-cycle' }
    ) {
        $script:uiAction = $null
        Mock Invoke-DesktopUiAction { param([string]$Name) $script:uiAction = $Name }
        Invoke-DesktopAction $Action
        $script:uiAction | Should -BeExactly $Action
    }

    It 'should return MTA worker results and preserve positional arguments' {
        $result = @(Invoke-DesktopMtaScript -ScriptBlock { param($Value) [Threading.Thread]::CurrentThread.GetApartmentState().ToString(); $Value } -Arguments @('argument with spaces'))
        ($result -join '|') | Should -Be 'MTA|argument with spaces'
    }

    It 'should propagate an MTA worker error to the action caller' {
        { Invoke-DesktopMtaScript -ScriptBlock { throw 'isolated worker failure' } } | Should -Throw '*isolated worker failure*'
    }

    It 'should reject unknown desktop actions explicitly' {
        { Invoke-DesktopAction 'unrecognized-action' } | Should -Throw '*Unknown desktop action*'
    }
}
