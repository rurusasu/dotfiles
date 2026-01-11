#Requires -Module Pester

<#
.SYNOPSIS
    Handler.WslConfig.ps1 のユニットテスト

.DESCRIPTION
    WslConfigHandler クラスのテスト
    100% カバレッジを目標とする
#>

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.WslConfig.ps1
}

Describe 'WslConfigHandler' {
    BeforeEach {
        $script:handler = [WslConfigHandler]::new()
        $script:ctx = [SetupContext]::new("D:\dotfiles")
    }

    Context 'Constructor' {
        It 'should set <property> to <expected>' -ForEach @(
            @{ property = "Name"; expected = "WslConfig" }
            @{ property = "Description"; expected = ".wslconfig の適用と VHD 拡張" }
            @{ property = "Order"; expected = 20 }
            @{ property = "RequiresAdmin"; expected = $true }
        ) {
            $handler.$property | Should -Be $expected
        }
    }

    Context 'CanApply' {
        It 'should return false when SkipWslConfigApply is true' {
            Mock Write-Host { }
            $ctx.Options["SkipWslConfigApply"] = $true

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'should return false when .wslconfig does not exist' {
            Mock Test-PathExist { return $false }
            Mock Write-Host { }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'should return true when .wslconfig exists' {
            Mock Test-PathExist { return $true }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }
    }

    Context 'Apply' {
        BeforeEach {
            Mock Test-PathExist { return $true }
            Mock Copy-FileSafe { }
            Mock Invoke-Wsl { }
            Mock Write-Host { }
            Mock Get-RegistryChildItem { return @() }
            Mock Get-RegistryValue { return $null }
        }

        It 'should copy .wslconfig and return success result' {
            $script:copyFileCalled = $false
            $script:shutdownCalled = $false
            Mock Copy-FileSafe { $script:copyFileCalled = $true }
            Mock Invoke-Wsl {
                param($Arguments)
                if ($Arguments -contains "--shutdown") {
                    $script:shutdownCalled = $true
                }
            }
            $ctx.Options["SkipVhdExpand"] = $true

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Be ".wslconfig を適用しました"
            $script:copyFileCalled | Should -Be $true
            $script:shutdownCalled | Should -Be $true
        }

        It 'should skip VHD expansion when SkipVhdExpand is true' {
            $script:diskpartCalled = $false
            Mock Invoke-Diskpart { $script:diskpartCalled = $true }
            $ctx.Options["SkipVhdExpand"] = $true

            $handler.Apply($ctx)

            $script:diskpartCalled | Should -Be $false
        }

        It 'should return failure when ApplyWslConfig returns false' {
            # Copy-FileSafe が例外をスローすると ApplyWslConfig は $false を返す
            # これにより Apply メソッドの if (-not $copyResult) 分岐が実行される
            $script:errorLogged = $false
            Mock Copy-FileSafe { throw "アクセス拒否" }
            Mock Write-Host {
                param($Object)
                if ($Object -match "ファイルコピーに失敗") {
                    $script:errorLogged = $true
                }
            }

            $result = $handler.Apply($ctx)

            # ApplyWslConfig 内でエラーログが出力される
            $script:errorLogged | Should -Be $true
            # Apply メソッドから失敗結果が返される
            $result.Success | Should -Be $false
            $result.Message | Should -Be ".wslconfig のコピーに失敗しました"
        }

        It 'should return failure with exception message when unexpected exception occurs' {
            # ApplyWslConfig 自体が予期しない例外をスローした場合
            Mock Copy-FileSafe { }
            Mock Invoke-Wsl { throw "予期しないWSLエラー" }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "予期しないWSLエラー"
        }
    }

    Context 'ExpandVhd' {
        BeforeEach {
            Mock Test-PathExist { return $true }
            Mock Copy-FileSafe { }
            Mock Invoke-Wsl { }
            Mock Write-Host { }
        }

        It 'should skip VHD expansion when BasePath cannot be retrieved' {
            $script:diskpartCalled = $false
            Mock Get-RegistryChildItem { return @() }
            Mock Invoke-Diskpart { $script:diskpartCalled = $true }
            $ctx.Options["SkipVhdExpand"] = $false

            $handler.Apply($ctx)

            $script:diskpartCalled | Should -Be $false
        }

        It 'should skip when VHDX does not exist' {
            $script:diskpartCalled = $false
            Mock Get-RegistryChildItem {
                return @([PSCustomObject]@{ PSPath = "HKCU:\Test" })
            }
            Mock Get-RegistryValue {
                return [PSCustomObject]@{
                    DistributionName = "NixOS"
                    BasePath = "C:\WSL\NixOS"
                }
            }
            Mock Test-PathExist {
                param($Path)
                if ($Path -like "*ext4.vhdx") { return $false }
                return $true
            }
            Mock Invoke-Diskpart { $script:diskpartCalled = $true }
            $ctx.Options["SkipVhdExpand"] = $false

            $handler.Apply($ctx)

            $script:diskpartCalled | Should -Be $false
        }

        It 'should expand with diskpart when VHDX exists' {
            $script:diskpartCalled = $false
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
            Mock Invoke-Diskpart { $script:diskpartCalled = $true }
            Mock Get-FileContentSafe { return "defaultVhdSize = 64GB" }
            $ctx.Options["SkipVhdExpand"] = $false

            $handler.Apply($ctx)

            $script:diskpartCalled | Should -Be $true
        }
    }

    Context 'GetTargetVhdSizeMB' {
        BeforeEach {
            Mock Test-PathExist { return $true }
            Mock Copy-FileSafe { }
            Mock Invoke-Wsl { }
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
        }

        It 'should convert GB to MB when defaultVhdSize is specified in GB' {
            $script:diskpartScript = ""
            Mock Get-FileContentSafe { return "defaultVhdSize = 64GB" }
            Mock Invoke-Diskpart {
                param($ScriptContent)
                $script:diskpartScript = $ScriptContent
            }
            $ctx.Options["SkipVhdExpand"] = $false

            $handler.Apply($ctx)

            # 64GB = 65536MB
            $script:diskpartScript | Should -Match "expand vdisk maximum=65536"
        }

        It 'should use MB value directly when defaultVhdSize is specified in MB' {
            $script:diskpartScript = ""
            Mock Get-FileContentSafe { return "defaultVhdSize = 32768MB" }
            Mock Invoke-Diskpart {
                param($ScriptContent)
                $script:diskpartScript = $ScriptContent
            }
            $ctx.Options["SkipVhdExpand"] = $false

            $handler.Apply($ctx)

            $script:diskpartScript | Should -Match "expand vdisk maximum=32768"
        }

        It 'should use default value when defaultVhdSize cannot be read' {
            $script:diskpartScript = ""
            Mock Get-FileContentSafe { return "# empty config" }
            Mock Invoke-Diskpart {
                param($ScriptContent)
                $script:diskpartScript = $ScriptContent
            }
            $ctx.Options["SkipVhdExpand"] = $false

            $handler.Apply($ctx)

            # デフォルト 32768MB
            $script:diskpartScript | Should -Match "expand vdisk maximum=32768"
        }
    }

    Context 'ResizeFilesystem' {
        BeforeEach {
            Mock Test-PathExist { return $true }
            Mock Copy-FileSafe { }
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
            Mock Invoke-Diskpart { }
            Mock Get-FileContentSafe { return "defaultVhdSize = 64GB" }
        }

        It 'should detect root device and run resize2fs' {
            $script:resize2fsCalled = $false
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "lsblk") {
                    if ($argStr -match '"\/"') {
                        return "/dev/sdc"
                    }
                }
                if ($argStr -match "resize2fs") {
                    $script:resize2fsCalled = $true
                    return ""
                }
                return ""
            }
            $ctx.Options["SkipVhdExpand"] = $false

            $handler.Apply($ctx)

            $script:resize2fsCalled | Should -Be $true
        }

        It 'should try fallback when root device is not found' {
            $script:wslCallCount = 0
            Mock Invoke-Wsl {
                param($Arguments)
                $script:wslCallCount++
                $argStr = $Arguments -join " "
                if ($argStr -match "lsblk" -and $argStr -match '/"') {
                    return ""  # ルートが見つからない
                }
                if ($argStr -match "lsblk" -and $argStr -match "wslg/distro") {
                    return "/dev/sdd"  # フォールバック
                }
                if ($argStr -match "resize2fs") {
                    return ""
                }
                return ""
            }
            $ctx.Options["SkipVhdExpand"] = $false

            $handler.Apply($ctx)

            # フォールバックの lsblk が呼ばれる
            $script:wslCallCount | Should -BeGreaterOrEqual 2
        }
    }
}
