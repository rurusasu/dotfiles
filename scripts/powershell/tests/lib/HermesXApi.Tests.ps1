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
        foreach ($name in @(
                'X_API_CLIENT_ID',
                'X_API_CLIENT_SECRET',
                'DOTFILES_HERMES_XAPI_1PASSWORD_ACCOUNT',
                'DOTFILES_HERMES_XAPI_1PASSWORD_VAULT',
                'DOTFILES_HERMES_XAPI_1PASSWORD_ITEM'
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
}
