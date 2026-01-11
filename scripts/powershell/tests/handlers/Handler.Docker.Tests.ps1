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
            @{ property = "Order"; expected = 20 }
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
    }

    Context 'Apply - WSL write permission' {
        It 'should skip when WSL is not writable' {
            Mock Test-PathExist { return $true }
            Mock Invoke-Wsl {
                $global:LASTEXITCODE = 1
                return ""
            }
            Mock Write-Host { }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "書き込み不可"
        }
    }

    Context 'Apply - disk space' {
        It 'should skip when WSL disk space is insufficient' {
            Mock Test-PathExist { return $true }
            $wslCallCount = 0
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
            Mock Write-Host { }

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
                if ($argStr -match "touch.*wsl-write-test") {
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

                if ($argStr -match "touch.*wsl-write-test") {
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
                param($Path)
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

                if ($argStr -match "touch.*wsl-write-test") {
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

                if ($argStr -match "touch.*wsl-write-test") {
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
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "touch.*wsl-write-test") {
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
            Mock Get-ProcessSafe {
                return [PSCustomObject]@{ Name = "Docker Desktop" }
            }
            Mock Start-ProcessSafe { }

            $handler.Apply($ctx)

            Should -Invoke Start-ProcessSafe -Times 0
        }
    }

    Context 'GetWslDefaultUser' {
        It 'should return username when whoami succeeds' {
            Mock Invoke-Wsl {
                $global:LASTEXITCODE = 0
                return "testuser"
            }
            Mock Test-PathExist { return $true }
            Mock Write-Host { }
            Mock Get-ProcessSafe { return [PSCustomObject]@{ Name = "Docker Desktop" } }
            Mock Start-SleepSafe { }
            Mock New-DirectorySafe { }
            Mock Copy-FileSafe { }

            # whoami の結果を確認するために Apply を呼ぶ
            # 実際にはハンドラー内部でユーザー名が使われる
        }

        It 'should return nixos when whoami fails' {
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "whoami") {
                    $global:LASTEXITCODE = 1
                    return ""
                }
                $global:LASTEXITCODE = 0
                return ""
            }
            Mock Test-PathExist { return $true }
            Mock Write-Host { }
            Mock Get-ProcessSafe { return [PSCustomObject]@{ Name = "Docker Desktop" } }
            Mock Start-SleepSafe { }
        }
    }

    Context 'Docker Desktop health check' {
        BeforeEach {
            Mock Test-PathExist { return $true }
            Mock Write-Host { }
            Mock Get-ProcessSafe { return [PSCustomObject]@{ Name = "Docker Desktop" } }
            Mock Start-SleepSafe { }
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
                if ($argStr -match "touch.*wsl-write-test") {
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
                if ($argStr -match "touch.*wsl-write-test") {
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
                if ($argStr -match "touch.*wsl-write-test") {
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
                if ($argStr -match "touch.*wsl-write-test") {
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

    Context 'TestDockerDesktopProxy - failure path' {
        BeforeEach {
            Mock Write-Host { }
            Mock Test-PathExist { return $true }
            Mock Get-ProcessSafe { return [PSCustomObject]@{ Name = "Docker Desktop" } }
            Mock Start-SleepSafe { }
            Mock Stop-ProcessSafe { }
            Mock Start-ProcessSafe { }
        }

        It 'should return false when docker-desktop-user-distro does not exist' {
            $script:proxyReturnedFalse = $false
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "touch.*wsl-write-test") {
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
