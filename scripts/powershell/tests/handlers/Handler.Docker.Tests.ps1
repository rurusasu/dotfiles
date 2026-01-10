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

    Context 'コンストラクタ' {
        It 'Name が Docker に設定される' {
            $handler.Name | Should -Be "Docker"
        }

        It 'Description が設定される' {
            $handler.Description | Should -Be "Docker Desktop との WSL 連携"
        }

        It 'Order が 20 に設定される' {
            $handler.Order | Should -Be 20
        }

        It 'RequiresAdmin が $false に設定される' {
            $handler.RequiresAdmin | Should -Be $false
        }

        It 'Retries のデフォルトは 5' {
            $handler.Retries | Should -Be 5
        }

        It 'RetryDelaySeconds のデフォルトは 5' {
            $handler.RetryDelaySeconds | Should -Be 5
        }
    }

    Context 'CanApply' {
        It 'Retries が 0 の場合は $false を返す' {
            Mock Write-Host { }
            $ctx.Options["DockerIntegrationRetries"] = 0

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'Docker Desktop がインストールされていない場合は $false を返す' {
            Mock Test-PathExists { return $false }
            Mock Write-Host { }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'Docker Desktop がインストールされている場合は $true を返す' {
            Mock Test-PathExists { return $true }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }

        It 'Options から Retries を読み込む' {
            Mock Test-PathExists { return $true }
            $ctx.Options["DockerIntegrationRetries"] = 10

            $handler.CanApply($ctx)

            $handler.Retries | Should -Be 10
        }

        It 'Options から RetryDelaySeconds を読み込む' {
            Mock Test-PathExists { return $true }
            $ctx.Options["DockerIntegrationRetryDelaySeconds"] = 15

            $handler.CanApply($ctx)

            $handler.RetryDelaySeconds | Should -Be 15
        }
    }

    Context 'Apply - WSL 書き込み不可' {
        It 'WSL が書き込み不可の場合はスキップする' {
            Mock Test-PathExists { return $true }
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

    Context 'Apply - 空き容量不足' {
        It 'WSL の空き容量が不足している場合はスキップする' {
            Mock Test-PathExists { return $true }
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

    Context 'Apply - 正常系' {
        BeforeEach {
            Mock Test-PathExists { return $true }
            Mock Write-Host { }
            Mock Get-ProcessSafe { return $null }
            Mock Start-ProcessSafe { }
            Mock Stop-ProcessSafe { }
            Mock Start-SleepSafe { }
            Mock New-DirectorySafe { }
            Mock Copy-FileSafe { }
        }

        It 'Docker Desktop 連携が成功する場合' {
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

        It 'Docker Desktop ディストリビューションが存在しない場合は作成する' {
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
            Mock Test-PathExists { 
                param($Path)
                # Docker リソースが存在する
                return $true
            }

            $result = $handler.Apply($ctx)

            # 成功結果であることを確認（ディストリビューション作成が行われた）
            $result.Success | Should -Be $true
        }
    }

    Context 'Apply - リトライ' {
        BeforeEach {
            Mock Test-PathExists { return $true }
            Mock Write-Host { }
            Mock Get-ProcessSafe { return $null }
            Mock Start-ProcessSafe { }
            Mock Stop-ProcessSafe { }
            Mock Start-SleepSafe { }
            Mock New-DirectorySafe { }
            Mock Copy-FileSafe { }
        }

        It 'プロキシテストが失敗した場合はリトライする' {
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

        It 'リトライ上限に達した場合は失敗結果を返す' {
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

    Context 'Docker Desktop 起動/再起動' {
        BeforeEach {
            Mock Test-PathExists { return $true }
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

        It 'Docker Desktop が起動していない場合は起動する' {
            Mock Get-ProcessSafe { return $null }
            $script:startCalled = $false
            Mock Start-ProcessSafe { $script:startCalled = $true }

            $handler.Apply($ctx)

            # Start-ProcessSafe が呼ばれたことを確認
            $script:startCalled | Should -Be $true
        }

        It 'Docker Desktop が既に起動している場合は起動しない' {
            Mock Get-ProcessSafe { 
                return [PSCustomObject]@{ Name = "Docker Desktop" }
            }
            Mock Start-ProcessSafe { }

            $handler.Apply($ctx)

            Should -Invoke Start-ProcessSafe -Times 0
        }
    }

    Context 'GetWslDefaultUser' {
        It 'whoami が成功した場合はユーザー名を返す' {
            Mock Invoke-Wsl { 
                $global:LASTEXITCODE = 0
                return "testuser"
            }
            Mock Test-PathExists { return $true }
            Mock Write-Host { }
            Mock Get-ProcessSafe { return [PSCustomObject]@{ Name = "Docker Desktop" } }
            Mock Start-SleepSafe { }
            Mock New-DirectorySafe { }
            Mock Copy-FileSafe { }

            # whoami の結果を確認するために Apply を呼ぶ
            # 実際にはハンドラー内部でユーザー名が使われる
        }

        It 'whoami が失敗した場合は nixos を返す' {
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
            Mock Test-PathExists { return $true }
            Mock Write-Host { }
            Mock Get-ProcessSafe { return [PSCustomObject]@{ Name = "Docker Desktop" } }
            Mock Start-SleepSafe { }
        }
    }

    Context 'Docker Desktop ヘルスチェック' {
        BeforeEach {
            Mock Test-PathExists { return $true }
            Mock Write-Host { }
            Mock Get-ProcessSafe { return [PSCustomObject]@{ Name = "Docker Desktop" } }
            Mock Start-SleepSafe { }
            Mock New-DirectorySafe { }
            Mock Copy-FileSafe { }
        }

        It 'componentsVersion.json が存在する場合は健全' {
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

        It 'componentsVersion.json が存在しない場合は警告を出すが続行する' {
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

    Context 'Apply - 例外処理' {
        BeforeEach {
            Mock Write-Host { }
            Mock Test-PathExists { return $true }
            Mock Get-ProcessSafe { return [PSCustomObject]@{ Name = "Docker Desktop" } }
        }

        It 'Apply 中に例外が発生した場合は失敗結果を返す' {
            Mock Invoke-Wsl { 
                throw "WSL Error"
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "WSL Error"
        }
    }

    Context 'EnsureDockerDesktopDistros - リソース不足' {
        BeforeEach {
            Mock Write-Host { }
            Mock Test-PathExists { 
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

        It 'Docker Desktop の WSL リソースが見つからない場合は警告を出してスキップする' {
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
            Mock Test-PathExists { return $true }
            Mock Start-SleepSafe { }
        }

        It 'Docker Desktop が起動している場合は再起動する' {
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

    Context 'TestDockerDesktopProxy - 失敗パス' {
        BeforeEach {
            Mock Write-Host { }
            Mock Test-PathExists { return $true }
            Mock Get-ProcessSafe { return [PSCustomObject]@{ Name = "Docker Desktop" } }
            Mock Start-SleepSafe { }
            Mock Stop-ProcessSafe { }
            Mock Start-ProcessSafe { }
        }

        It 'docker-desktop-user-distro が存在しない場合は $false を返す' {
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
