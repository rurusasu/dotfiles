BeforeAll {
    $script:adapterPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Sync-PowerToysKeyboard.ps1'
    $script:binding = '{"action":"terminal","key":"enter","modifiers":["super"]}'
    function Write-TestJson {
        param([string]$Path, [object]$Value)
        [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
        [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
    }
    function Read-TestJson {
        param([string]$Path)
        Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    function Get-TestSnapshot {
        param([string]$Directory)
        @((Get-ChildItem -LiteralPath $Directory -File -Recurse | Sort-Object FullName | ForEach-Object {
                    $_.FullName + ':' + [Convert]::ToBase64String([IO.File]::ReadAllBytes($_.FullName))
                })) -join "`n"
    }
}

Describe 'Sync-PowerToysKeyboard' {
    BeforeEach {
        $script:directory = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:keyboardDirectory = Join-Path $script:directory 'Keyboard Manager'
        $script:rootPath = Join-Path $script:directory 'settings.json'
        $script:modulePath = Join-Path $script:keyboardDirectory 'settings.json'
        $script:profilePath = Join-Path $script:keyboardDirectory 'personal.json'
        Write-TestJson $script:rootPath @{ startup = $true; enabled = @{ 'Keyboard Manager' = $false; FancyZones = $true; Awake = $false }; theme = 'dark' }
        Write-TestJson $script:modulePath @{ name = 'Keyboard Manager'; version = '1'; properties = @{ activeConfiguration = @{ value = 'personal' }; useNewEditor = $true } }
        Write-TestJson $script:profilePath @{ remapKeys = @{ inProcess = @(@{ originalKeys = '20'; newRemapKeys = '27' }) }; remapKeysToText = @{ inProcess = @() }; remapShortcuts = @{ global = @(@{ originalKeys = '17;67'; newRemapKeys = '17;86' }); appSpecific = @(@{ originalKeys = '260;13'; newRemapKeys = '17;13'; targetApp = 'code.exe' }) }; remapShortcutsToText = @{ global = @(); appSpecific = @() }; custom = 'preserved' }
    }

    It 'should merge the shared binding into the active profile while preserving unrelated settings' {
        & $script:adapterPath -BindingJson $script:binding -PowerToysDirectory $script:directory
        $root = Read-TestJson $script:rootPath
        $profile = Read-TestJson $script:profilePath
        $mapping = @($profile.remapShortcuts.global | Where-Object originalKeys -EQ '260;13')
        $mapping.Count | Should -Be 1
        $mapping[0].runProgramFilePath | Should -Be '%SystemRoot%\System32\wsl.exe'
        $mapping[0].runProgramArgs | Should -Be '--distribution NixOS --cd ~ --exec bash -lc ghostty'
        $mapping[0].operationType | Should -Be 1
        $mapping[0].runProgramStartWindowType | Should -Be 1
        $mapping[0].runProgramAlreadyRunningAction | Should -Be 1
        $mapping[0].runProgramElevationLevel | Should -Be 0
        $mapping[0].exactMatch | Should -BeTrue
        $root.enabled.'Keyboard Manager' | Should -BeTrue
        $root.enabled.FancyZones | Should -BeTrue
        $root.enabled.Awake | Should -BeFalse
        $root.theme | Should -Be 'dark'
        $profile.remapKeys.inProcess[0].newRemapKeys | Should -Be '27'
        $profile.remapShortcuts.global[0].newRemapKeys | Should -Be '17;86'
        $profile.remapShortcuts.appSpecific[0].targetApp | Should -Be 'code.exe'
        $profile.custom | Should -Be 'preserved'
        (Read-TestJson $script:modulePath).properties.activeConfiguration.value | Should -Be 'personal'
        Test-Path (Join-Path $script:keyboardDirectory 'editorSettings.json') | Should -BeFalse
    }

    It 'should replace existing global aliases for the same trigger' {
        $profile = Read-TestJson $script:profilePath
        $profile.remapShortcuts.global += @(@{ originalKeys = '91;13'; newRemapKeys = '18;13' }, @{ originalKeys = '92;13'; operationType = 1; runProgramFilePath = 'old.exe' })
        Write-TestJson $script:profilePath $profile
        & $script:adapterPath -BindingJson $script:binding -PowerToysDirectory $script:directory
        $profile = Read-TestJson $script:profilePath
        @($profile.remapShortcuts.global).Count | Should -Be 2
        @($profile.remapShortcuts.global | Where-Object originalKeys -EQ '260;13').Count | Should -Be 1
        @($profile.remapShortcuts.global | Where-Object originalKeys -In '91;13', '92;13').Count | Should -Be 0
    }

    It 'should preserve chords that contain additional action keys' {
        $profile = Read-TestJson $script:profilePath
        $profile.remapShortcuts.global += @{ originalKeys = '260;65;13'; newRemapKeys = '17;88' }
        Write-TestJson $script:profilePath $profile
        & $script:adapterPath -BindingJson $script:binding -PowerToysDirectory $script:directory
        $profile = Read-TestJson $script:profilePath
        ($profile.remapShortcuts.global | Where-Object originalKeys -EQ '260;65;13').newRemapKeys | Should -Be '17;88'
    }

    It 'should replace left and right modifier aliases for the selected shared trigger' -ForEach @(
        @{ Modifier = 'ctrl'; Left = '162;13'; Right = '163;13'; Expected = '17;13' },
        @{ Modifier = 'alt'; Left = '164;13'; Right = '165;13'; Expected = '18;13' },
        @{ Modifier = 'shift'; Left = '160;13'; Right = '161;13'; Expected = '16;13' }
    ) {
        $profile = Read-TestJson $script:profilePath
        $profile.remapShortcuts.global += @(@{ originalKeys = $Left; newRemapKeys = '17;65' }, @{ originalKeys = $Right; newRemapKeys = '17;66' })
        Write-TestJson $script:profilePath $profile
        $selectedBinding = '{"action":"terminal","key":"enter","modifiers":["' + $Modifier + '"]}'
        & $script:adapterPath -BindingJson $selectedBinding -PowerToysDirectory $script:directory
        $profile = Read-TestJson $script:profilePath
        @($profile.remapShortcuts.global).Count | Should -Be 2
        @($profile.remapShortcuts.global | Where-Object originalKeys -EQ $Expected).Count | Should -Be 1
    }

    It 'should keep an existing trigger position stable on repeated applies' {
        $profile = Read-TestJson $script:profilePath
        $profile.remapShortcuts.global = @(@{ originalKeys = '91;13'; newRemapKeys = '18;13' }) + $profile.remapShortcuts.global
        Write-TestJson $script:profilePath $profile
        & $script:adapterPath -BindingJson $script:binding -PowerToysDirectory $script:directory
        $snapshot = Get-TestSnapshot $script:directory
        & $script:adapterPath -BindingJson $script:binding -PowerToysDirectory $script:directory
        (Get-TestSnapshot $script:directory) | Should -BeExactly $snapshot
    }

    It 'should avoid duplicates and file rewrites on a second apply' {
        & $script:adapterPath -BindingJson $script:binding -PowerToysDirectory $script:directory
        $snapshot = Get-TestSnapshot $script:directory
        $fixedTime = [datetime]::SpecifyKind([datetime]'2020-01-01', [DateTimeKind]::Utc)
        Get-ChildItem $script:directory -File -Recurse | ForEach-Object { $_.LastWriteTimeUtc = $fixedTime }
        $times = @(Get-ChildItem $script:directory -File -Recurse | Sort-Object FullName | ForEach-Object { $_.LastWriteTimeUtc.Ticks }) -join ','
        & $script:adapterPath -BindingJson $script:binding -PowerToysDirectory $script:directory
        (Get-TestSnapshot $script:directory) | Should -BeExactly $snapshot
        (@(Get-ChildItem $script:directory -File -Recurse | Sort-Object FullName | ForEach-Object { $_.LastWriteTimeUtc.Ticks }) -join ',') | Should -BeExactly $times
    }

    It 'should remove the prior owned binding when the shared chord changes' {
        & $script:adapterPath -BindingJson $script:binding -PowerToysDirectory $script:directory
        & $script:adapterPath -BindingJson '{"action":"terminal","key":"enter","modifiers":["ctrl","shift","alt"]}' -PowerToysDirectory $script:directory
        $profile = Read-TestJson $script:profilePath
        @($profile.remapShortcuts.global | Where-Object originalKeys -EQ '260;13').Count | Should -Be 0
        @($profile.remapShortcuts.global | Where-Object originalKeys -EQ '17;18;16;13').Count | Should -Be 1
        $profile.remapShortcuts.global[0].newRemapKeys | Should -Be '17;86'
    }

    It 'should preserve a user edit to the previously owned mapping' {
        & $script:adapterPath -BindingJson $script:binding -PowerToysDirectory $script:directory
        $profile = Read-TestJson $script:profilePath
        ($profile.remapShortcuts.global | Where-Object originalKeys -EQ '260;13').runProgramArgs = 'user change'
        Write-TestJson $script:profilePath $profile
        & $script:adapterPath -BindingJson '{"action":"terminal","key":"enter","modifiers":["alt"]}' -PowerToysDirectory $script:directory
        $profile = Read-TestJson $script:profilePath
        ($profile.remapShortcuts.global | Where-Object originalKeys -EQ '260;13').runProgramArgs | Should -Be 'user change'
        @($profile.remapShortcuts.global | Where-Object originalKeys -EQ '18;13').Count | Should -Be 1
    }

    It 'should remove the prior owned mapping after the editor changes property order only' {
        & $script:adapterPath -BindingJson $script:binding -PowerToysDirectory $script:directory
        $profile = Read-TestJson $script:profilePath
        # MappingConfiguration::SaveSettingsToFile writes these properties in
        # this order, which differs from the adapter's initial serialization.
        $nativeOrder = [pscustomobject][ordered]@{
            originalKeys = '260;13'; exactMatch = $true
            runProgramElevationLevel = 0; operationType = 1
            runProgramAlreadyRunningAction = 1; runProgramStartWindowType = 1
            runProgramFilePath = '%SystemRoot%\System32\wsl.exe'
            runProgramArgs     = '--distribution NixOS --cd ~ --exec bash -lc ghostty'
            runProgramStartInDir = ''; unicodeText = '*Unsupported*'
        }
        $profile.remapShortcuts.global = @($profile.remapShortcuts.global | Where-Object originalKeys -NE '260;13') + @($nativeOrder)
        Write-TestJson $script:profilePath $profile
        & $script:adapterPath -BindingJson '{"action":"terminal","key":"enter","modifiers":["alt"]}' -PowerToysDirectory $script:directory
        $profile = Read-TestJson $script:profilePath
        @($profile.remapShortcuts.global).Count | Should -Be 2
        @($profile.remapShortcuts.global | Where-Object originalKeys -EQ '260;13').Count | Should -Be 0
        @($profile.remapShortcuts.global | Where-Object originalKeys -EQ '18;13').Count | Should -Be 1
    }

    It 'should preserve a scalar type change in the previously owned mapping' {
        & $script:adapterPath -BindingJson $script:binding -PowerToysDirectory $script:directory
        $profile = Read-TestJson $script:profilePath
        ($profile.remapShortcuts.global | Where-Object originalKeys -EQ '260;13').runProgramStartWindowType = '1'
        Write-TestJson $script:profilePath $profile
        & $script:adapterPath -BindingJson '{"action":"terminal","key":"enter","modifiers":["alt"]}' -PowerToysDirectory $script:directory
        $profile = Read-TestJson $script:profilePath
        ($profile.remapShortcuts.global | Where-Object originalKeys -EQ '260;13').runProgramStartWindowType | Should -BeOfType [string]
    }

    It 'should reject malformed or unsupported bindings before writing any file' -ForEach @(
        @{ Value = '{' },
        @{ Value = '[{"action":"terminal","key":"enter","modifiers":["super"]}]' },
        @{ Value = '{"action":"terminal","key":"enter","modifiers":[]}' },
        @{ Value = '{"action":"terminal","key":"enter","modifiers":"super"}' },
        @{ Value = '{"action":"terminal","key":"enter","modifiers":["super","super"]}' },
        @{ Value = '{"action":"terminal","key":"enter","modifiers":["hyper"]}' },
        @{ Value = '{"action":"terminal","key":"escape","modifiers":["super"]}' },
        @{ Value = '{"action":"other","key":"enter","modifiers":["super"]}' }
    ) {
        $snapshot = Get-TestSnapshot $script:directory
        { & $script:adapterPath -BindingJson $Value -PowerToysDirectory $script:directory } | Should -Throw
        (Get-TestSnapshot $script:directory) | Should -BeExactly $snapshot
    }

    It 'should reject malformed JSON in any existing input before writing any file' -ForEach @(
        @{ File = 'settings.json' }, @{ File = 'Keyboard Manager/settings.json' }, @{ File = 'Keyboard Manager/personal.json' }, @{ File = 'Keyboard Manager/editorSettings.json' }, @{ File = 'dotfiles-terminal-binding.json' }
    ) {
        [IO.File]::WriteAllText((Join-Path $script:directory $File), '{')
        $snapshot = Get-TestSnapshot $script:directory
        { & $script:adapterPath -BindingJson $script:binding -PowerToysDirectory $script:directory } | Should -Throw
        (Get-TestSnapshot $script:directory) | Should -BeExactly $snapshot
    }

    It 'should reject active profile names that escape the module directory' {
        Write-TestJson $script:modulePath @{ properties = @{ activeConfiguration = @{ value = '../outside' } } }
        $snapshot = Get-TestSnapshot $script:directory
        { & $script:adapterPath -BindingJson $script:binding -PowerToysDirectory $script:directory } | Should -Throw
        (Get-TestSnapshot $script:directory) | Should -BeExactly $snapshot
    }

    It 'should reject a top-level array or malformed profile section before writing' -ForEach @(
        @{ Json = '[{}]' }, @{ Json = '{"remapShortcuts":"invalid"}' }
    ) {
        [IO.File]::WriteAllText($script:profilePath, $Json)
        $snapshot = Get-TestSnapshot $script:directory
        { & $script:adapterPath -BindingJson $script:binding -PowerToysDirectory $script:directory } | Should -Throw
        (Get-TestSnapshot $script:directory) | Should -BeExactly $snapshot
    }

    It 'should sync existing editor metadata without replacing unrelated entries or profiles' {
        $editorPath = Join-Path $script:keyboardDirectory 'editorSettings.json'
        Write-TestJson $editorPath @{ ShortcutSettingsDictionary = @{ existing = @{ Id = 'existing'; Shortcut = @{ OriginalKeys = '91;13'; TargetApp = ''; OperationType = 0; TargetKeys = '18;13' }; Profiles = @('work'); IsActive = $false }; unrelated = @{ Id = 'unrelated'; Shortcut = @{ OriginalKeys = '17;67'; TargetApp = ''; OperationType = 0; TargetKeys = '17;86' }; Profiles = @(); IsActive = $true } }; ProfileDictionary = @{ work = @('existing') }; ShortcutsByOperationType = @{ RemapShortcut = @('existing', 'unrelated') }; ActiveProfile = 'work'; Custom = 'keep' }
        & $script:adapterPath -BindingJson $script:binding -PowerToysDirectory $script:directory
        $editor = Read-TestJson $editorPath
        $entry = $editor.ShortcutSettingsDictionary.existing
        $entry.Shortcut.OriginalKeys | Should -Be '260;13'
        $entry.Shortcut.OperationType | Should -Be 1
        $entry.Shortcut.TargetKeys | Should -Be '260;13'
        $entry.Shortcut.ProgramArgs | Should -Be '--distribution NixOS --cd ~ --exec bash -lc ghostty'
        $entry.Shortcut.Visibility | Should -Be 1
        $entry.Shortcut.IfRunningAction | Should -Be 1
        $entry.IsActive | Should -BeTrue
        $entry.Profiles | Should -Contain 'work'
        $editor.ShortcutsByOperationType.RunProgram | Should -Contain 'existing'
        $editor.ShortcutsByOperationType.RemapShortcut | Should -Not -Contain 'existing'
        $editor.ShortcutSettingsDictionary.unrelated.Shortcut.TargetKeys | Should -Be '17;86'
        $editor.ProfileDictionary.work | Should -Contain 'existing'
        $editor.ActiveProfile | Should -Be 'work'
        $editor.Custom | Should -Be 'keep'
    }

    It 'should create valid defaults when PowerToys has no saved configuration' {
        $empty = Join-Path $TestDrive 'first-use'
        & $script:adapterPath -BindingJson $script:binding -PowerToysDirectory $empty
        (Read-TestJson (Join-Path $empty 'Keyboard Manager/settings.json')).properties.activeConfiguration.value | Should -Be 'default'
        $profile = Read-TestJson (Join-Path $empty 'Keyboard Manager/default.json')
        @($profile.remapShortcuts.global).Count | Should -Be 1
        @($profile.remapShortcuts.appSpecific).Count | Should -Be 0
        @($profile.remapKeys.inProcess).Count | Should -Be 0
    }

    It 'should preserve user changes to old editor flags when the shared chord changes' {
        $editorPath = Join-Path $script:keyboardDirectory 'editorSettings.json'
        Write-TestJson $editorPath @{ ShortcutSettingsDictionary = @{}; ProfileDictionary = @{}; ShortcutsByOperationType = @{}; ActiveProfile = '' }
        & $script:adapterPath -BindingJson $script:binding -PowerToysDirectory $script:directory
        $editor = Read-TestJson $editorPath
        $oldId = @($editor.ShortcutSettingsDictionary.PSObject.Properties)[0].Name
        $editor.ShortcutSettingsDictionary.$oldId.Shortcut.Visibility = 2
        Write-TestJson $editorPath $editor
        & $script:adapterPath -BindingJson '{"action":"terminal","key":"enter","modifiers":["alt"]}' -PowerToysDirectory $script:directory
        $editor = Read-TestJson $editorPath
        $editor.ShortcutSettingsDictionary.$oldId.Shortcut.Visibility | Should -Be 2
        @($editor.ShortcutSettingsDictionary.PSObject.Properties).Count | Should -Be 2
    }

    It 'should remove prior editor ownership after property reordering without a value change' {
        $editorPath = Join-Path $script:keyboardDirectory 'editorSettings.json'
        Write-TestJson $editorPath @{ ShortcutSettingsDictionary = @{}; ProfileDictionary = @{}; ShortcutsByOperationType = @{}; ActiveProfile = '' }
        & $script:adapterPath -BindingJson $script:binding -PowerToysDirectory $script:directory
        $editor = Read-TestJson $editorPath
        $oldId = @($editor.ShortcutSettingsDictionary.PSObject.Properties)[0].Name
        $shortcut = $editor.ShortcutSettingsDictionary.$oldId.Shortcut
        $reordered = [ordered]@{}
        foreach ($name in @($shortcut.PSObject.Properties.Name | Sort-Object -Descending)) { $reordered[$name] = $shortcut.$name }
        $editor.ShortcutSettingsDictionary.$oldId.Shortcut = [pscustomobject]$reordered
        Write-TestJson $editorPath $editor
        & $script:adapterPath -BindingJson '{"action":"terminal","key":"enter","modifiers":["alt"]}' -PowerToysDirectory $script:directory
        $editor = Read-TestJson $editorPath
        @($editor.ShortcutSettingsDictionary.PSObject.Properties).Count | Should -Be 1
        $editor.ShortcutSettingsDictionary.PSObject.Properties.Name | Should -Not -Contain $oldId
    }

    It 'should compare ownership objects without changing array order or scalar types' {
        . $script:adapterPath -BindingJson $script:binding -PowerToysDirectory $script:directory
        $first = '{"flags":[1,2],"nested":{"a":true,"b":null}}' | ConvertFrom-Json
        $reordered = '{"nested":{"b":null,"a":true},"flags":[1,2]}' | ConvertFrom-Json
        $changedArray = '{"flags":[2,1],"nested":{"a":true,"b":null}}' | ConvertFrom-Json
        $changedType = '{"flags":[1,2],"nested":{"a":"true","b":null}}' | ConvertFrom-Json
        (Test-JsonEqual $first $reordered) | Should -BeTrue
        (Test-JsonEqual $first $changedArray) | Should -BeFalse
        (Test-JsonEqual $first $changedType) | Should -BeFalse
    }

    Context 'opt-in runtime updates' {
        BeforeEach {
            . $script:adapterPath -BindingJson $script:binding -PowerToysDirectory $script:directory
            $script:operations = New-Object 'Collections.Generic.List[string]'
            $script:runnerPath = Join-Path $env:LOCALAPPDATA 'PowerToys/PowerToys.exe'
            $script:processStopped = $false
            $script:runner = [pscustomobject]@{ Id = 4242 }
            $script:runner | Add-Member -MemberType ScriptProperty -Name Path -Value { if ($script:processStopped) { throw 'Path unavailable after process exit' }; $script:runnerPath }
            $script:runner | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($Timeout) $true }
            Mock Get-Process { @($script:runner, [pscustomobject]@{ Id = 9999; Path = 'C:\unrelated\PowerToys.exe' }) }
            Mock Stop-Process {
                param($Id)
                $script:operations.Add("stop:$Id")
                $script:processStopped = $true
                $script:stoppedBeforeWrite = -not (Read-TestJson $script:rootPath).enabled.'Keyboard Manager'
            }
            Mock Start-Process {
                param($FilePath, $WindowStyle)
                $script:operations.Add("start:$FilePath")
                $script:restartWindowStyle = $WindowStyle
            }
        }

        It 'should stop only the matching runner before enabling and restart it hidden' {
            Invoke-PowerToysKeyboardSync -BindingJson $script:binding -PowerToysDirectory $script:directory -RestartPowerToys
            $script:operations.Count | Should -Be 2
            $script:operations[0] | Should -Be 'stop:4242'
            $script:operations[1] | Should -Be ('start:' + $script:runnerPath)
            $script:stoppedBeforeWrite | Should -BeTrue
            $script:restartWindowStyle | Should -Be 'Hidden'
            (Read-TestJson $script:rootPath).enabled.'Keyboard Manager' | Should -BeTrue
        }

        It 'should restart a stopped runner even when a file write fails' {
            Mock Move-Item { throw 'simulated write failure' }
            { Invoke-PowerToysKeyboardSync -BindingJson $script:binding -PowerToysDirectory $script:directory -RestartPowerToys } | Should -Throw '*simulated write failure*'
            $script:operations.Count | Should -Be 2
            $script:operations[0] | Should -Be 'stop:4242'
            $script:operations[1] | Should -Be ('start:' + $script:runnerPath)
        }

        It 'should notify an enabled engine without restarting the runner' {
            $root = Read-TestJson $script:rootPath
            $root.enabled.'Keyboard Manager' = $true
            Write-TestJson $script:rootPath $root
            $script:notifications = 0
            Mock Send-KeyboardSettingsEvent { $script:notifications++ }
            Invoke-PowerToysKeyboardSync -BindingJson $script:binding -PowerToysDirectory $script:directory -RestartPowerToys
            $script:operations.Count | Should -Be 0
            $script:notifications | Should -Be 1
            Invoke-PowerToysKeyboardSync -BindingJson $script:binding -PowerToysDirectory $script:directory -RestartPowerToys
            $script:notifications | Should -Be 1
        }
    }
}
