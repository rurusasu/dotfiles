#Requires -Module Pester

BeforeAll {
    $script:entrypoint = Join-Path $PSScriptRoot '../hindsight.ps1'
    . $script:entrypoint
    $script:originalEnvironment = @{}
    foreach ($name in @('HERMES_DATA_DIR', 'USERPROFILE', 'HINDSIGHT_DATA_DIR', 'HINDSIGHT_ENV_FILE', 'HINDSIGHT_API_READY_ATTEMPTS', 'HINDSIGHT_API_READY_DELAY_SECONDS')) {
        $script:originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
    }
}

AfterAll {
    foreach ($name in $script:originalEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $script:originalEnvironment[$name])
    }
}

Describe 'Independent Hindsight runtime' {
    BeforeEach {
        $script:calls = [System.Collections.Generic.List[string]]::new()
        $script:waitShouldFail = $false
        $script:pullShouldFail = $false
        $script:upShouldFail = $false
        $script:stopShouldFail = $false
        $env:USERPROFILE = Join-Path $TestDrive 'home'
        $env:HERMES_DATA_DIR = Join-Path $TestDrive 'hermes'
        $env:HINDSIGHT_DATA_DIR = Join-Path $TestDrive 'current'
        $env:HINDSIGHT_ENV_FILE = ''
        $script:dataDir = $env:HINDSIGHT_DATA_DIR
        $script:legacyDir = Join-Path $env:HERMES_DATA_DIR 'hindsight'
        $composeDir = Join-Path $TestDrive 'compose'
        $script:composeFile = Join-Path $composeDir 'compose.yml'
        Remove-Item -LiteralPath $script:dataDir, $env:HERMES_DATA_DIR -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $composeDir, $env:USERPROFILE -Force | Out-Null
        Set-Content -LiteralPath $script:composeFile -Value 'services: {}'
        Set-Content -LiteralPath (Join-Path $composeDir 'hindsight.env') -Value @(
            'HINDSIGHT_OLLAMA_LLM_MODEL=qwen3.6:35b'
            'HINDSIGHT_OLLAMA_EMBEDDING_MODEL=qwen3-embedding:0.6b'
        )

        Mock Wait-HindsightApi {
            $script:calls.Add('wait')
            if ($script:waitShouldFail) { throw 'simulated readiness failure' }
        }
        Mock Invoke-HindsightCommand {
            $script:calls.Add("$Command $($Arguments -join ' ')")
            if ($script:pullShouldFail -and $Command -eq 'ollama') { throw 'simulated model pull failure' }
            if ($script:upShouldFail -and $Arguments -contains 'up') { throw 'simulated startup failure' }
            $exitCode = if ($script:stopShouldFail -and $Arguments -contains 'stop') { 46 } else { 0 }
            [PSCustomObject]@{ ExitCode = $exitCode; Output = @() }
        }
    }

    It 'should prepare models and image before starting and checking readiness' {
        Invoke-HindsightMain -RequestedAction up -RequestedComposeFile $script:composeFile

        $script:calls | Should -Contain 'ollama pull qwen3.6:35b'
        $script:calls | Should -Contain 'ollama pull qwen3-embedding:0.6b'
        $imageIndex = $script:calls.IndexOf("docker compose -f $script:composeFile pull hindsight")
        $upIndex = $script:calls.IndexOf("docker compose -f $script:composeFile up -d --force-recreate --remove-orphans hindsight")
        $script:calls.IndexOf('ollama pull qwen3-embedding:0.6b') | Should -BeLessThan $imageIndex
        $imageIndex | Should -BeLessThan $upIndex
        $upIndex | Should -BeLessThan $script:calls.IndexOf('wait')
        Test-Path -LiteralPath (Join-Path $script:dataDir 'pg0') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:dataDir 'cache') | Should -BeTrue
    }

    It 'should use current memory while leaving leftover Hermes data untouched' {
        New-Item -ItemType Directory -Path (Join-Path $script:legacyDir 'pg0'), (Join-Path $script:dataDir 'pg0') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:legacyDir 'pg0/memory') -Value 'legacy-memory'
        Set-Content -LiteralPath (Join-Path $script:dataDir 'pg0/memory') -Value 'current-memory'

        Invoke-HindsightMain -RequestedAction up -RequestedComposeFile $script:composeFile

        (Get-Content -LiteralPath (Join-Path $script:dataDir 'pg0/memory') -Raw).Trim() | Should -Be 'current-memory'
        (Get-Content -LiteralPath (Join-Path $script:legacyDir 'pg0/memory') -Raw).Trim() | Should -Be 'legacy-memory'
        Test-Path -LiteralPath (Join-Path $script:dataDir '.legacy-migration-source') | Should -BeFalse
        @($script:calls | Where-Object { $_ -like '*hermes-hindsight*' }).Count | Should -Be 0
    }

    It 'should stop the current service after readiness failure and preserve its memory and old marker' {
        New-Item -ItemType Directory -Path (Join-Path $script:dataDir 'pg0') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:dataDir 'pg0/memory') -Value 'current-memory'
        Set-Content -LiteralPath (Join-Path $script:dataDir '.legacy-migration-source') -Value $script:legacyDir
        $script:waitShouldFail = $true

        { Invoke-HindsightMain -RequestedAction up -RequestedComposeFile $script:composeFile } |
            Should -Throw '*simulated readiness failure*'

        $script:calls | Should -Contain "docker compose -f $script:composeFile stop hindsight"
        (Get-Content -LiteralPath (Join-Path $script:dataDir 'pg0/memory') -Raw).Trim() | Should -Be 'current-memory'
        (Get-Content -LiteralPath (Join-Path $script:dataDir '.legacy-migration-source') -Raw).Trim() | Should -Be $script:legacyDir
        @($script:calls | Where-Object { $_ -like '*hermes-hindsight*' }).Count | Should -Be 0
    }

    It 'should stop the current service after compose startup failure' {
        $script:upShouldFail = $true

        { Invoke-HindsightMain -RequestedAction up -RequestedComposeFile $script:composeFile } |
            Should -Throw '*simulated startup failure*'

        $script:calls | Should -Contain "docker compose -f $script:composeFile stop hindsight"
    }

    It 'should report cleanup failure along with the original readiness failure' {
        $script:waitShouldFail = $true
        $script:stopShouldFail = $true

        { Invoke-HindsightMain -RequestedAction up -RequestedComposeFile $script:composeFile } |
            Should -Throw '*simulated readiness failure*failed to stop*'
    }

    It 'should avoid startup and cleanup when model preparation fails' {
        $script:pullShouldFail = $true

        { Invoke-HindsightMain -RequestedAction up -RequestedComposeFile $script:composeFile } |
            Should -Throw '*simulated model pull failure*'

        @($script:calls | Where-Object { $_ -like '* up *' -or $_ -like '* stop *' }).Count | Should -Be 0
    }

    It 'should verify readiness without preparing models or starting the service' {
        Invoke-HindsightMain -RequestedAction verify -RequestedComposeFile $script:composeFile

        $script:calls.Count | Should -Be 2
        $script:calls | Should -Contain "docker compose -f $script:composeFile config --quiet"
        $script:calls | Should -Contain 'wait'
    }
}

Describe 'Hindsight API health' {
    BeforeEach {
        $env:HINDSIGHT_API_READY_ATTEMPTS = '1'
        $env:HINDSIGHT_API_READY_DELAY_SECONDS = '0'
    }

    It 'should accept a healthy API with a connected database' {
        Mock Invoke-RestMethod { [PSCustomObject]@{ status = 'healthy'; database = 'connected' } }
        { Wait-HindsightApi } | Should -Not -Throw
    }

    It 'should reject a healthy API with a disconnected database' {
        Mock Invoke-RestMethod { [PSCustomObject]@{ status = 'healthy'; database = 'disconnected' } }
        { Wait-HindsightApi } | Should -Throw '*did not become ready*'
    }
}
