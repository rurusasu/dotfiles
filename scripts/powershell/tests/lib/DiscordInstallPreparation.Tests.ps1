BeforeAll {
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
}

Describe 'Discord process termination runtime' {
    It 'should terminate and confirm exit of a real process before returning' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        $originalLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = Join-Path $TestDrive 'RuntimeLocalAppData'
        $nativeProcess = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe') -ArgumentList @('-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 60') -WindowStyle Hidden -PassThru
        try {
            # Substitute only discovery metadata. Stop-Process and the native
            # Process.WaitForExit remain real; no user applications are touched.
            $script:discordNativeFixture = [pscustomobject]@{
                Id            = $nativeProcess.Id
                ProcessName   = 'Discord'
                Path          = Join-Path $env:LOCALAPPDATA 'Discord/app-fixture/Discord.exe'
                NativeProcess = $nativeProcess
            }
            $script:discordNativeFixture | Add-Member -MemberType ScriptProperty -Name HasExited -Value { $this.NativeProcess.HasExited }
            $script:discordNativeFixture | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value {
                param($Timeout)
                return $this.NativeProcess.WaitForExit($Timeout)
            }
            Mock Get-Process { @($script:discordNativeFixture) }

            Invoke-DiscordInstallPreparation

            $nativeProcess.HasExited | Should -BeTrue
        }
        finally {
            if (-not $nativeProcess.HasExited) { Stop-Process -Id $nativeProcess.Id -Force }
            $nativeProcess.Dispose()
            $env:LOCALAPPDATA = $originalLocalAppData
        }
    }
}

Describe 'Invoke-DiscordInstallPreparation' {
    BeforeEach {
        $script:originalDiscordLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = Join-Path $TestDrive 'LocalAppData'
        $script:processEvents = [System.Collections.Generic.List[string]]::new()
        $script:discordProcess = [pscustomobject]@{
            Id            = 101
            ProcessName   = 'Discord'
            Path          = Join-Path $env:LOCALAPPDATA 'Discord/app-1.0.9259/Discord.exe'
            HasExited     = $false
            ExitConfirmed = $true
            Events        = $script:processEvents
        }
        $script:discordProcess | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value {
            param($Timeout)
            $this.Events.Add("wait:$($this.Id):$Timeout")
            return $this.ExitConfirmed
        }
        Mock Get-Process { @($script:discordProcess) }
        Mock Stop-Process {
            param($Id, $Force)
            if (-not $Force) { throw 'Discord must be force-stopped' }
            $script:processEvents.Add("stop:$Id")
        }
    }

    AfterEach {
        $env:LOCALAPPDATA = $script:originalDiscordLocalAppData
    }

    It 'should force-stop Discord and wait for its exit before returning' {
        Invoke-DiscordInstallPreparation

        @($script:processEvents) | Should -Be @('stop:101', 'wait:101:10000')
    }

    It 'should stop only Discord and its updater inside the current user installation directory' {
        $script:discordUpdater = $script:discordProcess.PSObject.Copy()
        $script:discordUpdater.Id = 102
        $script:discordUpdater.ProcessName = 'Update'
        $script:discordUpdater.Path = Join-Path $env:LOCALAPPDATA 'Discord/Update.exe'
        Mock Get-Process {
            @(
                $script:discordProcess
                $script:discordUpdater
                [pscustomobject]@{ Id = 201; ProcessName = 'Update'; Path = Join-Path $env:LOCALAPPDATA 'OtherApp/Update.exe' }
                [pscustomobject]@{ Id = 202; ProcessName = 'Discord'; Path = Join-Path $env:LOCALAPPDATA 'DiscordCanary/Discord.exe' }
                [pscustomobject]@{ Id = 203; ProcessName = 'Discord'; Path = 'C:\Users\AnotherUser\AppData\Local\Discord\Discord.exe' }
                [pscustomobject]@{ Id = 204; ProcessName = 'Discord'; Path = $null }
                [pscustomobject]@{ Id = 205; ProcessName = 'OtherTool'; Path = Join-Path $env:LOCALAPPDATA 'Discord/OtherTool.exe' }
            )
        }

        Invoke-DiscordInstallPreparation

        @($script:processEvents) | Should -Be @('stop:101', 'wait:101:10000', 'stop:102', 'wait:102:10000')
    }

    It 'should succeed without stopping anything when Discord is not running' {
        Mock Get-Process { @() }

        { Invoke-DiscordInstallPreparation } | Should -Not -Throw
        $script:processEvents.Count | Should -Be 0
    }

    It 'should propagate access denied instead of launching an installer with locked files' {
        Mock Stop-Process { throw 'Access denied' }

        { Invoke-DiscordInstallPreparation } | Should -Throw '*Access denied*'
    }

    It 'should tolerate a process that exits between discovery and termination' {
        $script:discordProcess.HasExited = $true
        Mock Stop-Process { throw 'Process already exited' }

        { Invoke-DiscordInstallPreparation } | Should -Not -Throw
    }

    It 'should fail when process termination is not confirmed within the timeout' {
        $script:discordProcess.ExitConfirmed = $false

        { Invoke-DiscordInstallPreparation } | Should -Throw '*101*'
    }

    It 'should fail before inspecting processes when the current user installation root is unavailable' {
        $env:LOCALAPPDATA = $null
        Mock Get-Process { throw 'must not inspect processes without an installation root' }

        { Invoke-DiscordInstallPreparation } | Should -Throw '*LOCALAPPDATA*'
    }
}
