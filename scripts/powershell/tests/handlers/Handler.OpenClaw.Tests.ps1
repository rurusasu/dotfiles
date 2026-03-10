#Requires -Module Pester

<#
.SYNOPSIS
    Handler.OpenClaw.ps1 のユニットテスト

.DESCRIPTION
    OpenClawHandler クラスのテスト
    100% カバレッジを目標とする
#>

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.OpenClaw.ps1
}

Describe 'OpenClawHandler' {
    BeforeEach {
        $script:handler = [OpenClawHandler]::new()
        $script:ctx = [SetupContext]::new("D:\dotfiles")
    }

    Context 'Constructor' {
        It 'should set <property> to <expected>' -ForEach @(
            @{ property = "Name"; expected = "OpenClaw" }
            @{ property = "Description"; expected = "OpenClaw Telegram AI ゲートウェイの起動" }
            @{ property = "Order"; expected = 120 }
            @{ property = "RequiresAdmin"; expected = $false }
            @{ property = "StartupRetries"; expected = 12 }
            @{ property = "StartupRetryDelaySeconds"; expected = 5 }
            @{ property = "ComposeRetries"; expected = 2 }
            @{ property = "ComposeRetryDelaySeconds"; expected = 10 }
        ) {
            $handler.$property | Should -Be $expected
        }
    }

    Context 'CanApply' {
        It 'should return false when docker command is not found' {
            Mock Get-ExternalCommand { return $null }
            Mock Write-Host { }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'should return false when docker-compose.yml does not exist' {
            Mock Get-ExternalCommand { return [PSCustomObject]@{ Name = "docker" } }
            Mock Test-PathExist { return $false }
            Mock Write-Host { }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'should return true when docker is available and docker-compose.yml exists' {
            Mock Get-ExternalCommand { return [PSCustomObject]@{ Name = "docker" } }
            Mock Test-PathExist { return $true }
            Mock Write-Host { }
            # ReadOpenClawEnabled が $true を返すよう chezmoi.toml を模倣
            Mock Test-Path { return $true } -ParameterFilter { $Path -like '*chezmoi.toml' }
            Mock Get-Content { return "[data]`nopenclaw_enabled = true" } -ParameterFilter { $Path -like '*chezmoi.toml' }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }

        It 'should read StartupRetries from Options' {
            Mock Get-ExternalCommand { return [PSCustomObject]@{ Name = "docker" } }
            Mock Test-PathExist { return $true }
            $ctx.Options["OpenClawStartupRetries"] = 6

            $handler.CanApply($ctx)

            $handler.StartupRetries | Should -Be 6
        }

        It 'should read StartupRetryDelaySeconds from Options' {
            Mock Get-ExternalCommand { return [PSCustomObject]@{ Name = "docker" } }
            Mock Test-PathExist { return $true }
            $ctx.Options["OpenClawStartupRetryDelaySeconds"] = 10

            $handler.CanApply($ctx)

            $handler.StartupRetryDelaySeconds | Should -Be 10
        }

        It 'should read ComposeRetries from Options' {
            Mock Get-ExternalCommand { return [PSCustomObject]@{ Name = "docker" } }
            Mock Test-PathExist { return $true }
            $ctx.Options["OpenClawComposeRetries"] = 5

            $handler.CanApply($ctx)

            $handler.ComposeRetries | Should -Be 5
        }

        It 'should read ComposeRetryDelaySeconds from Options' {
            Mock Get-ExternalCommand { return [PSCustomObject]@{ Name = "docker" } }
            Mock Test-PathExist { return $true }
            $ctx.Options["OpenClawComposeRetryDelaySeconds"] = 30

            $handler.CanApply($ctx)

            $handler.ComposeRetryDelaySeconds | Should -Be 30
        }
    }

    Context 'Apply - success' {
        BeforeEach {
            Mock Write-Host { }
            Mock Start-SleepSafe { }
            Mock Set-ContentNoNewline { }
            Mock Invoke-Chezmoi { $global:LASTEXITCODE = 0 }
            # op CLI は存在しない前提（1Password 未インストール環境を模倣）
            Mock Get-ExternalCommand { return $null } -ParameterFilter { $Name -eq "op" }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock Test-Path { return $true } -ParameterFilter { $Path -match "secrets" }
            # WriteSecretFile が token 未取得で throw しないよう環境変数を設定
            $env:OPENCLAW_GITHUB_TOKEN = "ghp_test_success"
            $env:OPENCLAW_XAI_API_KEY = ""
        }

        AfterEach {
            Remove-Item -Path Env:\OPENCLAW_GITHUB_TOKEN -ErrorAction SilentlyContinue
            Remove-Item -Path Env:\OPENCLAW_XAI_API_KEY -ErrorAction SilentlyContinue
        }

        It 'should start container successfully when config exists' {
            Mock Test-PathExist {
                param($Path)
                if ($Path -match "jobs\.seed\.json$") { return $false }
                return $true
            }
            Mock Invoke-Docker {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "up.*-d") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "ps.*--filter") {
                    return "openclaw"
                }
                return ""
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "起動しました"
        }

        It 'should return failure when config file is missing' {
            Mock Test-PathExist {
                param($Path)
                # .env は存在、config は存在しない
                if ($Path -match "docker-compose\.yml") { return $true }
                if ($Path -match "\.env$") { return $true }
                return $false
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "openclaw\.docker\.json"
        }

        It 'should create .env file when it does not exist' {
            $script:envFileCreated = $false
            Mock Test-PathExist {
                param($Path)
                if ($Path -match "\.env$") { return $false }
                return $true
            }
            Mock Set-ContentNoNewline {
                param($Path, $Value)
                if ($Path -match "\.env$") {
                    $script:envFileCreated = $true
                }
            }
            Mock Invoke-Docker {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "up") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "ps") { return "openclaw" }
                return ""
            }

            $handler.Apply($ctx)

            $script:envFileCreated | Should -Be $true
        }

        It 'should not recreate .env file when it already exists' {
            $script:envFileCreated = $false
            Mock Test-PathExist { return $true }
            Mock Set-ContentNoNewline {
                param($Path, $Value)
                if ($Path -match "\.env$") {
                    $script:envFileCreated = $true
                }
            }
            Mock Invoke-Docker {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "up") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "ps") { return "openclaw" }
                return ""
            }

            $handler.Apply($ctx)

            $script:envFileCreated | Should -Be $false
        }
    }

    Context 'Apply - failure cases' {
        BeforeEach {
            Mock Write-Host { }
            Mock Start-SleepSafe { }
            Mock Set-ContentNoNewline { }
            Mock Test-PathExist { return $true }
            Mock Get-ExternalCommand { return $null } -ParameterFilter { $Name -eq "op" }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock Test-Path { return $true } -ParameterFilter { $Path -match "secrets" }
            $env:OPENCLAW_GITHUB_TOKEN = "ghp_test_failure"
            $env:OPENCLAW_XAI_API_KEY = ""
        }

        AfterEach {
            Remove-Item -Path Env:\OPENCLAW_GITHUB_TOKEN -ErrorAction SilentlyContinue
            Remove-Item -Path Env:\OPENCLAW_XAI_API_KEY -ErrorAction SilentlyContinue
        }

        It 'should return failure when docker compose up fails' {
            Mock Invoke-Docker {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "up") {
                    $global:LASTEXITCODE = 1
                    return ""
                }
                return ""
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "docker compose up に失敗"
        }

        It 'should return failure when required secret is missing' {
            Mock Test-PathExist { return $true }
            # op CLI なし、かつ必須の GITHUB_TOKEN も空 → WriteSecretFile が throw
            $env:OPENCLAW_GITHUB_TOKEN = ""

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "github_token"
        }

        It 'should return failure when container startup times out' {
            $handler.StartupRetries = 2
            $handler.StartupRetryDelaySeconds = 0
            Mock Invoke-Docker {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "up") {
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "ps") {
                    return ""  # コンテナが起動しない
                }
                return ""
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "タイムアウト"
        }

        It 'should return failure when exception is thrown' {
            Mock Invoke-Docker {
                throw "Docker connection error"
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "Docker connection error"
        }
    }

    Context 'Apply - compose retry behavior' {
        BeforeEach {
            Mock Write-Host { }
            Mock Start-SleepSafe { }
            Mock Set-ContentNoNewline { }
            Mock Test-PathExist {
                param($Path)
                if ($Path -match "jobs\.seed\.json$") { return $false }
                return $true
            }
            Mock Get-ExternalCommand { return $null } -ParameterFilter { $Name -eq "op" }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock Test-Path { return $true } -ParameterFilter { $Path -match "secrets" }
            $env:OPENCLAW_GITHUB_TOKEN = "ghp_test_compose_retry"
            $env:OPENCLAW_XAI_API_KEY = ""
        }

        AfterEach {
            Remove-Item -Path Env:\OPENCLAW_GITHUB_TOKEN -ErrorAction SilentlyContinue
            Remove-Item -Path Env:\OPENCLAW_XAI_API_KEY -ErrorAction SilentlyContinue
        }

        It 'should succeed on second compose attempt when first fails' {
            $script:composeCallCount = 0
            Mock Invoke-Docker {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "up") {
                    $script:composeCallCount++
                    if ($script:composeCallCount -lt 2) {
                        $global:LASTEXITCODE = 1
                        return ""
                    }
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "ps") { return "openclaw" }
                return ""
            }
            $handler.ComposeRetries = 2

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $script:composeCallCount | Should -Be 2
        }

        It 'should log warning and sleep between compose retries' {
            $script:warningLogged = $false
            $script:sleepCalled = $false
            Mock Write-Host {
                param($Object, $ForegroundColor)
                if ($Object -match "再試行") { $script:warningLogged = $true }
            }
            Mock Start-SleepSafe {
                $script:sleepCalled = $true
            }
            $script:composeCallCount = 0
            Mock Invoke-Docker {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "up") {
                    $script:composeCallCount++
                    if ($script:composeCallCount -lt 2) {
                        $global:LASTEXITCODE = 1
                        return ""
                    }
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "ps") { return "openclaw" }
                return ""
            }
            $handler.ComposeRetries = 2
            $handler.ComposeRetryDelaySeconds = 0

            $handler.Apply($ctx)

            $script:warningLogged | Should -Be $true
            $script:sleepCalled | Should -Be $true
        }
    }

    Context 'Apply - .env content' {
        BeforeEach {
            # op CLI は存在しない前提
            Mock Get-ExternalCommand { return $null } -ParameterFilter { $Name -eq "op" }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock Test-Path { return $true } -ParameterFilter { $Path -match "secrets" }
            $env:OPENCLAW_GITHUB_TOKEN = "ghp_test_env_content"
            $env:OPENCLAW_XAI_API_KEY = ""
        }

        AfterEach {
            Remove-Item -Path Env:\OPENCLAW_GITHUB_TOKEN -ErrorAction SilentlyContinue
            Remove-Item -Path Env:\OPENCLAW_XAI_API_KEY -ErrorAction SilentlyContinue
        }

        It 'should include OPENCLAW_CONFIG_FILE with forward slashes in .env' {
            $script:envContent = ""
            Mock Write-Host { }
            Mock Start-SleepSafe { }
            Mock Test-PathExist {
                param($Path)
                if ($Path -match "\.env$") { return $false }
                return $true
            }
            Mock Set-ContentNoNewline {
                param($Path, $Value)
                if ($Path -match "\.env$") {
                    $script:envContent = $Value
                }
            }
            Mock Invoke-Docker {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "up") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "ps") { return "openclaw" }
                return ""
            }

            $handler.Apply($ctx)

            $script:envContent | Should -Match "OPENCLAW_CONFIG_FILE=.+/"
            $script:envContent | Should -Not -Match "OPENCLAW_CONFIG_FILE=.*\\"
        }

        It 'should include TZ=Asia/Tokyo in .env' {
            $script:envContent = ""
            Mock Write-Host { }
            Mock Start-SleepSafe { }
            Mock Test-PathExist {
                param($Path)
                if ($Path -match "\.env$") { return $false }
                return $true
            }
            Mock Set-ContentNoNewline {
                param($Path, $Value)
                if ($Path -match "\.env$") {
                    $script:envContent = $Value
                }
            }
            Mock Invoke-Docker {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "up") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "ps") { return "openclaw" }
                return ""
            }

            $handler.Apply($ctx)

            $script:envContent | Should -Match "TZ=Asia/Tokyo"
        }

        It 'should include OPENCLAW_GITHUB_TOKEN_FILE in .env but not raw token value' {
            $script:envContent = ""
            Mock Write-Host { }
            Mock Start-SleepSafe { }
            Mock Test-PathExist {
                param($Path)
                if ($Path -match "\.env$") { return $false }
                return $true
            }
            Mock Set-ContentNoNewline {
                param($Path, $Value)
                if ($Path -match "\.env$") {
                    $script:envContent = $Value
                }
            }
            Mock Invoke-Docker {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "up") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "ps") { return "openclaw" }
                return ""
            }

            $handler.Apply($ctx)

            $script:envContent | Should -Match "OPENCLAW_GITHUB_TOKEN_FILE=.+/github_token"
            $script:envContent | Should -Not -Match "GITHUB_TOKEN=ghp_"
        }

        It 'should include GEMINI_CREDENTIALS_DIR in .env with forward slashes' {
            $script:envContent = ""
            Mock Write-Host { }
            Mock Start-SleepSafe { }
            Mock Test-PathExist {
                param($Path)
                if ($Path -match "\.env$") { return $false }
                return $true
            }
            Mock Set-ContentNoNewline {
                param($Path, $Value)
                if ($Path -match "\.env$") {
                    $script:envContent = $Value
                }
            }
            Mock Invoke-Docker {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "up") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "ps") { return "openclaw" }
                return ""
            }

            $handler.Apply($ctx)

            $script:envContent | Should -Match "GEMINI_CREDENTIALS_DIR=.+/\.gemini"
            $script:envContent | Should -Not -Match "GEMINI_CREDENTIALS_DIR=.*\\"
        }
    }

    Context 'WaitForContainer - retry behavior' {
        BeforeEach {
            Mock Get-ExternalCommand { return $null } -ParameterFilter { $Name -eq "op" }
            Mock Set-ContentNoNewline { }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock Test-Path { return $true } -ParameterFilter { $Path -match "secrets" }
            $env:OPENCLAW_GITHUB_TOKEN = "ghp_test_wait"
            $env:OPENCLAW_XAI_API_KEY = ""
        }

        AfterEach {
            Remove-Item -Path Env:\OPENCLAW_GITHUB_TOKEN -ErrorAction SilentlyContinue
            Remove-Item -Path Env:\OPENCLAW_XAI_API_KEY -ErrorAction SilentlyContinue
        }

        It 'should succeed on second attempt' {
            $script:psCallCount = 0
            Mock Write-Host { }
            Mock Start-SleepSafe { }
            Mock Test-PathExist { return $true }
            $handler.StartupRetries = 3
            $handler.StartupRetryDelaySeconds = 0
            Mock Invoke-Docker {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "up") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "ps.*--filter") {
                    $script:psCallCount++
                    if ($script:psCallCount -ge 2) { return "openclaw" }
                    return ""
                }
                return ""
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $script:psCallCount | Should -BeGreaterOrEqual 2
        }
    }

    Context 'GetComposeFilePath' {
        It 'should return correct path relative to DotfilesPath' {
            Mock Get-ExternalCommand { return [PSCustomObject]@{ Name = "docker" } }
            Mock Test-PathExist { return $true }

            $handler.CanApply($ctx)

            # CanApply が正常終了すれば GetComposeFilePath は期待通りのパスを返している
            $result | Should -Not -Be $false
        }
    }
}
