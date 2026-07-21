#Requires -Module Pester

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../lib/HermesBootstrap.ps1
    . $PSScriptRoot/../../handlers/Handler.NixOSWSL.ps1
    . $PSScriptRoot/../../handlers/Handler.NixRebuild.ps1
    . $PSScriptRoot/../../handlers/Handler.HermesAgent.ps1
}

Describe 'HermesAgentHandler' {
    BeforeEach {
        $script:handler = [HermesAgentHandler]::new()
        $script:ctx = [SetupContext]::new($TestDrive)
        $script:composeDir = Join-Path $TestDrive 'docker/hermes-agent'
        $script:composeFile = Join-Path $script:composeDir 'compose.yml'
        $script:userProfile = Join-Path $TestDrive 'user'
        $script:oldUserProfile = $env:USERPROFILE
        $script:oldHome = $env:HOME
        $script:oldHermesDataDir = $env:HERMES_DATA_DIR
        $script:oldHermesBrowserDataDir = $env:HERMES_BROWSER_DATA_DIR
        $script:oldHermesBrowserViewPort = $env:HERMES_BROWSER_VIEW_PORT
        $script:dockerCalls = [System.Collections.Generic.List[string]]::new()

        $script:ctx.Options['NixRebuildApplied'] = $true
        New-Item -ItemType Directory -Path $script:composeDir -Force | Out-Null
        New-Item -ItemType Directory -Path $script:userProfile -Force | Out-Null
        Set-Content -LiteralPath $script:composeFile -Value 'services: {}' -Encoding utf8
        $env:USERPROFILE = $script:userProfile
        Remove-Item Env:\HOME -ErrorAction SilentlyContinue
        Remove-Item Env:\HERMES_DATA_DIR -ErrorAction SilentlyContinue
        Remove-Item Env:\HERMES_BROWSER_DATA_DIR -ErrorAction SilentlyContinue
        Remove-Item Env:\HERMES_BROWSER_VIEW_PORT -ErrorAction SilentlyContinue

        Mock Write-Host { }
        Mock Get-Command {
            [PSCustomObject]@{ Name = 'docker'; Source = 'C:\\Program Files\\Docker\\docker.exe' }
        } -ParameterFilter { $Name -eq 'docker' }
        Mock Test-DockerDaemon { $true }
        Mock Test-WslAvailable { $true }
        Mock Invoke-Wsl { $global:LASTEXITCODE = 0 }
        Mock Invoke-Docker {
            param([string[]]$Arguments)
            $script:dockerCalls.Add(($Arguments -join ' '))
            $global:LASTEXITCODE = 0
        }
        Mock Invoke-HermesBootstrap {
            [PSCustomObject]@{ Success = $true; Changed = $true; Message = 'Hermes bootstrap completed.' }
        }
    }

    AfterEach {
        $env:USERPROFILE = $script:oldUserProfile
        foreach ($entry in @(
                @{ Name = 'HOME'; Value = $script:oldHome },
                @{ Name = 'HERMES_DATA_DIR'; Value = $script:oldHermesDataDir },
                @{ Name = 'HERMES_BROWSER_DATA_DIR'; Value = $script:oldHermesBrowserDataDir },
                @{ Name = 'HERMES_BROWSER_VIEW_PORT'; Value = $script:oldHermesBrowserViewPort }
            )) {
            if ($null -eq $entry.Value) {
                Remove-Item "Env:\\$($entry.Name)" -ErrorAction SilentlyContinue
            }
            else {
                Set-Item "Env:\\$($entry.Name)" $entry.Value
            }
        }
    }

    Context 'constructor and prerequisites' {
        It 'keeps the Phase 2 non-admin installer metadata and ordering' {
            $handler.Name | Should -Be 'HermesAgent'
            $handler.Order | Should -Be 56
            $handler.RequiresAdmin | Should -BeFalse
            $handler.Phase | Should -Be 2
            $handler.Order | Should -BeGreaterThan ([NixOSWSLHandler]::new().Order)
            $handler.Order | Should -BeGreaterThan ([NixRebuildHandler]::new().Order)
        }

        It 'honors its enable option and compose, Docker, and Nix readiness checks' {
            $ctx.Options['SkipHermesAgent'] = $true
            $handler.CanApply($ctx) | Should -BeFalse

            $ctx.Options['SkipHermesAgent'] = $false
            Remove-Item -LiteralPath $script:composeFile -Force
            $handler.CanApply($ctx) | Should -BeFalse

            Set-Content -LiteralPath $script:composeFile -Value 'services: {}' -Encoding utf8
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'docker' }
            $handler.CanApply($ctx) | Should -BeFalse

            Mock Get-Command { [PSCustomObject]@{ Name = 'docker' } } -ParameterFilter { $Name -eq 'docker' }
            Mock Test-DockerDaemon { $false }
            $handler.CanApply($ctx) | Should -BeFalse

            Mock Test-DockerDaemon { $true }
            $ctx.Options['NixRebuildApplied'] = $false
            $handler.CanApply($ctx) | Should -BeFalse
        }
    }

    Context 'host paths' {
        It 'preserves data and browser path overrides and the browser viewer URL' {
            $env:HERMES_DATA_DIR = Join-Path $TestDrive 'data'
            $env:HERMES_BROWSER_DATA_DIR = Join-Path $TestDrive 'browser'
            $env:HERMES_BROWSER_VIEW_PORT = '6090'

            $handler.GetDataDir() | Should -Be $env:HERMES_DATA_DIR
            $handler.GetBrowserDataDir() | Should -Be $env:HERMES_BROWSER_DATA_DIR
            $handler.GetBrowserViewUrl() | Should -Be 'http://127.0.0.1:6090'
        }
    }

    Context 'Apply' {
        It 'validates, builds, bootstraps, then recreates services and reports both URLs' {
            $dataDir = Join-Path $TestDrive 'data'
            $browserDir = Join-Path $TestDrive 'browser'
            $env:HERMES_DATA_DIR = $dataDir
            $env:HERMES_BROWSER_DATA_DIR = $browserDir
            $env:HERMES_BROWSER_VIEW_PORT = '6090'

            $result = $handler.Apply($ctx)

            $result.Success | Should -BeTrue
            $result.HandlerName | Should -Be 'HermesAgent'
            $result.Message | Should -Match 'http://127.0.0.1:9119'
            $result.Message | Should -Match 'http://127.0.0.1:6090'
            $dataDir | Should -Exist
            (Join-Path $dataDir '.xurl') | Should -Exist
            $browserDir | Should -Exist
            $script:dockerCalls | Should -Be @(
                "compose -f $script:composeFile config --quiet",
                "compose -f $script:composeFile build hermes hermes-bootstrap",
                "compose -f $script:composeFile up -d --force-recreate"
            )
            Should -Invoke Invoke-HermesBootstrap -Times 1 -Exactly -ParameterFilter {
                $ComposeFile -eq $script:composeFile -and $DataDir -eq $dataDir
            }
        }

        It 'does not bootstrap or recreate services when compose validation fails' {
            Mock Invoke-Docker {
                $script:dockerCalls.Add(($Arguments -join ' '))
                $global:LASTEXITCODE = 17
                'compose validation failure'
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -BeFalse
            $result.Message | Should -Match 'compose validation failure'
            Should -Invoke Invoke-HermesBootstrap -Times 0 -Exactly
            $script:dockerCalls | Should -Not -Contain "compose -f $script:composeFile up -d --force-recreate"
        }

        It 'does not request secrets or recreate services when image build fails' {
            Mock Invoke-Docker {
                $script:dockerCalls.Add(($Arguments -join ' '))
                if ($Arguments[-1] -eq 'hermes-bootstrap') {
                    $global:LASTEXITCODE = 18
                    return 'build failure'
                }
                $global:LASTEXITCODE = 0
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -BeFalse
            $result.Message | Should -Match 'build failure'
            Should -Invoke Invoke-HermesBootstrap -Times 0 -Exactly
            $script:dockerCalls | Should -Not -Contain "compose -f $script:composeFile up -d --force-recreate"
        }

        It 'returns a redacted bootstrap failure without recreating or stopping existing services' {
            $secret = 'bootstrap-secret-value'
            Mock Invoke-HermesBootstrap {
                [PSCustomObject]@{
                    Success = $false
                    Changed = $false
                    Message = 'Hermes bootstrap failed (exit code 23). [REDACTED]'
                }
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -BeFalse
            $result.Message | Should -Match '\[REDACTED\]'
            $result.Message | Should -Not -Match ([regex]::Escape($secret))
            $script:dockerCalls | Should -Not -Contain "compose -f $script:composeFile up -d --force-recreate"
            ($script:dockerCalls -join "`n") | Should -Not -Match '\b(down|stop)\b'
        }

        It 'reports compose startup failure without stopping existing services' {
            Mock Invoke-Docker {
                $script:dockerCalls.Add(($Arguments -join ' '))
                if ($Arguments -contains 'up') {
                    $global:LASTEXITCODE = 19
                    return 'startup failure'
                }
                $global:LASTEXITCODE = 0
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -BeFalse
            $result.Message | Should -Match 'startup failure'
            $script:dockerCalls[-1] | Should -Be "compose -f $script:composeFile up -d --force-recreate"
            ($script:dockerCalls -join "`n") | Should -Not -Match '\b(down|stop)\b'
        }
    }

    Context 'loader and ownership boundary' {
        It 'loads the bootstrap library through the standard installer loader without calling op in an elevated phase' {
            $installer = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../install.admin.ps1') -Raw
            $installer | Should -Match 'HermesBootstrap\.ps1'
            $installer | Should -Not -Match '(?im)^\s*(?:&\s*)?op\b'
        }

        It 'contains orchestration only and no legacy host content generators' {
            $source = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../handlers/Handler.HermesAgent.ps1') -Raw
            foreach ($legacyMethod in @(
                    'EnsureDashboardAuth', 'EnsureSlackEnvironment', 'EnsureGitHubEnvironment',
                    'EnsureHomeRepositoryLayout', 'EnsureLifelogCore', 'EnsureLifelogCronJob',
                    'EnsureModelConfiguration', 'EnsureMcpConfiguration', 'InvokeLifelogCoreBootstrap'
                )) {
                $source | Should -Not -Match "function $legacyMethod|hidden .* $legacyMethod"
            }
            $source | Should -Not -Match 'dashboard-basic-auth-password|NewDashboardCredentials|GetOnePassword'
        }
    }
}
