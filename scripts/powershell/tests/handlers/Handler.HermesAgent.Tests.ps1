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
        $script:ctx.Options["HermesAgent1PasswordEnabled"] = $false
        $script:ctx.Options["HermesAgentSlack1PasswordEnabled"] = $false
        $script:ctx.Options["HermesAgentOpenClawSecrets1PasswordEnabled"] = $false
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

    Context 'Compose file' {
        It 'should build a Hermes image with GitHub CLI and npx installed' {
            $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
            $composePath = Join-Path $repoRoot "docker\hermes-agent\compose.yml"
            $dockerfilePath = Join-Path $repoRoot "docker\hermes-agent\Dockerfile"
            $composeContent = Get-Content -LiteralPath $composePath -Raw

            $composeContent | Should -Match "(?m)^\s*build:"
            $composeContent | Should -Match "(?m)^\s*context:\s*\."
            $composeContent | Should -Match "(?m)^\s*dockerfile:\s*Dockerfile"
            $dockerfilePath | Should -Exist

            $dockerfileContent = Get-Content -LiteralPath $dockerfilePath -Raw
            $dockerfileContent | Should -Match "nousresearch/hermes-agent:latest"
            $dockerfileContent | Should -Match "apt-get"
            $dockerfileContent | Should -Match "(?m)\bgh\b"
            $dockerfileContent | Should -Match "gh --version"
            $dockerfileContent | Should -Match "(?m)\bnpm\b"
            $dockerfileContent | Should -Match "npx --version"
            $dockerfileContent | Should -Match "xapi-mcp\.sh"
            $dockerfileContent | Should -Match "/usr/local/bin/hermes-xapi-mcp"
        }

        It 'should include an X API MCP wrapper that ignores unresolved credential placeholders' {
            $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
            $wrapperPath = Join-Path $repoRoot "docker\hermes-agent\xapi-mcp.sh"
            $wrapperPath | Should -Exist

            $wrapperContent = Get-Content -LiteralPath $wrapperPath -Raw
            $wrapperContent | Should -Match "X_API_CLIENT_ID"
            $wrapperContent | Should -Match "CLIENT_ID"
            $wrapperContent | Should -Match ([regex]::Escape('${X_API_CLIENT_ID}'))
            $wrapperContent | Should -Match ([regex]::Escape('exec npx -y @xdevplatform/xurl mcp https://api.x.com/mcp'))
        }

        It 'should pass the Hermes env file into the container without Compose interpolation' {
            $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
            $composePath = Join-Path $repoRoot "docker\hermes-agent\compose.yml"
            $composeContent = Get-Content -LiteralPath $composePath -Raw

            $composeContent | Should -Match "(?m)^\s*env_file:"
            $composeContent | Should -Match ([regex]::Escape('path: ${HERMES_DATA_DIR:-${USERPROFILE:-${HOME}}/.hermes}/.env'))
            $composeContent | Should -Match "(?m)^\s*format:\s*raw\s*$"
            $composeContent | Should -Match "(?m)^\s*required:\s*false\s*$"
        }

        It 'should persist xurl OAuth cache for the X API MCP bridge' {
            $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
            $composePath = Join-Path $repoRoot "docker\hermes-agent\compose.yml"
            $composeContent = Get-Content -LiteralPath $composePath -Raw

            $composeContent | Should -Match ([regex]::Escape('source: ${HERMES_DATA_DIR:-${USERPROFILE:-${HOME}}/.hermes}/.xurl'))
            $composeContent | Should -Match "(?m)^\s*target:\s*/root/\.xurl\s*$"
        }

        It 'should define an isolated researcher gateway service' {
            $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
            $composePath = Join-Path $repoRoot "docker\hermes-agent\compose.yml"
            $composeContent = Get-Content -LiteralPath $composePath -Raw

            $composeContent | Should -Match "(?m)^\s{2}researcher:"
            $composeContent | Should -Match "(?m)^\s{4}container_name:\s*hermes-researcher"
            $composeContent | Should -Match "(?m)^\s{4}restart:\s*unless-stopped"
            $composeContent | Should -Match "(?m)^\s{4}command:\s*-p researcher gateway run"
            $composeContent | Should -Match ([regex]::Escape('127.0.0.1:${HERMES_RESEARCHER_API_PORT:-8643}:8642'))
            $composeContent | Should -Match ([regex]::Escape('127.0.0.1:${HERMES_RESEARCHER_DASHBOARD_PORT:-9120}:9119'))
            $composeContent | Should -Match ([regex]::Escape('path: ${HERMES_DATA_DIR:-${USERPROFILE:-${HOME}}/.hermes}/profiles/researcher/.env'))
        }

        It 'should rebuild the local Hermes image instead of pulling it from a registry' {
            $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
            $taskfilePath = Join-Path $repoRoot "Taskfile.yml"
            $taskfileContent = Get-Content -LiteralPath $taskfilePath -Raw

            $taskfileContent | Should -Match "docker compose -f {{.HERMES_COMPOSE_FILE}} build --pull hermes"
            $taskfileContent | Should -Not -Match "docker compose -f {{.HERMES_COMPOSE_FILE}} pull"
        }

        It 'should expose researcher gateway lifecycle tasks' {
            $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
            $taskfilePath = Join-Path $repoRoot "Taskfile.yml"
            $taskfileContent = Get-Content -LiteralPath $taskfilePath -Raw

            $taskfileContent | Should -Match "(?m)^\s{2}hermes:profile:init:"
            $taskfileContent | Should -Match "PROFILE: '{{.CLI_ARGS | default `"researcher`"}}'"
            $taskfileContent | Should -Match "docker exec hermes sh -lc"
            $taskfileContent | Should -Match "git init -b main"
            $taskfileContent | Should -Match "(?m)^\s{2}hermes:researcher:up:"
            $taskfileContent | Should -Match "docker compose -f {{.HERMES_COMPOSE_FILE}} up -d --build researcher"
            $taskfileContent | Should -Match "(?m)^\s{2}hermes:researcher:down:"
            $taskfileContent | Should -Match "docker compose -f {{.HERMES_COMPOSE_FILE}} stop researcher"
            $taskfileContent | Should -Match "(?m)^\s{2}hermes:researcher:logs:"
            $taskfileContent | Should -Match "docker compose -f {{.HERMES_COMPOSE_FILE}} logs -f --tail=100 researcher"
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
                $script:dockerCalls += , @($Arguments)

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
            $composeCall | Should -Contain "--build"
        }

        It 'should configure the default Codex model in config.yaml' {
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $configPath = Join-Path $script:userProfile ".hermes\config.yaml"
            $configContent = Get-Content -LiteralPath $configPath -Raw

            $configContent | Should -Match "(?m)^model:\r?\n  provider: openai-codex\r?\n  default: gpt-5\.5"
        }

        It 'should replace stale Hermes model config while preserving other settings' {
            $dataDir = Join-Path $script:userProfile ".hermes"
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
            $configPath = Join-Path $dataDir "config.yaml"
            Set-Content -LiteralPath $configPath -Encoding UTF8 -Value @(
                "model:",
                "  default: anthropic/claude-opus-4.6",
                "  provider: auto",
                "  base_url: https://openrouter.ai/api/v1",
                "terminal:",
                "  backend: local"
            )

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $configContent = Get-Content -LiteralPath $configPath -Raw
            $configContent | Should -Match "(?m)^model:\r?\n  provider: openai-codex\r?\n  default: gpt-5\.5"
            $configContent | Should -Not -Match "claude-opus-4\.6|openrouter|model\.default|model\.provider"
            $configContent | Should -Match "(?m)^terminal:\r?\n  backend: local"
        }

        It 'should preserve nested model settings while replacing only the top-level model config' {
            $dataDir = Join-Path $script:userProfile ".hermes"
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
            $configPath = Join-Path $dataDir "config.yaml"
            Set-Content -LiteralPath $configPath -Encoding UTF8 -Value @(
                "auxiliary:",
                "  vision:",
                "    model: local-vision-model",
                "    provider: local-provider",
                "model:",
                "  default: stale-main-model",
                "  provider: auto",
                "agent:",
                "  max_turns: 60"
            )

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $configContent = Get-Content -LiteralPath $configPath -Raw
            $configContent | Should -Match "(?m)^auxiliary:\r?\n  vision:\r?\n    model: local-vision-model\r?\n    provider: local-provider"
            $configContent | Should -Match "(?m)^model:\r?\n  provider: openai-codex\r?\n  default: gpt-5\.5"
            $configContent | Should -Not -Match "stale-main-model"
        }

        It 'should normalize scalar and literal model keys from manual config edits' {
            $dataDir = Join-Path $script:userProfile ".hermes"
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
            $configPath = Join-Path $dataDir "config.yaml"
            Set-Content -LiteralPath $configPath -Encoding UTF8 -Value @(
                "model: gpt-5.5",
                "model.default: gpt-5.5",
                "model.provider: openai-codex",
                "agent:",
                "  max_turns: 60"
            )

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $configContent = Get-Content -LiteralPath $configPath -Raw
            $configContent | Should -Match "(?m)^model:\r?\n  provider: openai-codex\r?\n  default: gpt-5\.5"
            $configContent | Should -Not -Match "(?m)^model\.(default|provider):"
            $configContent | Should -Match "(?m)^agent:\r?\n  max_turns: 60"
        }

        It 'should fall back to generated dashboard auth when 1Password CLI is unavailable' {
            $ctx.Options.Remove("HermesAgent1PasswordEnabled")
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "op" }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $envPath = Join-Path $script:userProfile ".hermes\.env"
            $passwordPath = Join-Path $script:userProfile ".hermes\dashboard-basic-auth-password.txt"
            $envContent = Get-Content -LiteralPath $envPath -Raw
            $passwordContent = Get-Content -LiteralPath $passwordPath -Raw

            $envContent | Should -Match "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin"
            $envContent | Should -Match ([regex]::Escape('HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=scrypt$hash'))
            $passwordContent | Should -Match "generated-password"
        }

        It 'should fail before compose when 1Password is required but unavailable' {
            $ctx.Options.Remove("HermesAgent1PasswordEnabled")
            $ctx.Options["HermesAgentRequire1Password"] = $true
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "op" }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "1Password CLI"
            @($script:dockerCalls | Where-Object { $_[0] -eq "compose" }).Count | Should -Be 0
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
                $script:dockerCalls += , @($Arguments)
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

        It 'should prefer 1Password dashboard auth and avoid writing a plaintext password file' {
            $ctx.Options["HermesAgent1PasswordEnabled"] = $true
            $dataDir = Join-Path $script:userProfile ".hermes"
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
            $envPath = Join-Path $dataDir ".env"
            $passwordPath = Join-Path $dataDir "dashboard-basic-auth-password.txt"
            Set-Content -LiteralPath $envPath -Encoding UTF8 -Value @(
                "OTHER=value",
                "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=local-admin",
                'HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=local$hash',
                "HERMES_DASHBOARD_BASIC_AUTH_SECRET=local-secret"
            )
            Set-Content -LiteralPath $passwordPath -Encoding UTF8 -Value "stale-local-password"
            $onePasswordItemJson = @{
                fields = @(
                    @{
                        id      = "username"
                        label   = "username"
                        purpose = "USERNAME"
                        value   = "admin"
                    },
                    @{
                        id      = "password"
                        label   = "password"
                        purpose = "PASSWORD"
                        value   = "shared-password"
                    }
                )
            } | ConvertTo-Json -Compress

            Mock Get-Command {
                return [PSCustomObject]@{ Name = "op"; Source = "C:\op.exe" }
            } -ParameterFilter { $Name -eq "op" }
            Mock Invoke-OpCommand {
                param(
                    [string]$OpExe,
                    [string[]]$Arguments,
                    [int]$TimeoutSeconds
                )
                $null = $OpExe
                $null = $Arguments
                $null = $TimeoutSeconds
                return [PSCustomObject]@{ Output = @($onePasswordItemJson); ExitCode = 0 }
            }
            Mock Invoke-Docker {
                param(
                    [string[]]$Arguments,
                    [int]$TimeoutSeconds
                )
                $null = $TimeoutSeconds
                $script:dockerCalls += , @($Arguments)
                if ($Arguments[0] -eq "run") {
                    $global:LASTEXITCODE = 0
                    return @('scrypt$onepassword')
                }
                $global:LASTEXITCODE = 0
                return @("started")
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $envContent = Get-Content -LiteralPath $envPath -Raw
            $envContent | Should -Match "OTHER=value"
            $envContent | Should -Match "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin"
            $envContent | Should -Match ([regex]::Escape('HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=scrypt$onepassword'))
            $envContent | Should -Not -Match "local-admin"
            $envContent | Should -Not -Match "local-secret"
            Test-Path -LiteralPath $passwordPath | Should -Be $false
            Should -Invoke Invoke-OpCommand -Times 1 -ParameterFilter {
                $OpExe -eq "C:\op.exe" -and
                $Arguments[0] -eq "item" -and
                $Arguments[1] -eq "get" -and
                $Arguments -contains "Hermes Agent Dashboard" -and
                $Arguments -contains "--account" -and
                $Arguments -contains "my.1password.com" -and
                $Arguments -contains "--vault" -and
                $Arguments -contains "openclaw"
            }
        }

        It 'should configure Slack environment from the openclaw 1Password item' {
            $ctx.Options["HermesAgentSlack1PasswordEnabled"] = $true
            $onePasswordItemJson = @{
                fields = @(
                    @{
                        id      = "bot_token"
                        label   = "bot_token"
                        purpose = ""
                        value   = "xoxb-test-bot-token"
                    },
                    @{
                        id      = "app_level_token"
                        label   = "app_level_token"
                        purpose = ""
                        value   = "xapp-test-app-token"
                    },
                    @{
                        id      = "SLACK_ALLOWED_USERS"
                        label   = "SLACK_ALLOWED_USERS"
                        purpose = ""
                        value   = "U04BDJU87KJ"
                    }
                )
            } | ConvertTo-Json -Compress

            Mock Get-Command {
                return [PSCustomObject]@{ Name = "op"; Source = "C:\op.exe" }
            } -ParameterFilter { $Name -eq "op" }
            Mock Invoke-OpCommand {
                param(
                    [string]$OpExe,
                    [string[]]$Arguments,
                    [int]$TimeoutSeconds
                )
                $null = $OpExe
                $null = $TimeoutSeconds
                if ($Arguments -contains "SlackBot-OpenClaw") {
                    return [PSCustomObject]@{ Output = @($onePasswordItemJson); ExitCode = 0 }
                }
                return [PSCustomObject]@{ Output = @("not found"); ExitCode = 1 }
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $envPath = Join-Path $script:userProfile ".hermes\.env"
            $envContent = Get-Content -LiteralPath $envPath -Raw
            $envContent | Should -Match "SLACK_BOT_TOKEN=xoxb-test-bot-token"
            $envContent | Should -Match "SLACK_APP_TOKEN=xapp-test-app-token"
            $envContent | Should -Match "SLACK_ALLOWED_USERS=U04BDJU87KJ"
            Should -Invoke Invoke-OpCommand -Times 1 -ParameterFilter {
                $OpExe -eq "C:\op.exe" -and
                $Arguments[0] -eq "item" -and
                $Arguments[1] -eq "get" -and
                $Arguments -contains "SlackBot-OpenClaw" -and
                $Arguments -contains "--account" -and
                $Arguments -contains "my.1password.com" -and
                $Arguments -contains "--vault" -and
                $Arguments -contains "openclaw"
            }
        }

        It 'should configure researcher Slack environment from its dedicated 1Password item' {
            $ctx.Options["HermesAgentSlack1PasswordEnabled"] = $false
            $ctx.Options["HermesAgentResearcherSlack1PasswordEnabled"] = $true
            $dataDir = Join-Path $script:userProfile ".hermes"
            $researcherDir = Join-Path $dataDir "profiles\researcher"
            $researcherEnvPath = Join-Path $researcherDir ".env"
            New-Item -ItemType Directory -Path $researcherDir -Force | Out-Null
            Set-Content -LiteralPath $researcherEnvPath -Encoding UTF8 -Value @(
                "OTHER=value",
                "SLACK_BOT_TOKEN=xoxb-cloned-default",
                "SLACK_APP_TOKEN=xapp-cloned-default",
                "SLACK_ALLOWED_USERS=UDEFAULT"
            )
            $onePasswordItemJson = @{
                fields = @(
                    @{
                        id      = "bot_token"
                        label   = "bot_token"
                        purpose = ""
                        value   = "xoxb-researcher-bot-token"
                    },
                    @{
                        id      = "app_level_token"
                        label   = "app_level_token"
                        purpose = ""
                        value   = "xapp-researcher-app-token"
                    },
                    @{
                        id      = "SLACK_ALLOWED_USERS"
                        label   = "SLACK_ALLOWED_USERS"
                        purpose = ""
                        value   = "URESEARCHER"
                    }
                )
            } | ConvertTo-Json -Compress

            Mock Get-Command {
                return [PSCustomObject]@{ Name = "op"; Source = "C:\op.exe" }
            } -ParameterFilter { $Name -eq "op" }
            Mock Invoke-OpCommand {
                param(
                    [string]$OpExe,
                    [string[]]$Arguments,
                    [int]$TimeoutSeconds
                )
                $null = $OpExe
                $null = $TimeoutSeconds
                if ($Arguments -contains "SlackBot-Researcher") {
                    return [PSCustomObject]@{ Output = @($onePasswordItemJson); ExitCode = 0 }
                }
                return [PSCustomObject]@{ Output = @("not found"); ExitCode = 1 }
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $envContent = Get-Content -LiteralPath $researcherEnvPath -Raw
            $envContent | Should -Match "OTHER=value"
            $envContent | Should -Match "SLACK_BOT_TOKEN=xoxb-researcher-bot-token"
            $envContent | Should -Match "SLACK_APP_TOKEN=xapp-researcher-app-token"
            $envContent | Should -Match "SLACK_ALLOWED_USERS=URESEARCHER"
            $envContent | Should -Not -Match "xoxb-cloned-default"
            Should -Invoke Invoke-OpCommand -Times 1 -ParameterFilter {
                $OpExe -eq "C:\op.exe" -and
                $Arguments[0] -eq "item" -and
                $Arguments[1] -eq "get" -and
                $Arguments -contains "SlackBot-Researcher" -and
                $Arguments -contains "--account" -and
                $Arguments -contains "my.1password.com" -and
                $Arguments -contains "--vault" -and
                $Arguments -contains "openclaw"
            }
        }

        It 'should bootstrap separate Git-managed profile home policy for researcher' {
            $dataDir = Join-Path $script:userProfile ".hermes"
            $researcherDir = Join-Path $dataDir "profiles\researcher"
            New-Item -ItemType Directory -Path $researcherDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $dataDir ".gitignore") -Encoding UTF8 -Value @(
                ".env",
                "memories/"
            )
            Set-Content -LiteralPath (Join-Path $dataDir "SOUL.md") -Encoding UTF8 -Value "Default profile soul."
            Set-Content -LiteralPath (Join-Path $researcherDir "SOUL.md") -Encoding UTF8 -Value "Researcher profile soul."

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $rootGitignore = Get-Content -LiteralPath (Join-Path $dataDir ".gitignore") -Raw
            $rootGitignore | Should -Match "(?m)^profiles/\r?$"

            $sharedDocPath = Join-Path $dataDir "docs\profile-home-layout.md"
            $sharedDocPath | Should -Exist
            $sharedDoc = Get-Content -LiteralPath $sharedDocPath -Raw
            $sharedDoc | Should -Match "/opt/data/profiles/researcher"
            $sharedDoc | Should -Match "memories/"
            $sharedDoc | Should -Match "auth\.json"
            $sharedDoc | Should -Match "AGENTS.md"
            $sharedDoc | Should -Not -Match ([string][char]7)

            $rootSoul = Get-Content -LiteralPath (Join-Path $dataDir "SOUL.md") -Raw
            $rootSoul | Should -Match "/opt/data/docs/profile-home-layout.md"
            $rootSoul | Should -Match "auth\.json"
            $rootSoul | Should -Not -Match ([string][char]7)

            $researcherGitignorePath = Join-Path $researcherDir ".gitignore"
            $researcherGitignorePath | Should -Exist
            $researcherGitignore = Get-Content -LiteralPath $researcherGitignorePath -Raw
            $researcherGitignore | Should -Match "(?m)^\.env\r?$"
            $researcherGitignore | Should -Match "(?m)^memories/\r?$"
            $researcherGitignore | Should -Match "(?m)^sessions/\r?$"
            $researcherGitignore | Should -Match "(?m)^logs/\r?$"
            $researcherGitignore | Should -Match "(?m)^state\.db\*\r?$"
            $researcherGitignore | Should -Match "(?m)^skills/\.usage\.json\*\r?$"

            $profileDocPath = Join-Path $researcherDir "docs\profile-home-layout.md"
            $profileDocPath | Should -Exist
            $profileDoc = Get-Content -LiteralPath $profileDocPath -Raw
            $profileDoc | Should -Match "/opt/data/docs/profile-home-layout.md"
            $profileDoc | Should -Match "researcher profile home"
            $profileDoc | Should -Not -Match "\`$profileName"
            $profileDoc | Should -Match "SlackBot-Researcher"

            $profileSoul = Get-Content -LiteralPath (Join-Path $researcherDir "SOUL.md") -Raw
            $profileSoul | Should -Match "/opt/data/docs/profile-home-layout.md"
            $profileSoul | Should -Match "/opt/data/profiles/researcher/docs/profile-home-layout.md"
        }

        It 'should configure OpenClaw API environment from 1Password items' {
            $ctx.Options["HermesAgentOpenClawSecrets1PasswordEnabled"] = $true
            $items = @{
                "GitHubUsedOpenClawPAT"    = "github-token"
                "openclaw"                 = "gateway-token"
                "ExaUsedOpenclawPAT"       = "exa-token"
                "TavilyUsedOpenclawPAT"    = "tavily-token"
                "FirecrawlUsedOpenclawPAT" = "firecrawl-token"
                "OpenClawGeminiAPI"        = "gemini-token"
                "HuggingFace"              = "hf-token"
                "TelegramBot"              = "telegram-token"
                "XUsedOpenClaw"            = "xai-token"
                "AutoCLI"                  = "autocli-token"
            }

            Mock Get-Command {
                return [PSCustomObject]@{ Name = "op"; Source = "C:\op.exe" }
            } -ParameterFilter { $Name -eq "op" }
            Mock Invoke-OpCommand {
                param(
                    [string]$OpExe,
                    [string[]]$Arguments,
                    [int]$TimeoutSeconds
                )
                $null = $OpExe
                $null = $TimeoutSeconds
                $itemName = $Arguments[2]
                if ($items.ContainsKey($itemName)) {
                    $fieldId = "credential"
                    $fieldLabel = "認証情報"
                    if ($itemName -eq "openclaw") {
                        $fieldId = "password"
                        $fieldLabel = "gateway token"
                    }

                    return [PSCustomObject]@{
                        Output   = @(@{
                                fields = @(
                                    @{
                                        id      = $fieldId
                                        label   = $fieldLabel
                                        purpose = ""
                                        value   = $items[$itemName]
                                    }
                                )
                            } | ConvertTo-Json -Compress)
                        ExitCode = 0
                    }
                }
                return [PSCustomObject]@{ Output = @("not found"); ExitCode = 1 }
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $envPath = Join-Path $script:userProfile ".hermes\.env"
            $envContent = Get-Content -LiteralPath $envPath -Raw
            $envContent | Should -Match "GITHUB_TOKEN=github-token"
            $envContent | Should -Match "GH_TOKEN=github-token"
            $envContent | Should -Match "GITHUB_PERSONAL_ACCESS_TOKEN=github-token"
            $envContent | Should -Match "OPENCLAW_GATEWAY_TOKEN=gateway-token"
            $envContent | Should -Match "EXA_API_KEY=exa-token"
            $envContent | Should -Match "TAVILY_API_KEY=tavily-token"
            $envContent | Should -Match "FIRECRAWL_API_KEY=firecrawl-token"
            $envContent | Should -Match "GEMINI_API_KEY=gemini-token"
            $envContent | Should -Match "GOOGLE_API_KEY=gemini-token"
            $envContent | Should -Match "HF_TOKEN=hf-token"
            $envContent | Should -Match "HUGGINGFACEHUB_API_TOKEN=hf-token"
            $envContent | Should -Match "TELEGRAM_BOT_TOKEN=telegram-token"
            $envContent | Should -Match "XAI_API_KEY=xai-token"
            $envContent | Should -Match "AUTOCLI_API_KEY=autocli-token"
        }

        It 'should configure X MCP servers and remove the GitHub MCP server from config.yaml' {
            $configDir = Join-Path $script:userProfile ".hermes"
            $configPath = Join-Path $configDir "config.yaml"
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
            Set-Content -LiteralPath $configPath -Encoding UTF8 -Value @(
                "model:",
                "  provider: openai-codex",
                "mcp_servers:",
                "  github:",
                "    command: npx",
                '    args: ["-y", "@modelcontextprotocol/server-github"]',
                "  local:",
                "    command: local-tool"
            )

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $configContent = Get-Content -LiteralPath $configPath -Raw
            $configContent | Should -Match "(?m)^mcp_servers:"
            $configContent | Should -Not -Match "(?m)^\s{2}github:"
            $configContent | Should -Not -Match "@modelcontextprotocol/server-github"
            $configContent | Should -Match "(?m)^\s{2}local:"
            $configContent | Should -Match "(?m)^\s{2}xapi:"
            $configContent | Should -Match "(?m)^\s{4}command:\s*/usr/local/bin/hermes-xapi-mcp"
            $configContent | Should -Match "(?m)^\s{4}connect_timeout:\s*300"
            $configContent | Should -Match "(?m)^\s{6}X_API_CLIENT_ID:\s*`\$`\{X_API_CLIENT_ID`\}"
            $configContent | Should -Match "(?m)^\s{6}X_API_CLIENT_SECRET:\s*`\$`\{X_API_CLIENT_SECRET`\}"
            $configContent | Should -Match "(?m)^\s{2}x-docs:"
            $configContent | Should -Match "https://docs\.x\.com/mcp"
        }

        It 'should preserve X MCP servers when mcp_servers is absent' {
            $configDir = Join-Path $script:userProfile ".hermes"
            $configPath = Join-Path $configDir "config.yaml"
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
            Set-Content -LiteralPath $configPath -Encoding UTF8 -Value @(
                "model:",
                "  provider: openai-codex"
            )

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $configContent = Get-Content -LiteralPath $configPath -Raw
            $configContent | Should -Match "(?m)^mcp_servers:"
            $configContent | Should -Match "(?m)^\s{2}xapi:"
            $configContent | Should -Match "(?m)^\s{2}x-docs:"
        }

        It 'should configure X API MCP OAuth environment from the openclaw 1Password item' {
            $ctx.Options["HermesAgentOpenClawSecrets1PasswordEnabled"] = $true
            $items = @{
                "XApiMcp" = @{
                    "CLIENT_ID"     = "x-client-id"
                    "CLIENT_SECRET" = "x-client-secret"
                }
            }

            Mock Get-Command {
                return [PSCustomObject]@{ Name = "op"; Source = "C:\op.exe" }
            } -ParameterFilter { $Name -eq "op" }
            Mock Invoke-OpCommand {
                param(
                    [string]$OpExe,
                    [string[]]$Arguments,
                    [int]$TimeoutSeconds
                )
                $null = $OpExe
                $null = $TimeoutSeconds
                $itemName = $Arguments[2]
                if ($items.ContainsKey($itemName)) {
                    return [PSCustomObject]@{
                        Output   = @(@{
                                fields = @(
                                    @{
                                        id      = "CLIENT_ID"
                                        label   = "CLIENT_ID"
                                        purpose = ""
                                        value   = $items[$itemName]["CLIENT_ID"]
                                    },
                                    @{
                                        id      = "CLIENT_SECRET"
                                        label   = "CLIENT_SECRET"
                                        purpose = ""
                                        value   = $items[$itemName]["CLIENT_SECRET"]
                                    }
                                )
                            } | ConvertTo-Json -Compress)
                        ExitCode = 0
                    }
                }
                return [PSCustomObject]@{ Output = @("not found"); ExitCode = 1 }
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $envPath = Join-Path $script:userProfile ".hermes\.env"
            $envContent = Get-Content -LiteralPath $envPath -Raw
            $envContent | Should -Match "X_API_CLIENT_ID=x-client-id"
            $envContent | Should -Match "X_API_CLIENT_SECRET=x-client-secret"
        }

        It 'should fail before compose when Slack integration is required but unavailable' {
            $ctx.Options["HermesAgentSlack1PasswordEnabled"] = $true
            $ctx.Options["HermesAgentRequireSlack"] = $true
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "op" }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "Slack"
            @($script:dockerCalls | Where-Object { $_[0] -eq "compose" }).Count | Should -Be 0
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
                $script:dockerCalls += , @($Arguments)
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
                $script:dockerCalls += , @($Arguments)
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
