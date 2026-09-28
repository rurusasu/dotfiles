BeforeAll {
    $repo = Resolve-Path (Join-Path $PSScriptRoot '../../../..')
    . (Join-Path $repo 'nix/hosts/windows/start-glazewm.ps1')
    . (Join-Path $repo 'nix/home/keybindings/windows-actions.ps1')
}

Describe 'Omarchy GlazeWM managed startup' {
    BeforeEach {
        $script:configPath = Join-Path $TestDrive 'home with spaces/config.json'
        New-Item -ItemType Directory -Path (Split-Path $script:configPath) -Force | Out-Null
        '{"workspaces":[{"name":"1"}],"keybindings":[{"bindings":["lwin+enter"],"commands":["close"]}]}' | Set-Content -LiteralPath $script:configPath
        $script:exe = Join-Path $TestDrive 'Program Files/glazewm.exe'
        New-Item -ItemType Directory -Path (Split-Path $script:exe) -Force | Out-Null
        New-Item -ItemType File -Path $script:exe -Force | Out-Null
        $script:launches = @()
        $script:commands = @()
        $script:startupScripts = @()
        Mock Get-OmarchyGlazeWMProcess { @() }
        Mock Test-OmarchyGlazeWMInteractiveSession { $true }
        Mock Set-OmarchyGlazeWMStartup { param($StartupScript) $script:startupScripts += $StartupScript }
        Mock Invoke-OmarchyGlazeWM { param($Arguments) $script:commands += , $Arguments; '{"success":true,"data":{"version":"3.9.1"}}' }
        Mock Start-Process { param($FilePath, $ArgumentList) $script:launches += @{ Path = $FilePath; Arguments = $ArgumentList }; [pscustomobject]@{ HasExited = $false } }
    }

    It 'should start with the exact quoted config path and verify IPC readiness' {
        Start-OmarchyGlazeWM -Executable $script:exe -ConfigPath $script:configPath -StartupScript $PSCommandPath | Should -Be 'Started'
        $script:launches.Count | Should -Be 1
        $script:launches[0].Arguments | Should -Be ('start --config="{0}"' -f $script:configPath)
        ($script:commands[0] -join ' ') | Should -Be 'query app-metadata'
    }

    It 'should reload only the instance using the managed config and executable' {
        Mock Get-OmarchyGlazeWMProcess { , ([pscustomobject]@{ ExecutablePath = $script:exe; CommandLine = ('"{0}" start --config="{1}"' -f $script:exe, $script:configPath) }) }
        Start-OmarchyGlazeWM -Executable $script:exe -ConfigPath $script:configPath -StartupScript $PSCommandPath | Should -Be 'Reloaded'
        $script:launches.Count | Should -Be 0
        ($script:commands[0] -join ' ') | Should -Be 'command wm-reload-config'
    }

    It 'should refuse a different user config without stopping or reloading that instance' {
        Mock Get-OmarchyGlazeWMProcess { , ([pscustomobject]@{ ExecutablePath = $script:exe; CommandLine = 'glazewm.exe start --config="C:\other\config.yaml"' }) }
        { Start-OmarchyGlazeWM -Executable $script:exe -ConfigPath $script:configPath -StartupScript $PSCommandPath } | Should -Throw '*different config*'
        $script:launches.Count | Should -Be 0
        $script:commands.Count | Should -Be 0
    }

    It 'should reject prefix matches and unmanaged defaults when identifying the owned process' {
        Test-OmarchyGlazeWMOwnership -Process ([pscustomobject]@{ ExecutablePath = $script:exe; CommandLine = ('glazewm start --config="{0}.other"' -f $script:configPath) }) -Executable $script:exe -ConfigPath $script:configPath | Should -BeFalse
        Test-OmarchyGlazeWMOwnership -Process ([pscustomobject]@{ ExecutablePath = $script:exe; CommandLine = 'glazewm start' }) -Executable $script:exe -ConfigPath $script:configPath | Should -BeFalse
    }

    It 'should fail clearly when the executable is missing' {
        { Start-OmarchyGlazeWM -Executable (Join-Path $TestDrive 'missing.exe') -ConfigPath $script:configPath -StartupScript $PSCommandPath } | Should -Throw '*not found*'
        $script:launches.Count | Should -Be 0
    }

    It 'should defer a missing pre-admin package and start normally after installation' {
        Mock Resolve-OmarchyGlazeWMExecutable { param($AllowMissing) if (-not $AllowMissing) { throw 'GlazeWM executable was not found.' } }
        Initialize-OmarchyGlazeWM -ConfigPath $script:configPath -StartupScript $PSCommandPath -DeferMissing | Should -Be 'Deferred until GlazeWM installation and interactive login'
        $script:startupScripts | Should -Be @($PSCommandPath)
        $script:launches.Count | Should -Be 0
        $script:commands.Count | Should -Be 0
        Mock Resolve-OmarchyGlazeWMExecutable { $script:exe }
        Initialize-OmarchyGlazeWM -ConfigPath $script:configPath -StartupScript $PSCommandPath | Should -Be 'Started'
        $script:launches.Count | Should -Be 1
    }

    It 'should keep missing packages fatal outside the explicit bootstrap defer path' {
        Mock Resolve-OmarchyGlazeWMExecutable { param($AllowMissing) if (-not $AllowMissing) { throw 'GlazeWM executable was not found.' } }
        { Initialize-OmarchyGlazeWM -ConfigPath $script:configPath -StartupScript $PSCommandPath } | Should -Throw '*not found*'
        $script:startupScripts.Count | Should -Be 0
    }

    It 'should reject invalid config even while the package installation is deferred' {
        Mock Resolve-OmarchyGlazeWMExecutable { $null }
        '{"keybindings":[]}' | Set-Content -LiteralPath $script:configPath
        { Initialize-OmarchyGlazeWM -ConfigPath $script:configPath -StartupScript $PSCommandPath -DeferMissing } | Should -Throw '*workspaces*'
        $script:startupScripts.Count | Should -Be 0
    }

    It 'should deploy startup and defer window management outside an interactive desktop' {
        Mock Test-OmarchyGlazeWMInteractiveSession { $false }
        Start-OmarchyGlazeWM -Executable $script:exe -ConfigPath $script:configPath -StartupScript $PSCommandPath | Should -Be 'Deferred until interactive login'
        $script:launches.Count | Should -Be 0
        $script:commands.Count | Should -Be 0
    }

    It 'should surface reload rejection rather than treating it as success' {
        Mock Get-OmarchyGlazeWMProcess { , ([pscustomobject]@{ ExecutablePath = $script:exe; CommandLine = ('glazewm start --config="{0}"' -f $script:configPath) }) }
        Mock Invoke-OmarchyGlazeWM { '{"success":false,"error":"Invalid command"}' }
        { Start-OmarchyGlazeWM -Executable $script:exe -ConfigPath $script:configPath -StartupScript $PSCommandPath } | Should -Throw '*Invalid command*'
    }

    It 'should reject malformed deployment config before creating startup state' {
        '{"keybindings":[]}' | Set-Content -LiteralPath $script:configPath
        { Test-OmarchyGlazeWMConfig -ConfigPath $script:configPath } | Should -Throw '*workspaces*'
    }
}

Describe 'Omarchy Windows action dispatch' {
    It 'should compile the native shortcut and workstation lock API without performing desktop actions' {
        Initialize-OmarchyNativeType
        ('Dotfiles.OmarchyNativeKeys' -as [type]).GetMethod('LockWorkStation') | Should -Not -BeNullOrEmpty
        ('Dotfiles.OmarchyNativeKeys' -as [type]).GetMethod('Send') | Should -Not -BeNullOrEmpty
        Get-Command Invoke-OmarchyLockWorkstation | Should -Not -BeNullOrEmpty
    }

    BeforeEach {
        $script:opened = @()
        $script:sent = @()
        Mock Invoke-OmarchyOpen { param($Target, $Arguments) $script:opened += @{ Target = $Target; Arguments = $Arguments } }
        Mock Send-OmarchyWindowsShortcut { param($Key) $script:sent += $Key }
    }

    It 'should open native utility URIs without changing registry policies' {
        Invoke-OmarchyWindowsAction -Action 'audio'
        Invoke-OmarchyWindowsAction -Action 'capture'
        $script:opened[0].Target | Should -Be 'ms-settings:sound'
        $script:opened[1].Target | Should -Be 'ms-screenclip:'
    }

    It 'should launch a machine-installed Obsidian when it is absent from PATH and user install locations' {
        $previousProgramFiles = $env:ProgramFiles
        $previousLocalAppData = $env:LOCALAPPDATA
        try {
            $env:ProgramFiles = Join-Path $TestDrive 'Program Files'
            $env:LOCALAPPDATA = Join-Path $TestDrive 'Local App Data'
            $app = Join-Path $env:ProgramFiles 'Obsidian/Obsidian.exe'
            New-Item -ItemType Directory -Path (Split-Path $app) -Force | Out-Null
            New-Item -ItemType File -Path $app -Force | Out-Null
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Obsidian.exe' }
            Invoke-OmarchyWindowsAction -Action 'notes'
            $script:opened.Count | Should -Be 1
            $script:opened[0].Target | Should -Be $app
        }
        finally {
            $env:ProgramFiles = $previousProgramFiles
            $env:LOCALAPPDATA = $previousLocalAppData
        }
    }

    It 'should request Windows clipboard and emoji panels through their native shortcuts' {
        Invoke-OmarchyWindowsAction -Action 'clipboard'
        Invoke-OmarchyWindowsAction -Action 'emoji'
        $script:sent | Should -Be @('V', 'OEM_PERIOD')
    }

    It 'should fail for an unknown action rather than silently dropping it' {
        { Invoke-OmarchyWindowsAction -Action 'unknown' } | Should -Throw
    }
}
