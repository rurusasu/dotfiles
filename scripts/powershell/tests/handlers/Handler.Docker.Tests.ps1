#Requires -Module Pester

<#
.SYNOPSIS
    Handler.Docker.ps1 のユニットテスト

.DESCRIPTION
    DockerHandler クラスのテスト
    100% カバレッジを目標とする
#>

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.Docker.ps1
}

Describe 'DockerHandler' {
    BeforeEach {
        $script:handler = [DockerHandler]::new()
        $script:ctx = [SetupContext]::new("D:\dotfiles")
    }

    Context 'Constructor' {
        It 'should set <property> to <expected>' -ForEach @(
            @{ property = "Name"; expected = "Docker" }
            @{ property = "Description"; expected = "Docker Desktop との WSL 連携" }
            @{ property = "Order"; expected = 18 }
            @{ property = "RequiresAdmin"; expected = $false }
            @{ property = "Retries"; expected = 5 }
            @{ property = "RetryDelaySeconds"; expected = 5 }
        ) {
            $handler.$property | Should -Be $expected
        }
    }

    Context 'CanApply' {
        It 'should return false when Retries is 0' {
            Mock Write-Host { }
            $ctx.Options["DockerIntegrationRetries"] = 0

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'should return false when Docker Desktop is not installed' {
            Mock Test-PathExist { return $false }
            Mock Write-Host { }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'should return true when Docker Desktop is installed' {
            Mock Test-PathExist { return $true }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }

        It 'should read Retries from Options' {
            Mock Test-PathExist { return $true }
            $ctx.Options["DockerIntegrationRetries"] = 10

            $handler.CanApply($ctx)

            $handler.Retries | Should -Be 10
        }

        It 'should read RetryDelaySeconds from Options' {
            Mock Test-PathExist { return $true }
            $ctx.Options["DockerIntegrationRetryDelaySeconds"] = 15

            $handler.CanApply($ctx)

            $handler.RetryDelaySeconds | Should -Be 15
        }

        It 'should read WslWritableMaxAttempts from Options' {
            Mock Test-PathExist { return $true }
            $ctx.Options["WslWritableMaxAttempts"] = 12

            $handler.CanApply($ctx)

            $handler.WslWritableMaxAttempts | Should -Be 12
        }

        It 'should default WslWritableMaxAttempts to 8' {
            Mock Test-PathExist { return $true }

            $handler.CanApply($ctx)

            $handler.WslWritableMaxAttempts | Should -Be 8
        }
    }

    Context 'Apply - WSL write permission' {
        BeforeEach {
            Mock Write-Host { }
            Mock Test-PathExist { return $true }
            # Docker Desktop が実際に起動/停止しないようにモック
            Mock Get-ProcessSafe { return $null }
            Mock Start-ProcessSafe { }
            Mock Stop-ProcessSafe { }
            Mock Stop-Process { }
            Mock Start-SleepSafe { }
        }

        It 'should skip when WSL is not writable after all 4 retries' {
            $handler.WslWritableMaxAttempts = 4
            $script:writableCallCount = 0
            $script:sleepDelays = @()
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "wsl-write-test") {
                    $script:writableCallCount++
                    $global:LASTEXITCODE = 1
                    return ""
                }
                return ""
            }
            Mock Start-SleepSafe {
                param($Seconds)
                $script:sleepDelays += $Seconds
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "書き込み不可"
            # WaitForWslWritable は maxAttempts=4 回 TestWslWritable を呼ぶ
            $script:writableCallCount | Should -Be 4
            # 試行間のバックオフ: 3秒, 6秒, 9秒（最後の試行後は sleep しない）
            $script:sleepDelays | Should -Contain 3
            $script:sleepDelays | Should -Contain 6
            $script:sleepDelays | Should -Contain 9
        }

        It 'should succeed when WSL becomes writable on 3rd attempt' {
            $script:writableCallCount = 0
            $script:sleepDelays = @()
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "

                if ($argStr -match "wsl-write-test") {
                    $script:writableCallCount++
                    if ($script:writableCallCount -le 2) {
                        $global:LASTEXITCODE = 1
                    } else {
                        $global:LASTEXITCODE = 0
                    }
                    return ""
                }
                if ($argStr -match "df -Pk") {
                    return "50000"
                }
                if ($argStr -match "-l -q") {
                    return @("docker-desktop", "docker-desktop-data", "NixOS")
                }
                if ($argStr -match "groupadd|whoami") {
                    return "nixos"
                }
                if ($argStr -match "componentsVersion.json") {
                    $global:LASTEXITCODE = 0
                }
                if ($argStr -match "docker-desktop-user-distro") {
                    $global:LASTEXITCODE = 0
                }
                if ($argStr -match "proxy") {
                    $global:LASTEXITCODE = 0
                }
                return ""
            }
            Mock Start-SleepSafe {
                param($Seconds)
                $script:sleepDelays += $Seconds
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "連携を確認しました"
            # 3回目で成功するので TestWslWritable は正確に3回呼ばれる
            $script:writableCallCount | Should -Be 3
            # 試行間のバックオフ: 3秒, 6秒（3回目で成功するので9秒の sleep はない）
            $script:sleepDelays | Should -Contain 3
            $script:sleepDelays | Should -Contain 6
            $script:sleepDelays | Should -Not -Contain 9
        }

        It 'should succeed immediately when WSL is writable on first attempt' {
            $script:writableCallCount = 0
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "

                if ($argStr -match "wsl-write-test") {
                    $script:writableCallCount++
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "df -Pk") {
                    return "50000"
                }
                if ($argStr -match "-l -q") {
                    return @("docker-desktop", "docker-desktop-data", "NixOS")
                }
                if ($argStr -match "groupadd|whoami") {
                    return "nixos"
                }
                if ($argStr -match "componentsVersion.json") {
                    $global:LASTEXITCODE = 0
                }
                if ($argStr -match "docker-desktop-user-distro") {
                    $global:LASTEXITCODE = 0
                }
                if ($argStr -match "proxy") {
                    $global:LASTEXITCODE = 0
                }
                return ""
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            # 1回目で成功するので TestWslWritable は1回だけ
            $script:writableCallCount | Should -Be 1
        }

        It 'should log retry messages with attempt count' {
            $handler.WslWritableMaxAttempts = 4
            $script:writableCallCount = 0
            $script:logMessages = @()
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "wsl-write-test") {
                    $script:writableCallCount++
                    $global:LASTEXITCODE = 1
                    return ""
                }
                return ""
            }
            Mock Write-Host {
                param($Object)
                if ($Object -match "再試行します") {
                    $script:logMessages += $Object
                }
            }

            $handler.Apply($ctx)

            # 4回試行、最後の試行後はログなし → 3回ログが出る
            $script:logMessages.Count | Should -Be 3
            $script:logMessages[0] | Should -Match "1/4"
            $script:logMessages[1] | Should -Match "2/4"
            $script:logMessages[2] | Should -Match "3/4"
        }

        It 'should call EnsureDockerGroup before StartDockerDesktopIfNeeded' {
            # Docker Desktop 起動が wsl --shutdown を呼ぶ場合があるため
            # NixOS への groupadd は Docker 起動前に完了させる必要がある
            $script:callOrder = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "wsl-write-test") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "groupadd") { $script:callOrder.Add("groupadd"); $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "whoami") { $global:LASTEXITCODE = 0; return "nixos" }
                if ($argStr -match "df -Pk") { return "50000" }
                if ($argStr -match "-l -q") { return @("docker-desktop", "docker-desktop-data", "NixOS") }
                if ($argStr -match "componentsVersion.json|docker-desktop-user-distro|proxy") { $global:LASTEXITCODE = 0 }
                return ""
            }
            Mock Start-ProcessSafe { $script:callOrder.Add("startDocker") }

            $handler.Apply($ctx)

            $groupaddIndex = $script:callOrder.IndexOf("groupadd")
            $startIndex = $script:callOrder.IndexOf("startDocker")
            $groupaddIndex | Should -BeGreaterOrEqual 0
            $startIndex | Should -BeGreaterOrEqual 0
            $groupaddIndex | Should -BeLessThan $startIndex
        }

        It 'should use sh -c (not sh -lc) for write test to avoid NixOS /etc/profile failure' {
            # NixOS 早期 boot 時に sh -lc が /etc/profile sourcing に失敗するため
            # sh -c を使うことをリグレッションテストで保証する
            $script:writeCmdArgs = $null
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "wsl-write-test") {
                    $script:writeCmdArgs = $Arguments
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "df -Pk") { return "50000" }
                if ($argStr -match "-l -q") { return @("docker-desktop", "docker-desktop-data", "NixOS") }
                if ($argStr -match "groupadd|whoami") { $global:LASTEXITCODE = 0; return "nixos" }
                if ($argStr -match "componentsVersion.json|docker-desktop-user-distro|proxy") { $global:LASTEXITCODE = 0 }
                return ""
            }

            $handler.Apply($ctx)

            $script:writeCmdArgs | Should -Not -BeNullOrEmpty
            $script:writeCmdArgs | Should -Contain "sh"
            $script:writeCmdArgs | Should -Contain "-c"
            $script:writeCmdArgs | Should -Not -Contain "-lc"
        }
    }

    Context 'Apply - disk space' {
        BeforeEach {
            Mock Write-Host { }
            Mock Test-PathExist { return $true }
            # Docker Desktop が実際に起動/停止しないようにモック
            Mock Get-ProcessSafe { return $null }
            Mock Start-ProcessSafe { }
            Mock Stop-ProcessSafe { }
            Mock Stop-Process { }
            Mock Start-SleepSafe { }
        }

        It 'should skip when WSL disk space is insufficient' {
            $script:wslCallCount = 0
            Mock Invoke-Wsl {
                $script:wslCallCount++
                if ($script:wslCallCount -eq 1) {
                    # 書き込みテスト - 成功
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($script:wslCallCount -eq 2) {
                    # 空き容量チェック - 不足
                    return "5000"  # 10240 未満
                }
                return ""
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "空き容量不足"
        }
    }

    Context 'Apply - success cases' {
        BeforeEach {
            Mock Test-PathExist { return $true }
            Mock Write-Host { }
            Mock Get-ProcessSafe { return $null }
            Mock Start-ProcessSafe { }
            Mock Stop-ProcessSafe { }
            Mock Start-SleepSafe { }
            Mock New-DirectorySafe { }
            Mock Copy-FileSafe { }
        }

        It 'should succeed when Docker Desktop integration succeeds' {
            $wslCallCount = 0
            Mock Invoke-Wsl {
                param($Arguments)
                $script:wslCallCount++
                $argStr = $Arguments -join " "

                # 書き込みテスト
                if ($argStr -match "wsl-write-test") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                # 空き容量チェック
                if ($argStr -match "df -Pk") {
                    return "50000"
                }
                # ディストリビューション一覧
                if ($argStr -match "-l -q") {
                    return @("docker-desktop", "docker-desktop-data", "NixOS")
                }
                # グループ追加
                if ($argStr -match "groupadd") {
                    return ""
                }
                # whoami
                if ($argStr -match "whoami") {
                    return "nixos"
                }
                # Docker Desktop ヘルスチェック
                if ($argStr -match "componentsVersion.json") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                # プロキシテスト - 存在確認
                if ($argStr -match "docker-desktop-user-distro \]") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                # プロキシテスト - 実行
                if ($argStr -match "proxy --distro-name") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                return ""
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "連携を確認しました"
        }

        It 'should create Docker Desktop distribution when it does not exist' {
            $wslCallCount = 0
            Mock Invoke-Wsl {
                param($Arguments)
                $script:wslCallCount++
                $argStr = $Arguments -join " "

                if ($argStr -match "wsl-write-test") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "df -Pk") {
                    return "50000"
                }
                if ($argStr -match "-l -q") {
                    return @("NixOS")  # Docker ディストリビューションなし
                }
                if ($argStr -match "--import-in-place") {
                    return ""
                }
                if ($argStr -match "--import docker-desktop-data") {
                    return ""
                }
                if ($argStr -match "groupadd") {
                    return ""
                }
                if ($argStr -match "whoami") {
                    return "nixos"
                }
                if ($argStr -match "componentsVersion.json") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "docker-desktop-user-distro \]") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "proxy --distro-name") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                return ""
            }
            Mock Test-PathExist {
                # Docker リソースが存在する
                return $true
            }

            $result = $handler.Apply($ctx)

            # 成功結果であることを確認（ディストリビューション作成が行われた）
            $result.Success | Should -Be $true
        }
    }

    Context 'Apply - retry' {
        BeforeEach {
            Mock Test-PathExist { return $true }
            Mock Write-Host { }
            Mock Get-ProcessSafe { return $null }
            Mock Start-ProcessSafe { }
            Mock Stop-ProcessSafe { }
            Mock Start-SleepSafe { }
            Mock New-DirectorySafe { }
            Mock Copy-FileSafe { }
        }

        It 'should retry when proxy test fails' {
            $ctx.Options["DockerIntegrationRetries"] = 2
            $proxyTestCount = 0

            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "

                if ($argStr -match "wsl-write-test") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "df -Pk") {
                    return "50000"
                }
                if ($argStr -match "-l -q") {
                    return @("docker-desktop", "docker-desktop-data", "NixOS")
                }
                if ($argStr -match "groupadd") {
                    return ""
                }
                if ($argStr -match "whoami") {
                    return "nixos"
                }
                if ($argStr -match "componentsVersion.json") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "docker-desktop-user-distro \]") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "proxy --distro-name") {
                    $script:proxyTestCount++
                    if ($script:proxyTestCount -lt 2) {
                        $global:LASTEXITCODE = 1  # 失敗
                    } else {
                        $global:LASTEXITCODE = 0  # 成功
                    }
                    return ""
                }
                if ($argStr -match "--shutdown") {
                    return ""
                }
                return ""
            }

            $handler.CanApply($ctx)
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
        }

        It 'should fail when retry limit is reached' {
            $ctx.Options["DockerIntegrationRetries"] = 2

            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "

                if ($argStr -match "wsl-write-test") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "df -Pk") {
                    return "50000"
                }
                if ($argStr -match "-l -q") {
                    return @("docker-desktop", "docker-desktop-data", "NixOS")
                }
                if ($argStr -match "groupadd") {
                    return ""
                }
                if ($argStr -match "whoami") {
                    return "nixos"
                }
                if ($argStr -match "componentsVersion.json") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "docker-desktop-user-distro \]") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "proxy --distro-name") {
                    $global:LASTEXITCODE = 1  # 常に失敗
                    return ""
                }
                if ($argStr -match "--shutdown") {
                    return ""
                }
                return ""
            }

            $handler.CanApply($ctx)
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "2 回失敗"
        }
    }

    Context 'Docker Desktop start/restart' {
        BeforeEach {
            Mock Test-PathExist { return $true }
            Mock Write-Host { }
            Mock Start-SleepSafe { }
            Mock New-DirectorySafe { }
            Mock Copy-FileSafe { }
            Mock Stop-ProcessSafe { }
            Mock Stop-Process { }
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "wsl-write-test") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "df -Pk") {
                    return "50000"
                }
                if ($argStr -match "-l -q") {
                    return @("docker-desktop", "docker-desktop-data", "NixOS")
                }
                if ($argStr -match "groupadd|whoami") {
                    return "nixos"
                }
                if ($argStr -match "componentsVersion.json") {
                    $global:LASTEXITCODE = 0
                }
                if ($argStr -match "docker-desktop-user-distro") {
                    $global:LASTEXITCODE = 0
                }
                if ($argStr -match "proxy") {
                    $global:LASTEXITCODE = 0
                }
                return ""
            }
        }

        It 'should start Docker Desktop when not running' {
            Mock Get-ProcessSafe { return $null }
            $script:startCalled = $false
            Mock Start-ProcessSafe { $script:startCalled = $true }

            $handler.Apply($ctx)

            # Start-ProcessSafe が呼ばれたことを確認
            $script:startCalled | Should -Be $true
        }

        It 'should not start Docker Desktop when already running' {
            # Docker Desktop だけが動いており、残留プロセスはない
            Mock Get-ProcessSafe {
                param($Name)
                if ($Name -eq "Docker Desktop" -or $Name -eq "com.docker.backend") {
                    return [PSCustomObject]@{ Name = $Name }
                }
                return $null
            }
            Mock Start-ProcessSafe { }

            $handler.Apply($ctx)

            Should -Invoke Start-ProcessSafe -Times 0
        }
    }

    Context 'GetWslDefaultUser' {
        BeforeEach {
            Mock Test-PathExist { return $true }
            Mock Write-Host { }
            Mock Start-SleepSafe { }
            Mock New-DirectorySafe { }
            Mock Copy-FileSafe { }
            Mock Stop-ProcessSafe { }
            Mock Stop-Process { }
            Mock Get-ProcessSafe { return [PSCustomObject]@{ Name = "Docker Desktop" } }
        }

        It 'should use whoami result as user in docker group setup' {
            $script:usermodCmd = ""
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "wsl-write-test") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "df -Pk") { return "50000" }
                if ($argStr -match "-l -q") { return @("docker-desktop", "docker-desktop-data", "NixOS") }
                if ($argStr -match "whoami") { $global:LASTEXITCODE = 0; return "testuser" }
                if ($argStr -match "groupadd") { $script:usermodCmd = $argStr }
                if ($argStr -match "componentsVersion.json") { $global:LASTEXITCODE = 0 }
                if ($argStr -match "docker-desktop-user-distro") { $global:LASTEXITCODE = 0 }
                if ($argStr -match "proxy") { $global:LASTEXITCODE = 0 }
                return ""
            }

            $handler.Apply($ctx)

            $script:usermodCmd | Should -Match "testuser"
        }

        It 'should fall back to nixos when whoami fails' {
            $script:usermodCmd = ""
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "wsl-write-test") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "df -Pk") { return "50000" }
                if ($argStr -match "-l -q") { return @("docker-desktop", "docker-desktop-data", "NixOS") }
                if ($argStr -match "whoami") { $global:LASTEXITCODE = 1; return "" }
                if ($argStr -match "groupadd") { $script:usermodCmd = $argStr }
                if ($argStr -match "componentsVersion.json") { $global:LASTEXITCODE = 0 }
                if ($argStr -match "docker-desktop-user-distro") { $global:LASTEXITCODE = 0 }
                if ($argStr -match "proxy") { $global:LASTEXITCODE = 0 }
                return ""
            }

            $handler.Apply($ctx)

            $script:usermodCmd | Should -Match "nixos"
        }
    }

    Context 'Docker Desktop health check' {
        BeforeEach {
            Mock Test-PathExist { return $true }
            Mock Write-Host { }
            # Docker Desktop だけが動いており、残留プロセスはない（StopLingeringDockerProcesses が早期リターンするよう）
            Mock Get-ProcessSafe {
                param($Name)
                if ($Name -eq "Docker Desktop" -or $Name -eq "com.docker.backend") {
                    return [PSCustomObject]@{ Name = $Name }
                }
                return $null
            }
            Mock Start-SleepSafe { }
            Mock Stop-ProcessSafe { }
            Mock Stop-Process { }
            Mock New-DirectorySafe { }
            Mock Copy-FileSafe { }
        }

        It 'should be healthy when componentsVersion.json exists' {
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "componentsVersion.json") {
                    $global:LASTEXITCODE = 0
                }
                if ($argStr -match "wsl-write-test") {
                    $global:LASTEXITCODE = 0
                }
                if ($argStr -match "df -Pk") {
                    return "50000"
                }
                if ($argStr -match "-l -q") {
                    return @("docker-desktop", "docker-desktop-data", "NixOS")
                }
                if ($argStr -match "docker-desktop-user-distro") {
                    $global:LASTEXITCODE = 0
                }
                if ($argStr -match "proxy") {
                    $global:LASTEXITCODE = 0
                }
                return "nixos"
            }

            $result = $handler.Apply($ctx)

            # 警告なしで成功
            $result.Success | Should -Be $true
        }

        It 'should warn but continue when componentsVersion.json does not exist' {
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "componentsVersion.json") {
                    $global:LASTEXITCODE = 1  # 存在しない
                }
                if ($argStr -match "wsl-write-test") {
                    $global:LASTEXITCODE = 0
                }
                if ($argStr -match "df -Pk") {
                    return "50000"
                }
                if ($argStr -match "-l -q") {
                    return @("docker-desktop", "docker-desktop-data", "NixOS")
                }
                if ($argStr -match "docker-desktop-user-distro") {
                    $global:LASTEXITCODE = 0
                }
                if ($argStr -match "proxy") {
                    $global:LASTEXITCODE = 0
                }
                return "nixos"
            }

            $handler.Apply($ctx)

            # 警告が出るがテストは続行される
            Should -Invoke Write-Host -ParameterFilter {
                $Object -match "壊れている可能性"
            }
        }
    }

    Context 'Apply - exception handling' {
        BeforeEach {
            Mock Write-Host { }
            Mock Test-PathExist { return $true }
            Mock Get-ProcessSafe { return [PSCustomObject]@{ Name = "Docker Desktop" } }
            Mock Stop-Process { }
            Mock Stop-ProcessSafe { }
            Mock Start-SleepSafe { }
        }

        It 'should return failure when exception is thrown during Apply' {
            Mock Invoke-Wsl {
                throw "WSL Error"
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "WSL Error"
        }
    }

    Context 'EnsureDockerDesktopDistros - missing resources' {
        BeforeEach {
            Mock Write-Host { }
            Mock Test-PathExist {
                param($Path)
                # Docker Desktop の WSL リソースが存在しない
                if ($Path -like "*Docker\Docker\resources\wsl*") {
                    return $false
                }
                return $true
            }
            Mock Get-ProcessSafe { return [PSCustomObject]@{ Name = "Docker Desktop" } }
            Mock Start-SleepSafe { }
            Mock Stop-Process { }
            Mock Stop-ProcessSafe { }
        }

        It 'should warn and skip when Docker Desktop WSL resources are not found' {
            $script:warningShown = $false
            Mock Write-Host {
                param($Object)
                if ($Object -match "WSL リソースが見つからない") {
                    $script:warningShown = $true
                }
            }
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "wsl-write-test") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "df -Pk") {
                    return "50000"
                }
                if ($argStr -match "-l -q") {
                    # docker-desktop が存在しない
                    return @("NixOS")
                }
                if ($argStr -match "docker-desktop-user-distro") {
                    $global:LASTEXITCODE = 1
                }
                return ""
            }

            $handler.Apply($ctx)

            $script:warningShown | Should -Be $true
        }
    }

    Context 'RestartDockerDesktop' {
        BeforeEach {
            Mock Write-Host { }
            Mock Test-PathExist { return $true }
            Mock Start-SleepSafe { }
        }

        It 'should restart Docker Desktop when it is running' {
            $script:stopCalled = $false
            $script:startCalled = $false
            $script:restartLogShown = $false

            Mock Get-ProcessSafe {
                param($Name)
                if ($Name -eq "Docker Desktop") {
                    return [PSCustomObject]@{ Name = "Docker Desktop" }
                }
                return $null
            }
            Mock Stop-ProcessSafe { $script:stopCalled = $true }
            Mock Stop-Process { }
            Mock Start-ProcessSafe { $script:startCalled = $true }
            Mock Write-Host {
                param($Object)
                if ($Object -match "再起動します") {
                    $script:restartLogShown = $true
                }
            }
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "wsl-write-test") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "df -Pk") {
                    return "50000"
                }
                if ($argStr -match "-l -q") {
                    return @("docker-desktop", "docker-desktop-data", "NixOS")
                }
                if ($argStr -match "docker-desktop-user-distro") {
                    # 最初は失敗、RestartDockerDesktop 後は成功
                    $global:LASTEXITCODE = 1
                }
                if ($argStr -match "proxy") {
                    $global:LASTEXITCODE = 1
                }
                return ""
            }
            $handler.Retries = 1
            $handler.RetryDelaySeconds = 0

            $handler.Apply($ctx)

            # 再起動ログが表示される
            $script:restartLogShown | Should -Be $true
            $script:stopCalled | Should -Be $true
        }
    }

    Context 'StopAllDockerProcesses' {
        BeforeEach {
            Mock Write-Host { }
            Mock Test-PathExist { return $true }
            Mock Start-SleepSafe { }
            Mock Start-ProcessSafe { }
        }

        It 'should stop all Docker-related processes including com.docker.build' {
            $script:stoppedProcesses = @()

            Mock Get-ProcessSafe {
                param($Name)
                # com.docker.build を含む複数のプロセスが実行中
                if ($Name -in @("Docker Desktop", "com.docker.backend", "com.docker.build")) {
                    return [PSCustomObject]@{ Name = $Name }
                }
                return $null
            }
            Mock Stop-ProcessSafe {
                param($Name)
                $script:stoppedProcesses += $Name
            }
            Mock Stop-Process { }
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "wsl-write-test") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "df -Pk") {
                    return "50000"
                }
                if ($argStr -match "-l -q") {
                    return @("docker-desktop", "docker-desktop-data", "NixOS")
                }
                if ($argStr -match "docker-desktop-user-distro") {
                    $global:LASTEXITCODE = 1
                }
                if ($argStr -match "proxy") {
                    $global:LASTEXITCODE = 1
                }
                return ""
            }
            $handler.Retries = 1
            $handler.RetryDelaySeconds = 0

            $handler.Apply($ctx)

            # com.docker.build が終了対象に含まれることを確認
            $script:stoppedProcesses | Should -Contain "Docker Desktop"
            $script:stoppedProcesses | Should -Contain "com.docker.backend"
            $script:stoppedProcesses | Should -Contain "com.docker.build"
        }

        It 'should force kill lingering processes after initial stop attempt' {
            $script:forceKillCalled = $false
            $callCount = 0

            Mock Get-ProcessSafe {
                param($Name)
                $script:callCount++
                # 最初のループでは全プロセス存在、2回目のループでもまだ com.docker.build が残っている
                if ($Name -eq "com.docker.build") {
                    return [PSCustomObject]@{ Name = $Name }
                }
                if ($script:callCount -le 7 -and $Name -eq "Docker Desktop") {
                    return [PSCustomObject]@{ Name = $Name }
                }
                return $null
            }
            Mock Stop-ProcessSafe { }
            Mock Stop-Process {
                param($Name)
                if ($Name -eq "com.docker.build") {
                    $script:forceKillCalled = $true
                }
            }
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "wsl-write-test") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "df -Pk") {
                    return "50000"
                }
                if ($argStr -match "-l -q") {
                    return @("docker-desktop", "docker-desktop-data", "NixOS")
                }
                if ($argStr -match "docker-desktop-user-distro") {
                    $global:LASTEXITCODE = 1
                }
                return ""
            }
            $handler.Retries = 1
            $handler.RetryDelaySeconds = 0

            $handler.Apply($ctx)

            # 強制終了が呼ばれたことを確認
            $script:forceKillCalled | Should -Be $true
        }
    }

    Context 'StopLingeringDockerProcesses' {
        BeforeEach {
            Mock Write-Host { }
            Mock Test-PathExist { return $true }
            Mock Start-SleepSafe { }
        }

        It 'should stop lingering com.docker.build before starting Docker Desktop' {
            $script:lingeringProcessKilled = $false
            $script:dockerDesktopStarted = $false

            Mock Get-ProcessSafe {
                param($Name)
                # Docker Desktop は動いていないが、com.docker.build が残留
                if ($Name -eq "com.docker.build" -and -not $script:lingeringProcessKilled) {
                    return [PSCustomObject]@{ Name = $Name }
                }
                return $null
            }
            Mock Stop-Process {
                param($Name)
                if ($Name -eq "com.docker.build") {
                    $script:lingeringProcessKilled = $true
                }
            }
            Mock Start-ProcessSafe {
                $script:dockerDesktopStarted = $true
            }
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "wsl-write-test") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "df -Pk") {
                    return "50000"
                }
                if ($argStr -match "-l -q") {
                    return @("docker-desktop", "docker-desktop-data", "NixOS")
                }
                if ($argStr -match "docker-desktop-user-distro") {
                    $global:LASTEXITCODE = 0
                }
                if ($argStr -match "proxy") {
                    $global:LASTEXITCODE = 0
                }
                return ""
            }

            $handler.Apply($ctx)

            # 残留プロセスが終了されてからDocker Desktopが起動されることを確認
            $script:lingeringProcessKilled | Should -Be $true
            $script:dockerDesktopStarted | Should -Be $true
        }
    }

    Context 'TestDockerDesktopProxy - failure path' {
        BeforeEach {
            Mock Write-Host { }
            Mock Test-PathExist { return $true }
            Mock Get-ProcessSafe { return [PSCustomObject]@{ Name = "Docker Desktop" } }
            Mock Start-SleepSafe { }
            Mock Stop-ProcessSafe { }
            Mock Stop-Process { }
            Mock Start-ProcessSafe { }
        }

        It 'should return false when docker-desktop-user-distro does not exist' {
            $script:proxyReturnedFalse = $false
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "wsl-write-test") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "df -Pk") {
                    return "50000"
                }
                if ($argStr -match "-l -q") {
                    return @("docker-desktop", "docker-desktop-data", "NixOS")
                }
                if ($argStr -match "componentsVersion") {
                    $global:LASTEXITCODE = 0
                }
                # docker-desktop-user-distro の存在チェックで失敗
                if ($argStr -match "\[ -x.*docker-desktop-user-distro") {
                    $global:LASTEXITCODE = 1
                }
                return ""
            }
            $handler.Retries = 1
            $handler.RetryDelaySeconds = 0

            $result = $handler.Apply($ctx)

            # プロキシテスト失敗により失敗結果
            $result.Success | Should -Be $false
        }
    }
}
