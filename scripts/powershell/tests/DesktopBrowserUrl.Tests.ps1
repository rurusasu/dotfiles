BeforeAll {
    $script:runtimePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-DesktopAction.ps1'
    . $script:runtimePath -Action '__test_load_only__'
}

Describe 'Native Dia browser identity' {
    It 'should accept the native Dia browser process without relying on its title' {
        $identity = [pscustomobject]@{ ProcessName = 'Dia'; AppId = ''; Title = 'Example Domain' }
        Test-DesktopBrowserWindow -Window ([IntPtr]42) -Identity $identity | Should -BeTrue
    }

    It 'should reject an unrelated process whose title names Dia' {
        $identity = [pscustomobject]@{ ProcessName = 'Dia-helper'; AppId = ''; Title = 'Dia' }
        Test-DesktopBrowserWindow -Window ([IntPtr]42) -Identity $identity | Should -BeFalse
    }
}

Describe 'Desktop browser URL save' {
    BeforeEach {
        $script:window = [IntPtr]42
        $script:isBrowser = $true
        $script:sequence = 10
        $script:copiedText = ' https://example.test/path?q=two%20words&x=1 '
        $script:snapshot = [pscustomobject]@{ Text = 'original'; Html = '<b>original</b>'; Binary = [byte[]]@(0, 1, 255) }
        $script:snapshotReads = 0
        $script:restored = $null
        $script:restoreCount = 0
        $script:bookmarks = [Collections.Generic.List[Uri]]::new()
        $script:chords = [Collections.Generic.List[string]]::new()
        Mock Initialize-DesktopNative { }
        Mock Get-DesktopForegroundWindow { $script:window }
        Mock Test-DesktopBrowserWindow { $script:isBrowser }
        Mock Get-DesktopClipboardSnapshot { $script:snapshotReads++; $script:snapshot }
        Mock Get-DesktopClipboardSequence { $script:sequence }
        Mock Get-DesktopClipboardText { $script:copiedText }
        Mock Restore-DesktopClipboardSnapshot { param([object]$Snapshot) $script:restoreCount++; $script:restored = $Snapshot }
        Mock Write-DesktopBrowserBookmark { param([Uri]$Url) $script:bookmarks.Add($Url) }
        Mock Start-Sleep { }
        Mock Send-DesktopChord {
            param([uint16[]]$Keys, [IntPtr]$ExpectedWindow)
            if ($ExpectedWindow -ne [IntPtr]42) { throw 'URL input was sent to a different window' }
            $chord = $Keys -join ','
            $script:chords.Add($chord)
            if ($chord -eq '17,67') { $script:sequence = 20 }
        }
    }

    It 'should save the copied HTTP address and restore the original clipboard object without changing formats' {
        Save-DesktopBrowserUrl
        ($script:chords -join '|') | Should -Be '17,76|17,67|27'
        $script:bookmarks.Count | Should -Be 1
        $script:bookmarks[0].AbsoluteUri | Should -Be 'https://example.test/path?q=two%20words&x=1'
        $script:restoreCount | Should -Be 1
        [object]::ReferenceEquals($script:restored, $script:snapshot) | Should -BeTrue
        $script:restored.Html | Should -Be '<b>original</b>'
        ($script:restored.Binary -join ',') | Should -Be '0,1,255'
    }

    It 'should reject an unidentified foreground app before reading the clipboard or sending keys' {
        $script:isBrowser = $false
        { Save-DesktopBrowserUrl } | Should -Throw '*Focus WSL Chrome*'
        $script:snapshotReads | Should -Be 0
        $script:chords.Count | Should -Be 0
        $script:bookmarks.Count | Should -Be 0
        $script:restoreCount | Should -Be 0
    }

    It 'should restore action-owned clipboard data when the copied address is invalid' -ForEach @(
        @{ Text = 'javascript:alert(1)' }, @{ Text = 'file:///C:/private.txt' }, @{ Text = 'not a URL' }
    ) {
        $script:copiedText = $Text
        { Save-DesktopBrowserUrl } | Should -Throw '*HTTP or HTTPS URL*'
        $script:bookmarks.Count | Should -Be 0
        $script:restoreCount | Should -Be 1
        [object]::ReferenceEquals($script:restored, $script:snapshot) | Should -BeTrue
    }

    It 'should restore the original clipboard even when bookmark storage fails' {
        Mock Write-DesktopBrowserBookmark { throw 'isolated bookmark storage failure' }
        { Save-DesktopBrowserUrl } | Should -Throw '*bookmark storage failure*'
        $script:restoreCount | Should -Be 1
    }

    It 'should preserve a newer user copy instead of replacing it with the saved snapshot' {
        Mock Write-DesktopBrowserBookmark { param([Uri]$Url) $script:bookmarks.Add($Url); $script:sequence = 30 }
        Save-DesktopBrowserUrl
        $script:bookmarks.Count | Should -Be 1
        $script:restoreCount | Should -Be 0
        $script:sequence | Should -Be 30
    }

    It 'should stop after focus changes and avoid sending Escape or restoring an unowned clipboard update' {
        Mock Send-DesktopChord {
            param([uint16[]]$Keys, [IntPtr]$ExpectedWindow)
            $chord = $Keys -join ','
            $script:chords.Add($chord)
            if ($chord -eq '17,67') { $script:sequence = 20; $script:window = [IntPtr]43 }
        }
        { Save-DesktopBrowserUrl } | Should -Throw '*Browser focus changed*'
        ($script:chords -join '|') | Should -Be '17,76|17,67'
        $script:bookmarks.Count | Should -Be 0
        $script:restoreCount | Should -Be 0
    }

    It 'should restore owned clipboard data even if dismissing the address bar fails' {
        Mock Send-DesktopChord {
            param([uint16[]]$Keys, [IntPtr]$ExpectedWindow)
            if (($Keys -join ',') -eq '17,67') { $script:sequence = 20 }
            if (($Keys -join ',') -eq '27') { throw 'isolated Escape failure' }
        }
        { Save-DesktopBrowserUrl } | Should -Throw '*Escape failure*'
        $script:bookmarks.Count | Should -Be 1
        $script:restoreCount | Should -Be 1
    }
}
