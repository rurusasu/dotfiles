BeforeAll {
    $script:runtimePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-DesktopAction.ps1'
    . $script:runtimePath -Action '__test_load_only__'
}

Describe 'Desktop native recording shortcut' {
    BeforeEach {
        $script:chords = [Collections.Generic.List[string]]::new()
        Mock Send-DesktopChord { param([uint16[]]$Keys) $script:chords.Add(($Keys -join ',')) }
        Mock Invoke-DesktopUiAction { throw 'Recording does not need the UI Automation worker' }
        Mock Invoke-DesktopProcess { throw 'Recording does not need a process launch' }
        Mock Invoke-InstalledDesktopApp { throw 'Recording does not need application activation' }
    }

    It 'should dispatch recording to the Windows native video capture overlay' {
        Invoke-DesktopAction 'record'
        ($script:chords -join '|') | Should -Be '91,16,82'
        Should -Invoke Send-DesktopChord -Times 1 -Exactly
    }

    It 'should propagate a rejected native shortcut without launching a fallback' {
        Mock Send-DesktopChord { throw 'Release the shortcut modifiers and try again.' }
        { Invoke-DesktopAction 'record' } | Should -Throw '*Release the shortcut modifiers*'
    }
}