#Requires -Module Pester

<#
.SYNOPSIS
    Handler.ClaudeCode.ps1 のユニットテスト

.DESCRIPTION
    ClaudeCodeHandler クラスのテスト
#>

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.ClaudeCode.ps1
    $script:projectRoot = (Resolve-Path -LiteralPath "$PSScriptRoot/../../../..").Path
}

Describe 'ClaudeCodeHandler' {
    BeforeEach {
        $script:handler = [ClaudeCodeHandler]::new()
        $script:ctx = [SetupContext]::new($script:projectRoot)
    }

    Context 'Constructor' {
        It 'should set <property> correctly' -ForEach @(
            @{ property = "Name"; expected = "ClaudeCode"; checkType = "Be" }
            @{ property = "Description"; expected = $null; checkType = "Not -BeNullOrEmpty" }
            @{ property = "Order"; expected = 7; checkType = "Be" }
            @{ property = "RequiresAdmin"; expected = $false; checkType = "Be" }
            @{ property = "Phase"; expected = 1; checkType = "Be" }
        ) {
            if ($checkType -eq "Be") {
                $handler.$property | Should -Be $expected
            }
            else {
                $handler.$property | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'CanApply - claude.exe already exists' {
        BeforeEach {
            Mock Test-PathExist { return $true }
            Mock Write-Host { }
        }

        It 'should return false' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - claude.exe not found' {
        BeforeEach {
            Mock Test-PathExist { return $false }
            Mock Write-Host { }
        }

        It 'should return true' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }
    }

    Context 'Apply - successful install' {
        BeforeEach {
            Mock Write-Host { }
            Mock Test-Path { return $true }
            Mock Test-PathExist { return $true }
            Mock New-Item { }
            Mock Invoke-RestMethodSafe { return '# mock installer script' }
            Mock Get-UserEnvironmentPath { return "C:\existing\path" }
            Mock Set-UserEnvironmentPath { }

            # Mock the installer script execution by creating a ScriptBlock mock
            # The handler writes a temp file and executes it, so we mock at the file level
            $localBin = Join-Path $env:USERPROFILE ".local\bin"
            $claudeExe = Join-Path $localBin "claude.exe"
        }

        It 'should download and run the installer' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            Should -Invoke Invoke-RestMethodSafe -Times 1
        }
    }

    Context 'Apply - installer download fails' {
        BeforeEach {
            Mock Write-Host { }
            Mock Test-Path { return $false }
            Mock Test-PathExist { return $false }
            Mock Invoke-RestMethodSafe { throw "Network error" }
        }

        It 'should return failure' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $false
            $result.Message | Should -Match "Network error"
        }
    }

    Context 'Apply - claude.exe not found after install' {
        BeforeEach {
            Mock Write-Host { }
            Mock Test-Path { return $true } -ParameterFilter { $LiteralPath -notlike "*claude.exe" }
            Mock Test-PathExist { return $false }
            Mock New-Item { }
            Mock Invoke-RestMethodSafe { return '# mock installer' }
        }

        It 'should return failure when exe missing after install' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $false
            $result.Message | Should -Match "claude.exe が見つかりません"
        }
    }

    Context 'EnsureLocalBinInPath - adds to PATH when missing' {
        BeforeEach {
            Mock Write-Host { }
            Mock Test-Path { return $true }
            Mock Test-PathExist { return $true }
            Mock New-Item { }
            Mock Invoke-RestMethodSafe { return '# mock installer' }

            $script:capturedPath = $null
            Mock Get-UserEnvironmentPath { return "C:\other\path" }
            Mock Set-UserEnvironmentPath {
                param($Path)
                $script:capturedPath = $Path
            }
        }

        It 'should prepend .local\bin to PATH' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true

            $localBin = Join-Path $env:USERPROFILE ".local\bin"
            $escaped = [regex]::Escape($localBin)
            $script:capturedPath | Should -Match $escaped
            # .local\bin should be at the beginning
            $script:capturedPath | Should -Match "^$escaped"
        }
    }

    Context 'EnsureLocalBinInPath - skips when already in PATH' {
        BeforeEach {
            Mock Write-Host { }
            Mock Test-Path { return $true }
            Mock Test-PathExist { return $true }
            Mock New-Item { }
            Mock Invoke-RestMethodSafe { return '# mock installer' }

            $localBin = Join-Path $env:USERPROFILE ".local\bin"
            Mock Get-UserEnvironmentPath { return "$localBin;C:\other\path" }
            Mock Set-UserEnvironmentPath { }
        }

        It 'should not modify PATH' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            Should -Invoke Set-UserEnvironmentPath -Times 0
        }
    }
}
