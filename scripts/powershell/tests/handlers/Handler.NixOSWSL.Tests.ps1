#Requires -Module Pester

<#
.SYNOPSIS
    Handler.NixOSWSL.ps1 のユニットテスト

.DESCRIPTION
    NixOSWSLHandler クラスのテスト
    環境依存のテストはスキップし、ロジックのテストに集中
#>

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.NixOSWSL.ps1
}

Describe 'NixOSWSLHandler' {
    BeforeEach {
        $script:handler = [NixOSWSLHandler]::new()
        $script:ctx = [SetupContext]::new("D:\dotfiles")
        $script:ctx.DistroName = "NixOS"
        $script:ctx.InstallDir = "D:\WSL\NixOS"
    }

    Context 'Constructor' {
        It 'should set <property> to <expected>' -ForEach @(
            @{ property = "Name"; expected = "NixOSWSL" }
            @{ property = "Description"; expected = "NixOS-WSL のダウンロードとインストール" }
            @{ property = "Order"; expected = 50 }
            @{ property = "RequiresAdmin"; expected = $false }
        ) {
            $handler.$property | Should -Be $expected
        }
    }

    Context 'CanApply' {
        BeforeEach {
            # TestWslExecutable が実際の wsl.exe を呼ばないようにモック
            Mock Invoke-Wsl { $global:LASTEXITCODE = 0; return "Default Version: 2" }
        }

        It 'should return true when distro does not exist' {
            $handler | Add-Member -MemberType ScriptMethod -Name DistroExists -Value { return $false } -Force
            Mock Write-Host { }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }

        It 'should return false when distro already exists' {
            $handler | Add-Member -MemberType ScriptMethod -Name DistroExists -Value { return $true } -Force
            Mock Write-Host { }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }
    }

    Context 'Apply - success path (fresh install)' {
        BeforeEach {
            # すべての依存関数をモック（AssertAdmin は削除済み - RequiresAdmin = $false）
            $handler | Add-Member -MemberType ScriptMethod -Name EnsureWslReady -Value { } -Force
            $handler | Add-Member -MemberType ScriptMethod -Name GetRelease -Value {
                return @{ tag_name = "v24.5.1"; assets = @() }
            } -Force
            $handler | Add-Member -MemberType ScriptMethod -Name SelectAsset -Value {
                return @{ name = "nixos.wsl"; browser_download_url = "http://example.com/nixos.wsl" }
            } -Force
            $handler | Add-Member -MemberType ScriptMethod -Name DownloadAsset -Value {
                return "C:\Temp\nixos.wsl"
            } -Force
            $handler | Add-Member -MemberType ScriptMethod -Name InstallDistro -Value { } -Force
            $handler | Add-Member -MemberType ScriptMethod -Name ExecutePostInstall -Value { } -Force
            $handler | Add-Member -MemberType ScriptMethod -Name EnsureWhoamiShim -Value { } -Force
            $handler | Add-Member -MemberType ScriptMethod -Name EnsureWslWritable -Value { } -Force
            $handler | Add-Member -MemberType ScriptMethod -Name EnsureDockerGroup -Value { } -Force
            # VHD が存在しない場合（通常インストール）
            Mock Test-Path { return $false }
            Mock Write-Host { }
        }

        It 'should return success result' {
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "NixOS-WSL のインストールが完了しました"
        }

        It 'should call EnsureDockerGroup after installation' {
            $script:dockerGroupCalled = $false
            $handler | Add-Member -MemberType ScriptMethod -Name EnsureDockerGroup -Value {
                $script:dockerGroupCalled = $true
            } -Force

            $handler.Apply($ctx)

            $script:dockerGroupCalled | Should -Be $true
        }
    }

    Context 'Apply - VHD exists (reimport path)' {
        BeforeEach {
            $handler | Add-Member -MemberType ScriptMethod -Name EnsureWslReady -Value { } -Force
            $handler | Add-Member -MemberType ScriptMethod -Name ReimportExistingVhd -Value { } -Force
            $handler | Add-Member -MemberType ScriptMethod -Name ExecutePostInstall -Value { } -Force
            $handler | Add-Member -MemberType ScriptMethod -Name EnsureWhoamiShim -Value { } -Force
            $handler | Add-Member -MemberType ScriptMethod -Name EnsureWslWritable -Value { } -Force
            $handler | Add-Member -MemberType ScriptMethod -Name EnsureDockerGroup -Value { } -Force
            # VHD が存在するケース
            Mock Test-Path { return $true }
            Mock Write-Host { }
        }

        It 'should call ReimportExistingVhd when VHD exists' {
            $script:reimportCalled = $false
            $handler | Add-Member -MemberType ScriptMethod -Name ReimportExistingVhd -Value {
                $script:reimportCalled = $true
            } -Force

            $handler.Apply($ctx)

            $script:reimportCalled | Should -Be $true
        }

        It 'should not call GetRelease when VHD exists' {
            $script:getReleaseCalled = $false
            $handler | Add-Member -MemberType ScriptMethod -Name GetRelease -Value {
                $script:getReleaseCalled = $true
                return @{ tag_name = "v24.5.1"; assets = @() }
            } -Force

            $handler.Apply($ctx)

            $script:getReleaseCalled | Should -Be $false
        }

        It 'should return success result after reimport' {
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "NixOS-WSL のインストールが完了しました"
        }
    }

    Context 'Apply - error handling' {
        It 'should return failure result when exception occurs' {
            $handler | Add-Member -MemberType ScriptMethod -Name EnsureWslReady -Value {
                throw "WSL が有効化されていません"
            } -Force
            Mock Write-Host { }
            Mock Test-Path { return $false }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "WSL が有効化されていません"
        }
    }

    Context 'SupportsFromFileInstall' {
        It 'should return true when WSL version is 2.4.4+' {
            $handler | Add-Member -MemberType ScriptMethod -Name GetWslVersion -Value {
                return [version]"2.4.4.0"
            } -Force

            $result = $handler.SupportsFromFileInstall()

            $result | Should -Be $true
        }

        It 'should check help text when WSL version is below 2.4.4' {
            $handler | Add-Member -MemberType ScriptMethod -Name GetWslVersion -Value {
                return [version]"2.0.0.0"
            } -Force
            Mock Invoke-Wsl {
                $global:LASTEXITCODE = 0
                return "--install --from-file"
            }

            $result = $handler.SupportsFromFileInstall()

            $result | Should -Be $true
        }

        It 'should return false when help text does not contain --from-file' {
            $handler | Add-Member -MemberType ScriptMethod -Name GetWslVersion -Value {
                return [version]"2.0.0.0"
            } -Force
            Mock Invoke-Wsl {
                $global:LASTEXITCODE = 0
                return "Usage: wsl [Argument]"
            }

            $result = $handler.SupportsFromFileInstall()

            $result | Should -Be $false
        }
    }

    Context 'EnsureWslReady' {
        BeforeEach {
            Mock Write-Host { }
        }

        It 'should return when wsl --status succeeds' {
            Mock Invoke-Wsl {
                $global:LASTEXITCODE = 0
                return ""
            }

            { $handler.EnsureWslReady($ctx) } | Should -Not -Throw

            Should -Invoke Invoke-Wsl -ParameterFilter {
                $Arguments -contains "--status"
            } -Times 1
        }

        It 'should fall back to -l -q when --status fails' {
            $script:callCount = 0
            Mock Invoke-Wsl {
                param($Arguments)
                $script:callCount++
                if ($Arguments -contains "--status") {
                    $global:LASTEXITCODE = 1
                } else {
                    $global:LASTEXITCODE = 0
                }
            }

            { $handler.EnsureWslReady($ctx) } | Should -Not -Throw

            Should -Invoke Invoke-Wsl -ParameterFilter {
                $Arguments -contains "-l" -and $Arguments -contains "-q"
            } -Times 1
        }

        It 'should throw when SkipWslBaseInstall is true and WSL is not ready' {
            Mock Invoke-Wsl { $global:LASTEXITCODE = 1 }
            $ctx.Options["SkipWslBaseInstall"] = $true

            { $handler.EnsureWslReady($ctx) } | Should -Throw "*SkipWslBaseInstall*"
        }

        It 'should call wsl --install and throw restart message when WSL is not ready' {
            Mock Invoke-Wsl { $global:LASTEXITCODE = 1 }

            { $handler.EnsureWslReady($ctx) } | Should -Throw "*再起動*"

            Should -Invoke Invoke-Wsl -ParameterFilter {
                $Arguments -contains "--install" -and $Arguments -contains "--no-distribution"
            } -Times 1
        }
    }

    Context 'GetRelease' {
        It 'should fetch latest release from GitHub API' {
            Mock Invoke-RestMethodSafe {
                return @{
                    tag_name = "v24.5.1"
                    assets = @()
                }
            }
            Mock Write-Host { }

            $result = $handler.GetRelease("")

            $result.tag_name | Should -Be "v24.5.1"
            Should -Invoke Invoke-RestMethodSafe -ParameterFilter {
                $Uri -match "/releases/latest"
            }
        }

        It 'should fetch specific tag when specified' {
            Mock Invoke-RestMethodSafe {
                return @{
                    tag_name = "v24.5.0"
                    assets = @()
                }
            }
            Mock Write-Host { }

            $null = $handler.GetRelease("v24.5.0")

            Should -Invoke Invoke-RestMethodSafe -ParameterFilter {
                $Uri -match "/releases/tags/v24.5.0"
            }
        }
    }

    Context 'SelectAsset' {
        It 'should prefer nixos.wsl asset' {
            $release = @{
                assets = @(
                    @{ name = "nixos-wsl.tar.gz" },
                    @{ name = "nixos.wsl" }
                )
            }
            Mock Write-Host { }

            $result = $handler.SelectAsset($release)

            $result.name | Should -Be "nixos.wsl"
        }

        It 'should select nixos-wsl.tar.gz when nixos.wsl is not available' {
            $release = @{
                assets = @(
                    @{ name = "nixos-wsl.tar.gz" },
                    @{ name = "other.txt" }
                )
            }
            Mock Write-Host { }

            $result = $handler.SelectAsset($release)

            $result.name | Should -Be "nixos-wsl.tar.gz"
        }

        It 'should throw exception when no asset is found' {
            $release = @{
                tag_name = "v1.0.0"
                assets = @()
            }

            { $handler.SelectAsset($release) } | Should -Throw "*利用可能なアーカイブが見つかりません*"
        }
    }

    Context 'DownloadAsset' {
        It 'should download asset' {
            $asset = @{
                name = "nixos.wsl"
                browser_download_url = "http://example.com/nixos.wsl"
            }
            Mock Invoke-WebRequestSafe { }
            Mock Write-Host { }

            $result = $handler.DownloadAsset($asset)

            $result | Should -Match "nixos.wsl"
            Should -Invoke Invoke-WebRequestSafe -ParameterFilter {
                $Uri -eq "http://example.com/nixos.wsl"
            }
        }
    }

    Context 'DistroExists - null byte handling' {
        It 'should return false when WSL output contains null-byte-padded names that do not match' {
            Mock Invoke-Wsl {
                # WSL UTF-16 LE 出力をシミュレート: "docker-desktop" に null バイトが挟まれた形
                $global:LASTEXITCODE = 0
                return @("d`0o`0c`0k`0e`0r`0-`0d`0e`0s`0k`0t`0o`0p`0")
            }

            $result = $handler.DistroExists("NixOS")

            $result | Should -Be $false
        }

        It 'should return true when WSL output contains matching name with null bytes stripped' {
            Mock Invoke-Wsl {
                $global:LASTEXITCODE = 0
                return @("N`0i`0x`0O`0S`0")
            }

            $result = $handler.DistroExists("NixOS")

            $result | Should -Be $true
        }
    }

    Context 'ReimportExistingVhd' {
        It 'should call wsl --import-in-place as primary method' {
            Mock Invoke-Wsl { $global:LASTEXITCODE = 0 }
            $handler | Add-Member -MemberType ScriptMethod -Name WaitForWslReady -Value { } -Force
            Mock Write-Host { }

            { $handler.ReimportExistingVhd($ctx) } | Should -Not -Throw

            Should -Invoke Invoke-Wsl -ParameterFilter {
                $Arguments -contains "--import-in-place" -and
                $Arguments -contains "NixOS" -and
                $Arguments -contains "D:\WSL\NixOS"
            }
        }

        It 'should fallback to --import --vhd when --import-in-place fails' {
            $script:callCount = 0
            Mock Invoke-Wsl {
                $script:callCount++
                if ($script:callCount -eq 1) {
                    $global:LASTEXITCODE = 1  # --import-in-place fails
                } else {
                    $global:LASTEXITCODE = 0  # --import --vhd succeeds
                }
            }
            $handler | Add-Member -MemberType ScriptMethod -Name WaitForWslReady -Value { } -Force
            Mock Rename-Item { }
            Mock Remove-Item { }
            Mock Test-Path { return $false }
            Mock Write-Host { }

            { $handler.ReimportExistingVhd($ctx) } | Should -Not -Throw

            Should -Invoke Invoke-Wsl -ParameterFilter {
                $Arguments -contains "--import" -and $Arguments -contains "--vhd"
            }
        }

        It 'should throw when both --import-in-place and --import --vhd fail' {
            Mock Invoke-Wsl { $global:LASTEXITCODE = 1 }
            $handler | Add-Member -MemberType ScriptMethod -Name WaitForWslReady -Value { } -Force
            Mock Rename-Item { }
            Mock Remove-Item { }
            Mock Test-Path { return $false }
            Mock Write-Host { }

            { $handler.ReimportExistingVhd($ctx) } | Should -Throw "*再登録に失敗*"
        }
    }

    Context 'EnsureInstallDir' {
        It 'should create directory when it does not exist' {
            Mock Test-Path { return $false }
            Mock New-Item { }

            { $handler.EnsureInstallDir("C:\Test") } | Should -Not -Throw

            Should -Invoke New-Item -ParameterFilter {
                $ItemType -eq "Directory"
            }
        }

        It 'should throw exception when directory is not empty' {
            Mock Test-Path { return $true } -ParameterFilter { $PathType -eq 'Container' }
            Mock Test-Path { return $true } -ParameterFilter { -not $PSBoundParameters.ContainsKey('PathType') }
            Mock Get-ChildItemSafe {
                return @([PSCustomObject]@{ Name = "file.txt" })
            }

            { $handler.EnsureInstallDir("C:\Test") } | Should -Throw "*空ではありません*"
        }
    }

    Context 'InstallDistro' {
        BeforeEach {
            $script:asset = @{ name = "nixos.wsl" }
            $handler | Add-Member -MemberType ScriptMethod -Name SupportsFromFileInstall -Value { return $true } -Force
        }

        It 'should use InstallFromFile for .wsl file' {
            $script:callCount = 0
            $handler | Add-Member -MemberType ScriptMethod -Name InstallFromFile -Value { $script:callCount++ } -Force

            $handler.InstallDistro($ctx, $script:asset, "C:\Temp\nixos.wsl")

            $script:callCount | Should -Be 1
        }

        It 'should use ImportDistro directly for .tar.gz asset even with new WSL' {
            $tarAsset = @{ name = "nixos-wsl.tar.gz" }
            $script:importCalled = $false
            $script:installFromFileCalled = $false
            $handler | Add-Member -MemberType ScriptMethod -Name ImportDistro -Value { $script:importCalled = $true } -Force
            $handler | Add-Member -MemberType ScriptMethod -Name InstallFromFile -Value { $script:installFromFileCalled = $true } -Force

            $handler.InstallDistro($ctx, $tarAsset, "C:\Temp\nixos-wsl.tar.gz")

            $script:importCalled | Should -Be $true
            $script:installFromFileCalled | Should -Be $false
        }

        It 'should fallback to ImportDistro when InstallFromFile fails' {
            $handler | Add-Member -MemberType ScriptMethod -Name InstallFromFile -Value {
                throw "Failed"
            } -Force
            $script:callCount = 0
            $handler | Add-Member -MemberType ScriptMethod -Name ImportDistro -Value { $script:callCount++ } -Force
            Mock Write-Host { }

            $handler.InstallDistro($ctx, $script:asset, "C:\Temp\nixos.wsl")

            $script:callCount | Should -Be 1
        }
    }

    Context 'WaitForWslReady' {
        It 'should work when called with no arguments' {
            Mock Invoke-Wsl { $global:LASTEXITCODE = 0 }
            Mock Start-SleepSafe { }
            Mock Write-Host { }

            { $handler.WaitForWslReady() } | Should -Not -Throw

            Should -Not -Invoke Start-SleepSafe
            Should -Invoke Invoke-Wsl -ParameterFilter { $Arguments -contains "--status" }
        }

        It 'should return immediately when WSL is ready' {
            Mock Invoke-Wsl { $global:LASTEXITCODE = 0 }
            Mock Start-SleepSafe { }
            Mock Write-Host { }

            { $handler.WaitForWslReady(3, 1) } | Should -Not -Throw

            Should -Not -Invoke Start-SleepSafe
        }

        It 'should retry when WSL is not ready initially' {
            $script:wslCallCount = 0
            Mock Invoke-Wsl {
                $script:wslCallCount++
                if ($script:wslCallCount -le 2) {
                    $global:LASTEXITCODE = 1
                    return "error"
                }
                $global:LASTEXITCODE = 0
                return "ok"
            }
            Mock Start-SleepSafe { }
            Mock Write-Host { }

            { $handler.WaitForWslReady(5, 1) } | Should -Not -Throw

            Should -Invoke Start-SleepSafe -Times 2
        }

        It 'should warn but not throw when max attempts exhausted' {
            Mock Invoke-Wsl { $global:LASTEXITCODE = 1 }
            Mock Start-SleepSafe { }
            Mock Write-Host { }

            { $handler.WaitForWslReady(3, 1) } | Should -Not -Throw

            Should -Invoke Start-SleepSafe -Times 2
        }
    }

    Context 'ExecutePostInstall' {
        It 'should skip when SkipPostInstallSetup is true' {
            $ctx.Options["SkipPostInstallSetup"] = $true
            Mock Write-Host { }

            { $handler.ExecutePostInstall($ctx) } | Should -Not -Throw
        }

        It 'should show warning when script does not exist' {
            $ctx.Options["PostInstallScript"] = "C:\NonExistent\script.sh"
            Mock Test-Path { return $false }
            Mock Write-Host { }

            { $handler.ExecutePostInstall($ctx) } | Should -Not -Throw
        }

        It 'should use wslpath output when wslpath call succeeds' {
            $scriptFile = Join-Path $TestDrive "postinstall.sh"
            New-Item $scriptFile -ItemType File -Force | Out-Null
            $ctx.Options["PostInstallScript"] = $scriptFile
            $script:execCmd = ""
            Mock Invoke-Wsl {
                param($Arguments)
                if ($Arguments -contains "wslpath") {
                    $global:LASTEXITCODE = 0
                    return "/mnt/c/test/postinstall.sh"
                }
                # 実行呼び出し: sh -lc cmd
                $script:execCmd = $Arguments[-1]
                $global:LASTEXITCODE = 0
            }
            Mock Write-Host { }

            $handler.ExecutePostInstall($ctx)

            $script:execCmd | Should -Match '/mnt/c/test/postinstall\.sh'
        }

        It 'should fall back to /mnt/ path when wslpath call fails' {
            $scriptFile = Join-Path $TestDrive "postinstall.sh"
            New-Item $scriptFile -ItemType File -Force | Out-Null
            $ctx.Options["PostInstallScript"] = $scriptFile
            $script:execCmd = ""
            Mock Invoke-Wsl {
                param($Arguments)
                if ($Arguments -contains "wslpath") {
                    $global:LASTEXITCODE = 1
                    return ""
                }
                $script:execCmd = $Arguments[-1]
                $global:LASTEXITCODE = 0
            }
            Mock Write-Host { }

            $handler.ExecutePostInstall($ctx)

            $script:execCmd | Should -Match '/mnt/[a-z]/'
        }
    }

    Context 'EnsureDockerGroup' {
        BeforeEach {
            Mock Write-Host { }
        }

        It 'should add user to docker group' {
            $script:wslCmd = ""
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "whoami") {
                    $global:LASTEXITCODE = 0
                    return "nixos"
                }
                $script:wslCmd = $argStr
                $global:LASTEXITCODE = 0
                return ""
            }

            $handler.EnsureDockerGroup("NixOS")

            $script:wslCmd | Should -Match "groupadd docker"
            $script:wslCmd | Should -Match "usermod -aG docker nixos"
        }

        It 'should fall back to nixos user when whoami fails' {
            $script:wslCmd = ""
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "whoami") {
                    $global:LASTEXITCODE = 1
                    return ""
                }
                $script:wslCmd = $argStr
                $global:LASTEXITCODE = 0
                return ""
            }

            $handler.EnsureDockerGroup("NixOS")

            $script:wslCmd | Should -Match "usermod -aG docker nixos"
        }

        It 'should not throw when docker group command fails' {
            Mock Invoke-Wsl {
                $global:LASTEXITCODE = 1
                return ""
            }

            { $handler.EnsureDockerGroup("NixOS") } | Should -Not -Throw
        }
    }
}
