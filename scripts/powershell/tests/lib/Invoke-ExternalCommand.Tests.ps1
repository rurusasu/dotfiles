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

Describe 'Invoke-Winget' {
    BeforeEach {
        $script:originalWingetTimeout = $env:DOTFILES_WINGET_COMMAND_TIMEOUT_SECONDS
    }

    AfterEach {
        $env:DOTFILES_WINGET_COMMAND_TIMEOUT_SECONDS = $script:originalWingetTimeout
    }

    It 'should run winget through a timeout wrapper by default' {
        Remove-Item Env:\DOTFILES_WINGET_COMMAND_TIMEOUT_SECONDS -ErrorAction SilentlyContinue
        Mock Invoke-ExternalCommandWithTimeout {
            $global:LASTEXITCODE = 0
            return "winget ok"
        }

        $result = Invoke-Winget -Arguments @("--version")

        $result | Should -Contain "winget ok"
        Should -Invoke Invoke-ExternalCommandWithTimeout -Times 1 -ParameterFilter {
            $Command -eq "winget" -and
            $Arguments -contains "--version" -and
            $TimeoutSeconds -eq 300
        }
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
            "Start-Sleep -Seconds 5; exit 0"
        ) -TimeoutSeconds 1

        $result | Should -Match "タイムアウト"
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
}

Describe 'Invoke-OpCommand' {
    It 'should run op vault list through timeout wrapper' {
        Mock Invoke-ExternalCommandWithTimeout {
            $global:LASTEXITCODE = 124
            return "timeout"
        }
        Mock Get-OpCommandTimeoutSecond { return 3 }

        $result = Invoke-OpVaultList -OpExe "C:\op.exe" -Account "my.1password.com"

        $result.ExitCode | Should -Be 124
        $result.Output | Should -Contain "timeout"
        Should -Invoke Invoke-ExternalCommandWithTimeout -Times 1 -ParameterFilter {
            $Command -eq "C:\op.exe" -and
            $Arguments -contains "vault" -and
            $Arguments -contains "list" -and
            $Arguments -contains "--account" -and
            $Arguments -contains "my.1password.com" -and
            $TimeoutSeconds -eq 3
        }
    }

    It 'should use a separate timeout for op signin' {
        Mock Invoke-ExternalCommandWithTimeout {
            $global:LASTEXITCODE = 124
            return "timeout"
        }
        Mock Get-OpSignInTimeoutSecond { return 7 }

        $result = Invoke-OpSignIn -OpExe "C:\op.exe" -Account "my.1password.com"

        $result.ExitCode | Should -Be 124
        Should -Invoke Invoke-ExternalCommandWithTimeout -Times 1 -ParameterFilter {
            $Command -eq "C:\op.exe" -and
            $Arguments -contains "signin" -and
            $TimeoutSeconds -eq 7
        }
    }
}

Describe 'Invoke-Wsl' {
    It 'should pass arguments to WSL' {
        Mock wsl { return "test output" }

        $result = Invoke-Wsl --list --quiet

        Should -Invoke wsl -Times 1
    }

    It 'should allow calling without arguments' {
        Mock wsl { return "" }

        Invoke-Wsl

        Should -Invoke wsl -Times 1
    }

    It 'should pass multiple arguments' {
        Mock wsl { param($args) return "OK" }

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

        $result = Invoke-Dism /online /get-features

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

Describe 'Invoke-Diskpart' {
    BeforeAll {
        $script:tempDir = Join-Path $env:TEMP "diskpart_test_$(Get-Random)"
        New-Item -ItemType Directory -Path $script:tempDir -Force | Out-Null
        $script:tempFile = Join-Path $script:tempDir "script.tmp"
    }

    AfterAll {
        Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $script:diskpartInternalCalled = $false
        $script:setContentCalled = $false

        # diskpart.exe が実際に起動しないようにするための安全網
        Mock Start-Process { return [PSCustomObject]@{ ExitCode = 0 } }
        Mock Invoke-DiskpartInternal {
            $script:diskpartInternalCalled = $true
            return @{
                Output   = "diskpart output"
                ExitCode = 0
            }
        }
        Mock Set-ContentNoNewline {
            $script:setContentCalled = $true
        }
        Mock Remove-Item { }
        Mock New-TemporaryFile {
            return [PSCustomObject]@{ FullName = $script:tempFile }
        }
    }

    It 'should create script file and execute diskpart via internal function' {
        Invoke-Diskpart -ScriptContent "list disk"

        $script:diskpartInternalCalled | Should -Be $true
    }

    It 'should write script content to temp file' {
        Invoke-Diskpart -ScriptContent "select disk 0"

        $script:setContentCalled | Should -Be $true
    }

    It 'should throw when diskpart fails' {
        Mock Invoke-DiskpartInternal {
            return @{
                Output   = "Error: Access denied"
                ExitCode = 1
            }
        }

        { Invoke-Diskpart -ScriptContent "list disk" } | Should -Throw "*diskpart failed*"
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

Describe 'Get-ProcessSafe' {
    It 'should return process info when process <exists>' -ForEach @(
        @{ exists = "exists"; name = "pwsh"; mockReturn = [PSCustomObject]@{ Name = "pwsh"; Id = 1234 }; expectedNull = $false }
        @{ exists = "does not exist"; name = "NonExistentProcess"; mockReturn = $null; expectedNull = $true }
    ) {
        Mock Get-Process { return $mockReturn }

        $result = Get-ProcessSafe -Name $name

        if ($expectedNull) {
            $result | Should -BeNullOrEmpty
        }
        else {
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be $name
        }
    }
}

Describe 'Stop-ProcessSafe' {
    It 'should stop process by name' {
        Mock Stop-Process { }

        Stop-ProcessSafe -Name "TestProcess"

        Should -Invoke Stop-Process -Times 1 -ParameterFilter {
            $Name -eq "TestProcess"
        }
    }

    It 'should not throw when process does not exist' {
        Mock Stop-Process { }

        { Stop-ProcessSafe -Name "NonExistent" } | Should -Not -Throw
    }
}

Describe 'Start-ProcessSafe' {
    It 'should start process with file path' {
        Mock Start-Process { return [PSCustomObject]@{ Id = 5678 } }

        Start-ProcessSafe -FilePath "C:\test\app.exe"

        Should -Invoke Start-Process -Times 1 -ParameterFilter {
            $FilePath -eq "C:\test\app.exe"
        }
    }
}

Describe 'Copy-FileSafe' {
    It 'should copy file from source to destination' {
        Mock Copy-Item { }

        Copy-FileSafe -Source "C:\source.txt" -Destination "C:\dest.txt"

        Should -Invoke Copy-Item -Times 1 -ParameterFilter {
            $LiteralPath -eq "C:\source.txt" -and
            $Destination -eq "C:\dest.txt"
        }
    }

    It 'should pass -Force option when specified' {
        Mock Copy-Item { }

        Copy-FileSafe -Source "C:\source.txt" -Destination "C:\dest.txt" -Force

        Should -Invoke Copy-Item -Times 1 -ParameterFilter {
            $Force -eq $true
        }
    }
}

Describe 'Get-FileContentSafe' {
    It 'should get file content with -Raw option' {
        Mock Get-Content { return "file content" }

        $result = Get-FileContentSafe -Path "C:\test.txt"

        $result | Should -Be "file content"
        Should -Invoke Get-Content -Times 1 -ParameterFilter {
            $LiteralPath -eq "C:\test.txt" -and
            $Raw -eq $true
        }
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

Describe 'Get-RegistryValue' {
    It 'should return registry value when path <exists>' -ForEach @(
        @{ exists = "exists"; mockReturn = [PSCustomObject]@{ TestValue = "TestData" }; expectedNull = $false }
        @{ exists = "does not exist"; mockReturn = $null; expectedNull = $true }
    ) {
        Mock Get-ItemProperty { return $mockReturn }

        $result = Get-RegistryValue -Path "HKCU:\Test"

        if ($expectedNull) {
            $result | Should -BeNullOrEmpty
        }
        else {
            $result.TestValue | Should -Be "TestData"
        }
    }
}

Describe 'Get-RegistryChildItem' {
    It 'should return <count> child keys' -ForEach @(
        @{ count = 2; mockReturn = @([PSCustomObject]@{ Name = "Key1" }, [PSCustomObject]@{ Name = "Key2" }) }
        @{ count = 0; mockReturn = @() }
    ) {
        Mock Get-ChildItem { return $mockReturn }

        $result = Get-RegistryChildItem -Path "HKCU:\Test"

        $result | Should -HaveCount $count
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

Describe 'Test-DockerDaemon' {
    It 'should return true when docker version succeeds' {
        Mock Invoke-Docker { $global:LASTEXITCODE = 0 }

        $result = Test-DockerDaemon

        $result | Should -Be $true
        Should -Invoke Invoke-Docker -Times 1 -ParameterFilter {
            $Arguments -contains "--context" -and
            $Arguments -contains "desktop-linux" -and
            "$Arguments" -match 'version' -and
            $TimeoutSeconds -eq 15
        }
    }

    It 'should return false when docker version fails' {
        Mock Invoke-Docker { $global:LASTEXITCODE = 1 }

        $result = Test-DockerDaemon

        $result | Should -Be $false
    }

    It 'should pass custom timeout to docker version' {
        Mock Invoke-Docker { $global:LASTEXITCODE = 0 }

        Test-DockerDaemon -TimeoutSeconds 3

        Should -Invoke Invoke-Docker -Times 1 -ParameterFilter {
            $TimeoutSeconds -eq 3
        }
    }

    It 'should ignore ambient Docker context environment variables during the Desktop check' {
        $originalDockerHost = $env:DOCKER_HOST
        $originalDockerContext = $env:DOCKER_CONTEXT
        try {
            $env:DOCKER_HOST = "tcp://example.invalid:2375"
            $env:DOCKER_CONTEXT = "remote"
            $script:dockerHostDuringCheck = $null
            $script:dockerContextDuringCheck = $null
            Mock Invoke-Docker {
                $script:dockerHostDuringCheck = $env:DOCKER_HOST
                $script:dockerContextDuringCheck = $env:DOCKER_CONTEXT
                $global:LASTEXITCODE = 0
            }

            Test-DockerDaemon | Should -Be $true

            $script:dockerHostDuringCheck | Should -BeNullOrEmpty
            $script:dockerContextDuringCheck | Should -BeNullOrEmpty
            $env:DOCKER_HOST | Should -Be "tcp://example.invalid:2375"
            $env:DOCKER_CONTEXT | Should -Be "remote"
        }
        finally {
            if ($null -eq $originalDockerHost) {
                Remove-Item Env:\DOCKER_HOST -ErrorAction SilentlyContinue
            }
            else {
                $env:DOCKER_HOST = $originalDockerHost
            }

            if ($null -eq $originalDockerContext) {
                Remove-Item Env:\DOCKER_CONTEXT -ErrorAction SilentlyContinue
            }
            else {
                $env:DOCKER_CONTEXT = $originalDockerContext
            }
        }
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
        $uniqueUserPath = "C:\TestUserPath-$([guid]::NewGuid())"
        Mock Get-UserEnvironmentPath { return $uniqueUserPath }

        $env:PATH = "C:\ExistingPath"

        Update-ProcessEnvironmentPath

        ($env:PATH -split ";") | Should -Contain $uniqueUserPath
        ($env:PATH -split ";") | Should -Contain "C:\ExistingPath"
    }

    It 'should remove duplicate entries case-insensitively' {
        $uniquePath = "C:\DuplicatePath-$([guid]::NewGuid())"
        Mock Get-UserEnvironmentPath { return $uniquePath }

        $env:PATH = "$uniquePath;$($uniquePath.ToUpperInvariant())"

        Update-ProcessEnvironmentPath

        @($env:PATH -split ";" | Where-Object { $_ -eq $uniquePath -or $_ -eq $uniquePath.ToUpperInvariant() }).Count | Should -Be 1
    }
}

Describe 'Test-WslAvailable' {
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
