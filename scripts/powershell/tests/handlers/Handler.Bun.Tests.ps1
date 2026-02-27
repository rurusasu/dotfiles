#Requires -Module Pester

<#
.SYNOPSIS
    Handler.Bun.ps1 のユニットテスト

.DESCRIPTION
    BunHandler クラスのテスト
#>

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.Bun.ps1
    $script:projectRoot = git -C $PSScriptRoot rev-parse --show-toplevel
}

Describe 'BunHandler' {
    BeforeEach {
        $script:handler = [BunHandler]::new()
        $script:ctx = [SetupContext]::new($script:projectRoot)
    }

    Context 'Constructor' {
        It 'should set <property> correctly' -ForEach @(
            @{ property = "Name"; expected = "Bun"; checkType = "Be" }
            @{ property = "Description"; expected = $null; checkType = "Not -BeNullOrEmpty" }
            @{ property = "Order"; expected = 7; checkType = "Be" }
            @{ property = "RequiresAdmin"; expected = $false; checkType = "Be" }
        ) {
            if ($checkType -eq "Be") {
                $handler.$property | Should -Be $expected
            } else {
                $handler.$property | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'CanApply - bun not found' {
        BeforeEach {
            Mock Get-ExternalCommand { return $null }
            Mock Write-Host { }
        }

        It 'should return false' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - bun not executable' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\bun.exe" } }
            Mock Invoke-Bun {
                $global:LASTEXITCODE = 1
                return ""
            }
            Mock Write-Host { }
        }

        It 'should return false' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - package file missing' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\bun.exe" } }
            Mock Invoke-Bun {
                $global:LASTEXITCODE = 0
                return "1.2.0"
            }
            Mock Test-PathExist { return $false }
            Mock Write-Host { }
        }

        It 'should return false' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - all conditions met' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\bun.exe" } }
            Mock Invoke-Bun {
                $global:LASTEXITCODE = 0
                return "1.2.0"
            }
            Mock Test-PathExist { return $true }
        }

        It 'should return true' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }
    }

    Context 'CreateBunxShim - bun not found' {
        BeforeEach {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'bun' }
            Mock Write-Host { }
        }

        It 'should do nothing' {
            { $handler.CreateBunxShim() } | Should -Not -Throw
        }
    }

    Context 'CreateBunxShim - shim already exists' {
        BeforeEach {
            $fakeBunExe = Join-Path $TestDrive "bun.exe"
            $fakeShim   = Join-Path $TestDrive "bunx.cmd"
            New-Item $fakeBunExe -ItemType File -Force | Out-Null
            New-Item $fakeShim   -ItemType File -Force | Out-Null
            Mock Get-Command { return [PSCustomObject]@{ Source = $fakeBunExe } } -ParameterFilter { $Name -eq 'bun' }
            Mock Write-Host { }
        }

        It 'should skip creation and log gray message' {
            $handler.CreateBunxShim()
            (Get-Item $fakeShim).Length | Should -Be 0
        }
    }

    Context 'CreateBunxShim - shim does not exist' {
        BeforeEach {
            $fakeBunExe = Join-Path $TestDrive "bun.exe"
            New-Item $fakeBunExe -ItemType File -Force | Out-Null
            Mock Get-Command { return [PSCustomObject]@{ Source = $fakeBunExe } } -ParameterFilter { $Name -eq 'bun' }
            Mock Write-Host { }
        }

        It 'should create bunx.cmd with correct content' {
            $handler.CreateBunxShim()
            $shimPath = Join-Path $TestDrive "bunx.cmd"
            $shimPath | Should -Exist
            $content = Get-Content $shimPath -Raw
            $content | Should -Match '@echo off'
            $content | Should -Match 'bun\.exe" x \%\*'
        }
    }

    Context 'Apply - all new packages' {
        BeforeEach {
            $fakeBunExe = Join-Path $TestDrive "bun.exe"
            New-Item $fakeBunExe -ItemType File -Force | Out-Null
            Mock Get-Command { return [PSCustomObject]@{ Source = $fakeBunExe } } -ParameterFilter { $Name -eq 'bun' }
            Mock Get-ExternalCommand { return @{ Source = $fakeBunExe } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return @{
                    globalPackages = @("@google/gemini-cli", "typescript")
                }
            }
            Mock Invoke-Bun {
                param($Arguments)
                if ($Arguments -contains "ls") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                $global:LASTEXITCODE = 0
                return "installed"
            }
        }

        It 'should return success result' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "2 個インストール"
        }
    }

    Context 'Apply - already installed packages' {
        BeforeEach {
            $fakeBunExe = Join-Path $TestDrive "bun.exe"
            New-Item $fakeBunExe -ItemType File -Force | Out-Null
            Mock Get-Command { return [PSCustomObject]@{ Source = $fakeBunExe } } -ParameterFilter { $Name -eq 'bun' }
            Mock Get-ExternalCommand { return @{ Source = $fakeBunExe } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return @{
                    globalPackages = @("@google/gemini-cli", "typescript")
                }
            }
            Mock Invoke-Bun {
                param($Arguments)
                if ($Arguments -contains "ls") {
                    $global:LASTEXITCODE = 0
                    return "@google/gemini-cli@1.0.0"
                }
                $global:LASTEXITCODE = 0
                return "installed"
            }
        }

        It 'should skip already installed packages' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個インストール"
            $result.Message | Should -Match "1 個スキップ"
        }
    }

    Context 'Apply - empty package list' {
        BeforeEach {
            $fakeBunExe = Join-Path $TestDrive "bun.exe"
            New-Item $fakeBunExe -ItemType File -Force | Out-Null
            Mock Get-Command { return [PSCustomObject]@{ Source = $fakeBunExe } } -ParameterFilter { $Name -eq 'bun' }
            Mock Get-ExternalCommand { return @{ Source = $fakeBunExe } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return @{
                    globalPackages = @()
                }
            }
        }

        It 'should return success with empty message' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "空"
        }
    }

    Context 'Apply - install failure' {
        BeforeEach {
            $fakeBunExe = Join-Path $TestDrive "bun.exe"
            New-Item $fakeBunExe -ItemType File -Force | Out-Null
            Mock Get-Command { return [PSCustomObject]@{ Source = $fakeBunExe } } -ParameterFilter { $Name -eq 'bun' }
            Mock Get-ExternalCommand { return @{ Source = $fakeBunExe } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return @{
                    globalPackages = @("pkg1", "pkg2")
                }
            }
            $script:callCount = 0
            Mock Invoke-Bun {
                param($Arguments)
                if ($Arguments -contains "ls") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                $script:callCount++
                if ($script:callCount -eq 1) {
                    $global:LASTEXITCODE = 0
                } else {
                    $global:LASTEXITCODE = 1
                }
                return "output"
            }
        }

        It 'should return success with partial failure info' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個成功"
            $result.Message | Should -Match "1 個失敗"
        }
    }

    Context 'Apply - exception thrown' {
        BeforeEach {
            $fakeBunExe = Join-Path $TestDrive "bun.exe"
            New-Item $fakeBunExe -ItemType File -Force | Out-Null
            Mock Get-Command { return [PSCustomObject]@{ Source = $fakeBunExe } } -ParameterFilter { $Name -eq 'bun' }
            Mock Get-ExternalCommand { return @{ Source = $fakeBunExe } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent { throw "bun error" }
        }

        It 'should return failure result' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $false
            $result.Message | Should -Match "bun error"
        }
    }
}
