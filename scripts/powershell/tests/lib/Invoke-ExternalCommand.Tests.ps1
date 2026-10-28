#Requires -Module Pester

BeforeAll {
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    $script:psExe = (Get-Process -Id $PID).Path
}

Describe 'Invoke-NativeCommand' {
    It 'should not throw when a native command writes stderr and exits 0' {
        $result = Invoke-NativeCommand -Command $script:psExe -Arguments @(
            "-NoLogo",
            "-NoProfile",
            "-Command",
            "[Console]::Error.WriteLine('stderr version output'); exit 0"
        )

        $result | Should -Contain "stderr version output"
        $global:LASTEXITCODE | Should -Be 0
    }

    It 'should preserve non-zero exit code without throwing on stderr' {
        $result = Invoke-NativeCommand -Command $script:psExe -Arguments @(
            "-NoLogo",
            "-NoProfile",
            "-Command",
            "[Console]::Error.WriteLine('stderr warning output'); exit 23"
        )

        $result | Should -Contain "stderr warning output"
        $global:LASTEXITCODE | Should -Be 23
    }
}

Describe 'Import-WindowsPackage' {
    BeforeEach {
        $script:originalInstallTimeout = $env:DOTFILES_INSTALL_TIMEOUT_SECONDS
        Remove-Item Env:\DOTFILES_INSTALL_TIMEOUT_SECONDS -ErrorAction SilentlyContinue
        $script:manifestPath = Join-Path $TestDrive 'master with spaces.json'
        Set-Content -LiteralPath $script:manifestPath -Value '{"Sources":[]}'
        $script:nativeExitCode = 0
        $script:nativeArguments = @()
        $script:logs = [Collections.Generic.List[string]]::new()
        Mock Get-Content { throw 'Pass the standard manifest directly to WinGet' }
        Mock Invoke-ExternalCommandWithTimeout {
            param($Command, $Arguments, $TimeoutSeconds)
            $script:nativeArguments = @($Arguments)
            $global:LASTEXITCODE = $script:nativeExitCode
            return 'native import output'
        }
        Mock Update-ProcessEnvironmentPath { $script:logs.Add('PATH_REFRESHED') }
        Mock Write-Host { param($Object) $script:logs.Add([string]$Object) }
    }

    AfterEach {
        if ($null -eq $script:originalInstallTimeout) {
            Remove-Item Env:\DOTFILES_INSTALL_TIMEOUT_SECONDS -ErrorAction SilentlyContinue
        }
        else {
            $env:DOTFILES_INSTALL_TIMEOUT_SECONDS = $script:originalInstallTimeout
        }
    }

    It 'should import the unchanged master once and refresh the process PATH before logging completion' {
        Import-WindowsPackage -ManifestPath $script:manifestPath

        $script:nativeArguments | Should -Be @(
            'import', '--import-file', $script:manifestPath, '--ignore-versions',
            '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
        )
        Should -Invoke Invoke-ExternalCommandWithTimeout -Times 1 -Exactly -ParameterFilter { $Command -eq 'winget' -and $TimeoutSeconds -eq 3600 }
        Should -Invoke Get-Content -Times 0
        Should -Invoke Update-ProcessEnvironmentPath -Times 1
        $script:logs | Should -Contain '[Winget] native import output'
        $script:logs[-2] | Should -Be 'PATH_REFRESHED'
        $script:logs[-1] | Should -Be '[Winget] WINGET_IMPORT_COMPLETED'
    }

    It 'should stop immediately on native exit <ExitCode> without refreshing PATH or claiming completion' -ForEach @(
        @{ ExitCode = 1 }, @{ ExitCode = 124 }, @{ ExitCode = 127 }
    ) {
        $script:nativeExitCode = $ExitCode

        { Import-WindowsPackage -ManifestPath $script:manifestPath } | Should -Throw "*WinGet import failed (exit=$ExitCode)*"
        Should -Invoke Invoke-ExternalCommandWithTimeout -Times 1 -Exactly
        Should -Invoke Update-ProcessEnvironmentPath -Times 0
        ($script:logs -join "`n") | Should -Not -Match 'WINGET_IMPORT_COMPLETED'
    }

}

Describe 'Get-PackageInstallTimeoutSecond' {
    BeforeEach { $script:originalInstallTimeout = $env:DOTFILES_INSTALL_TIMEOUT_SECONDS }
    AfterEach { $env:DOTFILES_INSTALL_TIMEOUT_SECONDS = $script:originalInstallTimeout }

    It 'should use timeout <Expected> for override <Override>' -ForEach @(
        @{ Override = $null; Expected = 3600 }
        @{ Override = 'invalid'; Expected = 3600 }
        @{ Override = '-1'; Expected = 3600 }
        @{ Override = '0'; Expected = 0 }
        @{ Override = '73'; Expected = 73 }
    ) {
        $env:DOTFILES_INSTALL_TIMEOUT_SECONDS = $Override
        Get-PackageInstallTimeoutSecond | Should -Be $Expected
    }
}

Describe 'Invoke-ExternalCommandWithTimeout' {
    It 'should return output when a native command exits before timeout' {
        $result = Invoke-ExternalCommandWithTimeout -Command $script:psExe -Arguments @(
            "-NoLogo",
            "-NoProfile",
            "-Command",
            "Write-Output 'verify ok'; exit 0"
        ) -TimeoutSeconds 5

        $result | Should -Contain "verify ok"
        $global:LASTEXITCODE | Should -Be 0
    }

    It 'should stop a native command when timeout expires and retain partial output' {
        $result = Invoke-ExternalCommandWithTimeout -Command $script:psExe -Arguments @(
            "-NoLogo",
            "-NoProfile",
            "-Command",
            "Write-Output 'partial output'; Start-Sleep -Seconds 5; exit 0"
        ) -TimeoutSeconds 2

        ($result -join "`n") | Should -Match "タイムアウト"
        $result | Should -Contain 'partial output'
        $global:LASTEXITCODE | Should -Be 124
    }

    It 'should preserve a script path containing spaces when the caller explicitly selects a PowerShell executable' {
        $binDir = Join-Path $TestDrive 'script with spaces'
        $shimPath = Join-Path $binDir "gcloud.ps1"
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
        Set-Content -LiteralPath $shimPath -Value @'
Write-Output "shim ok: $($args -join ',')"
exit 0
'@
        $result = Invoke-ExternalCommandWithTimeout -Command $script:psExe -Arguments @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $shimPath, 'value with spaces', 'C:\path with spaces\'
        ) -TimeoutSeconds 5

        $result | Should -Contain 'shim ok: value with spaces,C:\path with spaces\'
        $global:LASTEXITCODE | Should -Be 0
    }

    It 'should report a missing timed native command without throwing a ProcessStart exception' {
        $missingCommand = Join-Path $TestDrive 'does-not-exist.exe'

        $result = Invoke-ExternalCommandWithTimeout -Command $missingCommand -Arguments @('--version') -TimeoutSeconds 1

        $result | Should -Match 'コマンドが見つかりません'
        $global:LASTEXITCODE | Should -Be 127
    }

    It 'should wait for normal completion when the timeout is explicitly disabled' {
        $result = Invoke-ExternalCommandWithTimeout -Command $script:psExe -Arguments @(
            '-NoProfile', '-Command', "Start-Sleep -Milliseconds 100; Write-Output 'completed'; exit 7"
        ) -TimeoutSeconds 0

        $result | Should -Contain 'completed'
        $global:LASTEXITCODE | Should -Be 7
    }
}

Describe 'Invoke-Wsl' {
    BeforeEach { $script:originalWslUtf8 = $env:WSL_UTF8 }
    AfterEach { $env:WSL_UTF8 = $script:originalWslUtf8 }

    It 'should pass multiple arguments' {
        Mock Invoke-ExternalCommandWithTimeout { return "OK" }

        Invoke-Wsl -Arguments @('-d', 'NixOS', '-u', 'root', '--', 'sh', '-lc', 'whoami')

        Should -Invoke Invoke-ExternalCommandWithTimeout -Times 1 -Exactly -ParameterFilter {
            $Command -eq 'wsl' -and ($Arguments -join '|') -eq '-d|NixOS|-u|root|--|sh|-lc|whoami' -and $TimeoutSeconds -eq 0
        }
    }

    It 'should run WSL through timeout wrapper when TimeoutSeconds is specified' {
        Mock Invoke-ExternalCommandWithTimeout {
            $global:LASTEXITCODE = 124
            return "timeout"
        }

        $result = Invoke-Wsl -TimeoutSeconds 1 -Arguments @("--status")

        $result | Should -Contain "timeout"
        $global:LASTEXITCODE | Should -Be 124
        Should -Invoke Invoke-ExternalCommandWithTimeout -Times 1 -ParameterFilter {
            $Command -eq "wsl" -and
            $Arguments -contains "--status" -and
            $TimeoutSeconds -eq 1
        }
    }

    It 'should preserve UTF-8 Linux output and restore the inherited WSL encoding after success or failure' {
        $env:WSL_UTF8 = 'parent-value'
        $script:unicodeOutput = '/mnt/d/' + [char]0x65E5 + [char]0x672C + [char]0x8A9E + '/.dotfiles'
        $script:unicodeOutputBytes = [Text.Encoding]::UTF8.GetBytes($script:unicodeOutput)
        $script:childWslUtf8 = $null
        Mock Invoke-ExternalCommandWithTimeout {
            param($OutputEncoding)
            $script:childWslUtf8 = $env:WSL_UTF8
            $global:LASTEXITCODE = 23
            return $OutputEncoding.GetString($script:unicodeOutputBytes)
        }

        Invoke-Wsl -TimeoutSeconds 5 -Arguments @('-d', 'NixOS', '--exec', 'wslpath', '-a', 'D:/checkout') | Should -BeExactly $script:unicodeOutput
        $global:LASTEXITCODE | Should -Be 23
        $script:childWslUtf8 | Should -BeExactly '1'
        $env:WSL_UTF8 | Should -BeExactly 'parent-value'

        Mock Invoke-ExternalCommandWithTimeout { throw 'fixture failure' }
        { Invoke-Wsl -Arguments @('--list', '--quiet') } | Should -Throw '*fixture failure*'
        $env:WSL_UTF8 | Should -BeExactly 'parent-value'
    }
}

Describe 'Update-ProcessEnvironmentPath' {
    BeforeEach {
        $script:originalPath = $env:PATH

    }

    AfterEach {
        $env:PATH = $script:originalPath
    }

    It 'should include User PATH entries in the current process PATH' {
        $uniqueUserPath = Join-Path $TestDrive "TestUserPath-$([guid]::NewGuid())"
        $null = New-Item -ItemType Directory -Path $uniqueUserPath -Force
        Mock Get-UserEnvironmentPath { return $uniqueUserPath }

        $existingPath = Join-Path $TestDrive 'ExistingPath'
        $null = New-Item -ItemType Directory -Path $existingPath -Force
        $env:PATH = $existingPath

        Update-ProcessEnvironmentPath

        ($env:PATH -split ";") | Should -Contain $uniqueUserPath
        ($env:PATH -split ";") | Should -Contain $existingPath
    }

    It 'should expand valid environment-variable PATH entries before checking and importing them' {
        $variablePath = Join-Path $TestDrive "VariablePath-$([guid]::NewGuid())"
        $null = New-Item -ItemType Directory -Path $variablePath -Force
        $env:DOTFILES_CI_EXPANDED_PATH = $variablePath
        Mock Get-UserEnvironmentPath { return '%DOTFILES_CI_EXPANDED_PATH%' }
        $env:PATH = $script:originalPath

        try {
            Update-ProcessEnvironmentPath
            ($env:PATH -split ';') | Should -Contain $variablePath
        }
        finally {
            Remove-Item Env:\DOTFILES_CI_EXPANDED_PATH -ErrorAction SilentlyContinue
        }
    }

    It 'should remove duplicate entries case-insensitively' {
        $uniquePath = Join-Path $TestDrive "DuplicatePath-$([guid]::NewGuid())"
        $null = New-Item -ItemType Directory -Path $uniquePath -Force
        Mock Get-UserEnvironmentPath { return $uniquePath }

        $env:PATH = "$uniquePath;$($uniquePath.ToUpperInvariant())"

        Update-ProcessEnvironmentPath

        @($env:PATH -split ";" | Where-Object { $_ -eq $uniquePath -or $_ -eq $uniquePath.ToUpperInvariant() }).Count | Should -Be 1
    }



    It 'should discard oversized stale inherited and User PATH entries while preserving native commands' {
        if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
            Set-ItResult -Skipped -Because 'Windows directory filtering and the cmd.exe environment limit are Windows-specific'
            return
        }

        $validUserPath = Join-Path $TestDrive 'valid-command-directory'
        $null = New-Item -ItemType Directory -Path $validUserPath -Force
        $staleEntries = 1..1000 | ForEach-Object { "C:\$([string]::new('S', 80))$_" }
        $oversizedUserPath = (@($staleEntries) + @($validUserPath)) -join ';'
        $oversizedUserPath.Length | Should -BeGreaterThan 50000
        Mock Get-UserEnvironmentPath { return $oversizedUserPath }

        $env:PATH = (@($script:originalPath -split ';') + @($staleEntries | Select-Object -First 120)) -join ';'
        $env:PATH.Length | Should -BeGreaterThan 8191
        $env:PATH.Length | Should -BeLessThan 32767

        Update-ProcessEnvironmentPath

        $paths = $env:PATH -split ';'
        $env:PATH.Length | Should -BeLessOrEqual 8191
        $paths | Should -Contain $validUserPath
        @($paths | Where-Object { $staleEntries -contains $_ }).Count | Should -Be 0
        $paths | Should -Contain (Split-Path -Parent (Get-Command cmd.exe).Source)
        $commandInterpreter = Join-Path $env:SystemRoot 'System32\cmd.exe'
        & $commandInterpreter /d /c 'exit 0'
        $LASTEXITCODE | Should -Be 0
    }
}

Describe 'Test-WslAvailable' {
    BeforeEach { Mock Get-CimInstance { [pscustomobject]@{ InstallState = 1 } } }

    It 'should reject Virtual Machine Platform state <InstallState> before checking WSL status' -ForEach @(
        @{ InstallState = 2 }
        @{ InstallState = 3 }
    ) {
        $script:featureInstallState = $InstallState
        Mock Get-CimInstance { [pscustomobject]@{ InstallState = $script:featureInstallState } }
        Mock Invoke-Wsl { $global:LASTEXITCODE = 0 }

        Test-WslAvailable | Should -BeFalse
        Should -Invoke Invoke-Wsl -Times 0
        Should -Invoke Get-CimInstance -Times 1 -ParameterFilter {
            $ClassName -eq 'Win32_OptionalFeature' -and $Filter -eq "Name = 'VirtualMachinePlatform'"
        }
    }

    It 'should fall back to WSL status when the optional feature query is unavailable' {
        Mock Get-CimInstance { throw 'CIM unavailable' }
        Mock Invoke-Wsl { $global:LASTEXITCODE = 0 }

        Test-WslAvailable | Should -BeTrue
    }

    It 'should return true when wsl --status succeeds' {
        Mock Invoke-Wsl { $global:LASTEXITCODE = 0 }

        $result = Test-WslAvailable

        $result | Should -Be $true
        Should -Invoke Invoke-Wsl -Times 1 -ParameterFilter {
            "$Arguments" -match '--status'
        }
    }

    It 'should return false for WSL status exit <ExitCode>' -ForEach @(
        @{ ExitCode = 1 }
        @{ ExitCode = 124 }
    ) {
        $script:statusExitCode = $ExitCode
        Mock Invoke-Wsl { $global:LASTEXITCODE = $script:statusExitCode }

        Test-WslAvailable | Should -BeFalse
        Should -Invoke Invoke-Wsl -Times 1 -ParameterFilter {
            $TimeoutSeconds -eq 5 -and $Arguments -contains "--status"
        }
    }

    It 'should return false when Invoke-Wsl throws an exception' {
        Mock Invoke-Wsl { throw "wsl: WSL component not installed" }

        $result = Test-WslAvailable

        $result | Should -Be $false
    }
}

Describe 'Windows setup with missing command directories in PATH' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    BeforeEach {
        $script:originalPath = $env:PATH
        $script:originalLocalAppData = $env:LOCALAPPDATA
        $env:PATH = "$PSHOME;$env:SystemRoot\System32"
        $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $env:LOCALAPPDATA = Join-Path $caseRoot 'local'
        New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force | Out-Null
    }

    AfterEach {
        $env:PATH = $script:originalPath
        $env:LOCALAPPDATA = $script:originalLocalAppData
    }

    It 'should restore the existing WindowsApps directory without duplicating or replacing PATH entries' {
        $windowsApps = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
        New-Item -ItemType Directory -Path $windowsApps -Force | Out-Null
        $before = $env:PATH

        Update-ProcessEnvironmentPath
        Update-ProcessEnvironmentPath

        @($env:PATH -split ';' | Where-Object { $_ -eq $windowsApps }).Count | Should -Be 1
        foreach ($entry in $before -split ';' ) { ($env:PATH -split ';') | Should -Contain $entry }
    }

}
