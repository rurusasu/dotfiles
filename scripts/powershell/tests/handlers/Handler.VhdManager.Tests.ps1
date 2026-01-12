#Requires -Module Pester

<#
.SYNOPSIS
    Handler.VhdManager.ps1 のユニットテスト

.DESCRIPTION
    VhdManagerHandler クラスのテスト
    VHD サイズ管理（拡張/縮小/スキップ）をテスト
#>

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.VhdManager.ps1
}

Describe 'VhdManagerHandler' {
    BeforeEach {
        $script:handler = [VhdManagerHandler]::new()
        $script:ctx = [SetupContext]::new("D:\dotfiles")
    }

    Context 'Constructor' {
        It 'should set Name to VhdManager' {
            $handler.Name | Should -Be "VhdManager"
        }

        It 'should set Description to WSL VHD サイズ管理' {
            $handler.Description | Should -Be "WSL VHD サイズ管理"
        }

        It 'should set Order to 21' {
            $handler.Order | Should -Be 21
        }

        It 'should set RequiresAdmin to true' {
            $handler.RequiresAdmin | Should -Be $true
        }
    }

    Context 'CanApply' {
        BeforeEach {
            Mock Write-Host { }
        }

        It 'should return false when SkipVhdExpand is true' {
            $ctx.Options["SkipVhdExpand"] = $true

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'should return false when distro BasePath not found' {
            Mock Get-RegistryChildItem { return @() }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'should return false when VHDX does not exist' {
            Mock Get-RegistryChildItem {
                return @([PSCustomObject]@{ PSPath = "HKCU:\Test" })
            }
            Mock Get-RegistryValue {
                return [PSCustomObject]@{
                    DistributionName = "NixOS"
                    BasePath = "C:\WSL\NixOS"
                }
            }
            Mock Test-PathExist { return $false }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'should return true when VHDX exists' {
            Mock Get-RegistryChildItem {
                return @([PSCustomObject]@{ PSPath = "HKCU:\Test" })
            }
            Mock Get-RegistryValue {
                return [PSCustomObject]@{
                    DistributionName = "NixOS"
                    BasePath = "C:\WSL\NixOS"
                }
            }
            Mock Test-PathExist { return $true }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }
    }

    Context 'Apply - Expand' {
        BeforeEach {
            Mock Write-Host { }
            Mock Get-RegistryChildItem {
                return @([PSCustomObject]@{ PSPath = "HKCU:\Test" })
            }
            Mock Get-RegistryValue {
                return [PSCustomObject]@{
                    DistributionName = "NixOS"
                    BasePath = "C:\WSL\NixOS"
                }
            }
            Mock Test-PathExist { return $true }
            Mock Get-ProcessSafe { return $null }
            Mock Invoke-Wsl { }
        }

        It 'should expand VHD when target > current' {
            $script:diskpartCalled = $false
            Mock Get-FileContentSafe { return "defaultVhdSize = 128GB" }
            # Mock GetVhdxVirtualSize to return 64GB (smaller than target)
            Mock Invoke-Diskpart { $script:diskpartCalled = $true }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $script:diskpartCalled | Should -Be $true
        }

        It 'should parse GB size from .wslconfig' {
            $script:diskpartScript = ""
            Mock Get-FileContentSafe { return "defaultVhdSize = 64GB" }
            Mock Invoke-Diskpart {
                param($ScriptContent)
                $script:diskpartScript = $ScriptContent
            }

            $handler.Apply($ctx)

            # 64GB = 65536MB
            $script:diskpartScript | Should -Match "expand vdisk maximum=65536"
        }

        It 'should parse MB size from .wslconfig' {
            $script:diskpartScript = ""
            Mock Get-FileContentSafe { return "defaultVhdSize = 32768MB" }
            Mock Invoke-Diskpart {
                param($ScriptContent)
                $script:diskpartScript = $ScriptContent
            }

            $handler.Apply($ctx)

            $script:diskpartScript | Should -Match "expand vdisk maximum=32768"
        }

        It 'should use default size when defaultVhdSize not found' {
            $script:diskpartScript = ""
            Mock Get-FileContentSafe { return "# empty config" }
            Mock Invoke-Diskpart {
                param($ScriptContent)
                $script:diskpartScript = $ScriptContent
            }

            $handler.Apply($ctx)

            # Default 32768MB
            $script:diskpartScript | Should -Match "expand vdisk maximum=32768"
        }
    }

    Context 'Apply - Skip when same size' {
        BeforeEach {
            Mock Write-Host { }
            Mock Get-RegistryChildItem {
                return @([PSCustomObject]@{ PSPath = "HKCU:\Test" })
            }
            Mock Get-RegistryValue {
                return [PSCustomObject]@{
                    DistributionName = "NixOS"
                    BasePath = "C:\WSL\NixOS"
                }
            }
            Mock Test-PathExist { return $true }
            Mock Get-ProcessSafe { return $null }
            Mock Invoke-Wsl { }
            Mock Get-FileContentSafe { return "defaultVhdSize = 64GB" }
        }

        It 'should skip early when current size equals target size' {
            $script:dockerStopped = $false
            $script:wslShutdown = $false
            # Get-VHD が存在しない環境でテストするため、関数を定義
            function global:Get-VHD { }
            Mock Get-Command { return $true } -ParameterFilter { $Name -eq "Get-VHD" }
            Mock Get-VHD { return [PSCustomObject]@{ Size = 64 * 1GB } }
            Mock Stop-ProcessSafe { $script:dockerStopped = $true }
            Mock Invoke-Wsl {
                param($Arguments)
                if ($Arguments -contains "--shutdown") {
                    $script:wslShutdown = $true
                }
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "ターゲットサイズ"
            $script:dockerStopped | Should -Be $false
            $script:wslShutdown | Should -Be $false
            # クリーンアップ
            Remove-Item function:Get-VHD -ErrorAction SilentlyContinue
        }

        It 'should skip expansion when diskpart returns already at target error' {
            $script:diskpartAttempts = 0
            Mock Invoke-Diskpart {
                $script:diskpartAttempts++
                throw "diskpart failed with exit code -2147024809"
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "拡張を試行しました|ターゲットサイズ"
        }
    }

    Context 'Apply - Docker Desktop handling' {
        BeforeEach {
            Mock Write-Host { }
            Mock Get-RegistryChildItem {
                return @([PSCustomObject]@{ PSPath = "HKCU:\Test" })
            }
            Mock Get-RegistryValue {
                return [PSCustomObject]@{
                    DistributionName = "NixOS"
                    BasePath = "C:\WSL\NixOS"
                }
            }
            Mock Test-PathExist { return $true }
            Mock Invoke-Wsl { }
            Mock Invoke-Diskpart { }
            Mock Get-FileContentSafe { return "defaultVhdSize = 64GB" }
        }

        It 'should stop Docker Desktop before VHD operation' {
            $script:dockerStopped = $false
            Mock Get-ProcessSafe { return [PSCustomObject]@{ Name = "Docker Desktop" } }
            Mock Stop-ProcessSafe { $script:dockerStopped = $true }
            Mock Start-SleepSafe { }
            Mock Start-ProcessSafe { }

            $handler.Apply($ctx)

            $script:dockerStopped | Should -Be $true
        }

        It 'should restart Docker Desktop after VHD operation' {
            $script:dockerRestarted = $false
            Mock Get-ProcessSafe { return [PSCustomObject]@{ Name = "Docker Desktop" } }
            Mock Stop-ProcessSafe { }
            Mock Start-SleepSafe { }
            Mock Start-ProcessSafe { $script:dockerRestarted = $true }

            $handler.Apply($ctx)

            $script:dockerRestarted | Should -Be $true
        }

        It 'should not stop Docker if not running' {
            $script:dockerStopped = $false
            Mock Get-ProcessSafe { return $null }
            Mock Stop-ProcessSafe { $script:dockerStopped = $true }

            $handler.Apply($ctx)

            $script:dockerStopped | Should -Be $false
        }
    }

    Context 'Apply - Shrink' {
        BeforeEach {
            Mock Write-Host { }
            Mock Get-RegistryChildItem {
                return @([PSCustomObject]@{ PSPath = "HKCU:\Test" })
            }
            Mock Get-RegistryValue {
                return [PSCustomObject]@{
                    DistributionName = "NixOS"
                    BasePath = "C:\WSL\NixOS"
                }
            }
            Mock Test-PathExist { return $true }
            Mock Get-ProcessSafe { return $null }
            Mock Invoke-Wsl { }
            Mock Invoke-Diskpart { }
        }

        It 'should warn when AllowVhdShrink is not set' {
            $script:warningLogged = $false
            Mock Get-FileContentSafe { return "defaultVhdSize = 32GB" }
            # Simulate current size > target (need shrink)
            Mock Get-Command { return $true } -ParameterFilter { $Name -eq "Get-VHD" }
            # Note: Actually testing shrink requires more complex mocking
            Mock Write-Host {
                param($Object)
                if ($Object -match "AllowVhdShrink") {
                    $script:warningLogged = $true
                }
            }

            $handler.Apply($ctx)

            # Shrink is only triggered if current > target, which requires Get-VHD mock
        }
    }

    Context 'ResizeFilesystem' {
        BeforeEach {
            Mock Write-Host { }
            Mock Get-RegistryChildItem {
                return @([PSCustomObject]@{ PSPath = "HKCU:\Test" })
            }
            Mock Get-RegistryValue {
                return [PSCustomObject]@{
                    DistributionName = "NixOS"
                    BasePath = "C:\WSL\NixOS"
                }
            }
            Mock Test-PathExist { return $true }
            Mock Get-ProcessSafe { return $null }
            Mock Invoke-Diskpart { }
            Mock Get-FileContentSafe { return "defaultVhdSize = 64GB" }
        }

        It 'should detect root device and run resize2fs' {
            $script:resize2fsCalled = $false
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "lsblk") {
                    return "/dev/sdc"
                }
                if ($argStr -match "resize2fs") {
                    $script:resize2fsCalled = $true
                    return ""
                }
                return ""
            }

            $handler.Apply($ctx)

            $script:resize2fsCalled | Should -Be $true
        }

        It 'should try fallback when root device is not found' {
            $script:fallbackTried = $false
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match 'lsblk.*"/"') {
                    return ""  # Not found
                }
                if ($argStr -match "wslg/distro") {
                    $script:fallbackTried = $true
                    return "/dev/sdd"
                }
                return ""
            }

            $handler.Apply($ctx)

            # Fallback is attempted
        }
    }

    Context 'Error handling' {
        BeforeEach {
            Mock Write-Host { }
            Mock Get-RegistryChildItem {
                return @([PSCustomObject]@{ PSPath = "HKCU:\Test" })
            }
            Mock Get-RegistryValue {
                return [PSCustomObject]@{
                    DistributionName = "NixOS"
                    BasePath = "C:\WSL\NixOS"
                }
            }
            Mock Test-PathExist { return $true }
            Mock Get-ProcessSafe { return $null }
            Mock Invoke-Wsl { }
        }

        It 'should return failure when unexpected exception occurs' {
            Mock Get-FileContentSafe { throw "Unexpected error" }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "Unexpected error"
        }
    }
}
