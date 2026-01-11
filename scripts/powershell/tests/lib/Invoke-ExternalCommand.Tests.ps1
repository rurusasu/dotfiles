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
}

Describe 'Invoke-Diskpart' {
    BeforeAll {
        $script:diskpartCalled = $false
        $script:setContentCalled = $false
        Mock diskpart {
            $script:diskpartCalled = $true
            return "diskpart output"
        }
        Mock Set-ContentNoNewline {
            $script:setContentCalled = $true
        }
        Mock Remove-Item { }
        Mock New-TemporaryFile {
            return [PSCustomObject]@{ FullName = "C:\temp\diskpart_test.txt" }
        }
    }

    It 'should create script file and execute diskpart' {
        Invoke-Diskpart -ScriptContent "list disk"

        $script:diskpartCalled | Should -Be $true
    }

    It 'should write script content to temp file' {
        Invoke-Diskpart -ScriptContent "select disk 0"

        $script:setContentCalled | Should -Be $true
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
        } else {
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
        } else {
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
        } else {
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
