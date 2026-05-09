#Requires -Module Pester

<#
.SYNOPSIS
    Handler.WslInstall.ps1 のユニットテスト
#>

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.WslInstall.ps1
}

Describe 'WslInstallHandler' {
    BeforeEach {
        $script:handler = [WslInstallHandler]::new()
        $script:ctx = [SetupContext]::new('D:\dotfiles')
    }

    Context 'Constructor' {
        It 'should set Name to WslInstall' {
            $handler.Name | Should -Be 'WslInstall'
        }

        It 'should set Order to 5' {
            $handler.Order | Should -Be 5
        }

        It 'should require admin' {
            $handler.RequiresAdmin | Should -Be $true
        }
    }

    Context 'CanApply' {
        It 'should return false when WSL is already available' {
            Mock Test-WslAvailable { return $true }
            Mock Write-Host { }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'should return true when WSL is not available' {
            Mock Test-WslAvailable { return $false }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }

        It 'should return false when SkipWslInstall is set' {
            Mock Write-Host { }
            $ctx.Options["SkipWslInstall"] = $true

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }
    }

    Context 'Apply' {
        BeforeEach {
            Mock Write-Host { }
        }

        It 'should run wsl --install --no-distribution' {
            $script:wslInstallCalled = $false
            Mock Invoke-Wsl {
                $script:wslInstallCalled = $true
                $global:LASTEXITCODE = 0
                return "Installing WSL..."
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match '再起動が必要'
            $script:wslInstallCalled | Should -Be $true
        }

        It 'should fallback to dism when wsl --install fails' {
            Mock Invoke-Wsl {
                $global:LASTEXITCODE = 1
                return "Installation failed"
            }
            $script:dismCalls = @()
            Mock Invoke-Dism {
                $script:dismCalls += ($Arguments -join " ")
                $global:LASTEXITCODE = 0
                return "The operation completed successfully."
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match '再起動が必要'
            $script:dismCalls.Count | Should -Be 2
            $script:dismCalls[0] | Should -Match 'Microsoft-Windows-Subsystem-Linux'
            $script:dismCalls[1] | Should -Match 'VirtualMachinePlatform'
        }

        It 'should return failure when both wsl --install and dism fail' {
            Mock Invoke-Wsl {
                $global:LASTEXITCODE = 1
                return "Installation failed"
            }
            Mock Invoke-Dism {
                $global:LASTEXITCODE = 1
                return "Error"
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match 'dism.exe'
        }

        It 'should return failure when second dism feature fails' {
            Mock Invoke-Wsl {
                $global:LASTEXITCODE = 1
                return "Installation failed"
            }
            Mock Invoke-Dism {
                # VirtualMachinePlatform の有効化が失敗するシナリオ
                $global:LASTEXITCODE = if ($Arguments -match 'VirtualMachinePlatform') { 1 } else { 0 }
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            Should -Invoke Invoke-Dism -Times 2
        }
    }
}
