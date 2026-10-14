BeforeAll {
    $script:adapterPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Sync-PowerToysKeyboard.ps1'
    $script:repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    $script:contractJson = [IO.File]::ReadAllText((Join-Path $script:repoRoot 'nix/home/keybindings/generated.json'))
    function Write-ContractTestJson {
        param([string]$Path, [object]$Value)
        [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
        [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
    }
    function Read-ContractTestJson {
        param([string]$Path)
        [IO.File]::ReadAllText($Path) | ConvertFrom-Json
    }
    function Get-ContractTestSnapshot {
        param([string]$Directory)
        @((Get-ChildItem -LiteralPath $Directory -File -Recurse | Sort-Object FullName | ForEach-Object {
                    $_.FullName + ':' + [Convert]::ToBase64String([IO.File]::ReadAllBytes($_.FullName))
                })) -join "`n"
    }
    function New-TransportTestContract {
        param([string]$SourceKey = 'left', [string]$TargetKey = 'left', [switch]$Large, [string]$TargetApp = 'msrdc.exe')
        $modifiers = @('super', 'ctrl', 'shift')
        if ($Large) { $modifiers += 'alt' }
        [pscustomobject]@{
            windows = [pscustomobject]@{
                bindings          = @([pscustomobject]@{ action = 'terminal'; key = 'enter'; modifiers = @('super') })
                disabledShortcuts = @()
                ghosttyTransport  = @([pscustomobject]@{
                        action = 'ghostty-resize-test'; targetApp = $TargetApp
                        source = [pscustomobject]@{ key = $SourceKey; modifiers = $modifiers }
                        target = [pscustomobject]@{ key = $TargetKey; modifiers = @('ctrl', 'alt', 'shift') }
                    })
            }
        }
    }
}

Describe 'Sync-PowerToysKeyboard exported desktop contract' {
    BeforeEach {
        $script:directory = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:profilePath = Join-Path $script:directory 'Keyboard Manager/default.json'
        $script:rootPath = Join-Path $script:directory 'settings.json'
        $script:colorPath = Join-Path $script:directory 'ColorPicker/settings.json'
        $script:actionPath = Join-Path $TestDrive 'desktop actions/Invoke-DesktopAction.ps1'
        Write-ContractTestJson $script:rootPath @{ enabled = @{ 'Keyboard Manager' = $false; ColorPicker = $false; FancyZones = $true }; theme = 'dark' }
    }

    It 'should deploy every exported Windows action through the launcher or its native shortcut' {
        & $script:adapterPath -ContractJson $script:contractJson -ActionScriptPath $script:actionPath -PowerToysDirectory $script:directory
        $contract = $script:contractJson | ConvertFrom-Json
        $profile = Read-ContractTestJson $script:profilePath
        $owner = Read-ContractTestJson (Join-Path $script:directory 'dotfiles-terminal-binding.json')
        $globalOwned = @($owner.mappings | Where-Object scope -EQ 'global')
        $expectedActions = @($contract.windows.bindings | Where-Object action -NE 'color-picker' | ForEach-Object action) + @('disabled')
        $globalOwned.Count | Should -Be $expectedActions.Count
        @($profile.remapShortcuts.global).Count | Should -Be $expectedActions.Count
        (@($globalOwned.action) | Sort-Object) -join ',' | Should -BeExactly (($expectedActions | Sort-Object) -join ',')
        foreach ($entry in @($globalOwned | Where-Object { $_.action -notin @('disabled', 'clipboard', 'screenshot-clipboard') })) {
            $entry.mapping.operationType | Should -Be 1
            $entry.mapping.runProgramFilePath | Should -Be '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe'
            $entry.mapping.runProgramStartInDir | Should -BeExactly (Split-Path -Parent $script:actionPath)
            $entry.mapping.runProgramArgs | Should -BeExactly ('-NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $script:actionPath + '" -Action "' + $entry.action + '"')
            $entry.mapping.exactMatch | Should -BeTrue
        }
        ($owner.mappings | Where-Object action -EQ 'clipboard').mapping.newRemapKeys | Should -Be '260;86'
        ($owner.mappings | Where-Object action -EQ 'screenshot-clipboard').mapping.newRemapKeys | Should -Be '260;16;83'
        ($owner.mappings | Where-Object action -EQ 'disabled').mapping.originalKeys | Should -Be '260;68'
        ($owner.mappings | Where-Object action -EQ 'disabled').mapping.newRemapKeys | Should -Be '256'
        (Read-ContractTestJson $script:rootPath).enabled.FancyZones | Should -BeTrue
        (Read-ContractTestJson $script:rootPath).theme | Should -Be 'dark'
        $color = Read-ContractTestJson $script:colorPath
        $color.properties.ActivationShortcut.win | Should -BeTrue
        $color.properties.ActivationShortcut.code | Should -Be 44
        (Read-ContractTestJson $script:rootPath).enabled.ColorPicker | Should -BeTrue
    }

    It 'should remain byte and timestamp idempotent with the complete exported contract' {
        & $script:adapterPath -ContractJson $script:contractJson -ActionScriptPath $script:actionPath -PowerToysDirectory $script:directory
        $snapshot = Get-ContractTestSnapshot $script:directory
        $fixedTime = [datetime]::SpecifyKind([datetime]'2020-01-01', [DateTimeKind]::Utc)
        Get-ChildItem $script:directory -File -Recurse | ForEach-Object { $_.LastWriteTimeUtc = $fixedTime }
        $times = @(Get-ChildItem $script:directory -File -Recurse | Sort-Object FullName | ForEach-Object { $_.LastWriteTimeUtc.Ticks }) -join ','
        & $script:adapterPath -ContractJson $script:contractJson -ActionScriptPath $script:actionPath -PowerToysDirectory $script:directory
        (Get-ContractTestSnapshot $script:directory) | Should -BeExactly $snapshot
        (@(Get-ChildItem $script:directory -File -Recurse | Sort-Object FullName | ForEach-Object { $_.LastWriteTimeUtc.Ticks }) -join ',') | Should -BeExactly $times
    }

    It 'should use the deployed runtime directory in native and editor launch settings' {
        $editorPath = Join-Path $script:directory 'Keyboard Manager/editorSettings.json'
        Write-ContractTestJson $editorPath @{ ShortcutSettingsDictionary = @{}; ProfileDictionary = @{}; ShortcutsByOperationType = @{}; ActiveProfile = '' }
        & $script:adapterPath -ContractJson $script:contractJson -ActionScriptPath $script:actionPath -PowerToysDirectory $script:directory
        $editor = Read-ContractTestJson $editorPath
        $runtimeEntries = @($editor.ShortcutSettingsDictionary.PSObject.Properties | ForEach-Object Value | Where-Object { $_.Shortcut.OperationType -eq 1 })
        $runtimeEntries.Count | Should -BeGreaterThan 0
        foreach ($entry in $runtimeEntries) {
            $entry.Shortcut.StartInDirectory | Should -BeExactly (Split-Path -Parent $script:actionPath)
        }
    }

    It 'should migrate the terminal-only ownership file to the complete allocation' {
        & $script:adapterPath -BindingJson '{"action":"terminal","key":"enter","modifiers":["super"]}' -PowerToysDirectory $script:directory
        $ownerPath = Join-Path $script:directory 'dotfiles-terminal-binding.json'
        $current = Read-ContractTestJson $ownerPath
        $old = $current.mappings[0]
        Write-ContractTestJson $ownerPath @{ profile = 'default'; mapping = $old.mapping; editorId = $old.editorId; editorMapping = $old.editorMapping }
        & $script:adapterPath -ContractJson $script:contractJson -ActionScriptPath $script:actionPath -PowerToysDirectory $script:directory
        $profile = Read-ContractTestJson $script:profilePath
        @($profile.remapShortcuts.global | Where-Object originalKeys -EQ '260;13').Count | Should -Be 1
        ($profile.remapShortcuts.global | Where-Object originalKeys -EQ '260;13').runProgramArgs | Should -Match '\-Action "terminal"$'
        (Read-ContractTestJson $ownerPath).version | Should -Be 2
    }

    It 'should restore ColorPicker ownership when its shared binding is removed' {
        $oldActivation = @{ win = $false; ctrl = $true; alt = $false; shift = $true; code = 67; key = 'C' }
        Write-ContractTestJson $script:colorPath @{ name = 'ColorPicker'; properties = @{ ActivationShortcut = $oldActivation; unrelated = 'keep' } }
        & $script:adapterPath -ContractJson $script:contractJson -ActionScriptPath $script:actionPath -PowerToysDirectory $script:directory
        $contract = $script:contractJson | ConvertFrom-Json
        $contract.windows.bindings = @($contract.windows.bindings | Where-Object action -NE 'color-picker')
        & $script:adapterPath -ContractJson ($contract | ConvertTo-Json -Depth 100) -ActionScriptPath $script:actionPath -PowerToysDirectory $script:directory
        $color = Read-ContractTestJson $script:colorPath
        $color.properties.ActivationShortcut.ctrl | Should -BeTrue
        $color.properties.ActivationShortcut.win | Should -BeFalse
        $color.properties.ActivationShortcut.code | Should -Be 67
        $color.properties.unrelated | Should -Be 'keep'
        (Read-ContractTestJson $script:rootPath).enabled.ColorPicker | Should -BeFalse
    }

    It 'should preserve user ColorPicker changes when its shared binding is removed' {
        & $script:adapterPath -ContractJson $script:contractJson -ActionScriptPath $script:actionPath -PowerToysDirectory $script:directory
        $color = Read-ContractTestJson $script:colorPath
        $color.properties.ActivationShortcut.code = 65
        Write-ContractTestJson $script:colorPath $color
        $contract = $script:contractJson | ConvertFrom-Json
        $contract.windows.bindings = @($contract.windows.bindings | Where-Object action -NE 'color-picker')
        & $script:adapterPath -ContractJson ($contract | ConvertTo-Json -Depth 100) -ActionScriptPath $script:actionPath -PowerToysDirectory $script:directory
        (Read-ContractTestJson $script:colorPath).properties.ActivationShortcut.code | Should -Be 65
        (Read-ContractTestJson $script:rootPath).enabled.ColorPicker | Should -BeTrue
    }

    It 'should transport <SourceKey> resize to <TargetKey> only inside WSLg' -ForEach @(
        @{ SourceKey = 'left'; TargetKey = 'left'; Large = $false; SourceCode = 37; TargetCode = 37 },
        @{ SourceKey = 'right'; TargetKey = 'right'; Large = $false; SourceCode = 39; TargetCode = 39 },
        @{ SourceKey = 'up'; TargetKey = 'up'; Large = $false; SourceCode = 38; TargetCode = 38 },
        @{ SourceKey = 'down'; TargetKey = 'down'; Large = $false; SourceCode = 40; TargetCode = 40 },
        @{ SourceKey = 'left'; TargetKey = 'home'; Large = $true; SourceCode = 37; TargetCode = 36 },
        @{ SourceKey = 'right'; TargetKey = 'end'; Large = $true; SourceCode = 39; TargetCode = 35 },
        @{ SourceKey = 'up'; TargetKey = 'page_up'; Large = $true; SourceCode = 38; TargetCode = 33 },
        @{ SourceKey = 'down'; TargetKey = 'page_down'; Large = $true; SourceCode = 40; TargetCode = 34 }
    ) {
        $contract = New-TransportTestContract -SourceKey $SourceKey -TargetKey $TargetKey -Large:$Large
        & $script:adapterPath -ContractJson ($contract | ConvertTo-Json -Depth 100) -ActionScriptPath $script:actionPath -PowerToysDirectory $script:directory
        $profile = Read-ContractTestJson $script:profilePath
        $expectedSource = if ($Large) { '260;17;18;16;' + $SourceCode } else { '260;17;16;' + $SourceCode }
        $profile.remapShortcuts.appSpecific.Count | Should -Be 1
        $mapping = $profile.remapShortcuts.appSpecific[0]
        $mapping.originalKeys | Should -Be $expectedSource
        $mapping.newRemapKeys | Should -Be ('17;18;16;' + $TargetCode)
        $mapping.targetApp | Should -Be 'msrdc.exe'
        $mapping.operationType | Should -Be 0
        $mapping.exactMatch | Should -BeTrue
        @($profile.remapShortcuts.global | Where-Object originalKeys -EQ $expectedSource).Count | Should -Be 0
        $owner = Read-ContractTestJson (Join-Path $script:directory 'dotfiles-terminal-binding.json')
        @($owner.mappings | Where-Object scope -EQ 'appSpecific').Count | Should -Be 1
    }

    It 'should preserve the same trigger in global and other-app mappings while replacing WSLg aliases' {
        Write-ContractTestJson $script:profilePath @{
            remapShortcuts       = @{
                global      = @(@{ originalKeys = '260;17;16;37'; newRemapKeys = '17;65' })
                appSpecific = @(@{ originalKeys = '260;17;16;37'; newRemapKeys = '17;66'; targetApp = 'code.exe' }, @{ originalKeys = '91;162;160;37'; newRemapKeys = '17;67'; targetApp = 'MsRdC.ExE' })
            }
            remapShortcutsToText = @{
                global      = @(@{ originalKeys = '260;17;16;37'; unicodeText = 'global text' })
                appSpecific = @(@{ originalKeys = '260;17;16;37'; unicodeText = 'other text'; targetApp = 'code.exe' }, @{ originalKeys = '260;17;16;37'; unicodeText = 'old WSLg text'; targetApp = 'msrdc.exe' })
            }
        }
        $contract = New-TransportTestContract
        & $script:adapterPath -ContractJson ($contract | ConvertTo-Json -Depth 100) -ActionScriptPath $script:actionPath -PowerToysDirectory $script:directory
        $profile = Read-ContractTestJson $script:profilePath
        ($profile.remapShortcuts.global | Where-Object originalKeys -EQ '260;17;16;37').newRemapKeys | Should -Be '17;65'
        ($profile.remapShortcuts.appSpecific | Where-Object targetApp -EQ 'code.exe').newRemapKeys | Should -Be '17;66'
        @($profile.remapShortcuts.appSpecific | Where-Object targetApp -EQ 'msrdc.exe').Count | Should -Be 1
        ($profile.remapShortcuts.appSpecific | Where-Object targetApp -EQ 'msrdc.exe').newRemapKeys | Should -Be '17;18;16;37'
        $profile.remapShortcutsToText.global[0].unicodeText | Should -Be 'global text'
        $profile.remapShortcutsToText.appSpecific.Count | Should -Be 1
        $profile.remapShortcutsToText.appSpecific[0].targetApp | Should -Be 'code.exe'
    }

    It 'should keep scoped editor metadata and complete file bytes stable on repeated applies' {
        $editorPath = Join-Path $script:directory 'Keyboard Manager/editorSettings.json'
        Write-ContractTestJson $editorPath @{ ShortcutSettingsDictionary = @{}; ProfileDictionary = @{}; ShortcutsByOperationType = @{}; ActiveProfile = '' }
        $contractJson = New-TransportTestContract | ConvertTo-Json -Depth 100
        & $script:adapterPath -ContractJson $contractJson -ActionScriptPath $script:actionPath -PowerToysDirectory $script:directory
        $editor = Read-ContractTestJson $editorPath
        $transport = @($editor.ShortcutSettingsDictionary.PSObject.Properties | ForEach-Object Value | Where-Object { $_.Shortcut.TargetApp -eq 'msrdc.exe' })
        $transport.Count | Should -Be 1
        $transport[0].Shortcut.OriginalKeys | Should -Be '260;17;16;37'
        $transport[0].Shortcut.TargetKeys | Should -Be '17;18;16;37'
        $transport[0].Shortcut.OperationType | Should -Be 0
        $transport[0].Shortcut.ProgramPath | Should -Be ''
        $transport[0].Shortcut.StartInDirectory | Should -Be ''
        $editor.ShortcutsByOperationType.RemapShortcut | Should -Contain $transport[0].Id
        $snapshot = Get-ContractTestSnapshot $script:directory
        & $script:adapterPath -ContractJson $contractJson -ActionScriptPath $script:actionPath -PowerToysDirectory $script:directory
        (Get-ContractTestSnapshot $script:directory) | Should -BeExactly $snapshot
    }

    It 'should remove unchanged scoped ownership when its target app changes or the transport is removed' -ForEach @(
        @{ Mode = 'move' }, @{ Mode = 'remove' }
    ) {
        $contract = New-TransportTestContract
        & $script:adapterPath -ContractJson ($contract | ConvertTo-Json -Depth 100) -ActionScriptPath $script:actionPath -PowerToysDirectory $script:directory
        if ($Mode -eq 'move') { $contract.windows.ghosttyTransport[0].targetApp = 'ghostty.exe' }
        else { $contract.windows.ghosttyTransport = @() }
        & $script:adapterPath -ContractJson ($contract | ConvertTo-Json -Depth 100) -ActionScriptPath $script:actionPath -PowerToysDirectory $script:directory
        $profile = Read-ContractTestJson $script:profilePath
        @($profile.remapShortcuts.appSpecific | Where-Object targetApp -EQ 'msrdc.exe').Count | Should -Be 0
        $profile.remapShortcuts.appSpecific.Count | Should -Be $(if ($Mode -eq 'move') { 1 } else { 0 })
        if ($Mode -eq 'move') { $profile.remapShortcuts.appSpecific[0].targetApp | Should -Be 'ghostty.exe' }
    }

    It 'should preserve a user change to a previously owned WSLg transport' {
        $contract = New-TransportTestContract
        & $script:adapterPath -ContractJson ($contract | ConvertTo-Json -Depth 100) -ActionScriptPath $script:actionPath -PowerToysDirectory $script:directory
        $profile = Read-ContractTestJson $script:profilePath
        $profile.remapShortcuts.appSpecific[0].newRemapKeys = '17;90'
        Write-ContractTestJson $script:profilePath $profile
        $contract.windows.ghosttyTransport = @()
        & $script:adapterPath -ContractJson ($contract | ConvertTo-Json -Depth 100) -ActionScriptPath $script:actionPath -PowerToysDirectory $script:directory
        $profile = Read-ContractTestJson $script:profilePath
        $profile.remapShortcuts.appSpecific.Count | Should -Be 1
        $profile.remapShortcuts.appSpecific[0].newRemapKeys | Should -Be '17;90'
    }

    It 'should preserve user-edited scoped editor metadata after its shared transport is removed' {
        $editorPath = Join-Path $script:directory 'Keyboard Manager/editorSettings.json'
        Write-ContractTestJson $editorPath @{ ShortcutSettingsDictionary = @{}; ProfileDictionary = @{}; ShortcutsByOperationType = @{}; ActiveProfile = '' }
        $contract = New-TransportTestContract
        & $script:adapterPath -ContractJson ($contract | ConvertTo-Json -Depth 100) -ActionScriptPath $script:actionPath -PowerToysDirectory $script:directory
        $editor = Read-ContractTestJson $editorPath
        $entry = $editor.ShortcutSettingsDictionary.PSObject.Properties | ForEach-Object Value | Where-Object { $_.Shortcut.TargetApp -eq 'msrdc.exe' }
        $entry.Shortcut.TargetKeys = '17;90'
        $entryId = $entry.Id
        Write-ContractTestJson $editorPath $editor
        $contract.windows.ghosttyTransport = @()
        & $script:adapterPath -ContractJson ($contract | ConvertTo-Json -Depth 100) -ActionScriptPath $script:actionPath -PowerToysDirectory $script:directory
        $editor = Read-ContractTestJson $editorPath
        $editor.ShortcutSettingsDictionary.$entryId.Shortcut.TargetKeys | Should -Be '17;90'
        $editor.ShortcutsByOperationType.RemapShortcut | Should -Contain $entryId
        (Read-ContractTestJson $script:profilePath).remapShortcuts.appSpecific.Count | Should -Be 0
    }

    It 'should reject invalid or conflicting scoped transport allocations before writing' -ForEach @(
        @{ Mode = 'duplicate' }, @{ Mode = 'invalid-app' }
    ) {
        $contract = New-TransportTestContract
        if ($Mode -eq 'duplicate') { $contract.windows.ghosttyTransport += $contract.windows.ghosttyTransport[0] }
        else { $contract.windows.ghosttyTransport[0].targetApp = '../outside.exe' }
        $snapshot = Get-ContractTestSnapshot $script:directory
        { & $script:adapterPath -ContractJson ($contract | ConvertTo-Json -Depth 100) -ActionScriptPath $script:actionPath -PowerToysDirectory $script:directory } | Should -Throw
        (Get-ContractTestSnapshot $script:directory) | Should -BeExactly $snapshot
    }

    It 'should reject conflicting or malformed full allocations before writing any settings' -ForEach @(
        @{ Json = '{"windows":{"bindings":[{"action":"browser","key":"b","modifiers":["super"]},{"action":"files","key":"b","modifiers":["super"]}]}}' },
        @{ Json = '{"windows":{"bindings":[{"action":"browser","key":"b","modifiers":["super"]}],"disabledShortcuts":[{"key":"b","modifiers":["super"]}]}}' },
        @{ Json = '{"windows":{"bindings":{},"disabledShortcuts":[]}}' },
        @{ Json = '{"windows":{"bindings":[],"disabledShortcuts":{}}}' },
        @{ Json = '{"windows":{"bindings":[{"action":"Browser","key":"b","modifiers":["super"]}]}}' }
    ) {
        $snapshot = Get-ContractTestSnapshot $script:directory
        { & $script:adapterPath -ContractJson $Json -ActionScriptPath $script:actionPath -PowerToysDirectory $script:directory } | Should -Throw
        (Get-ContractTestSnapshot $script:directory) | Should -BeExactly $snapshot
    }
}
