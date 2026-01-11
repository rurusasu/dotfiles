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

    Context 'コンストラクタ' {
        It 'Name が WslConfig に設定される' {
            $handler.Name | Should -Be "WslConfig"
        }

        It 'Description が設定される' {
            $handler.Description | Should -Be ".wslconfig の適用と VHD 拡張"
        }

        It 'Order が 10 に設定される' {
            $handler.Order | Should -Be 10
        }

        It 'RequiresAdmin が $true に設定される' {
            $handler.RequiresAdmin | Should -Be $true
        }
    }

    Context 'CanApply' {
        It 'SkipWslConfigApply が true の場合は $false を返す' {
            Mock Write-Host { }
            $ctx.Options["SkipWslConfigApply"] = $true

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It '.wslconfig が存在しない場合は $false を返す' {
            Mock Test-PathExist { return $false }
            Mock Write-Host { }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It '.wslconfig が存在する場合は $true を返す' {
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

        It '.wslconfig をコピーして成功結果を返す' {
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

        It 'VHD 拡張がスキップされる（SkipVhdExpand = true）' {
            $script:diskpartCalled = $false
            Mock Invoke-Diskpart { $script:diskpartCalled = $true }
            $ctx.Options["SkipVhdExpand"] = $true

            $handler.Apply($ctx)

            $script:diskpartCalled | Should -Be $false
        }

        It 'ApplyWslConfig が $false を返した場合は失敗結果を返す' {
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

        It 'Apply 中に予期しない例外が発生した場合は例外メッセージで失敗結果を返す' {
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

        It 'BasePath が取得できない場合は VHD 拡張をスキップする' {
            $script:diskpartCalled = $false
            Mock Get-RegistryChildItem { return @() }
            Mock Invoke-Diskpart { $script:diskpartCalled = $true }
            $ctx.Options["SkipVhdExpand"] = $false

            $handler.Apply($ctx)

            $script:diskpartCalled | Should -Be $false
        }

        It 'VHDX が存在しない場合はスキップする' {
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

        It 'VHDX が存在する場合は diskpart で拡張する' {
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

        It 'defaultVhdSize が GB で指定されている場合' {
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

        It 'defaultVhdSize が MB で指定されている場合' {
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

        It 'defaultVhdSize が読み取れない場合はデフォルト値を使用' {
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

        It 'ルートデバイスを検出して resize2fs を実行する' {
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

        It 'ルートデバイスが見つからない場合はフォールバックを試す' {
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
