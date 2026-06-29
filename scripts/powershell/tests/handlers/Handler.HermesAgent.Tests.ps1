#Requires -Module Pester

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.NixOSWSL.ps1
    . $PSScriptRoot/../../handlers/Handler.NixRebuild.ps1
    . $PSScriptRoot/../../handlers/Handler.HermesAgent.ps1
}

Describe 'HermesAgentHandler' {
    BeforeEach {
        $script:handler = [HermesAgentHandler]::new()
        $script:ctx = [SetupContext]::new($TestDrive)
        $script:composeDir = Join-Path $TestDrive "docker\hermes-agent"
        $script:composeFile = Join-Path $script:composeDir "compose.yml"
        $script:userProfile = Join-Path $TestDrive "user"
        $script:oldUserProfile = $env:USERPROFILE
        $script:oldHome = $env:HOME
        $script:oldHermesDataDir = $env:HERMES_DATA_DIR
        $script:dockerCalls = @()

        $script:ctx.Options["NixRebuildApplied"] = $true
        Remove-Item -LiteralPath $script:userProfile -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $script:composeDir -Force | Out-Null
        New-Item -ItemType Directory -Path $script:userProfile -Force | Out-Null
        Set-Content -LiteralPath $script:composeFile -Value "services: {}" -Encoding UTF8

        $env:USERPROFILE = $script:userProfile
        Remove-Item Env:\HOME -ErrorAction SilentlyContinue
        Remove-Item Env:\HERMES_DATA_DIR -ErrorAction SilentlyContinue

        Mock Write-Host { }
        Mock Get-Command {
            return [PSCustomObject]@{ Name = "docker"; Source = "C:\Program Files\Docker\Docker\resources\bin\docker.exe" }
        } -ParameterFilter { $Name -eq "docker" }
        Mock Test-DockerDaemon { return $true }
        Mock Test-WslAvailable { return $true }
        Mock Invoke-Wsl {
            $global:LASTEXITCODE = 0
            return @()
        }
    }

    AfterEach {
        $env:USERPROFILE = $script:oldUserProfile
        if ($null -eq $script:oldHome) {
            Remove-Item Env:\HOME -ErrorAction SilentlyContinue
        }
        else {
            $env:HOME = $script:oldHome
        }

        if ($null -eq $script:oldHermesDataDir) {
            Remove-Item Env:\HERMES_DATA_DIR -ErrorAction SilentlyContinue
        }
        else {
            $env:HERMES_DATA_DIR = $script:oldHermesDataDir
        }
    }

    Context 'Constructor' {
        It 'should set installer metadata' {
            $handler.Name | Should -Be "HermesAgent"
            $handler.Description | Should -Not -BeNullOrEmpty
            $handler.Order | Should -Be 56
            $handler.RequiresAdmin | Should -Be $false
            $handler.Phase | Should -Be 2
        }

        It 'should run after NixOS setup handlers' {
            $handler.Order | Should -BeGreaterThan ([NixOSWSLHandler]::new().Order)
            $handler.Order | Should -BeGreaterThan ([NixRebuildHandler]::new().Order)
        }
    }

    Context 'CanApply' {
        It 'should return false when Hermes setup is skipped by option' {
            $ctx.Options["SkipHermesAgent"] = $true

            $handler.CanApply($ctx) | Should -Be $false
        }

        It 'should return false when compose file is missing' {
            Remove-Item -LiteralPath $script:composeFile -Force

            $handler.CanApply($ctx) | Should -Be $false
        }

        It 'should return false when docker command is unavailable' {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "docker" }

            $handler.CanApply($ctx) | Should -Be $false
        }

        It 'should return false when Docker daemon is not ready' {
            Mock Test-DockerDaemon { return $false }

            $handler.CanApply($ctx) | Should -Be $false
        }

        It 'should return false when WSL is unavailable' {
            Mock Test-WslAvailable { return $false }

            $handler.CanApply($ctx) | Should -Be $false
        }

        It 'should return false when the NixOS distro is not runnable' {
            Mock Invoke-Wsl {
                $global:LASTEXITCODE = 1
                return @("not found")
            }

            $handler.CanApply($ctx) | Should -Be $false
        }

        It 'should return false when NixRebuild has not completed in the current setup run' {
            $ctx.Options.Remove("NixRebuildApplied")

            $handler.CanApply($ctx) | Should -Be $false
        }

        It 'should return true when compose file, Docker daemon, NixOS distro, and NixRebuild are available' {
            $handler.CanApply($ctx) | Should -Be $true

            Should -Invoke Test-DockerDaemon -Times 1 -ParameterFilter {
                $TimeoutSeconds -eq 15
            }
            Should -Invoke Invoke-Wsl -Times 1 -ParameterFilter {
                $TimeoutSeconds -eq (Get-WslCheckTimeoutSecond) -and
                $Arguments[0] -eq "-d" -and
                $Arguments[1] -eq $ctx.DistroName -and
                $Arguments[2] -eq "-u" -and
                $Arguments[3] -eq "root" -and
                $Arguments[4] -eq "--" -and
                $Arguments[5] -eq "true"
            }
        }
    }

    Context 'Apply' {
        BeforeEach {
            Mock Invoke-Docker {
                param(
                    [string[]]$Arguments,
                    [int]$TimeoutSeconds
                )
                $null = $TimeoutSeconds
                $script:dockerCalls += ,@($Arguments)

                if ($Arguments[0] -eq "run") {
                    $global:LASTEXITCODE = 0
                    return @("generated-password", 'scrypt$hash')
                }

                if ($Arguments[0] -eq "compose") {
                    $global:LASTEXITCODE = 0
                    return @("started")
                }

                $global:LASTEXITCODE = 1
                return @("unexpected docker call")
            }
        }

        It 'should generate dashboard auth and start the compose service' {
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $envPath = Join-Path $script:userProfile ".hermes\.env"
            $passwordPath = Join-Path $script:userProfile ".hermes\dashboard-basic-auth-password.txt"
            $envContent = Get-Content -LiteralPath $envPath -Raw
            $passwordContent = Get-Content -LiteralPath $passwordPath -Raw

            $envContent | Should -Match "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin"
            $envContent | Should -Match ([regex]::Escape('HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=scrypt$hash'))
            $envContent | Should -Match "HERMES_DASHBOARD_BASIC_AUTH_SECRET="
            $passwordContent | Should -Match "generated-password"

            $composeCall = @($script:dockerCalls | Where-Object { $_[0] -eq "compose" })[0]
            $composeCall | Should -Contain "-f"
            $composeCall | Should -Contain $script:composeFile
            $composeCall | Should -Contain "up"
            $composeCall | Should -Contain "-d"
        }

        It 'should preserve existing dashboard auth without regenerating the password' {
            $dataDir = Join-Path $script:userProfile ".hermes"
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
            $envPath = Join-Path $dataDir ".env"
            Set-Content -LiteralPath $envPath -Encoding UTF8 -Value @(
                "OTHER=value",
                "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin",
                'HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=existing$hash',
                "HERMES_DASHBOARD_BASIC_AUTH_SECRET=existing-secret"
            )
            Mock Invoke-Docker {
                param(
                    [string[]]$Arguments,
                    [int]$TimeoutSeconds
                )
                $null = $TimeoutSeconds
                $script:dockerCalls += ,@($Arguments)
                if ($Arguments[0] -eq "run") {
                    throw "password hash should not be regenerated"
                }
                $global:LASTEXITCODE = 0
                return @("started")
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $envContent = Get-Content -LiteralPath $envPath -Raw
            $envContent | Should -Match "OTHER=value"
            $envContent | Should -Match ([regex]::Escape('HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=existing$hash'))
            Test-Path -LiteralPath (Join-Path $dataDir "dashboard-basic-auth-password.txt") | Should -Be $false
        }

        It 'should remove legacy plaintext dashboard auth when rotating credentials' {
            $dataDir = Join-Path $script:userProfile ".hermes"
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
            $envPath = Join-Path $dataDir ".env"
            Set-Content -LiteralPath $envPath -Encoding UTF8 -Value @(
                "OTHER=value",
                "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin",
                "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=old-plaintext-password",
                "HERMES_DASHBOARD_BASIC_AUTH_SECRET=old-secret"
            )

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $envContent = Get-Content -LiteralPath $envPath -Raw
            $envContent | Should -Match "OTHER=value"
            $envContent | Should -Match ([regex]::Escape('HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=scrypt$hash'))
            $envContent | Should -Not -Match "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD="
            $envContent | Should -Not -Match "old-plaintext-password"
            $passwordContent = Get-Content -LiteralPath (Join-Path $dataDir "dashboard-basic-auth-password.txt") -Raw
            $passwordContent | Should -Match "generated-password"
        }

        It 'should return failure when password hash generation fails' {
            Mock Invoke-Docker {
                param(
                    [string[]]$Arguments,
                    [int]$TimeoutSeconds
                )
                $null = $TimeoutSeconds
                $script:dockerCalls += ,@($Arguments)
                if ($Arguments[0] -eq "run") {
                    $global:LASTEXITCODE = 1
                    return @("hash failed")
                }
                $global:LASTEXITCODE = 0
                return @("started")
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            @($script:dockerCalls | Where-Object { $_[0] -eq "compose" }).Count | Should -Be 0
        }

        It 'should return failure when compose up fails' {
            Mock Invoke-Docker {
                param(
                    [string[]]$Arguments,
                    [int]$TimeoutSeconds
                )
                $null = $TimeoutSeconds
                $script:dockerCalls += ,@($Arguments)
                if ($Arguments[0] -eq "run") {
                    $global:LASTEXITCODE = 0
                    return @("generated-password", 'scrypt$hash')
                }
                $global:LASTEXITCODE = 1
                return @("compose failed")
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "起動に失敗"
        }
    }
}
