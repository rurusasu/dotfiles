#Requires -Module Pester

<#
.SYNOPSIS
    Handler.Pnpm.ps1 のユニットテスト

.DESCRIPTION
    PnpmHandler クラスのテスト
#>

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.Pnpm.ps1
    $script:projectRoot = git -C $PSScriptRoot rev-parse --show-toplevel
}

Describe 'PnpmHandler' {
    BeforeEach {
        $script:handler = [PnpmHandler]::new()
        $script:ctx = [SetupContext]::new($script:projectRoot)
    }

    Context 'Constructor' {
        It 'should set <property> correctly' -ForEach @(
            @{ property = "Name"; expected = "Pnpm"; checkType = "Be" }
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

    Context 'CanApply - pnpm not found' {
        BeforeEach {
            Mock Get-ExternalCommand { return $null }
            Mock Write-Host { }
        }

        It 'should return false' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - pnpm not executable' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\pnpm.cmd" } }
            Mock Invoke-Pnpm {
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
            Mock Get-ExternalCommand { return @{ Source = "C:\pnpm.cmd" } }
            Mock Invoke-Pnpm {
                $global:LASTEXITCODE = 0
                return "9.15.0"
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
            Mock Get-ExternalCommand { return @{ Source = "C:\pnpm.cmd" } }
            Mock Invoke-Pnpm {
                $global:LASTEXITCODE = 0
                return "9.15.0"
            }
            Mock Test-PathExist { return $true }
        }

        It 'should return true' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }
    }

    Context 'AddPnpmBinToPath - bin path retrieval fails' {
        BeforeEach {
            Mock Invoke-Pnpm {
                $global:LASTEXITCODE = 1
                return ""
            }
            Mock Write-Host { }
        }

        It 'should do nothing without throwing' {
            { $handler.AddPnpmBinToPath() } | Should -Not -Throw
        }
    }

    Context 'AddPnpmBinToPath - already in PATH' {
        BeforeEach {
            $script:pnpmBin = Join-Path $TestDrive "pnpm-global-bin"
            New-Item $script:pnpmBin -ItemType Directory -Force | Out-Null
            Mock Invoke-Pnpm {
                $global:LASTEXITCODE = 0
                return $script:pnpmBin
            }
            Mock Get-UserEnvironmentPath { return $script:pnpmBin }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }

        It 'should skip and not call Set-UserEnvironmentPath' {
            $handler.AddPnpmBinToPath()
            Should -Invoke Set-UserEnvironmentPath -Times 0
        }
    }

    Context 'AddPnpmBinToPath - not yet in PATH' {
        BeforeEach {
            $script:pnpmBin = Join-Path $TestDrive "pnpm-global-bin"
            New-Item $script:pnpmBin -ItemType Directory -Force | Out-Null
            Mock Invoke-Pnpm {
                $global:LASTEXITCODE = 0
                return $script:pnpmBin
            }
            Mock Get-UserEnvironmentPath { return "C:\Windows\System32" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }

        It 'should call Set-UserEnvironmentPath with pnpm bin prepended' {
            $handler.AddPnpmBinToPath()
            Should -Invoke Set-UserEnvironmentPath -Times 1
        }
    }

    Context 'IsPackageInstalled - package exists' {
        BeforeEach {
            $script:globalRoot = Join-Path $TestDrive "pnpm-global\node_modules"
            New-Item (Join-Path $script:globalRoot "typescript") -ItemType Directory -Force | Out-Null
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "root") {
                    $global:LASTEXITCODE = 0
                    return $script:globalRoot
                }
                $global:LASTEXITCODE = 0
                return ""
            }
        }

        It 'should return true for installed package' {
            $result = $handler.IsPackageInstalled("typescript")
            $result | Should -Be $true
        }
    }

    Context 'IsPackageInstalled - package not installed' {
        BeforeEach {
            $script:globalRoot = Join-Path $TestDrive "pnpm-global\node_modules"
            New-Item $script:globalRoot -ItemType Directory -Force | Out-Null
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "root") {
                    $global:LASTEXITCODE = 0
                    return $script:globalRoot
                }
                $global:LASTEXITCODE = 0
                return ""
            }
        }

        It 'should return false for missing package' {
            $result = $handler.IsPackageInstalled("nonexistent-pkg")
            $result | Should -Be $false
        }
    }

    Context 'Apply - all new packages' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\pnpm.cmd" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return @{
                    globalPackages = @("@google/gemini-cli", "typescript")
                }
            }
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "root") {
                    $global:LASTEXITCODE = 0
                    return (Join-Path $TestDrive "nonexistent-root")
                }
                if ($Arguments -contains "bin") {
                    $global:LASTEXITCODE = 1
                    return ""
                }
                $global:LASTEXITCODE = 0
                return "installed"
            }
            Mock Test-Path { return $false } -ParameterFilter {
                ($LiteralPath -and $LiteralPath -like '*nonexistent-root*')
            }
            Mock Write-Host { }
            Mock Get-UserEnvironmentPath { return "" }
            Mock Set-UserEnvironmentPath { }
        }

        It 'should return success result' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "2 個インストール"
        }
    }

    Context 'Apply - empty package list' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\pnpm.cmd" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return @{
                    globalPackages = @()
                }
            }
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "bin") {
                    $global:LASTEXITCODE = 1
                    return ""
                }
                $global:LASTEXITCODE = 0
                return ""
            }
            Mock Write-Host { }
        }

        It 'should return success with empty message' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "空"
        }
    }

    Context 'Apply - exception thrown' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\pnpm.cmd" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent { throw "pnpm error" }
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "bin") {
                    $global:LASTEXITCODE = 1
                    return ""
                }
                $global:LASTEXITCODE = 0
                return ""
            }
            Mock Write-Host { }
        }

        It 'should return failure result' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $false
            $result.Message | Should -Match "pnpm error"
        }
    }

    Context 'EnsureGeminiCommandShim - gemini command healthy' {
        BeforeEach {
            $script:origProfile = $env:USERPROFILE
            $env:USERPROFILE = $TestDrive
            $script:globalRoot = Join-Path $TestDrive "pnpm-global\node_modules"
            $entryDir = Join-Path $script:globalRoot "@google\gemini-cli\dist"
            New-Item $entryDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $entryDir "index.js") -Value "console.log('ok')" -NoNewline
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "root") {
                    $global:LASTEXITCODE = 0
                    return $script:globalRoot
                }
                $global:LASTEXITCODE = 0
                return ""
            }
            Mock gemini {
                $global:LASTEXITCODE = 0
                return "0.32.0"
            }
            Mock Get-UserEnvironmentPath { return "C:\Windows\System32" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }
        AfterEach {
            $env:USERPROFILE = $script:origProfile
        }

        It 'should skip shim creation when gemini is healthy' {
            $handler.EnsureGeminiCommandShim()
            (Join-Path $TestDrive ".local\bin\gemini.cmd") | Should -Not -Exist
            Should -Invoke Set-UserEnvironmentPath -Times 0
        }
    }

    Context 'EnsureGeminiCommandShim - gemini command broken' {
        BeforeEach {
            $script:origProfile = $env:USERPROFILE
            $env:USERPROFILE = $TestDrive
            $script:globalRoot = Join-Path $TestDrive "pnpm-global\node_modules"
            $entryDir = Join-Path $script:globalRoot "@google\gemini-cli\dist"
            New-Item $entryDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $entryDir "index.js") -Value "console.log('ok')" -NoNewline
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "root") {
                    $global:LASTEXITCODE = 0
                    return $script:globalRoot
                }
                $global:LASTEXITCODE = 0
                return ""
            }
            Mock gemini {
                $global:LASTEXITCODE = 1
                throw "broken"
            }
            Mock Get-UserEnvironmentPath { return "C:\Windows\System32" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }
        AfterEach {
            $env:USERPROFILE = $script:origProfile
        }

        It 'should create gemini.cmd shim and prepend .local\bin to user PATH' {
            $handler.EnsureGeminiCommandShim()
            $shimPath = Join-Path $TestDrive ".local\bin\gemini.cmd"
            $shimPath | Should -Exist
            $content = Get-Content $shimPath -Raw
            $content | Should -Match 'GEMINI_JS'
            $content | Should -Match 'pnpm root -g'
            $content | Should -Match 'node "%GEMINI_JS%" %\*'
            Should -Invoke Set-UserEnvironmentPath -Times 1
        }
    }
}
