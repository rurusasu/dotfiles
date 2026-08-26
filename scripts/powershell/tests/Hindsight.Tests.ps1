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
            $exitCode = if ($Arguments[0] -eq 'container' -and $Arguments[2] -ne 'hermes-hindsight') { 1 } else { 0 }
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
        $script:calls.Count | Should -Be 0
    }

    It 'should write the migration marker without a PowerShell 7-only Set-Content encoding' {
        Mock Set-Content { throw 'Set-Content utf8NoBOM is unavailable in Windows PowerShell 5.1' }

        Move-HindsightLegacyData -DataDir $script:dataDir

        (Get-Content -LiteralPath (Join-Path $script:dataDir '.legacy-migration-source') -Raw).Trim() | Should -Be $legacyDir
    }

    It 'should refuse to overwrite an independent memory database' {
        New-Item -ItemType Directory -Path (Join-Path $script:dataDir 'pg0') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:dataDir 'pg0/memory') -Value 'current-memory'

        { Move-HindsightLegacyData -DataDir $script:dataDir } | Should -Throw '*both contain data*'

        (Get-Content -LiteralPath (Join-Path $script:dataDir 'pg0/memory') -Raw).Trim() | Should -Be 'current-memory'
        $script:calls.Count | Should -Be 0
    }
}
