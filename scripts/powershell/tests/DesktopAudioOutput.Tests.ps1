BeforeAll {
    $script:runtimePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-DesktopAction.ps1'
    . $script:runtimePath -Action '__test_load_only__'
}

Describe 'Desktop audio output group selection' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    BeforeAll {
        Add-Type -AssemblyName UIAutomationClient
        Add-Type -AssemblyName UIAutomationTypes
        function New-AudioTestItem {
            param([string]$Id, [object]$Container, [bool]$Selected)
            $pattern = [pscustomobject]@{ Current = [pscustomobject]@{ IsSelected = $Selected; SelectionContainer = $Container }; Id = $Id }
            $pattern | Add-Member -MemberType ScriptMethod -Name Select -Value { $script:selections.Add($this.Id); $this.Current.IsSelected = $true }
            $control = [pscustomobject]@{ Current = [pscustomobject]@{ IsEnabled = $true; AutomationId = $Id; ClassName = 'ListViewItem' }; Pattern = $pattern }
            $control | Add-Member -MemberType ScriptMethod -Name TryGetCurrentPattern -Value {
                param($PatternId, [ref]$Pattern)
                if ($PatternId -ne [System.Windows.Automation.SelectionItemPattern]::Pattern) { return $false }
                $Pattern.Value = $this.Pattern
                $true
            }
            $control
        }
    }

    BeforeEach {
        $script:selections = [Collections.Generic.List[string]]::new()
        $script:enumerations = 0
        $script:evidence = $null
        $script:audioGroup = [pscustomobject]@{ Current = [pscustomobject]@{ ClassName = 'ListView'; AutomationId = 'ListWithOutputGroupTitle' } }
        $script:spatialGroup = [pscustomobject]@{ Current = [pscustomobject]@{ ClassName = 'ListView'; AutomationId = '' } }
        $script:items = @(
            (New-AudioTestItem -Id 'audio-first' -Container $script:audioGroup -Selected $true),
            (New-AudioTestItem -Id 'spatial-off' -Container $script:spatialGroup -Selected $true),
            (New-AudioTestItem -Id 'spatial-sonic' -Container $script:spatialGroup -Selected $false)
        )
        Mock Send-DesktopChord { }
        Mock Assert-DesktopShellPanel { [IntPtr]42 }
        Mock Assert-DesktopPanelFocus { }
        Mock Start-Sleep { }
        Mock Find-DesktopUiControl { [pscustomobject]@{} }
        Mock Invoke-DesktopUiControl { }
        Mock Test-DesktopUiSameElement { param($First, $Second) [object]::ReferenceEquals($First, $Second) }
        Mock Get-DesktopUiControls { $script:enumerations++; if ($script:enumerations -gt 1) { throw 'Audio endpoint groups were not separated' }; $script:items }
        Mock Write-DesktopActionEvidence { param($Name, $Details) $script:evidence = [pscustomobject]@{ Name = $Name; Details = $Details }; throw 'Verified audio boundary reached' }
    }

    It 'should report one audio output even when spatial sound has a separate selected item' {
        { Switch-DesktopAudioOutput } | Should -Throw '*only one active audio output*'
        $script:selections.Count | Should -Be 0
        $script:evidence | Should -BeNullOrEmpty
    }

    It 'should select the next audio endpoint and exclude spatial sound from verified counts' {
        $script:items += New-AudioTestItem -Id 'audio-second' -Container $script:audioGroup -Selected $false
        { Switch-DesktopAudioOutput } | Should -Throw '*Verified audio boundary reached*'
        ($script:selections -join ',') | Should -Be 'audio-second'
        $script:evidence.Name | Should -Be 'audio-output-cycle'
        $script:evidence.Details.count | Should -Be 2
        $script:evidence.Details.beforeIndex | Should -Be 0
        $script:evidence.Details.afterIndex | Should -Be 1
    }

    It 'should never cycle selection items in an unidentified audio group' {
        $script:items = @($script:items | Where-Object { $_.Current.AutomationId -like 'spatial-*' })
        { Switch-DesktopAudioOutput } | Should -Throw '*Audio endpoint groups were not separated*'
        $script:selections.Count | Should -Be 0
        $script:evidence | Should -BeNullOrEmpty
    }
}

Describe 'Desktop audio endpoint diagnostics' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    BeforeAll {
        Add-Type -AssemblyName UIAutomationClient
        Add-Type -AssemblyName UIAutomationTypes
    }

    It 'should expose control capabilities and container IDs without private endpoint names' {
        $script:control = [pscustomobject]@{
            Current   = [pscustomobject]@{ Name = 'private device'; ClassName = 'RadioButton'; AutomationId = 'AudioDevice'; IsEnabled = $true }
            Selection = [pscustomobject]@{ Current = [pscustomobject]@{ IsSelected = $true; SelectionContainer = [pscustomobject]@{ Current = [pscustomobject]@{ ClassName = 'ListView'; AutomationId = 'AudioDeviceList'; Name = 'private container' } } } }
        }
        $script:control | Add-Member -MemberType ScriptMethod -Name TryGetCurrentPattern -Value {
            param($PatternId, [ref]$Pattern)
            if ($PatternId -eq [System.Windows.Automation.SelectionItemPattern]::Pattern) { $Pattern.Value = $this.Selection; return $true }
            if ($PatternId -eq [System.Windows.Automation.InvokePattern]::Pattern) { $Pattern.Value = [pscustomobject]@{}; return $true }
            $false
        }
        Mock Assert-DesktopPanelFocus { }
        Mock Get-DesktopUiControls { $script:control }
        $rows = @(Get-DesktopAudioDiagnostics -Window ([IntPtr]42))
        $rows.Count | Should -Be 1
        $rows[0].Index | Should -Be 0
        $rows[0].ClassName | Should -Be 'RadioButton'
        $rows[0].AutomationId | Should -Be 'AudioDevice'
        $rows[0].IsEnabled | Should -BeTrue
        $rows[0].InvokeAvailable | Should -BeTrue
        $rows[0].ToggleAvailable | Should -BeFalse
        $rows[0].SelectionAvailable | Should -BeTrue
        $rows[0].IsSelected | Should -BeTrue
        $rows[0].ContainerClassName | Should -Be 'ListView'
        $rows[0].ContainerAutomationId | Should -Be 'AudioDeviceList'
        $rows[0].PSObject.Properties.Name | Should -Contain 'ToggleState'
        $rows[0].PSObject.Properties.Name | Should -Not -Contain 'Name'
        $rows | ConvertTo-Json -Depth 6 | Should -Not -Match 'private device|private container'
    }
}
