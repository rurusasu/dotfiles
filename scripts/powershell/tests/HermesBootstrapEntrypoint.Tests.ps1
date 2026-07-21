BeforeAll {
    $script:repositoryRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $script:entrypointPath = Join-Path $script:repositoryRoot 'scripts/powershell/hermes-bootstrap.ps1'
    $script:taskfilePath = Join-Path $script:repositoryRoot 'Taskfile.yml'

    . $script:entrypointPath

    function Get-HermesTestEnvironmentVariableState {
        param([Parameter(Mandatory)][string]$Name)

        $path = "Env:\$Name"
        return [PSCustomObject]@{
            Exists = Test-Path -LiteralPath $path
            Value  = [Environment]::GetEnvironmentVariable($Name, 'Process')
        }
    }

    function Restore-HermesTestEnvironmentVariable {
        param(
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][PSCustomObject]$State
        )

        $path = "Env:\$Name"
        if ($State.Exists) {
            Set-Item -LiteralPath $path -Value $State.Value
        }
        else {
            Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Hermes bootstrap PowerShell entrypoint' {
    BeforeEach {
        $script:composeFile = Join-Path $TestDrive 'compose.yml'
        $script:dataDir = Join-Path $TestDrive '.hermes'
        $script:browserDir = Join-Path $script:dataDir '.browser'
        Remove-Item -LiteralPath $script:dataDir -Recurse -Force -ErrorAction SilentlyContinue
        Set-Content -LiteralPath $script:composeFile -Value 'services: {}' -Encoding utf8

        $script:dockerCalls = [System.Collections.Generic.List[string]]::new()
        $script:eventLog = [System.Collections.Generic.List[string]]::new()
        $script:environmentObservations = [System.Collections.Generic.List[object]]::new()
        $script:originalDataEnvironment = Get-HermesTestEnvironmentVariableState -Name 'HERMES_DATA_DIR'
        $script:originalBrowserEnvironment = Get-HermesTestEnvironmentVariableState -Name 'HERMES_BROWSER_DATA_DIR'
        $global:LASTEXITCODE = 0

        Mock Get-Command {
            [PSCustomObject]@{ Name = $Name; Source = $Name }
        } -ParameterFilter { $Name -in @('docker', 'op') }

        Mock Invoke-Docker {
            $script:dockerCalls.Add(($Arguments -join ' '))
            $phase = if ($Arguments.Count -gt 3 -and $Arguments[0] -eq 'compose' -and $Arguments[1] -eq '-f') {
                [string]$Arguments[3]
            }
            else {
                $Arguments -join ' '
            }
            $script:environmentObservations.Add([PSCustomObject]@{
                    Phase          = $phase
                    DataDir        = [Environment]::GetEnvironmentVariable('HERMES_DATA_DIR', 'Process')
                    BrowserDataDir = [Environment]::GetEnvironmentVariable('HERMES_BROWSER_DATA_DIR', 'Process')
                })
            if ($Arguments.Count -gt 3 -and $Arguments[0] -eq 'compose' -and $Arguments[1] -eq '-f') {
                $script:eventLog.Add([string]$Arguments[3])
            }
            $global:LASTEXITCODE = 0
            return @()
        }

        Mock Invoke-HermesBootstrap {
            $script:eventLog.Add('bootstrap')
            $script:environmentObservations.Add([PSCustomObject]@{
                    Phase          = 'bootstrap'
                    DataDir        = [Environment]::GetEnvironmentVariable('HERMES_DATA_DIR', 'Process')
                    BrowserDataDir = [Environment]::GetEnvironmentVariable('HERMES_BROWSER_DATA_DIR', 'Process')
                })
            $global:LASTEXITCODE = 0
            [PSCustomObject]@{
                Success = $true
                Changed = $true
                Message = 'Hermes bootstrap completed.'
            }
        }
    }

    AfterEach {
        Restore-HermesTestEnvironmentVariable `
            -Name 'HERMES_DATA_DIR' `
            -State $script:originalDataEnvironment
        Restore-HermesTestEnvironmentVariable `
            -Name 'HERMES_BROWSER_DATA_DIR' `
            -State $script:originalBrowserEnvironment
    }

    It 'should run the focused Docker phases in order and create only runtime directories' {
        Set-Item -LiteralPath Env:\HERMES_DATA_DIR -Value 'original-data-dir'
        Set-Item -LiteralPath Env:\HERMES_BROWSER_DATA_DIR -Value 'original-browser-dir'

        $result = Invoke-HermesBootstrapEntrypoint `
            -ComposeFile $script:composeFile `
            -DataDir $script:dataDir `
            -BrowserDataDir $script:browserDir

        $result.ExitCode | Should -Be 0
        $script:eventLog | Should -Be @('config', 'build', 'bootstrap', 'up')
        $script:dockerCalls | Should -Be @(
            'info',
            'compose version',
            "compose -f $script:composeFile config --quiet",
            "compose -f $script:composeFile build hermes hermes-bootstrap",
            "compose -f $script:composeFile up -d --force-recreate"
        )
        $script:environmentObservations.Phase | Should -Be @(
            'info',
            'compose version',
            'config',
            'build',
            'bootstrap',
            'up'
        )
        foreach ($observation in $script:environmentObservations) {
            $observation.DataDir | Should -Be $script:dataDir
            $observation.BrowserDataDir | Should -Be $script:browserDir
        }
        (Test-Path -LiteralPath Env:\HERMES_DATA_DIR) | Should -BeTrue
        (Test-Path -LiteralPath Env:\HERMES_BROWSER_DATA_DIR) | Should -BeTrue
        $env:HERMES_DATA_DIR | Should -Be 'original-data-dir'
        $env:HERMES_BROWSER_DATA_DIR | Should -Be 'original-browser-dir'
        $script:dataDir | Should -Exist
        (Join-Path $script:dataDir '.xurl') | Should -Exist
        $script:browserDir | Should -Exist
        @((Get-ChildItem -LiteralPath $script:dataDir -Force).Name | Sort-Object) |
            Should -Be @('.browser', '.xurl')
        Should -Invoke Invoke-HermesBootstrap -Times 1 -Exactly -ParameterFilter {
            $ComposeFile -eq $script:composeFile -and $DataDir -eq $script:dataDir
        }
    }

    It 'should make the Windows task use the focused pwsh entrypoint without installer skip gates' {
        $taskfile = Get-Content -LiteralPath $script:taskfilePath -Raw
        $source = Get-Content -LiteralPath $script:entrypointPath -Raw

        $taskfile | Should -Match "pwsh -NoProfile -File scripts/powershell/hermes-bootstrap\.ps1"
        $taskfile | Should -Not -Match "cmd\.exe /d /c install\.cmd"
        $source | Should -Not -Match 'SkipHermesAgent|NixRebuildApplied|Test-WslAvailable|install\.cmd'
    }

    It 'should resolve the canonical Compose and Windows runtime paths' {
        $previousUserProfile = [Environment]::GetEnvironmentVariable('USERPROFILE', 'Process')
        $previousDataDir = [Environment]::GetEnvironmentVariable('HERMES_DATA_DIR', 'Process')
        $previousBrowserDir = [Environment]::GetEnvironmentVariable('HERMES_BROWSER_DATA_DIR', 'Process')
        try {
            $env:USERPROFILE = $TestDrive
            Remove-Item Env:\HERMES_DATA_DIR -ErrorAction SilentlyContinue
            Remove-Item Env:\HERMES_BROWSER_DATA_DIR -ErrorAction SilentlyContinue

            $paths = Get-HermesBootstrapEntrypointPath

            $paths.ComposeFile | Should -Be (Join-Path $script:repositoryRoot 'docker/hermes-agent/compose.yml')
            $paths.DataDir | Should -Be (Join-Path $TestDrive '.hermes')
            $paths.BrowserDataDir | Should -Be (Join-Path $TestDrive '.hermes/.browser')
        }
        finally {
            [Environment]::SetEnvironmentVariable('USERPROFILE', $previousUserProfile, 'Process')
            [Environment]::SetEnvironmentVariable('HERMES_DATA_DIR', $previousDataDir, 'Process')
            [Environment]::SetEnvironmentVariable('HERMES_BROWSER_DATA_DIR', $previousBrowserDir, 'Process')
        }
    }

    It 'should derive browser data from a custom data environment and restore an unset browser environment' {
        $customDataDir = Join-Path $TestDrive 'custom-hermes-data'
        $customBrowserDir = Join-Path $customDataDir '.browser'
        Set-Item -LiteralPath Env:\HERMES_DATA_DIR -Value $customDataDir
        Remove-Item -LiteralPath Env:\HERMES_BROWSER_DATA_DIR -ErrorAction SilentlyContinue

        $result = Invoke-HermesBootstrapEntrypoint -ComposeFile $script:composeFile

        $result.ExitCode | Should -Be 0
        foreach ($observation in $script:environmentObservations) {
            $observation.DataDir | Should -Be $customDataDir
            $observation.BrowserDataDir | Should -Be $customBrowserDir
        }
        (Test-Path -LiteralPath Env:\HERMES_DATA_DIR) | Should -BeTrue
        $env:HERMES_DATA_DIR | Should -Be $customDataDir
        (Test-Path -LiteralPath Env:\HERMES_BROWSER_DATA_DIR) | Should -BeFalse
    }

    It 'should return nonzero from direct invocation when preflight fails' {
        $missingCompose = Join-Path $TestDrive 'missing-compose.yml'

        $output = @(& pwsh -NoProfile -File $script:entrypointPath -ComposeFile $missingCompose 2>&1)

        $LASTEXITCODE | Should -Be 2
        ($output -join "`n") | Should -Be 'Hermes Compose file was not found.'
    }

    It 'should fail before Docker work when required <commandName> is missing' -ForEach @(
        @{ commandName = 'docker' }
        @{ commandName = 'op' }
    ) {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq $commandName }

        $result = Invoke-HermesBootstrapEntrypoint `
            -ComposeFile $script:composeFile `
            -DataDir $script:dataDir `
            -BrowserDataDir $script:browserDir

        $result.ExitCode | Should -Not -Be 0
        $script:dockerCalls.Count | Should -Be 0
        Should -Invoke Invoke-HermesBootstrap -Times 0 -Exactly
        $script:dataDir | Should -Not -Exist
    }

    It 'should stop when Docker Compose is unavailable' {
        Mock Invoke-Docker {
            $script:dockerCalls.Add(($Arguments -join ' '))
            $global:LASTEXITCODE = if (($Arguments -join ' ') -eq 'compose version') { 12 } else { 0 }
            return @()
        }

        $result = Invoke-HermesBootstrapEntrypoint `
            -ComposeFile $script:composeFile `
            -DataDir $script:dataDir `
            -BrowserDataDir $script:browserDir

        $result.ExitCode | Should -Be 12
        $script:dockerCalls | Should -Be @('info', 'compose version')
        Should -Invoke Invoke-HermesBootstrap -Times 0 -Exactly
        $script:dataDir | Should -Not -Exist
    }

    It 'should stop after compose validation fails' {
        Set-Item -LiteralPath Env:\HERMES_DATA_DIR -Value 'failure-original-data'
        Remove-Item -LiteralPath Env:\HERMES_BROWSER_DATA_DIR -ErrorAction SilentlyContinue
        Mock Invoke-Docker {
            $script:dockerCalls.Add(($Arguments -join ' '))
            if ($Arguments.Count -gt 3 -and $Arguments[3] -eq 'config') {
                $script:eventLog.Add('config')
                $global:LASTEXITCODE = 21
            }
            else {
                $global:LASTEXITCODE = 0
            }
            return @()
        }

        $result = Invoke-HermesBootstrapEntrypoint `
            -ComposeFile $script:composeFile `
            -DataDir $script:dataDir `
            -BrowserDataDir $script:browserDir

        $result.ExitCode | Should -Be 21
        $script:eventLog | Should -Be @('config')
        Should -Invoke Invoke-HermesBootstrap -Times 0 -Exactly
        ($script:dockerCalls -join "`n") | Should -Not -Match 'build|force-recreate'
        (Test-Path -LiteralPath Env:\HERMES_DATA_DIR) | Should -BeTrue
        $env:HERMES_DATA_DIR | Should -Be 'failure-original-data'
        (Test-Path -LiteralPath Env:\HERMES_BROWSER_DATA_DIR) | Should -BeFalse
    }

    It 'should stop after image build fails' {
        Mock Invoke-Docker {
            $script:dockerCalls.Add(($Arguments -join ' '))
            if ($Arguments.Count -gt 3 -and $Arguments[0] -eq 'compose' -and $Arguments[1] -eq '-f') {
                $script:eventLog.Add([string]$Arguments[3])
                $global:LASTEXITCODE = if ($Arguments[3] -eq 'build') { 22 } else { 0 }
            }
            else {
                $global:LASTEXITCODE = 0
            }
            return @()
        }

        $result = Invoke-HermesBootstrapEntrypoint `
            -ComposeFile $script:composeFile `
            -DataDir $script:dataDir `
            -BrowserDataDir $script:browserDir

        $result.ExitCode | Should -Be 22
        $script:eventLog | Should -Be @('config', 'build')
        Should -Invoke Invoke-HermesBootstrap -Times 0 -Exactly
        ($script:dockerCalls -join "`n") | Should -Not -Match 'force-recreate'
    }

    It 'should surface only the redacted bootstrap message and never start services after failure' {
        $secret = 'bootstrap-secret-value'
        Mock Invoke-HermesBootstrap {
            $script:eventLog.Add('bootstrap')
            $global:LASTEXITCODE = 23
            [PSCustomObject]@{
                Success = $false
                Changed = $false
                Message = 'Hermes bootstrap failed (exit code 23). [REDACTED]'
                Secret  = $secret
            }
        }

        $result = Invoke-HermesBootstrapEntrypoint `
            -ComposeFile $script:composeFile `
            -DataDir $script:dataDir `
            -BrowserDataDir $script:browserDir

        $result.ExitCode | Should -Be 23
        $result.Message | Should -Be 'Hermes bootstrap failed (exit code 23). [REDACTED]'
        $result.Message | Should -Not -Match ([regex]::Escape($secret))
        $script:eventLog | Should -Be @('config', 'build', 'bootstrap')
        ($script:dockerCalls -join "`n") | Should -Not -Match 'force-recreate'
    }

    It 'should return nonzero and never start services when bootstrap throws' {
        Remove-Item -LiteralPath Env:\HERMES_DATA_DIR -ErrorAction SilentlyContinue
        Set-Item -LiteralPath Env:\HERMES_BROWSER_DATA_DIR -Value 'throw-original-browser'
        Mock Invoke-HermesBootstrap {
            $script:eventLog.Add('bootstrap')
            throw 'secret-bearing exception must not escape'
        }

        $result = Invoke-HermesBootstrapEntrypoint `
            -ComposeFile $script:composeFile `
            -DataDir $script:dataDir `
            -BrowserDataDir $script:browserDir

        $result.ExitCode | Should -Not -Be 0
        $result.Message | Should -Be 'Hermes bootstrap failed.'
        $result.Message | Should -Not -Match 'secret-bearing'
        $script:eventLog | Should -Be @('config', 'build', 'bootstrap')
        ($script:dockerCalls -join "`n") | Should -Not -Match 'force-recreate'
        (Test-Path -LiteralPath Env:\HERMES_DATA_DIR) | Should -BeFalse
        (Test-Path -LiteralPath Env:\HERMES_BROWSER_DATA_DIR) | Should -BeTrue
        $env:HERMES_BROWSER_DATA_DIR | Should -Be 'throw-original-browser'
    }

    It 'should propagate the compose startup exit code' {
        Mock Invoke-Docker {
            $script:dockerCalls.Add(($Arguments -join ' '))
            if ($Arguments.Count -gt 3 -and $Arguments[0] -eq 'compose' -and $Arguments[1] -eq '-f') {
                $script:eventLog.Add([string]$Arguments[3])
                $global:LASTEXITCODE = if ($Arguments[3] -eq 'up') { 29 } else { 0 }
            }
            else {
                $global:LASTEXITCODE = 0
            }
            return @()
        }

        $result = Invoke-HermesBootstrapEntrypoint `
            -ComposeFile $script:composeFile `
            -DataDir $script:dataDir `
            -BrowserDataDir $script:browserDir

        $result.ExitCode | Should -Be 29
        $script:eventLog | Should -Be @('config', 'build', 'bootstrap', 'up')
        $script:dockerCalls[-1] | Should -Be "compose -f $script:composeFile up -d --force-recreate"
    }
}
