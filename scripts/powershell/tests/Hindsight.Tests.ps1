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
        $script:failLegacyRemove = $false
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
            if ($script:failLegacyRemove -and $Arguments[0] -eq 'rm' -and $Arguments[1] -eq 'hermes-hindsight') {
                throw 'simulated legacy container removal failure'
            }
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

    It 'should copy legacy memory atomically and retire the legacy container' {
        Move-HindsightLegacyData -DataDir $script:dataDir

        (Get-Content -LiteralPath (Join-Path $script:dataDir 'pg0/memory') -Raw).Trim() | Should -Be 'retained-memory'
        (Get-Content -LiteralPath (Join-Path $script:dataDir 'cache/model') -Raw).Trim() | Should -Be 'reranker-cache'
        (Get-Content -LiteralPath (Join-Path $legacyDir 'pg0/memory') -Raw).Trim() | Should -Be 'retained-memory'
        (Get-Content -LiteralPath (Join-Path $script:dataDir '.legacy-migration-source') -Raw).Trim() | Should -Be $legacyDir
        $script:calls | Should -Contain 'docker container inspect hermes-hindsight'
        $script:calls | Should -Contain 'docker stop hermes-hindsight'
        $script:calls | Should -Contain 'docker rm hermes-hindsight'

        $script:calls.Clear()
        Move-HindsightLegacyData -DataDir $script:dataDir
        $script:calls | Should -Be @('docker container inspect hermes-hindsight')
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

    It 'should retry legacy retirement before honoring a completed marker' {
        $script:failLegacyRemove = $true

        { Move-HindsightLegacyData -DataDir $script:dataDir } | Should -Throw '*simulated legacy container removal failure*'
        Test-Path -LiteralPath (Join-Path $script:dataDir '.legacy-migration-source') | Should -BeTrue
        $script:calls | Should -Contain 'docker start hermes-hindsight'

        $script:calls.Clear()
        $script:failLegacyRemove = $false
        Move-HindsightLegacyData -DataDir $script:dataDir

        $script:calls | Should -Contain 'docker stop hermes-hindsight'
        $script:calls | Should -Contain 'docker rm hermes-hindsight'
    }

    It 'should refuse to overwrite an independent memory database' {
        New-Item -ItemType Directory -Path (Join-Path $script:dataDir 'pg0') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:dataDir 'pg0/memory') -Value 'current-memory'

        { Move-HindsightLegacyData -DataDir $script:dataDir } | Should -Throw '*both contain data*'

        (Get-Content -LiteralPath (Join-Path $script:dataDir 'pg0/memory') -Raw).Trim() | Should -Be 'current-memory'
        $script:calls.Count | Should -Be 0
    }
}
