#Requires -Module Pester

BeforeAll {
    $script:entrypoint = Join-Path $PSScriptRoot '../hindsight.ps1'
    . $script:entrypoint
    $script:originalHermesDataDir = $env:HERMES_DATA_DIR
    $script:originalUserProfile = $env:USERPROFILE
}

AfterAll {
    $env:HERMES_DATA_DIR = $script:originalHermesDataDir
    $env:USERPROFILE = $script:originalUserProfile
}

Describe 'Independent Hindsight data migration' {
    BeforeEach {
        $script:calls = [System.Collections.Generic.List[string]]::new()
        $script:legacyContainerExists = $true
        $env:USERPROFILE = Join-Path $TestDrive 'home'
        $env:HERMES_DATA_DIR = Join-Path $TestDrive 'hermes'
        $legacyDir = Join-Path $env:HERMES_DATA_DIR 'hindsight'
        $script:dataDir = Join-Path $env:USERPROFILE '.local/share/hindsight'
        Remove-Item -LiteralPath $env:HERMES_DATA_DIR, $env:USERPROFILE -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path (Join-Path $legacyDir 'pg0'), (Join-Path $legacyDir 'cache') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $legacyDir 'pg0/memory') -Value 'retained-memory'
        Set-Content -LiteralPath (Join-Path $legacyDir 'cache/model') -Value 'reranker-cache'

        Mock Invoke-HindsightCommand {
            $script:calls.Add("$Command $($Arguments -join ' ')")
            if ($Arguments[0] -eq 'rm' -and $Arguments[1] -eq 'hermes-hindsight') {
                $script:legacyContainerExists = $false
            }
            if ($Arguments[0] -eq 'start' -and $Arguments[1] -eq 'hermes-hindsight') {
                $script:legacyContainerExists = $true
            }
            $exitCode = if ($Arguments[0] -eq 'container' -and
                ($Arguments[2] -ne 'hermes-hindsight' -or -not $script:legacyContainerExists)) { 1 } else { 0 }
            [PSCustomObject]@{ ExitCode = $exitCode; Output = @() }
        }
    }

    It 'should copy legacy memory atomically and keep the database quiescent until replacement' {
        Move-HindsightLegacyData -DataDir $script:dataDir

        (Get-Content -LiteralPath (Join-Path $script:dataDir 'pg0/memory') -Raw).Trim() | Should -Be 'retained-memory'
        (Get-Content -LiteralPath (Join-Path $script:dataDir 'cache/model') -Raw).Trim() | Should -Be 'reranker-cache'
        (Get-Content -LiteralPath (Join-Path $legacyDir 'pg0/memory') -Raw).Trim() | Should -Be 'retained-memory'
        (Get-Content -LiteralPath (Join-Path $script:dataDir '.legacy-migration-source') -Raw).Trim() | Should -Be $legacyDir
        $script:calls | Should -Contain 'docker container inspect hermes-hindsight'
        $script:calls | Should -Contain 'docker stop hermes-hindsight'
        $script:calls | Should -Not -Contain 'docker start hermes-hindsight'
        $script:calls | Should -Not -Contain 'docker rm hermes-hindsight'

        $script:calls.Clear()
        Move-HindsightLegacyData -DataDir $script:dataDir
        $script:calls.Count | Should -Be 0
    }

    It 'should write the migration marker without a PowerShell 7-only Set-Content encoding' {
        Mock Set-Content { throw 'Set-Content utf8NoBOM is unavailable in Windows PowerShell 5.1' }

        Move-HindsightLegacyData -DataDir $script:dataDir

        (Get-Content -LiteralPath (Join-Path $script:dataDir '.legacy-migration-source') -Raw).Trim() | Should -Be $legacyDir
    }

    It 'should restart the legacy container when migration fails after stopping it' {
        Mock Copy-Item { throw 'simulated copy failure' }

        { Move-HindsightLegacyData -DataDir $script:dataDir } | Should -Throw '*Unable to copy legacy Hindsight data*'

        $script:calls | Should -Contain 'docker stop hermes-hindsight'
        $script:calls | Should -Contain 'docker start hermes-hindsight'
        $script:calls | Should -Not -Contain 'docker rm hermes-hindsight'
        (Get-Content -LiteralPath (Join-Path $legacyDir 'pg0/memory') -Raw).Trim() | Should -Be 'retained-memory'
    }

    It 'should honor a completed marker without retiring the legacy service during preparation' {
        Move-HindsightLegacyData -DataDir $script:dataDir

        $script:calls.Clear()
        Move-HindsightLegacyData -DataDir $script:dataDir

        $script:calls.Count | Should -Be 0
    }

    It 'should refuse to overwrite an independent memory database' {
        New-Item -ItemType Directory -Path (Join-Path $script:dataDir 'pg0') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:dataDir 'pg0/memory') -Value 'current-memory'

        { Move-HindsightLegacyData -DataDir $script:dataDir } | Should -Throw '*both contain data*'

        (Get-Content -LiteralPath (Join-Path $script:dataDir 'pg0/memory') -Raw).Trim() | Should -Be 'current-memory'
        $script:calls.Count | Should -Be 0
    }
}

Describe 'Independent Hindsight startup cutover' {
    BeforeEach {
        $script:calls = [System.Collections.Generic.List[string]]::new()
        $script:waitShouldFail = $false
        $script:pullShouldFail = $false
        $env:USERPROFILE = Join-Path $TestDrive 'startup-home'
        $composeDir = Join-Path $TestDrive 'compose'
        $script:composeFile = Join-Path $composeDir 'compose.yml'
        New-Item -ItemType Directory -Path $composeDir, $env:USERPROFILE -Force | Out-Null
        Set-Content -LiteralPath $script:composeFile -Value 'services: {}'
        Set-Content -LiteralPath (Join-Path $composeDir 'hindsight.env') -Value @(
            'HINDSIGHT_API_LLM_MODEL=qwen3.6:35b'
            'HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL=qwen3-embedding:0.6b'
        )

        Mock Move-HindsightLegacyData {
            $script:calls.Add($(if ($ValidateOnly) { 'migrate validate' } else { 'migrate' }))
        }
        Mock Wait-HindsightApi {
            $script:calls.Add('wait')
            if ($script:waitShouldFail) { throw 'simulated readiness failure' }
        }
        Mock Invoke-HindsightCommand {
            $script:calls.Add("$Command $($Arguments -join ' ')")
            if ($script:pullShouldFail -and $Command -eq 'ollama' -and $Arguments[0] -eq 'pull') {
                throw 'simulated model pull failure'
            }
            $exitCode = if ($Arguments[0] -eq 'container' -and $Arguments[1] -eq 'inspect') { 0 } else { 0 }
            [PSCustomObject]@{ ExitCode = $exitCode; Output = @() }
        }
    }

    It 'should retire the legacy container only after the replacement is healthy' {
        Invoke-HindsightMain -RequestedAction up -RequestedComposeFile $script:composeFile

        $validateIndex = $script:calls.IndexOf('migrate validate')
        $pullIndex = $script:calls.IndexOf('ollama pull qwen3-embedding:0.6b')
        $migrateIndex = $script:calls.IndexOf('migrate')
        $stopIndex = $script:calls.IndexOf('docker stop hermes-hindsight')
        $upIndex = $script:calls.IndexOf("docker compose -f $script:composeFile up -d hindsight")
        $waitIndex = $script:calls.IndexOf('wait')
        $retireIndex = $script:calls.IndexOf('docker rm hermes-hindsight')
        $validateIndex | Should -BeLessThan $pullIndex
        $pullIndex | Should -BeLessThan $migrateIndex
        $migrateIndex | Should -BeLessThan $stopIndex
        $stopIndex | Should -BeLessThan $upIndex
        $upIndex | Should -BeLessThan $waitIndex
        $waitIndex | Should -BeLessThan $retireIndex
    }

    It 'should leave legacy data running when model preparation fails' {
        $script:pullShouldFail = $true

        { Invoke-HindsightMain -RequestedAction up -RequestedComposeFile $script:composeFile } |
            Should -Throw '*simulated model pull failure*'

        $script:calls | Should -Contain 'migrate validate'
        $script:calls | Should -Not -Contain 'migrate'
        $script:calls | Should -Not -Contain 'docker stop hermes-hindsight'
    }

    It 'should restore the legacy container when replacement readiness fails' {
        $script:waitShouldFail = $true

        { Invoke-HindsightMain -RequestedAction up -RequestedComposeFile $script:composeFile } |
            Should -Throw '*simulated readiness failure*'

        $script:calls | Should -Contain "docker compose -f $script:composeFile stop hindsight"
        $script:calls | Should -Contain 'docker start hermes-hindsight'
        $script:calls | Should -Not -Contain 'docker rm hermes-hindsight'
    }
}
