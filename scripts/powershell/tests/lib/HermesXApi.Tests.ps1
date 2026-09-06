BeforeAll {
    . $PSScriptRoot/../../lib/HermesXApi.ps1

    function Get-HermesXApiTestEnvironmentVariableState {
        param([Parameter(Mandatory)][string]$Name)

        $path = "Env:\$Name"
        return [PSCustomObject]@{
            Exists = Test-Path -LiteralPath $path
            Value  = [Environment]::GetEnvironmentVariable($Name, 'Process')
        }
    }

    function Restore-HermesXApiTestEnvironmentVariable {
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

Describe 'Hermes X API PowerShell credentials' {
    BeforeEach {
        $script:opCalls = [System.Collections.Generic.List[string]]::new()
        $script:originalClientId = Get-HermesXApiTestEnvironmentVariableState -Name 'X_API_CLIENT_ID'
        $script:originalClientSecret = Get-HermesXApiTestEnvironmentVariableState -Name 'X_API_CLIENT_SECRET'
        $script:originalAccount = Get-HermesXApiTestEnvironmentVariableState -Name 'DOTFILES_HERMES_XAPI_1PASSWORD_ACCOUNT'
        $script:originalVault = Get-HermesXApiTestEnvironmentVariableState -Name 'DOTFILES_HERMES_XAPI_1PASSWORD_VAULT'
        $script:originalItem = Get-HermesXApiTestEnvironmentVariableState -Name 'DOTFILES_HERMES_XAPI_1PASSWORD_ITEM'
        $script:originalOAuthItem = Get-HermesXApiTestEnvironmentVariableState -Name 'DOTFILES_HERMES_XAPI_OAUTH_ITEM'
        foreach ($name in @(
                'X_API_CLIENT_ID',
                'X_API_CLIENT_SECRET',
                'DOTFILES_HERMES_XAPI_1PASSWORD_ACCOUNT',
                'DOTFILES_HERMES_XAPI_1PASSWORD_VAULT',
                'DOTFILES_HERMES_XAPI_1PASSWORD_ITEM',
                'DOTFILES_HERMES_XAPI_OAUTH_ITEM'
            )) {
            Remove-Item -LiteralPath "Env:\$name" -ErrorAction SilentlyContinue
        }
    }

    AfterEach {
        Restore-HermesXApiTestEnvironmentVariable -Name 'X_API_CLIENT_ID' -State $script:originalClientId
        Restore-HermesXApiTestEnvironmentVariable -Name 'X_API_CLIENT_SECRET' -State $script:originalClientSecret
        Restore-HermesXApiTestEnvironmentVariable `
            -Name 'DOTFILES_HERMES_XAPI_1PASSWORD_ACCOUNT' `
            -State $script:originalAccount
        Restore-HermesXApiTestEnvironmentVariable `
            -Name 'DOTFILES_HERMES_XAPI_1PASSWORD_VAULT' `
            -State $script:originalVault
        Restore-HermesXApiTestEnvironmentVariable `
            -Name 'DOTFILES_HERMES_XAPI_1PASSWORD_ITEM' `
            -State $script:originalItem
        Restore-HermesXApiTestEnvironmentVariable `
            -Name 'DOTFILES_HERMES_XAPI_OAUTH_ITEM' `
            -State $script:originalOAuthItem
    }

    It 'should classify only explicit xurl OAuth errors as authentication failures' {
        $authFailure = Resolve-HermesXApiTokenProbeResult `
            -ExitCode 1 `
            -Output @(
                'Error: no valid oauth2 token for app "default": Auth Error: TokenNotFound (cause: oauth2 token not found)',
                'Run: xurl auth oauth2'
            )
        $dockerFailure = Resolve-HermesXApiTokenProbeResult `
            -ExitCode 125 `
            -Output @('Cannot connect to the Docker daemon.')

        $authFailure.Kind | Should -Be 'AuthFailure'
        $authFailure.ExitCode | Should -Be 1
        $dockerFailure.Kind | Should -Be 'InfrastructureFailure'
        $dockerFailure.ExitCode | Should -Be 125
        $authFailure.PSObject.Properties.Name | Should -Not -Contain 'Output'
        $dockerFailure.PSObject.Properties.Name | Should -Not -Contain 'Output'
    }

    It 'loads the canonical 1Password item and restores existing process credentials' {
        Set-Item -LiteralPath Env:\X_API_CLIENT_ID -Value 'original-client-id'
        Set-Item -LiteralPath Env:\X_API_CLIENT_SECRET -Value 'original-client-secret'
        $invoker = {
            param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

            $script:opCalls.Add(($Arguments -join '|'))
            if ($Arguments[0] -eq 'signin') {
                return @('signed in')
            }
            return @(
                '{"fields":[',
                '{"label":"X_API_CLIENT_ID","value":"xapi-client-id-marker"},',
                '{"label":"X_API_CLIENT_SECRET","value":"xapi-client-secret-marker"}',
                ']}'
            )
        }

        $inside = Invoke-HermesXApiCredentialScope -InvokeOnePassword $invoker -Action {
            [PSCustomObject]@{
                ClientId     = $env:X_API_CLIENT_ID
                ClientSecret = $env:X_API_CLIENT_SECRET
            }
        }

        $inside.ClientId | Should -Be 'xapi-client-id-marker'
        $inside.ClientSecret | Should -Be 'xapi-client-secret-marker'
        $env:X_API_CLIENT_ID | Should -Be 'original-client-id'
        $env:X_API_CLIENT_SECRET | Should -Be 'original-client-secret'
        $script:opCalls | Should -Be @(
            'signin|--account|my.1password.com',
            'item|get|Hermes X API MCP|--account|my.1password.com|--vault|openclaw|--format|json'
        )
    }

    It 'accepts configured item coordinates and alternate field labels' {
        $env:DOTFILES_HERMES_XAPI_1PASSWORD_ACCOUNT = 'team.1password.com'
        $env:DOTFILES_HERMES_XAPI_1PASSWORD_VAULT = 'ops'
        $env:DOTFILES_HERMES_XAPI_1PASSWORD_ITEM = 'custom x item'
        $invoker = {
            param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

            $script:opCalls.Add(($Arguments -join '|'))
            if ($Arguments[0] -eq 'signin') {
                return @('signed in')
            }
            return @('{"fields":[{"label":"Client ID","value":"custom-id"},{"label":"client_secret","value":"custom-secret"}]}')
        }

        $credential = Get-HermesXApiCredential -InvokeOnePassword $invoker

        $credential.ClientId | Should -Be 'custom-id'
        $credential.ClientSecret | Should -Be 'custom-secret'
        $script:opCalls | Should -Be @(
            'signin|--account|team.1password.com',
            'item|get|custom x item|--account|team.1password.com|--vault|ops|--format|json'
        )
    }

    It 'fails closed when a required field is missing and leaves env unset' {
        $invoker = {
            param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

            if ($Arguments[0] -eq 'signin') {
                return @('signed in')
            }
            return @('{"fields":[{"label":"X_API_CLIENT_ID","value":"client-only"}]}')
        }

        { Invoke-HermesXApiCredentialScope -InvokeOnePassword $invoker -Action { 'should not run' } } |
            Should -Throw
        (Test-Path -LiteralPath Env:\X_API_CLIENT_ID) | Should -BeFalse
        (Test-Path -LiteralPath Env:\X_API_CLIENT_SECRET) | Should -BeFalse
    }

    It 'loads the refresh token from the shared X API item' {
        $invoker = {
            param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

            $script:opCalls.Add(($Arguments -join '|'))
            if ($Arguments[0] -eq 'signin') {
                return @('signed in')
            }
            return @('{"fields":[{"label":"X_API_REFRESH_TOKEN","value":"xapi-refresh-token-marker"}]}')
        }

        $token = Get-HermesXApiRefreshToken -InvokeOnePassword $invoker

        $token | Should -Be 'xapi-refresh-token-marker'
        $script:opCalls | Should -Be @(
            'signin|--account|my.1password.com',
            'item|get|Hermes X API MCP|--account|my.1password.com|--vault|openclaw|--format|json'
        )
    }

    It 'syncs the cached refresh token into the shared 1Password field' {
        $dataDir = Join-Path $TestDrive 'hermes-sync'
        $xurlDir = Join-Path $dataDir '.xurl'
        $null = New-Item -ItemType Directory -Path $xurlDir -Force
        Set-Content -LiteralPath (Join-Path $xurlDir 'auth.yml') -Value @'
apps:
  default:
    oauth2_tokens:
      app-user:
        oauth2:
          refresh_token: cached-refresh-token
default_app: default
'@ -NoNewline

        $invoker = {
            param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

            $script:opCalls.Add(($Arguments -join '|'))
            $global:LASTEXITCODE = 0
            if ($Arguments[0] -eq 'signin') {
                return @('signed in')
            }
            if ($Arguments[0] -eq 'item' -and $Arguments[1] -eq 'get') {
                return @('{"fields":[{"label":"X_API_REFRESH_TOKEN","section":{"label":"Refresh Token"},"value":""}]}')
            }
            if ($Arguments[0] -eq 'item' -and $Arguments[1] -eq 'edit') {
                $templateIndex = [Array]::IndexOf($Arguments, '--template')
                $template = Get-Content -LiteralPath $Arguments[$templateIndex + 1] -Raw | ConvertFrom-Json
                $template.fields[0].value | Should -Be 'cached-refresh-token'
                return @('updated')
            }
            throw "Unexpected op invocation: $($Arguments -join '|')"
        }

        Sync-HermesXApiRefreshTokenToOnePassword -DataDir $dataDir -InvokeOnePassword $invoker
        $script:opCalls[0] | Should -Be 'signin|--account|my.1password.com'
        $script:opCalls[1] | Should -Be 'item|get|Hermes X API MCP|--account|my.1password.com|--vault|openclaw|--format|json'
        $script:opCalls[2] | Should -Match '^item\|edit\|Hermes X API MCP\|--account\|my\.1password\.com\|--vault\|openclaw\|--template\|.+'
    }

    It 'writes a private xurl cache containing only the refresh token' {
        $dataDir = Join-Path $TestDrive 'hermes-data'
        $xurlDir = Join-Path $dataDir '.xurl'
        $null = New-Item -ItemType Directory -Path $xurlDir -Force

        Write-HermesXApiAuthCache `
            -DataDir $dataDir `
            -ClientId 'xapi-client-id-marker' `
            -ClientSecret 'xapi-client-secret-marker' `
            -RefreshToken 'xapi-refresh-token-marker'

        $cache = Get-Content -LiteralPath (Join-Path $xurlDir 'auth.yml') -Raw
        $cache | Should -Match 'client_id: "xapi-client-id-marker"'
        $cache | Should -Match 'client_secret: "xapi-client-secret-marker"'
        $cache | Should -Match 'refresh_token: "xapi-refresh-token-marker"'
        $cache | Should -Not -Match 'access_token'
    }

    It 'replaces an invalid local token from 1Password and probes it once more' {
        $dataDir = Join-Path $TestDrive 'hermes-reconcile'
        $xurlDir = Join-Path $dataDir '.xurl'
        $null = New-Item -ItemType Directory -Path $xurlDir -Force
        Set-Content -LiteralPath (Join-Path $xurlDir 'auth.yml') -Value @'
apps:
  default:
    oauth2_tokens:
      default:
        type: oauth2
        oauth2:
          refresh_token: "stale-refresh-token"
default_app: default
'@ -NoNewline
        $script:probeCount = 0
        $script:actionRan = $false
        $invoker = {
            param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

            if ($Arguments[0] -eq 'signin') {
                return @('signed in')
            }
            if ($Arguments[2] -eq 'Hermes X API MCP') {
                return @('{"fields":[{"label":"X_API_CLIENT_ID","value":"client-id"},{"label":"X_API_CLIENT_SECRET","value":"client-secret"},{"label":"X_API_REFRESH_TOKEN","section":{"label":"Refresh Token"},"value":"fresh-refresh-token"}]}')
            }
            throw "Unexpected op invocation: $($Arguments -join '|')"
        }

        $result = Invoke-HermesXApiCredentialScope `
            -DataDir $dataDir `
            -InvokeOnePassword $invoker `
            -TokenProbe {
                $script:probeCount++
                if ($script:probeCount -eq 1) {
                    return [PSCustomObject]@{ Kind = 'AuthFailure'; ExitCode = 10 }
                }
                return [PSCustomObject]@{ Kind = 'Success'; ExitCode = 0 }
            } `
            -Action {
                $script:actionRan = $true
                return 'started'
            }

        $result | Should -Be 'started'
        $script:actionRan | Should -BeTrue
        $script:probeCount | Should -Be 2
        (Get-HermesXApiRefreshTokenFromCache -DataDir $dataDir) | Should -Be 'fresh-refresh-token'
    }

    It 'stops before the action when local and 1Password tokens both fail validation' {
        $dataDir = Join-Path $TestDrive 'hermes-invalid'
        $xurlDir = Join-Path $dataDir '.xurl'
        $null = New-Item -ItemType Directory -Path $xurlDir -Force
        Set-Content -LiteralPath (Join-Path $xurlDir 'auth.yml') -Value @'
apps:
  default:
    oauth2_tokens:
      default:
        type: oauth2
        oauth2:
          refresh_token: "stale-refresh-token"
default_app: default
'@ -NoNewline
        $script:probeCount = 0
        $script:actionRan = $false
        $invoker = {
            param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

            if ($Arguments[0] -eq 'signin') {
                return @('signed in')
            }
            return @('{"fields":[{"label":"X_API_CLIENT_ID","value":"client-id"},{"label":"X_API_CLIENT_SECRET","value":"client-secret"},{"label":"X_API_REFRESH_TOKEN","value":"invalid-refresh-token"}]}')
        }

        {
            Invoke-HermesXApiCredentialScope `
                -DataDir $dataDir `
                -InvokeOnePassword $invoker `
                -TokenProbe {
                    $script:probeCount++
                    return [PSCustomObject]@{ Kind = 'AuthFailure'; ExitCode = 10 }
                } `
                -Action {
                    $script:actionRan = $true
                }
        } | Should -Throw '*task hermes:xapi:setup*'
        $script:probeCount | Should -Be 2
        $script:actionRan | Should -BeFalse
        (Get-HermesXApiRefreshTokenFromCache -DataDir $dataDir) | Should -Be 'stale-refresh-token'
    }

    It 'should preserve the local cache and skip fallback after an infrastructure probe failure' {
        $dataDir = Join-Path $TestDrive 'hermes-infrastructure-failure'
        $xurlDir = Join-Path $dataDir '.xurl'
        $null = New-Item -ItemType Directory -Path $xurlDir -Force
        $cachePath = Join-Path $xurlDir 'auth.yml'
        $originalCache = @'
apps:
  default:
    oauth2_tokens:
      default:
        type: oauth2
        oauth2:
          refresh_token: "local-refresh-token"
default_app: default
'@
        Set-Content -LiteralPath $cachePath -Value $originalCache -NoNewline
        $script:probeCount = 0
        $script:actionRan = $false
        $invoker = {
            param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

            if ($Arguments[0] -eq 'signin') { return @('signed in') }
            return @('{
                "fields":[
                    {"label":"X_API_CLIENT_ID","value":"client-id"},
                    {"label":"X_API_CLIENT_SECRET","value":"client-secret"},
                    {"label":"X_API_REFRESH_TOKEN","value":"one-password-refresh-token"}
                ]
            }')
        }

        {
            Invoke-HermesXApiCredentialScope `
                -DataDir $dataDir `
                -InvokeOnePassword $invoker `
                -TokenProbe {
                    $script:probeCount++
                    return [PSCustomObject]@{ Kind = 'InfrastructureFailure'; ExitCode = 125 }
                } `
                -Action { $script:actionRan = $true }
        } | Should -Throw 'Hermes X API token probe failed.'
        $script:probeCount | Should -Be 1
        $script:actionRan | Should -BeFalse
        (Get-Content -LiteralPath $cachePath -Raw) | Should -BeExactly $originalCache
    }

    It 'should never interpret a Boolean false probe result as an authentication failure' {
        $dataDir = Join-Path $TestDrive 'hermes-boolean-probe'
        $xurlDir = Join-Path $dataDir '.xurl'
        $null = New-Item -ItemType Directory -Path $xurlDir -Force
        $cachePath = Join-Path $xurlDir 'auth.yml'
        $originalCache = @'
apps:
  default:
    oauth2_tokens:
      default:
        oauth2:
          refresh_token: "local-refresh-token"
'@
        Set-Content -LiteralPath $cachePath -Value $originalCache -NoNewline
        $script:probeCount = 0
        $invoker = {
            param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

            if ($Arguments[0] -eq 'signin') { return @('signed in') }
            return @('{"fields":[{"label":"X_API_CLIENT_ID","value":"client-id"},{"label":"X_API_CLIENT_SECRET","value":"client-secret"},{"label":"X_API_REFRESH_TOKEN","value":"one-password-refresh-token"}]}')
        }

        {
            Invoke-HermesXApiCredentialScope `
                -DataDir $dataDir `
                -InvokeOnePassword $invoker `
                -TokenProbe {
                    $script:probeCount++
                    return $false
                } `
                -Action { 'must not run' }
        } | Should -Throw 'Hermes X API token probe failed.'
        $script:probeCount | Should -Be 1
        (Get-Content -LiteralPath $cachePath -Raw) | Should -BeExactly $originalCache
    }

    It 'should sync a refresh token rotated by a successful probe back to 1Password' {
        $dataDir = Join-Path $TestDrive 'hermes-rotated-token'
        $xurlDir = Join-Path $dataDir '.xurl'
        $null = New-Item -ItemType Directory -Path $xurlDir -Force
        $script:editedRefreshToken = ''
        $script:actionRan = $false
        Write-HermesXApiAuthCache `
            -DataDir $dataDir `
            -ClientId 'client-id' `
            -ClientSecret 'client-secret' `
            -RefreshToken 'local-refresh-token'
        $invoker = {
            param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

            $global:LASTEXITCODE = 0
            if ($Arguments[0] -eq 'signin') { return @('signed in') }
            if ($Arguments[0] -eq 'item' -and $Arguments[1] -eq 'get') {
                return @('{
                    "fields":[
                        {"label":"X_API_CLIENT_ID","value":"client-id"},
                        {"label":"X_API_CLIENT_SECRET","value":"client-secret"},
                        {"label":"X_API_REFRESH_TOKEN","section":{"label":"Refresh Token"},"value":"local-refresh-token"}
                    ]
                }')
            }
            if ($Arguments[0] -eq 'item' -and $Arguments[1] -eq 'edit') {
                $templateIndex = [Array]::IndexOf($Arguments, '--template')
                $template = Get-Content -LiteralPath $Arguments[$templateIndex + 1] -Raw | ConvertFrom-Json
                $script:editedRefreshToken = [string]($template.fields | Where-Object label -eq 'X_API_REFRESH_TOKEN').value
                return @('updated')
            }
            throw "Unexpected op invocation: $($Arguments -join '|')"
        }

        $result = Invoke-HermesXApiCredentialScope `
            -DataDir $dataDir `
            -InvokeOnePassword $invoker `
            -TokenProbe {
                Write-HermesXApiAuthCache `
                    -DataDir $dataDir `
                    -ClientId 'client-id' `
                    -ClientSecret 'client-secret' `
                    -RefreshToken 'rotated-refresh-token' `
                    -Force
                return [PSCustomObject]@{ Kind = 'Success'; ExitCode = 0 }
            } `
            -Action {
                $script:actionRan = $true
                return 'started'
            }

        $result | Should -Be 'started'
        $script:actionRan | Should -BeTrue
        $script:editedRefreshToken | Should -Be 'rotated-refresh-token'
    }

    It 'should preserve a rotated local token when its 1Password synchronization fails' {
        $dataDir = Join-Path $TestDrive 'hermes-rotated-token-sync-failure'
        $xurlDir = Join-Path $dataDir '.xurl'
        $null = New-Item -ItemType Directory -Path $xurlDir -Force
        Write-HermesXApiAuthCache `
            -DataDir $dataDir `
            -ClientId 'client-id' `
            -ClientSecret 'client-secret' `
            -RefreshToken 'local-refresh-token'
        $script:actionRan = $false
        $invoker = {
            param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

            $global:LASTEXITCODE = 0
            if ($Arguments[0] -eq 'signin') { return @('signed in') }
            if ($Arguments[0] -eq 'item' -and $Arguments[1] -eq 'get') {
                return @('{"fields":[{"label":"X_API_CLIENT_ID","value":"client-id"},{"label":"X_API_CLIENT_SECRET","value":"client-secret"},{"label":"X_API_REFRESH_TOKEN","section":{"label":"Refresh Token"},"value":"local-refresh-token"}]}')
            }
            if ($Arguments[0] -eq 'item' -and $Arguments[1] -eq 'edit') {
                $global:LASTEXITCODE = 73
                return @('redacted synchronization failure')
            }
            throw "Unexpected op invocation: $($Arguments -join '|')"
        }

        {
            Invoke-HermesXApiCredentialScope `
                -DataDir $dataDir `
                -InvokeOnePassword $invoker `
                -TokenProbe {
                    Write-HermesXApiAuthCache `
                        -DataDir $dataDir `
                        -ClientId 'client-id' `
                        -ClientSecret 'client-secret' `
                        -RefreshToken 'rotated-refresh-token' `
                        -Force
                    return [PSCustomObject]@{ Kind = 'Success'; ExitCode = 0 }
                } `
                -Action {
                    $script:actionRan = $true
                    return 'started'
                }
        } | Should -Throw 'Hermes X API refresh token could not be written to 1Password.'
        $script:actionRan | Should -BeFalse
        (Get-HermesXApiRefreshTokenFromCache -DataDir $dataDir) | Should -Be 'rotated-refresh-token'
    }

    It 'should retry a previously failed 1Password sync after an unchanged successful probe' {
        $dataDir = Join-Path $TestDrive 'hermes-pending-token-sync'
        $xurlDir = Join-Path $dataDir '.xurl'
        $null = New-Item -ItemType Directory -Path $xurlDir -Force
        Write-HermesXApiAuthCache `
            -DataDir $dataDir `
            -ClientId 'client-id' `
            -ClientSecret 'client-secret' `
            -RefreshToken 'local-rotated-token'
        $script:editedRefreshToken = ''
        $invoker = {
            param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

            $global:LASTEXITCODE = 0
            if ($Arguments[0] -eq 'signin') { return @('signed in') }
            if ($Arguments[0] -eq 'item' -and $Arguments[1] -eq 'get') {
                return @('{"fields":[{"label":"X_API_CLIENT_ID","value":"client-id"},{"label":"X_API_CLIENT_SECRET","value":"client-secret"},{"label":"X_API_REFRESH_TOKEN","section":{"label":"Refresh Token"},"value":"stale-onepassword-token"}]}')
            }
            if ($Arguments[0] -eq 'item' -and $Arguments[1] -eq 'edit') {
                $templateIndex = [Array]::IndexOf($Arguments, '--template')
                $template = Get-Content -LiteralPath $Arguments[$templateIndex + 1] -Raw | ConvertFrom-Json
                $script:editedRefreshToken = [string]($template.fields | Where-Object label -eq 'X_API_REFRESH_TOKEN').value
                return @('updated')
            }
            throw "Unexpected op invocation: $($Arguments -join '|')"
        }

        $result = Invoke-HermesXApiCredentialScope `
            -DataDir $dataDir `
            -InvokeOnePassword $invoker `
            -TokenProbe { return [PSCustomObject]@{ Kind = 'Success'; ExitCode = 0 } } `
            -Action { return 'started' }

        $result | Should -Be 'started'
        $script:editedRefreshToken | Should -Be 'local-rotated-token'
    }
}
