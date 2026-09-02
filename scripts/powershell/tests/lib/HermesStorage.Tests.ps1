#Requires -Module Pester

BeforeAll {
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../lib/HermesStorage.ps1
}

Describe 'Hermes Docker storage initialization' {
    BeforeEach {
        $script:dockerCalls = [System.Collections.Generic.List[string]]::new()
        $script:volumeExists = $true
        $script:seedExitCode = 0
        $script:oldVolume = $env:HERMES_DATA_VOLUME
        Remove-Item Env:\HERMES_DATA_VOLUME -ErrorAction SilentlyContinue

        Mock Invoke-Docker {
            $script:dockerCalls.Add(($Arguments -join ' '))
            if ($Arguments[0] -eq 'volume' -and $Arguments[1] -eq 'inspect') {
                    $global:LASTEXITCODE = if ($script:volumeExists) { 0 } else { 1 }
            }
            elseif ($Arguments[0] -eq 'volume' -and $Arguments[1] -eq 'create') {
                $global:LASTEXITCODE = 0
            }
            elseif ($Arguments[0] -eq 'run') {
                $global:LASTEXITCODE = $script:seedExitCode
            }
            elseif ($Arguments[0] -eq 'volume' -and $Arguments[1] -eq 'rm') {
                $global:LASTEXITCODE = 0
            }
        }
    }

    AfterEach {
        if ($null -eq $script:oldVolume) {
            Remove-Item Env:\HERMES_DATA_VOLUME -ErrorAction SilentlyContinue
        }
        else {
            Set-Item Env:\HERMES_DATA_VOLUME $script:oldVolume
        }
    }

    It 'leaves an existing volume untouched' {
        $result = Initialize-HermesStorageVolume -DataDir 'C:\Users\test\.hermes'

        $result.Success | Should -BeTrue
        $result.Existing | Should -BeTrue
        $script:dockerCalls | Should -Be @('volume inspect hermes-data')
    }

    It 'seeds a missing volume and does not remove it after success' {
        $script:volumeExists = $false

        $result = Initialize-HermesStorageVolume -DataDir 'C:\Users\test\.hermes'

        $result.Success | Should -BeTrue
        $result.Existing | Should -BeFalse
        $script:dockerCalls[0] | Should -Be 'volume inspect hermes-data'
        $script:dockerCalls[1] | Should -Be 'volume create hermes-data'
        $script:dockerCalls[2] | Should -Match 'run --rm --entrypoint /usr/local/bin/hermes-storage-seed --mount .*local/hermes-agent-gh:latest'
        $script:dockerCalls | Should -Not -Contain 'volume rm hermes-data'
    }

    It 'removes only the newly created volume after a seed failure' {
        $script:volumeExists = $false
        $script:seedExitCode = 42

        $result = Initialize-HermesStorageVolume -DataDir 'C:\Users\test\.hermes'

        $result.Success | Should -BeFalse
        $script:dockerCalls[-1] | Should -Be 'volume rm hermes-data'
    }

    It 'rejects an unsafe volume name before Docker work' {
        $env:HERMES_DATA_VOLUME = 'hermes/data'

        { Initialize-HermesStorageVolume -DataDir 'C:\Users\test\.hermes' } |
            Should -Throw '*invalid Docker volume name*'
        $script:dockerCalls | Should -BeNullOrEmpty
    }
}
