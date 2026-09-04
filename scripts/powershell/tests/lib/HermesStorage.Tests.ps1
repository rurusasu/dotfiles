#Requires -Module Pester

BeforeAll {
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../lib/HermesStorage.ps1
}

Describe 'Hermes Docker storage initialization' {
    BeforeEach {
        $script:dockerCalls = [System.Collections.Generic.List[string]]::new()
        $script:volumeExists = $true
        $script:volumeSchema = ''
        $script:volumeToken = ''
        $script:createdToken = ''
        $script:raceToken = ''
        $script:volumeReady = $true
        $script:seedExitCode = 0
        $script:removeExitCode = 0
        $script:oldVolume = $env:HERMES_DATA_VOLUME
        Remove-Item Env:\HERMES_DATA_VOLUME -ErrorAction SilentlyContinue

        Mock Invoke-Docker {
            $script:dockerCalls.Add(($Arguments -join ' '))
            if ($Arguments[0] -eq 'volume' -and $Arguments[1] -eq 'inspect') {
                $global:LASTEXITCODE = if ($script:volumeExists) { 0 } else { 1 }
                if ($global:LASTEXITCODE -eq 0 -and $Arguments -contains '--format') {
                    $format = $Arguments[$Arguments.IndexOf('--format') + 1]
                    if ($format -match 'hermes-storage\.schema') {
                        $script:volumeSchema
                    }
                    elseif ($format -match 'hermes-storage\.init-token') {
                        $script:volumeToken
                    }
                }
            }
            elseif ($Arguments[0] -eq 'volume' -and $Arguments[1] -eq 'create') {
                $script:volumeExists = $true
                $script:volumeSchema = '1'
                $tokenArgument = $Arguments | Where-Object { $_ -like 'com.rurusasu.dotfiles.hermes-storage.init-token=*' }
                $script:createdToken = ($tokenArgument -split '=', 2)[1]
                $script:volumeToken = if ([string]::IsNullOrEmpty($script:raceToken)) { $script:createdToken } else { $script:raceToken }
                $global:LASTEXITCODE = 0
            }
            elseif ($Arguments[0] -eq 'run') {
                $entrypointIndex = $Arguments.IndexOf('--entrypoint')
                if ($entrypointIndex -ge 0 -and $Arguments[$entrypointIndex + 1] -eq 'test') {
                    $global:LASTEXITCODE = if ($script:volumeReady) { 0 } else { 1 }
                }
                else {
                    $global:LASTEXITCODE = $script:seedExitCode
                }
            }
            elseif ($Arguments[0] -eq 'volume' -and $Arguments[1] -eq 'rm') {
                $global:LASTEXITCODE = $script:removeExitCode
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
        $script:dockerCalls | Should -Be @('volume inspect --format {{ index .Labels "com.rurusasu.dotfiles.hermes-storage.schema" }} hermes-data')
    }

    It 'seeds a missing volume and does not remove it after success' {
        $script:volumeExists = $false

        $result = Initialize-HermesStorageVolume -DataDir 'C:\Users\test\.hermes'

        $result.Success | Should -BeTrue
        $result.Existing | Should -BeFalse
        $script:dockerCalls[0] | Should -Match 'volume inspect --format .*hermes-storage\.schema.* hermes-data'
        $script:dockerCalls[1] | Should -Match 'volume create --label com\.rurusasu\.dotfiles\.hermes-storage\.schema=1 --label com\.rurusasu\.dotfiles\.hermes-storage\.init-token=.+ hermes-data'
        ($script:dockerCalls -join "`n") | Should -Match 'volume inspect --format .*hermes-storage\.init-token.* hermes-data'
        ($script:dockerCalls -join "`n") | Should -Match 'run --rm --entrypoint /usr/local/bin/hermes-storage-seed --mount .*local/hermes-agent-gh:latest'
        $script:dockerCalls | Should -Not -Contain 'volume rm hermes-data'
    }

    It 'removes only the newly created volume after a seed failure' {
        $script:volumeExists = $false
        $script:seedExitCode = 42

        $result = Initialize-HermesStorageVolume -DataDir 'C:\Users\test\.hermes'

        $result.Success | Should -BeFalse
        $script:dockerCalls[-1] | Should -Be 'volume rm hermes-data'
    }

    It 'does not seed or remove a volume won by a concurrent creator' {
        $script:volumeExists = $false
        $script:raceToken = 'another-initializer'

        $result = Initialize-HermesStorageVolume -DataDir 'C:\Users\test\.hermes'

        $result.Success | Should -BeFalse
        $result.Message | Should -Match 'created concurrently'
        ($script:dockerCalls -join "`n") | Should -Not -Match 'run --rm --entrypoint /usr/local/bin/hermes-storage-seed'
        $script:dockerCalls | Should -Not -Contain 'volume rm hermes-data'
    }

    It 'rejects a managed volume without the ready marker' {
        $script:volumeSchema = '1'
        $script:volumeToken = 'previous-initializer'
        $script:volumeReady = $false

        $result = Initialize-HermesStorageVolume -DataDir 'C:\Users\test\.hermes'

        $result.Success | Should -BeFalse
        $result.Existing | Should -BeTrue
        $result.Message | Should -Match 'incomplete'
        ($script:dockerCalls -join "`n") | Should -Match 'run --rm --entrypoint test'
        ($script:dockerCalls -join "`n") | Should -Not -Match 'run --rm --entrypoint /usr/local/bin/hermes-storage-seed'
    }

    It 'accepts a managed volume with the ready marker' {
        $script:volumeSchema = '1'
        $script:volumeToken = 'previous-initializer'

        $result = Initialize-HermesStorageVolume -DataDir 'C:\Users\test\.hermes'

        $result.Success | Should -BeTrue
        $result.Existing | Should -BeTrue
        ($script:dockerCalls -join "`n") | Should -Match 'run --rm --entrypoint test'
        ($script:dockerCalls -join "`n") | Should -Not -Match 'run --rm --entrypoint /usr/local/bin/hermes-storage-seed'
    }

    It 'surfaces failure to remove an owned partial volume' {
        $script:volumeExists = $false
        $script:seedExitCode = 42
        $script:removeExitCode = 17

        $result = Initialize-HermesStorageVolume -DataDir 'C:\Users\test\.hermes'

        $result.Success | Should -BeFalse
        $result.Message | Should -Match 'could not be removed'
        $script:dockerCalls[-1] | Should -Be 'volume rm hermes-data'
    }

    It 'removes an owned volume when seed returns without a ready marker' {
        $script:volumeExists = $false
        $script:volumeReady = $false

        $result = Initialize-HermesStorageVolume -DataDir 'C:\Users\test\.hermes'

        $result.Success | Should -BeFalse
        $result.Message | Should -Match 'ready marker'
        $script:dockerCalls[-1] | Should -Be 'volume rm hermes-data'
    }

    It 'rejects an unsafe volume name before Docker work' {
        $env:HERMES_DATA_VOLUME = 'hermes/data'

        { Initialize-HermesStorageVolume -DataDir 'C:\Users\test\.hermes' } |
            Should -Throw '*invalid Docker volume name*'
        $script:dockerCalls | Should -BeNullOrEmpty
    }
}
