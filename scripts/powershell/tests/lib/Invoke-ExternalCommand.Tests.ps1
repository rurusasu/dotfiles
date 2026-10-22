#Requires -Module Pester

<#
.SYNOPSIS
    Invoke-ExternalCommand.ps1 のユニットテスト

.DESCRIPTION
    外部コマンドラッパー関数のテスト
    100% カバレッジを目標とする
#>

BeforeAll {
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
}

Describe 'Invoke-Chezmoi' {
    # ExePath を使ったテスト（chezmoi 本体のモックはスコープ競合するため回避）
    BeforeAll {
        # 固定出力を持つ偽 chezmoi スクリプトを作成
        $script:fakeScript = Join-Path $env:TEMP "fake_chezmoi_$(Get-Random).ps1"
        Set-Content $script:fakeScript -Value "Write-Host 'progress line 1'; Write-Host 'progress line 2'"
        # pwsh (PowerShell 7) がなければ powershell.exe にフォールバック
        $script:psExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell.exe" }
    }

    AfterAll {
        Remove-Item $script:fakeScript -ErrorAction SilentlyContinue
    }

    It 'should write each output line to host when MergeStderr is set' {
        $script:written = @()
        Mock Write-Host { param($Object) $script:written += $Object }

        Invoke-Chezmoi -ExePath $script:psExe -MergeStderr "-NoProfile" "-NonInteractive" "-File" $script:fakeScript

        $script:written | Should -Contain "progress line 1"
        $script:written | Should -Contain "progress line 2"
    }

    It 'should return output via pipeline when MergeStderr is not set' {
        Mock Write-Host { }

        $result = Invoke-Chezmoi -ExePath $script:psExe "-NoProfile" "-NonInteractive" "-File" $script:fakeScript

        Should -Invoke Write-Host -Times 0
        $result | Should -Contain "progress line 1"
    }
}

Describe 'Invoke-NativeCommand' {
    BeforeAll {
        $script:psExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell.exe" }
    }

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

$script:isWindowsRuntime = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT

Describe 'Invoke-Winget' {
    BeforeEach {
        $script:originalInstallTimeout = $env:DOTFILES_INSTALL_TIMEOUT_SECONDS
        $script:originalWingetTimeout = $env:DOTFILES_WINGET_COMMAND_TIMEOUT_SECONDS
    }

    AfterEach {
        if ($null -eq $script:originalInstallTimeout) {
            Remove-Item Env:\DOTFILES_INSTALL_TIMEOUT_SECONDS -ErrorAction SilentlyContinue
        }
        else {
            $env:DOTFILES_INSTALL_TIMEOUT_SECONDS = $script:originalInstallTimeout
        }
        if ($null -eq $script:originalWingetTimeout) {
            Remove-Item Env:\DOTFILES_WINGET_COMMAND_TIMEOUT_SECONDS -ErrorAction SilentlyContinue
        }
        else {
            $env:DOTFILES_WINGET_COMMAND_TIMEOUT_SECONDS = $script:originalWingetTimeout
        }
    }

    It 'should run winget through the shared 3600-second timeout wrapper by default' {
        Remove-Item Env:\DOTFILES_INSTALL_TIMEOUT_SECONDS -ErrorAction SilentlyContinue
        Remove-Item Env:\DOTFILES_WINGET_COMMAND_TIMEOUT_SECONDS -ErrorAction SilentlyContinue
        Mock Invoke-ExternalCommandWithTimeout {
            $global:LASTEXITCODE = 0
            return "winget ok"
        }

        $result = Invoke-Winget -Arguments @("install", "--id", "example.package")

        $result | Should -Contain "winget ok"
        Should -Invoke Invoke-ExternalCommandWithTimeout -Times 1 -ParameterFilter {
            $Command -eq "winget" -and
            $Arguments -contains "example.package" -and
            $TimeoutSeconds -eq 3600
        }
    }

    It 'should ignore negative install overrides while preserving explicit zero' -TestCases @(
        @{ Shared = '-1'; Legacy = $null; Expected = 3600 }
        @{ Shared = '-1'; Legacy = '73'; Expected = 73 }
        @{ Shared = $null; Legacy = '-1'; Expected = 3600 }
        @{ Shared = '0'; Legacy = '73'; Expected = 0 }
    ) {
        param($Shared, $Legacy, $Expected)
        $env:DOTFILES_INSTALL_TIMEOUT_SECONDS = $Shared
        $env:DOTFILES_WINGET_COMMAND_TIMEOUT_SECONDS = $Legacy
        Get-PackageInstallTimeoutSecond -LegacyEnvironmentVariable 'DOTFILES_WINGET_COMMAND_TIMEOUT_SECONDS' | Should -Be $Expected
    }

    It 'should allow disabling the winget timeout for tests or debugging' {
        $env:DOTFILES_WINGET_COMMAND_TIMEOUT_SECONDS = "0"
        Mock Invoke-ExternalCommandWithTimeout { throw "timeout wrapper should be disabled" }
        Mock Invoke-NativeCommand {
            $global:LASTEXITCODE = 0
            return "native winget ok"
        }

        $result = Invoke-Winget -Arguments @("--version")

        $result | Should -Contain "native winget ok"
        Should -Invoke Invoke-ExternalCommandWithTimeout -Times 0
        Should -Invoke Invoke-NativeCommand -Times 1 -ParameterFilter {
            $Command -eq "winget" -and $Arguments -contains "--version"
        }
    }

    It 'should prefer an explicit timeout over the default environment timeout' {
        Remove-Item Env:\DOTFILES_INSTALL_TIMEOUT_SECONDS -ErrorAction SilentlyContinue
        $env:DOTFILES_WINGET_COMMAND_TIMEOUT_SECONDS = "180"
        Mock Invoke-ExternalCommandWithTimeout {
            $global:LASTEXITCODE = 0
            return "winget ok"
        }

        $result = Invoke-Winget -Arguments @("install", "--id", "Google.CloudSDK") -TimeoutSeconds 900

        $result | Should -Contain "winget ok"
        Should -Invoke Invoke-ExternalCommandWithTimeout -Times 1 -ParameterFilter {
            $Command -eq "winget" -and
            $Arguments -contains "Google.CloudSDK" -and
            $TimeoutSeconds -eq 900
        }
    }
}

Describe 'Invoke-VerifyCommand' {
    BeforeAll {
        $script:psExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell.exe" }
    }

    It 'should return output when verify command exits before timeout' {
        $result = Invoke-VerifyCommand -Command $script:psExe -Arguments @(
            "-NoLogo",
            "-NoProfile",
            "-Command",
            "Write-Output 'verify ok'; exit 0"
        ) -TimeoutSeconds 5

        $result | Should -Contain "verify ok"
        $global:LASTEXITCODE | Should -Be 0
    }

    It 'should stop verify command when timeout expires' {
        $result = Invoke-VerifyCommand -Command $script:psExe -Arguments @(
            "-NoLogo",
            "-NoProfile",
            "-Command",
            "Write-Output 'partial output'; Start-Sleep -Seconds 5; exit 0"
        ) -TimeoutSeconds 2

        ($result -join "`n") | Should -Match "タイムアウト"
        $result | Should -Contain 'partial output'
        $global:LASTEXITCODE | Should -Be 124
    }

    It 'should run a ps1 shim from a path containing spaces without splitting the file path' {
        $tempRoot = Join-Path $env:TEMP "verify shim $(Get-Random)"
        $binDir = Join-Path $tempRoot "Google Cloud SDK\bin"
        $shimPath = Join-Path $binDir "gcloud.ps1"
        $oldPath = $env:PATH
        try {
            New-Item -ItemType Directory -Path $binDir -Force | Out-Null
            Set-Content -LiteralPath $shimPath -Value @'
Write-Output "shim ok: $($args -join ',')"
exit 0
'@
            $env:PATH = "$binDir;$env:PATH"

            $result = Invoke-VerifyCommand -Command "gcloud" -Arguments @("version") -TimeoutSeconds 5

            $result | Should -Contain "shim ok: version"
            $global:LASTEXITCODE | Should -Be 0
        }
        finally {
            $env:PATH = $oldPath
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'should report a missing timed verification command without throwing a ProcessStart exception' {
        $missingCommand = Join-Path $TestDrive 'does-not-exist.exe'

        $result = Invoke-VerifyCommand -Command $missingCommand -Arguments @('--version') -TimeoutSeconds 1

        $result | Should -Match 'コマンドが見つかりません'
        $global:LASTEXITCODE | Should -Be 127
    }
}

Describe 'Invoke-Wsl' {
    It 'should pass arguments to WSL' {
        Mock wsl { return "test output" }

        Invoke-Wsl --list --quiet

        Should -Invoke wsl -Times 1
    }

    It 'should allow calling without arguments' {
        Mock wsl { return "" }

        Invoke-Wsl

        Should -Invoke wsl -Times 1
    }

    It 'should pass multiple arguments' {
        Mock wsl { return "OK" }

        Invoke-Wsl -d NixOS -u root -- sh -lc "whoami"

        Should -Invoke wsl -Times 1
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
            $TimeoutSeconds -eq 1 -and
            $null -ne $OutputEncoding
        }
    }
}

Describe 'Invoke-Dism' {
    It 'should pass arguments to dism.exe' {
        Mock dism.exe { return "test output" }

        Invoke-Dism /online /get-features

        Should -Invoke dism.exe -Times 1
    }

    It 'should pass multiple arguments' {
        Mock dism.exe { return "The operation completed successfully." }

        Invoke-Dism /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart

        Should -Invoke dism.exe -Times 1
    }

    It 'should run dism.exe through timeout wrapper when TimeoutSeconds is specified' {
        Mock Invoke-ExternalCommandWithTimeout {
            $global:LASTEXITCODE = 3010
            return "The operation completed successfully."
        }

        $result = Invoke-Dism -TimeoutSeconds 300 /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart

        $result | Should -Contain "The operation completed successfully."
        $global:LASTEXITCODE | Should -Be 3010
        Should -Invoke Invoke-ExternalCommandWithTimeout -Times 1 -ParameterFilter {
            $Command -eq "dism.exe" -and
            $Arguments -contains "/online" -and
            $Arguments -contains "/enable-feature" -and
            $Arguments -contains "/featurename:VirtualMachinePlatform" -and
            $TimeoutSeconds -eq 300 -and
            $null -ne $OutputEncoding
        }
    }
}

Describe 'Get-ExternalCommand' {
    It 'should return command info when command <exists>' -ForEach @(
        @{ exists = "exists"; name = "powershell"; mockReturn = [PSCustomObject]@{ Name = "powershell"; Source = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" }; expectedNull = $false }
        @{ exists = "does not exist"; name = "nonexistent"; mockReturn = $null; expectedNull = $true }
    ) {
        Mock Get-Command { return $mockReturn }

        $result = Get-ExternalCommand -Name $name

        if ($expectedNull) {
            $result | Should -BeNullOrEmpty
        }
        else {
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be $name
        }
    }
}

Describe 'Get-ExternalCommandPath' {
    It 'should resolve Path-only command metadata in strict mode' {
        Set-StrictMode -Version Latest
        try {
            Get-ExternalCommandPath -CommandInfo ([pscustomobject]@{ Path = 'C:\tools\npm.cmd' }) |
                Should -Be 'C:\tools\npm.cmd'
        }
        finally {
            Set-StrictMode -Off
        }
    }
}

Describe 'Test-PathExist' {
    It 'should return <expected> when path <exists>' -ForEach @(
        @{ exists = "exists"; expected = $true }
        @{ exists = "does not exist"; expected = $false }
    ) {
        Mock Test-Path { return $expected }

        $result = Test-PathExist -Path "C:\SomePath"

        $result | Should -Be $expected
    }
}

Describe 'Get-JsonContent' {
    It 'should parse JSON file and return object' {
        Mock Get-Content { return '{"key": "value"}' }

        $result = Get-JsonContent -Path "C:\test.json"

        $result.key | Should -Be "value"
    }

    It 'should parse JSON with arrays' {
        Mock Get-Content { return '{"items": [1, 2, 3]}' }

        $result = Get-JsonContent -Path "C:\test.json"

        $result.items | Should -HaveCount 3
    }
}

Describe 'New-DirectorySafe' {
    It 'should create directory with -Force option' {
        Mock New-Item { return [PSCustomObject]@{ FullName = "C:\newdir" } }

        New-DirectorySafe -Path "C:\newdir"

        Should -Invoke New-Item -Times 1 -ParameterFilter {
            $ItemType -eq "Directory" -and
            $Path -eq "C:\newdir" -and
            $Force -eq $true
        }
    }
}

Describe 'Get-ChildItemSafe' {
    It 'should get files in directory' {
        Mock Get-ChildItem {
            return @(
                [PSCustomObject]@{ Name = "file1.txt" },
                [PSCustomObject]@{ Name = "file2.txt" }
            )
        }

        $result = Get-ChildItemSafe -Path "C:\test"

        $result | Should -HaveCount 2
    }

    It 'should apply Filter option' {
        Mock Get-ChildItem { return @([PSCustomObject]@{ Name = "file.ps1" }) }

        Get-ChildItemSafe -Path "C:\test" -Filter "*.ps1"

        Should -Invoke Get-ChildItem -Times 1 -ParameterFilter {
            $Filter -eq "*.ps1"
        }
    }

    It 'should apply Recurse option' {
        Mock Get-ChildItem { return @() }

        Get-ChildItemSafe -Path "C:\test" -Recurse

        Should -Invoke Get-ChildItem -Times 1 -ParameterFilter {
            $Recurse -eq $true
        }
    }

    It 'should apply Directory option' {
        Mock Get-ChildItem { return @() }

        Get-ChildItemSafe -Path "C:\test" -Directory

        Should -Invoke Get-ChildItem -Times 1 -ParameterFilter {
            $Directory -eq $true
        }
    }
}

Describe 'Invoke-WebRequestSafe' {
    It 'should download file with UseBasicParsing' {
        Mock Invoke-WebRequest { }

        Invoke-WebRequestSafe -Uri "https://example.com/file.zip" -OutFile "C:\temp\file.zip"

        Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
            $Uri -eq "https://example.com/file.zip" -and
            $OutFile -eq "C:\temp\file.zip" -and
            $UseBasicParsing -eq $true
        }
    }
}

Describe 'Invoke-RestMethodSafe' {
    It 'should call REST API and return result' {
        Mock Invoke-RestMethod {
            return [PSCustomObject]@{ result = "success" }
        }

        $result = Invoke-RestMethodSafe -Uri "https://api.example.com/data"

        $result.result | Should -Be "success"
    }

    It 'should pass headers when specified' {
        Mock Invoke-RestMethod { return @{} }

        Invoke-RestMethodSafe -Uri "https://api.example.com" -Headers @{ "Authorization" = "Bearer token" }

        Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter {
            $Headers["Authorization"] -eq "Bearer token"
        }
    }
}

Describe 'Start-SleepSafe' {
    It 'should sleep for specified seconds' {
        Mock Start-Sleep { }

        Start-SleepSafe -Seconds 5

        Should -Invoke Start-Sleep -Times 1 -ParameterFilter {
            $Seconds -eq 5
        }
    }
}

Describe 'Update-ProcessEnvironmentPath' {
    BeforeEach {
        $script:originalPath = $env:PATH
        Mock Set-UserEnvironmentPath {
            throw 'PATH normalization tests must explicitly mock persisted User PATH writes.'
        }
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

    It 'should exclude selected paths while importing updated User PATH entries' {
        $excludedPath = Join-Path $TestDrive "RunnerPnpm-$([guid]::NewGuid())"
        $newUserPath = Join-Path $TestDrive "NewUserPath-$([guid]::NewGuid())"
        $null = New-Item -ItemType Directory -Path $excludedPath, $newUserPath -Force
        $userPath = "$newUserPath;$excludedPath"
        Mock Get-UserEnvironmentPath { return $userPath }
        $existingPath = Join-Path $TestDrive 'ExistingPath'
        $null = New-Item -ItemType Directory -Path $existingPath -Force
        $env:PATH = "$existingPath;$excludedPath"

        Update-ProcessEnvironmentPath -ExcludePath @($excludedPath)

        ($env:PATH -split ';') | Should -Contain $existingPath
        ($env:PATH -split ';') | Should -Contain $newUserPath
        ($env:PATH -split ';') | Should -Not -Contain $excludedPath
    }

    It 'should discard missing PATH directories before they crowd valid command paths out of the child environment' {
        if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
            Set-ItResult -Skipped -Because 'missing directory filtering is Windows-specific'
            return
        }

        $validUserPath = Join-Path $TestDrive 'valid-command-directory'
        $null = New-Item -ItemType Directory -Path $validUserPath -Force
        $staleEntries = 1..500 | ForEach-Object { "C:\dotfiles-ci-stale-path-entry-$_" }
        Mock Get-UserEnvironmentPath { return (@($staleEntries) + @($validUserPath)) -join ';' }
        Mock Set-UserEnvironmentPath { }
        $env:PATH = (@($script:originalPath -split ';') + @($staleEntries)) -join ';'

        Update-ProcessEnvironmentPath

        $env:PATH.Length | Should -BeLessOrEqual 8191
        ($env:PATH -split ';') | Should -Contain $validUserPath
        foreach ($entry in $staleEntries) {
            ($env:PATH -split ';') | Should -Not -Contain $entry
        }
    }

    It 'should refresh only the process without changing a stale oversized persisted User PATH' {
        $validUserPath = Join-Path $TestDrive 'gui-only-command-directory'
        $null = New-Item -ItemType Directory -Path $validUserPath -Force
        $staleEntries = 1..1000 | ForEach-Object { "C:\dotfiles-ci-stale-path-entry-$_" }
        $oversizedUserPath = (@($staleEntries) + @($validUserPath)) -join ';'
        $oversizedUserPath.Length | Should -BeGreaterThan 32767
        Mock Get-UserEnvironmentPath { return $oversizedUserPath }
        Mock Set-UserEnvironmentPath { throw 'GUI setup must not rewrite persisted PATH' }
        $env:PATH = $script:originalPath

        Update-ProcessEnvironmentPath -ProcessOnly

        $env:PATH.Length | Should -BeLessOrEqual 8191
        ($env:PATH -split ';') | Should -Contain $validUserPath
        Should -Invoke Set-UserEnvironmentPath -Times 0 -Exactly
    }

    It 'should persistently remove stale local directories while retaining unresolved and offline User PATH entries' {
        if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
            Set-ItResult -Skipped -Because 'User PATH registry repair is Windows-specific'
            return
        }

        $validUserPath = Join-Path $TestDrive 'valid-persistent-user-path'
        $null = New-Item -ItemType Directory -Path $validUserPath -Force
        $staleUserPath = Join-Path $env:TEMP "dotfiles-stale-user-path-$([guid]::NewGuid())"
        $offlineUserPath = '\\dotfiles-ci-unavailable\share\bin'
        $unresolvedUserPath = '%DOTFILES_CI_UNRESOLVED_PATH%\bin'
        $script:persistedUserPath = $null
        Mock Get-UserEnvironmentPath { return "$staleUserPath;$validUserPath;$offlineUserPath;$unresolvedUserPath" }
        Mock Set-UserEnvironmentPath {
            param([string]$Path)
            $script:persistedUserPath = $Path
        }
        $env:PATH = $script:originalPath

        Update-ProcessEnvironmentPath -ReportStatus

        $script:persistedUserPath -split ';' | Should -Contain $validUserPath
        $script:persistedUserPath -split ';' | Should -Contain $offlineUserPath
        $script:persistedUserPath -split ';' | Should -Contain $unresolvedUserPath
        $script:persistedUserPath -split ';' | Should -Not -Contain $staleUserPath
        ($env:PATH -split ';') | Should -Contain $validUserPath
    }

    It 'should keep the refreshed PATH below the Windows command environment limit' {
        if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
            Set-ItResult -Skipped -Because 'the cmd.exe environment limit is Windows-specific'
            return
        }

        $oversizedUserPath = (1..600 | ForEach-Object { "C:\$([string]::new('U', 80))$_" }) -join ';'
        Mock Get-UserEnvironmentPath { return $oversizedUserPath }
        Mock Set-UserEnvironmentPath { }
        $env:PATH = "$script:originalPath;" + ((1..120 | ForEach-Object { "C:\$([string]::new('P', 80))$_" }) -join ';')
        $oversizedUserPath.Length | Should -BeGreaterThan 50000

        Update-ProcessEnvironmentPath

        $env:PATH.Length | Should -BeLessOrEqual 8191
        ($env:PATH -split ';') | Should -Contain (Split-Path -Parent (Get-Command cmd.exe).Source)
        $commandInterpreter = Join-Path $env:SystemRoot 'System32\cmd.exe'
        & $commandInterpreter /d /c 'exit 0'
        $LASTEXITCODE | Should -Be 0
    }
}

Describe 'Test-WslAvailable' {
    BeforeEach { Mock Get-CimInstance { [pscustomobject]@{ InstallState = 1 } } }

    It 'should reject a disabled Virtual Machine Platform even when WSL status exits zero' {
        Mock Get-CimInstance { [pscustomobject]@{ InstallState = 2 } }
        Mock Invoke-Wsl { $global:LASTEXITCODE = 0 }

        Test-WslAvailable | Should -BeFalse
        Should -Invoke Invoke-Wsl -Times 0
        Should -Invoke Get-CimInstance -Times 1 -ParameterFilter {
            $ClassName -eq 'Win32_OptionalFeature' -and $Filter -eq "Name = 'VirtualMachinePlatform'"
        }
    }

    It 'should reject an absent Virtual Machine Platform' {
        Mock Get-CimInstance { [pscustomobject]@{ InstallState = 3 } }
        Mock Invoke-Wsl { $global:LASTEXITCODE = 0 }

        Test-WslAvailable | Should -BeFalse
        Should -Invoke Invoke-Wsl -Times 0
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

    It 'should return false when wsl --status fails' {
        Mock Invoke-Wsl { $global:LASTEXITCODE = 1 }

        $result = Test-WslAvailable

        $result | Should -Be $false
    }

    It 'should return false when Invoke-Wsl throws an exception' {
        Mock Invoke-Wsl { throw "wsl: WSL component not installed" }

        $result = Test-WslAvailable

        $result | Should -Be $false
    }

    It 'should return false when WSL status check times out' {
        Mock Get-WslCheckTimeoutSecond { return 1 }
        Mock Invoke-Wsl {
            $global:LASTEXITCODE = 124
            return "timeout"
        }

        $result = Test-WslAvailable

        $result | Should -Be $false
        Should -Invoke Invoke-Wsl -Times 1 -ParameterFilter {
            $TimeoutSeconds -eq 1 -and $Arguments -contains "--status"
        }
    }
}
