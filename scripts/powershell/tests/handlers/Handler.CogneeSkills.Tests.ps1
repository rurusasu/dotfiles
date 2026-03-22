#Requires -Module Pester

<#
.SYNOPSIS
    Handler.CogneeSkills.ps1 のユニットテスト

.DESCRIPTION
    CogneeSkillsHandler クラスのテスト
    2 層ゲート（対話確認 + インフラチェック）と Docker Compose 起動をテスト
#>

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.CogneeSkills.ps1
}

Describe 'CogneeSkillsHandler' {
    BeforeEach {
        $script:handler = [CogneeSkillsHandler]::new()
        $script:ctx = [SetupContext]::new("D:\dotfiles")
    }

    Context 'Constructor' {
        It 'should set <property> to <expected>' -ForEach @(
            @{ property = "Name"; expected = "CogneeSkills" }
            @{ property = "Description"; expected = "CogneeSkills スキルサーバーの起動" }
            @{ property = "Order"; expected = 130 }
            @{ property = "RequiresAdmin"; expected = $false }
            @{ property = "StartupRetries"; expected = 12 }
            @{ property = "StartupRetryDelaySeconds"; expected = 5 }
            @{ property = "ComposeRetries"; expected = 2 }
            @{ property = "ComposeRetryDelaySeconds"; expected = 10 }
        ) {
            $handler.$property | Should -Be $expected
        }
    }

    Context 'CanApply - consent flag is null (not yet decided)' {
        BeforeEach {
            Mock Write-Host { }
            Mock Test-Path { return $false } -ParameterFilter { $Path -like '*chezmoi.toml' }
        }

        It 'should return false' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - consent flag is false' {
        BeforeEach {
            Mock Write-Host { }
            Mock Test-Path { return $true } -ParameterFilter { $Path -like '*chezmoi.toml' }
            Mock Get-Content { return "[data]`ncognee_skills_enabled = false" } -ParameterFilter { $Path -like '*chezmoi.toml' }
        }

        It 'should return false' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - consent flag is true, proceeds to Layer 2' {
        BeforeEach {
            Mock Write-Host { }
            Mock Test-Path { return $true } -ParameterFilter { $Path -like '*chezmoi.toml' }
            Mock Get-Content { return "[data]`ncognee_skills_enabled = true" } -ParameterFilter { $Path -like '*chezmoi.toml' }
            Mock Get-ExternalCommand { return [PSCustomObject]@{ Name = "docker" } }
            Mock Test-PathExist { return $true }
        }

        It 'should return true' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }
    }

    Context 'CanApply - Layer 2: docker not found' {
        BeforeEach {
            Mock Write-Host { }
            Mock Test-Path { return $true } -ParameterFilter { $Path -like '*chezmoi.toml' }
            Mock Get-Content { return "[data]`ncognee_skills_enabled = true" } -ParameterFilter { $Path -like '*chezmoi.toml' }
            Mock Get-ExternalCommand { return $null }
        }

        It 'should return false' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - Layer 2: compose file missing' {
        BeforeEach {
            Mock Write-Host { }
            Mock Test-Path { return $true } -ParameterFilter { $Path -like '*chezmoi.toml' }
            Mock Get-Content { return "[data]`ncognee_skills_enabled = true" } -ParameterFilter { $Path -like '*chezmoi.toml' }
            Mock Get-ExternalCommand { return [PSCustomObject]@{ Name = "docker" } }
            Mock Test-PathExist { return $false }
        }

        It 'should return false' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - option reading' {
        BeforeEach {
            Mock Write-Host { }
            Mock Test-Path { return $true } -ParameterFilter { $Path -like '*chezmoi.toml' }
            Mock Get-Content { return "[data]`ncognee_skills_enabled = true" } -ParameterFilter { $Path -like '*chezmoi.toml' }
            Mock Get-ExternalCommand { return [PSCustomObject]@{ Name = "docker" } }
            Mock Test-PathExist { return $true }
        }

        It 'should read StartupRetries from Options' {
            $ctx.Options["CogneeSkillsStartupRetries"] = 6
            $handler.CanApply($ctx)
            $handler.StartupRetries | Should -Be 6
        }

        It 'should read StartupRetryDelaySeconds from Options' {
            $ctx.Options["CogneeSkillsStartupRetryDelaySeconds"] = 10
            $handler.CanApply($ctx)
            $handler.StartupRetryDelaySeconds | Should -Be 10
        }

        It 'should read ComposeRetries from Options' {
            $ctx.Options["CogneeSkillsComposeRetries"] = 5
            $handler.CanApply($ctx)
            $handler.ComposeRetries | Should -Be 5
        }

        It 'should read ComposeRetryDelaySeconds from Options' {
            $ctx.Options["CogneeSkillsComposeRetryDelaySeconds"] = 30
            $handler.CanApply($ctx)
            $handler.ComposeRetryDelaySeconds | Should -Be 30
        }
    }

    Context 'Apply - success' {
        BeforeEach {
            Mock Write-Host { }
            Mock Start-SleepSafe { }
            Mock Set-ContentNoNewline { }
            Mock Test-PathExist {
                param($Path)
                return $true
            }
        }

        It 'should start container successfully' {
            Mock Invoke-Docker {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "network.*ls") { return "" }
                if ($argStr -match "network.*create") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "up.*-d") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "ps.*--filter") { return "cognee-skills" }
                return ""
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "起動しました"
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
                if ($Path -match "\.env$") { $script:envFileCreated = $true }
            }
            Mock Invoke-Docker {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "network.*ls") { return "" }
                if ($argStr -match "network.*create") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "up") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "ps") { return "cognee-skills" }
                return ""
            }

            $handler.Apply($ctx)

            $script:envFileCreated | Should -Be $true
        }

        It 'should not recreate .env file when it already exists' {
            $script:envFileCreated = $false
            Mock Set-ContentNoNewline {
                param($Path, $Value)
                if ($Path -match "\.env$") { $script:envFileCreated = $true }
            }
            Mock Invoke-Docker {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "network.*ls") { return "cognee-network" }
                if ($argStr -match "up") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "ps") { return "cognee-skills" }
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
        }

        It 'should return failure when docker compose up fails' {
            Mock Invoke-Docker {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "network.*ls") { return "cognee-network" }
                if ($argStr -match "up") { $global:LASTEXITCODE = 1; return "" }
                return ""
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "docker compose up に失敗"
        }

        It 'should return failure when container startup times out' {
            $handler.StartupRetries = 2
            $handler.StartupRetryDelaySeconds = 0
            Mock Invoke-Docker {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "network.*ls") { return "cognee-network" }
                if ($argStr -match "up") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "ps") { return "" }
                return ""
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "タイムアウト"
        }

        It 'should return failure when exception is thrown' {
            Mock Invoke-Docker { throw "Docker connection error" }

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
            Mock Test-PathExist { return $true }
        }

        It 'should succeed on second compose attempt when first fails' {
            $script:composeCallCount = 0
            Mock Invoke-Docker {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "network.*ls") { return "cognee-network" }
                if ($argStr -match "up") {
                    $script:composeCallCount++
                    if ($script:composeCallCount -lt 2) {
                        $global:LASTEXITCODE = 1; return ""
                    }
                    $global:LASTEXITCODE = 0; return ""
                }
                if ($argStr -match "ps") { return "cognee-skills" }
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
            Mock Start-SleepSafe { $script:sleepCalled = $true }
            $script:composeCallCount = 0
            Mock Invoke-Docker {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "network.*ls") { return "cognee-network" }
                if ($argStr -match "up") {
                    $script:composeCallCount++
                    if ($script:composeCallCount -lt 2) {
                        $global:LASTEXITCODE = 1; return ""
                    }
                    $global:LASTEXITCODE = 0; return ""
                }
                if ($argStr -match "ps") { return "cognee-skills" }
                return ""
            }
            $handler.ComposeRetries = 2
            $handler.ComposeRetryDelaySeconds = 0

            $handler.Apply($ctx)

            $script:warningLogged | Should -Be $true
            $script:sleepCalled | Should -Be $true
        }
    }

    Context 'WaitForContainer - retry behavior' {
        BeforeEach {
            Mock Write-Host { }
            Mock Start-SleepSafe { }
            Mock Set-ContentNoNewline { }
            Mock Test-PathExist { return $true }
        }

        It 'should succeed on second attempt' {
            $script:psCallCount = 0
            $handler.StartupRetries = 3
            $handler.StartupRetryDelaySeconds = 0
            Mock Invoke-Docker {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "network.*ls") { return "cognee-network" }
                if ($argStr -match "up") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "ps.*--filter") {
                    $script:psCallCount++
                    if ($script:psCallCount -ge 2) { return "cognee-skills" }
                    return ""
                }
                return ""
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $script:psCallCount | Should -BeGreaterOrEqual 2
        }

        It 'should not sleep on final retry iteration' {
            $script:sleepCount = 0
            $handler.StartupRetries = 2
            $handler.StartupRetryDelaySeconds = 5
            Mock Start-SleepSafe { $script:sleepCount++ }
            Mock Invoke-Docker {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "network.*ls") { return "cognee-network" }
                if ($argStr -match "up") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "ps") { return "" }
                return ""
            }

            $handler.Apply($ctx)

            # 2 retries, sleep only between (not after last) = 1 sleep
            $script:sleepCount | Should -Be 1
        }
    }

    Context 'EnsureDockerNetwork' {
        BeforeEach {
            Mock Write-Host { }
            Mock Start-SleepSafe { }
            Mock Set-ContentNoNewline { }
            Mock Test-PathExist { return $true }
        }

        It 'should skip creation when network already exists' {
            $script:networkCreated = $false
            Mock Invoke-Docker {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "network.*ls") { return "cognee-network" }
                if ($argStr -match "network.*create") {
                    $script:networkCreated = $true
                    $global:LASTEXITCODE = 0; return ""
                }
                if ($argStr -match "up") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "ps") { return "cognee-skills" }
                return ""
            }

            $handler.Apply($ctx)

            $script:networkCreated | Should -Be $false
        }

        It 'should create network when it does not exist' {
            $script:networkCreated = $false
            Mock Invoke-Docker {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "network.*ls") { return "" }
                if ($argStr -match "network.*create") {
                    $script:networkCreated = $true
                    $global:LASTEXITCODE = 0; return ""
                }
                if ($argStr -match "up") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "ps") { return "cognee-skills" }
                return ""
            }

            $handler.Apply($ctx)

            $script:networkCreated | Should -Be $true
        }
    }

    Context '.env content' {
        BeforeEach {
            Mock Write-Host { }
            Mock Start-SleepSafe { }
        }

        It 'should include SKILLS_PATH with forward slashes' {
            $script:envContent = ""
            Mock Test-PathExist {
                param($Path)
                if ($Path -match "\.env$") { return $false }
                return $true
            }
            Mock Set-ContentNoNewline {
                param($Path, $Value)
                if ($Path -match "\.env$") { $script:envContent = $Value }
            }
            Mock Invoke-Docker {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "network.*ls") { return "cognee-network" }
                if ($argStr -match "up") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "ps") { return "cognee-skills" }
                return ""
            }

            $handler.Apply($ctx)

            $script:envContent | Should -Match "SKILLS_PATH=.+/dot_claude/skills"
            $script:envContent | Should -Not -Match 'SKILLS_PATH=.*\\'
        }

        It 'should include LLM_PROVIDER=gemini' {
            $script:envContent = ""
            Mock Test-PathExist {
                param($Path)
                if ($Path -match "\.env$") { return $false }
                return $true
            }
            Mock Set-ContentNoNewline {
                param($Path, $Value)
                if ($Path -match "\.env$") { $script:envContent = $Value }
            }
            Mock Invoke-Docker {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "network.*ls") { return "cognee-network" }
                if ($argStr -match "up") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "ps") { return "cognee-skills" }
                return ""
            }

            $handler.Apply($ctx)

            $script:envContent | Should -Match "LLM_PROVIDER=gemini"
        }
    }
}
