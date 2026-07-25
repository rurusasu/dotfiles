<#
.SYNOPSIS
    Reads Hermes X API OAuth credentials from 1Password for PowerShell callers.
#>

$script:DefaultHermesXApiOnePasswordInvoker = {
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Arguments
    )

    $output = @(& op @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw [System.InvalidOperationException]::new('Hermes X API 1Password retrieval failed.')
    }
    return $output
}

function ConvertFrom-HermesXApiJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Json,
        [Parameter(Mandatory)]
        [int]$Depth
    )

    $command = Get-Command -Name ConvertFrom-Json -CommandType Cmdlet -ErrorAction Stop
    if ($command.Parameters.ContainsKey('Depth')) {
        return ($Json | ConvertFrom-Json -Depth $Depth -ErrorAction Stop)
    }
    return ($Json | ConvertFrom-Json -ErrorAction Stop)
}

function ConvertTo-HermesXApiItemObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Output
    )

    if ($Output.Count -eq 1 -and $Output[0] -isnot [string]) {
        return $Output[0]
    }

    $json = @($Output | ForEach-Object { [string]$_ }) -join "`n"
    try {
        return ConvertFrom-HermesXApiJson -Json $json -Depth 64
    }
    catch {
        throw [System.InvalidOperationException]::new('Hermes X API 1Password retrieval failed.')
    }
}

function Get-HermesXApiOnePasswordAccount {
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace($env:DOTFILES_HERMES_XAPI_1PASSWORD_ACCOUNT)) {
        return $env:DOTFILES_HERMES_XAPI_1PASSWORD_ACCOUNT
    }
    return 'my.1password.com'
}

function Get-HermesXApiOnePasswordVault {
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace($env:DOTFILES_HERMES_XAPI_1PASSWORD_VAULT)) {
        return $env:DOTFILES_HERMES_XAPI_1PASSWORD_VAULT
    }
    return 'openclaw'
}

function Get-HermesXApiOnePasswordItem {
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace($env:DOTFILES_HERMES_XAPI_1PASSWORD_ITEM)) {
        return $env:DOTFILES_HERMES_XAPI_1PASSWORD_ITEM
    }
    return 'Hermes X API MCP'
}

function Get-HermesXApiItemFieldValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Item,
        [Parameter(Mandatory)]
        [string[]]$Labels
    )

    if ($null -eq $Item -or $null -eq $Item.fields) {
        throw [System.InvalidOperationException]::new('Hermes X API credential field is missing.')
    }

    $fields = @($Item.fields | Where-Object {
            $null -ne $_ -and
            $_.PSObject.Properties.Name -contains 'label' -and
            $_.PSObject.Properties.Name -contains 'value' -and
            $_.label -in $Labels -and
            $_.value -is [string] -and
            $_.value.Length -gt 0
        })
    if ($fields.Count -ne 1) {
        throw [System.InvalidOperationException]::new('Hermes X API credential field is missing.')
    }

    return [string]$fields[0].value
}

function Get-HermesXApiCredential {
    [CmdletBinding()]
    param(
        [scriptblock]$InvokeOnePassword = $script:DefaultHermesXApiOnePasswordInvoker
    )

    $account = Get-HermesXApiOnePasswordAccount
    $vault = Get-HermesXApiOnePasswordVault
    $itemName = Get-HermesXApiOnePasswordItem

    [void](& $InvokeOnePassword 'signin' '--account' $account)
    $itemOutput = @(& $InvokeOnePassword 'item' 'get' $itemName '--account' $account '--vault' $vault '--format' 'json')
    $item = ConvertTo-HermesXApiItemObject -Output $itemOutput

    return [PSCustomObject]@{
        ClientId     = Get-HermesXApiItemFieldValue -Item $item -Labels @('X_API_CLIENT_ID', 'client_id', 'Client ID')
        ClientSecret = Get-HermesXApiItemFieldValue -Item $item -Labels @('X_API_CLIENT_SECRET', 'client_secret', 'Client Secret')
    }
}

function Invoke-HermesXApiCredentialScope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Action,
        [scriptblock]$InvokeOnePassword = $script:DefaultHermesXApiOnePasswordInvoker
    )

    $clientIdPath = 'Env:\X_API_CLIENT_ID'
    $clientSecretPath = 'Env:\X_API_CLIENT_SECRET'
    $clientIdExists = Test-Path -LiteralPath $clientIdPath
    $clientSecretExists = Test-Path -LiteralPath $clientSecretPath
    $clientIdValue = if ($clientIdExists) { (Get-Item -LiteralPath $clientIdPath).Value } else { $null }
    $clientSecretValue = if ($clientSecretExists) { (Get-Item -LiteralPath $clientSecretPath).Value } else { $null }

    try {
        $credential = Get-HermesXApiCredential -InvokeOnePassword $InvokeOnePassword
    }
    catch {
        throw [System.InvalidOperationException]::new('Hermes X API credential retrieval failed.')
    }

    try {
        Set-Item -LiteralPath $clientIdPath -Value $credential.ClientId
        Set-Item -LiteralPath $clientSecretPath -Value $credential.ClientSecret
        return & $Action
    }
    finally {
        $credential = $null
        if ($clientIdExists) {
            Set-Item -LiteralPath $clientIdPath -Value $clientIdValue
        }
        else {
            Remove-Item -LiteralPath $clientIdPath -ErrorAction SilentlyContinue
        }
        if ($clientSecretExists) {
            Set-Item -LiteralPath $clientSecretPath -Value $clientSecretValue
        }
        else {
            Remove-Item -LiteralPath $clientSecretPath -ErrorAction SilentlyContinue
        }
    }
}
