BeforeAll {
    $script:runtimePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-DesktopAction.ps1'
    . $script:runtimePath -Action '__test_load_only__'
}

Describe 'Desktop UI stale element classification' {
    It 'should recognize the stale COM HRESULT through invocation wrappers without hiding other failures' -ForEach @(
        @{ Kind = 'direct'; Expected = $true },
        @{ Kind = 'wrapped'; Expected = $true },
        @{ Kind = 'other-com'; Expected = $false },
        @{ Kind = 'focus'; Expected = $false }
    ) {
        $exception = switch ($Kind) {
            'direct' { [Runtime.InteropServices.COMException]::new('stale element', -2147220991) }
            'wrapped' { [Reflection.TargetInvocationException]::new('wrapped', [Runtime.InteropServices.COMException]::new('stale element', -2147220991)) }
            'other-com' { [Runtime.InteropServices.COMException]::new('unrelated COM failure', -2147467259) }
            'focus' { [InvalidOperationException]::new('Focus changed while operating the Windows panel') }
        }
        Test-DesktopElementUnavailable -Exception $exception | Should -Be $Expected
    }
}

Describe 'Desktop UI stale element traversal' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    BeforeAll {
        Add-Type -AssemblyName UIAutomationClient
        Add-Type -AssemblyName UIAutomationTypes
    }

    BeforeEach {
        Mock Assert-DesktopPanelFocus { }
        Mock Start-Sleep { }
        $script:validControl = [pscustomobject]@{ Current = [pscustomobject]@{ Name = 'Night light'; AutomationId = 'target'; IsEnabled = $true } }
        $script:validControl | Add-Member -MemberType ScriptMethod -Name TryGetCurrentPattern -Value { param($PatternId, [ref]$Pattern) $Pattern.Value = [pscustomobject]@{}; $true }
        $script:staleControl = [pscustomobject]@{ Current = [pscustomobject]@{ Name = 'Night light'; AutomationId = 'target'; IsEnabled = $true }; Failure = [Runtime.InteropServices.COMException]::new('stale element', -2147220991) }
        $script:staleControl | Add-Member -MemberType ScriptMethod -Name TryGetCurrentPattern -Value { param($PatternId, [ref]$Pattern) throw $this.Failure }
    }

    It 'should skip a stale COM pattern and find the next valid control in the same pinned panel' {
        Mock Get-DesktopUiControls { @($script:staleControl, $script:validControl) }
        $found = Find-DesktopUiControl -Window ([IntPtr]42) -Names @('Night light') -TimeoutSeconds 0
        [object]::ReferenceEquals($found, $script:validControl) | Should -BeTrue
    }

    It 'should propagate unrelated COM errors while looking for a control' {
        $script:staleControl.Failure = [Runtime.InteropServices.COMException]::new('unrelated COM failure', -2147467259)
        Mock Get-DesktopUiControls { @($script:staleControl, $script:validControl) }
        { Find-DesktopUiControl -Window ([IntPtr]42) -Names @('Night light') -TimeoutSeconds 0 } | Should -Throw '*unrelated COM failure*'
    }

    It 'should return no controls for a stale root enumeration so the pinned-panel caller can retry' {
        $script:rootControl = [pscustomobject]@{ Current = [pscustomobject]@{ ClassName = 'ControlCenterWindow'; AutomationId = 'root'; ProcessId = 123 } }
        $script:rootControl | Add-Member -MemberType ScriptMethod -Name FindAll -Value { param($Scope, $Condition) throw [Runtime.InteropServices.COMException]::new('stale root', -2147220991) }
        Mock Get-DesktopUiRoot { $script:rootControl }
        @(Get-DesktopUiControls -Window ([IntPtr]42)).Count | Should -Be 0
    }

    It 'should propagate a nonstale root enumeration COM error' {
        $script:rootControl = [pscustomobject]@{ Current = [pscustomobject]@{ ClassName = 'ControlCenterWindow'; AutomationId = 'root'; ProcessId = 123 } }
        $script:rootControl | Add-Member -MemberType ScriptMethod -Name FindAll -Value { param($Scope, $Condition) throw [Runtime.InteropServices.COMException]::new('unrelated root failure', -2147467259) }
        Mock Get-DesktopUiRoot { $script:rootControl }
        { Get-DesktopUiControls -Window ([IntPtr]42) } | Should -Throw '*unrelated root failure*'
    }

    It 'should return no controls if the pinned root itself becomes unavailable' {
        Mock Get-DesktopUiRoot { throw [Runtime.InteropServices.COMException]::new('stale root factory', -2147220991) }
        @(Get-DesktopUiControls -Window ([IntPtr]42)).Count | Should -Be 0
    }

    It 'should propagate an unrelated root factory failure' {
        Mock Get-DesktopUiRoot { throw [Runtime.InteropServices.COMException]::new('unrelated root factory', -2147467259) }
        { Get-DesktopUiControls -Window ([IntPtr]42) } | Should -Throw '*unrelated root factory*'
    }

    It 'should retry audio endpoint enumeration through the guarded pinned-panel traversal' {
        $script:enumerations = 0
        $script:endpoint = [pscustomobject]@{ Current = [pscustomobject]@{ IsEnabled = $true }; Pattern = [pscustomobject]@{ Current = [pscustomobject]@{ IsSelected = $true; SelectionContainer = [pscustomobject]@{ Current = [pscustomobject]@{ ClassName = 'ListView'; AutomationId = 'ListWithOutputGroupTitle' } } } } }
        $script:endpoint | Add-Member -MemberType ScriptMethod -Name TryGetCurrentPattern -Value { param($PatternId, [ref]$Pattern) $Pattern.Value = $this.Pattern; $true }
        Mock Send-DesktopChord { }
        Mock Assert-DesktopShellPanel { [IntPtr]42 }
        Mock Find-DesktopUiControl { [pscustomobject]@{} }
        Mock Invoke-DesktopUiControl { }
        Mock Get-DesktopUiRoot { throw [Runtime.InteropServices.COMException]::new('unguarded root access', -2147220991) }
        Mock Get-DesktopUiControls { $script:enumerations++; if ($script:enumerations -gt 1) { $script:endpoint } }
        Mock Test-DesktopUiSameElement { throw 'isolated endpoint filter reached' }
        { Switch-DesktopAudioOutput } | Should -Throw '*isolated endpoint filter reached*'
        $script:enumerations | Should -Be 2
    }

    It 'should retry a stale audio container comparison only before an output is selected' {
        $script:enumerations = 0
        $script:comparisons = 0
        $script:endpoint = [pscustomobject]@{ Current = [pscustomobject]@{ IsEnabled = $true }; Pattern = [pscustomobject]@{ Current = [pscustomobject]@{ IsSelected = $true; SelectionContainer = [pscustomobject]@{ Current = [pscustomobject]@{ ClassName = 'ListView'; AutomationId = 'ListWithOutputGroupTitle' } } } } }
        $script:endpoint | Add-Member -MemberType ScriptMethod -Name TryGetCurrentPattern -Value { param($PatternId, [ref]$Pattern) $Pattern.Value = $this.Pattern; $true }
        Mock Send-DesktopChord { }
        Mock Assert-DesktopShellPanel { [IntPtr]42 }
        Mock Find-DesktopUiControl { [pscustomobject]@{} }
        Mock Invoke-DesktopUiControl { }
        Mock Get-DesktopUiControls { $script:enumerations++; $script:endpoint }
        Mock Test-DesktopUiSameElement {
            $script:comparisons++
            if ($script:comparisons -eq 1) { throw [Runtime.InteropServices.COMException]::new('stale container', -2147220991) }
            throw 'isolated comparison retry reached'
        }
        { Switch-DesktopAudioOutput } | Should -Throw '*isolated comparison retry reached*'
        $script:enumerations | Should -Be 2
        $script:comparisons | Should -Be 2
    }

    It 'should propagate a stale verification after Select without cycling the output a second time' {
        $script:enumerations = 0
        $script:selections = 0
        $script:endpoints = @()
        foreach ($selected in @($true, $false)) {
            $pattern = [pscustomobject]@{ Current = [pscustomobject]@{ IsSelected = $selected; SelectionContainer = [pscustomobject]@{ Current = [pscustomobject]@{ ClassName = 'ListView'; AutomationId = 'ListWithOutputGroupTitle' } } } }
            $pattern | Add-Member -MemberType ScriptMethod -Name Select -Value { $script:selections++; $this.Current.IsSelected = $true }
            $control = [pscustomobject]@{ Current = [pscustomobject]@{ IsEnabled = $true }; Pattern = $pattern }
            $control | Add-Member -MemberType ScriptMethod -Name TryGetCurrentPattern -Value { param($PatternId, [ref]$Pattern) $Pattern.Value = $this.Pattern; $true }
            $script:endpoints += $control
        }
        Mock Send-DesktopChord { }
        Mock Assert-DesktopShellPanel { [IntPtr]42 }
        Mock Find-DesktopUiControl { [pscustomobject]@{} }
        Mock Invoke-DesktopUiControl { }
        Mock Get-DesktopUiControls { $script:enumerations++; $script:endpoints }
        Mock Test-DesktopUiSameElement { $true }
        Mock Write-DesktopActionEvidence { throw 'Selection was not verified and must not be recorded' }
        Mock Assert-DesktopPanelFocus { if ($script:selections -gt 0) { throw [Runtime.InteropServices.COMException]::new('stale verification after selection', -2147220991) } }
        { Switch-DesktopAudioOutput } | Should -Throw '*stale verification after selection*'
        $script:selections | Should -Be 1
        $script:enumerations | Should -Be 1
    }
}
