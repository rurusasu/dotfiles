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
        $script:seedWritesMarker = $true
        $script:lockCreateExitCode = 0
        $script:lockCreateFailOnce = $false
        $script:lockCreateAttempts = 0
        $script:lockState = ''
        $script:lockId = '1111111111111111111111111111111111111111111111111111111111111111'
        $script:replacementLockId = '2222222222222222222222222222222222222222222222222222222222222222'
        $script:unixTime = 0
        $script:lockReleaseExitCode = 0
        $script:oldVolume = $env:HERMES_DATA_VOLUME
        Remove-Item Env:\HERMES_DATA_VOLUME -ErrorAction SilentlyContinue

        Mock Get-HermesStorageUnixTime {
            $script:unixTime += 100
            return $script:unixTime
        }

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
                $script:volumeToken = if ([string]::IsNullOrEmpty($script:raceToken)) {
                    $script:createdToken
                }
                else {
                    $script:raceToken
                }
                $script:volumeReady = $false
                $global:LASTEXITCODE = 0
            }
            elseif ($Arguments[0] -eq 'run') {
                $entrypointIndex = $Arguments.IndexOf('--entrypoint')
                $entrypoint = if ($entrypointIndex -ge 0) { $Arguments[$entrypointIndex + 1] } else { '' }
                if ($entrypoint -eq 'python') {
                    $global:LASTEXITCODE = if ($script:volumeReady) { 0 } else { 1 }
                }
                else {
                    $global:LASTEXITCODE = 1
                }
            }
            elseif ($Arguments[0] -eq 'create') {
                $script:lockCreateAttempts++
                if ($script:lockCreateFailOnce -and $script:lockCreateAttempts -eq 1) {
                    $global:LASTEXITCODE = 125
                }
                else {
                    if ($script:lockCreateExitCode -eq 0) {
                        if ($script:lockCreateAttempts -gt 1) {
                            $script:replacementLockId
                        }
                        else {
                            $script:lockId
                        }
                    }
                    $global:LASTEXITCODE = $script:lockCreateExitCode
                }
            }
            elseif ($Arguments[0] -eq 'inspect') {
                if ([string]::IsNullOrEmpty($script:lockState)) {
                    $global:LASTEXITCODE = 1
                }
                else {
                    $script:lockState
                    $global:LASTEXITCODE = 0
                }
            }
            elseif ($Arguments[0] -eq 'start' -and $Arguments[1] -eq '-a') {
                if ($script:seedExitCode -eq 0 -and $script:seedWritesMarker) {
                    $script:volumeReady = $true
                }
                $global:LASTEXITCODE = $script:seedExitCode
            }
            elseif ($Arguments[0] -eq 'rm' -and $Arguments[1] -eq '-f') {
                $global:LASTEXITCODE = $script:lockReleaseExitCode
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

    It 'leaves an existing legacy volume untouched' {
        $result = Initialize-HermesStorageVolume -DataDir 'C:\Users\test\.hermes'

        $result.Success | Should -BeTrue
        $result.Existing | Should -BeTrue
        $script:dockerCalls | Should -Be @('volume inspect --format {{ index .Labels "com.rurusasu.dotfiles.hermes-storage.schema" }} hermes-data')
    }

    It 'locks and seeds a missing volume with its token' {
        $script:volumeExists = $false

        $result = Initialize-HermesStorageVolume -DataDir 'C:\Users\test\.hermes'

        $result.Success | Should -BeTrue
        $result.Existing | Should -BeFalse
        $script:dockerCalls[1] | Should -Match 'volume create --label com\.rurusasu\.dotfiles\.hermes-storage\.schema=1 --label com\.rurusasu\.dotfiles\.hermes-storage\.init-token=.+ hermes-data'
        ($script:dockerCalls -join "`n") | Should -Match 'create --name dotfiles-hermes-storage-[0-9a-f]{20} .*--entrypoint /usr/local/bin/hermes-storage-seed'
        ($script:dockerCalls -join "`n") | Should -Match 'create .* --ready-token [0-9a-f]{32} --replace-incomplete'
        ($script:dockerCalls -join "`n") | Should -Match 'run --rm --entrypoint python .*volume_token='
        $script:dockerCalls[-1] | Should -Be "rm -f $($script:lockId)"
        ($script:dockerCalls -join "`n") | Should -Not -Match 'volume rm'
    }

    It 'leaves failed seed data incomplete and releases the lock' {
        $script:volumeExists = $false
        $script:seedExitCode = 42

        $result = Initialize-HermesStorageVolume -DataDir 'C:\Users\test\.hermes'

        $result.Success | Should -BeFalse
        $result.Message | Should -Match 'safe retry'
        $script:dockerCalls[-1] | Should -Be "rm -f $($script:lockId)"
        ($script:dockerCalls -join "`n") | Should -Not -Match 'volume rm'
    }

    It 'does not seed a volume whose token changed before lock verification' {
        $script:volumeExists = $false
        $script:raceToken = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'

        $result = Initialize-HermesStorageVolume -DataDir 'C:\Users\test\.hermes'

        $result.Success | Should -BeFalse
        $result.Message | Should -Match 'changed before its lock was acquired'
        ($script:dockerCalls -join "`n") | Should -Not -Match 'start -a'
        ($script:dockerCalls -join "`n") | Should -Not -Match 'volume rm'
    }

    It 'safely reseeds a managed incomplete volume while locked' {
        $script:volumeSchema = '1'
        $script:volumeToken = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        $script:volumeReady = $false

        $result = Initialize-HermesStorageVolume -DataDir 'C:\Users\test\.hermes'

        $result.Success | Should -BeTrue
        $result.Existing | Should -BeTrue
        ($script:dockerCalls -join "`n") | Should -Match 'create .* /usr/local/bin/hermes-storage-seed .*--replace-incomplete'
        ($script:dockerCalls -join "`n") | Should -Match "start -a $($script:lockId)"
    }

    It 'accepts an exactly matching regular marker while locked' {
        $script:volumeSchema = '1'
        $script:volumeToken = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'

        $result = Initialize-HermesStorageVolume -DataDir 'C:\Users\test\.hermes'

        $result.Success | Should -BeTrue
        $result.Existing | Should -BeTrue
        ($script:dockerCalls -join "`n") | Should -Match '--entrypoint python'
        ($script:dockerCalls -join "`n") | Should -Not -Match 'start -a'
    }

    It 'rejects a concurrent running lock before marker access' {
        $script:volumeSchema = '1'
        $script:volumeToken = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        $script:lockCreateExitCode = 125
        $script:lockState = "$($script:lockId)|1|aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|0|running"

        $result = Initialize-HermesStorageVolume -DataDir 'C:\Users\test\.hermes'

        $result.Success | Should -BeFalse
        $result.Message | Should -Match 'already locked'
        ($script:dockerCalls -join "`n") | Should -Not -Match '--entrypoint python'
        ($script:dockerCalls -join "`n") | Should -Not -Match 'start -a'
    }

    It 'reclaims an exited owned lock before retrying atomically' {
        $script:volumeSchema = '1'
        $script:volumeToken = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        $script:volumeReady = $false
        $script:lockCreateFailOnce = $true
        $script:lockState = "$($script:lockId)|1|aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|0|exited"

        $result = Initialize-HermesStorageVolume -DataDir 'C:\Users\test\.hermes'

        $result.Success | Should -BeTrue
        $script:lockCreateAttempts | Should -Be 2
        ($script:dockerCalls -join "`n") | Should -Match 'inspect --format .*State.Status.*dotfiles-hermes-storage-'
        ($script:dockerCalls -join "`n") | Should -Match "rm -f $($script:lockId)"
        ($script:dockerCalls -join "`n") | Should -Match "start -a $($script:replacementLockId)"
    }

    It 'reclaims an aged created lock by immutable container ID' {
        $script:volumeSchema = '1'
        $script:volumeToken = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        $script:volumeReady = $false
        $script:lockCreateFailOnce = $true
        $script:lockState = "$($script:lockId)|1|aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|0|created"

        $result = Initialize-HermesStorageVolume -DataDir 'C:\Users\test\.hermes'

        $result.Success | Should -BeTrue
        $script:lockCreateAttempts | Should -Be 2
        ($script:dockerCalls -join "`n") | Should -Match "rm -f $($script:lockId)"
        ($script:dockerCalls -join "`n") | Should -Match "start -a $($script:replacementLockId)"
        $createCalls = @($script:dockerCalls | Where-Object { $_ -like 'create *' })
        $createCalls[0] | Should -Match 'lock-created-at=100'
        $createCalls[1] | Should -Match 'lock-created-at=300'
    }

    It 'does not touch a replacement after losing stale ID removal' {
        $script:volumeSchema = '1'
        $script:volumeToken = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        $script:lockCreateFailOnce = $true
        $script:lockState = "$($script:lockId)|1|aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|0|exited"
        $script:lockReleaseExitCode = 17

        $result = Initialize-HermesStorageVolume -DataDir 'C:\Users\test\.hermes'

        $result.Success | Should -BeFalse
        $result.Message | Should -Match 'stale lock could not be reclaimed'
        $script:lockCreateAttempts | Should -Be 1
        ($script:dockerCalls -join "`n") | Should -Not -Match $script:replacementLockId
        ($script:dockerCalls -join "`n") | Should -Not -Match 'start -a'
    }

    It 'surfaces lock release failure without deleting the volume' {
        $script:volumeExists = $false
        $script:seedExitCode = 42
        $script:lockReleaseExitCode = 17

        $result = Initialize-HermesStorageVolume -DataDir 'C:\Users\test\.hermes'

        $result.Success | Should -BeFalse
        $result.Message | Should -Match 'lock could not be released'
        ($script:dockerCalls -join "`n") | Should -Not -Match 'volume rm'
    }

    It 'rejects a successful seed without an exact ready marker' {
        $script:volumeExists = $false
        $script:seedWritesMarker = $false

        $result = Initialize-HermesStorageVolume -DataDir 'C:\Users\test\.hermes'

        $result.Success | Should -BeFalse
        $result.Message | Should -Match 'valid ready marker'
        $script:dockerCalls[-1] | Should -Be "rm -f $($script:lockId)"
    }

    It 'rejects a malformed managed volume token before locking' {
        $script:volumeSchema = '1'
        $script:volumeToken = 'malformed'

        $result = Initialize-HermesStorageVolume -DataDir 'C:\Users\test\.hermes'

        $result.Success | Should -BeFalse
        $result.Message | Should -Match 'invalid initialization token'
        ($script:dockerCalls -join "`n") | Should -Not -Match '^create --name'
    }

    It 'rejects an unsafe volume name before Docker work' {
        $env:HERMES_DATA_VOLUME = 'hermes/data'

        { Initialize-HermesStorageVolume -DataDir 'C:\Users\test\.hermes' } |
            Should -Throw '*invalid Docker volume name*'
        $script:dockerCalls | Should -BeNullOrEmpty
    }
}
