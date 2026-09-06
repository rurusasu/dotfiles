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

function Get-HermesXApiOAuthItem {
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace($env:DOTFILES_HERMES_XAPI_OAUTH_ITEM)) {
        return $env:DOTFILES_HERMES_XAPI_OAUTH_ITEM
    }
    return Get-HermesXApiOnePasswordItem
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

function Get-HermesXApiRefreshToken {
    [CmdletBinding()]
    param(
        [scriptblock]$InvokeOnePassword = $script:DefaultHermesXApiOnePasswordInvoker
    )

    $account = Get-HermesXApiOnePasswordAccount
    $vault = Get-HermesXApiOnePasswordVault
    $itemName = Get-HermesXApiOAuthItem

    [void](& $InvokeOnePassword 'signin' '--account' $account)
    $itemOutput = @(& $InvokeOnePassword 'item' 'get' $itemName '--account' $account '--vault' $vault '--format' 'json')
    $item = ConvertTo-HermesXApiItemObject -Output $itemOutput
    return Get-HermesXApiItemFieldValue -Item $item -Labels @('X_API_REFRESH_TOKEN', 'refresh_token', 'Refresh Token')
}

function Get-HermesXApiRefreshTokenFromCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DataDir
    )

    $cachePath = Join-Path ([System.IO.Path]::GetFullPath($DataDir)) '.xurl/auth.yml'
    if (-not (Test-Path -LiteralPath $cachePath -PathType Leaf)) {
        throw [System.InvalidOperationException]::new("xurl OAuth cache is missing: $cachePath")
    }

    $cache = Get-Content -LiteralPath $cachePath -Raw
    $match = [regex]::Match($cache, '(?m)^\s+refresh_token:\s*(?:"([^"]+)"|([^\s#]+))\s*$')
    if (-not $match.Success) {
        throw [System.InvalidOperationException]::new('xurl refresh token is missing.')
    }

    return $(if ($match.Groups[1].Success) { $match.Groups[1].Value } else { $match.Groups[2].Value })
}

function Sync-HermesXApiRefreshTokenToOnePassword {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DataDir,
        [scriptblock]$InvokeOnePassword = $script:DefaultHermesXApiOnePasswordInvoker
    )

    $account = Get-HermesXApiOnePasswordAccount
    $vault = Get-HermesXApiOnePasswordVault
    $itemName = Get-HermesXApiOAuthItem
    $refreshToken = Get-HermesXApiRefreshTokenFromCache -DataDir $DataDir
    [void](& $InvokeOnePassword 'signin' '--account' $account)
    $itemOutput = @(& $InvokeOnePassword 'item' 'get' $itemName '--account' $account '--vault' $vault '--format' 'json')
    $item = ConvertTo-HermesXApiItemObject -Output $itemOutput
    $fields = @($item.fields | Where-Object {
            $_.label -eq 'X_API_REFRESH_TOKEN' -and
            $_.section.label -eq 'Refresh Token'
        })
    if ($fields.Count -ne 1) {
        throw [System.InvalidOperationException]::new('Refresh Token/X_API_REFRESH_TOKEN field is missing or duplicated.')
    }
    if ([string]$fields[0].value -eq $refreshToken) {
        return
    }
    $fields[0].value = $refreshToken

    $templatePath = [System.IO.Path]::GetTempFileName()
    try {
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($templatePath, ($item | ConvertTo-Json -Depth 64 -Compress), $utf8NoBom)
        [void](& $InvokeOnePassword 'item' 'edit' $itemName '--account' $account '--vault' $vault '--template' $templatePath)
        if ($LASTEXITCODE -ne 0) {
            throw [System.InvalidOperationException]::new('Hermes X API refresh token could not be written to 1Password.')
        }
    }
    finally {
        Remove-Item -LiteralPath $templatePath -Force -ErrorAction SilentlyContinue
    }
}

function Write-HermesXApiAuthCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DataDir,
        [Parameter(Mandatory)]
        [string]$ClientId,
        [Parameter(Mandatory)]
        [string]$ClientSecret,
        [Parameter(Mandatory)]
        [string]$RefreshToken,
        [switch]$Force
    )

    foreach ($value in @($ClientId, $ClientSecret, $RefreshToken)) {
        if ([string]::IsNullOrWhiteSpace($value) -or $value.Contains("`r") -or $value.Contains("`n")) {
            throw [System.InvalidOperationException]::new('Hermes X API OAuth cache value is invalid.')
        }
    }

    $xurlDir = Join-Path $DataDir '.xurl'
    $cachePath = Join-Path $xurlDir 'auth.yml'
    $null = New-Item -ItemType Directory -Path $xurlDir -Force
    $directory = Get-Item -LiteralPath $xurlDir -Force
    if (($directory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw [System.InvalidOperationException]::new('Hermes X API OAuth cache directory must not be a reparse point.')
    }
    if (-not $Force -and $env:DOTFILES_HERMES_XAPI_FORCE_CACHE_SYNC -ne '1' -and
        (Test-Path -LiteralPath $cachePath -PathType Leaf)) {
        $existingCache = Get-Content -LiteralPath $cachePath -Raw
        if ($existingCache -match '(?m)^\s*refresh_token:') {
            return
        }
    }

    $jsonClientId = $ClientId | ConvertTo-Json -Compress
    $jsonClientSecret = $ClientSecret | ConvertTo-Json -Compress
    $jsonRefreshToken = $RefreshToken | ConvertTo-Json -Compress
    $temporary = Join-Path $xurlDir ('.auth.yml.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    $content = @(
        'apps:',
        '  default:',
        "    client_id: $jsonClientId",
        "    client_secret: $jsonClientSecret",
        '    oauth2_tokens:',
        '      default:',
        '        type: oauth2',
        '        oauth2:',
        "          refresh_token: $jsonRefreshToken",
        'default_app: default'
    ) -join "`n"

    try {
        Set-Content -LiteralPath $temporary -Value $content -Encoding utf8NoBOM -NoNewline
        $isWindowsPlatform = ($PSVersionTable.PSEdition -eq 'Desktop') -or ($IsWindows -eq $true)
        if ($isWindowsPlatform) {
            $currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
            if ($null -eq $currentSid) {
                throw [System.InvalidOperationException]::new('Could not resolve the current Windows user.')
            }
            $fileSecurity = [System.Security.AccessControl.FileSecurity]::new()
            $fileSecurity.SetOwner($currentSid)
            $fileSecurity.SetAccessRuleProtection($true, $false)
            $readRule = [System.Security.AccessControl.FileSystemAccessRule]::new(
                $currentSid,
                [System.Security.AccessControl.FileSystemRights]::Read,
                [System.Security.AccessControl.InheritanceFlags]::None,
                [System.Security.AccessControl.PropagationFlags]::None,
                [System.Security.AccessControl.AccessControlType]::Allow
            )
            [void]$fileSecurity.AddAccessRule($readRule)
            Set-Acl -LiteralPath $temporary -AclObject $fileSecurity
        }
        else {
            & chmod 600 $temporary
            if ($LASTEXITCODE -ne 0) {
                throw [System.InvalidOperationException]::new('Could not protect Hermes X API OAuth cache.')
            }
        }
        Move-Item -LiteralPath $temporary -Destination $cachePath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
    }
}

function Resolve-HermesXApiTokenProbeResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$ExitCode,
        [object[]]$Output = @()
    )

    if ($ExitCode -eq 0) {
        return [PSCustomObject]@{ Kind = 'Success'; ExitCode = 0 }
    }

    $diagnostic = @($Output | ForEach-Object { [string]$_ }) -join "`n"
    $authPattern = 'Auth Error: TokenNotFound|oauth2 token not found|invalid_grant|invalid_client|unauthorized_client'
    $kind = if ($diagnostic -match $authPattern) { 'AuthFailure' } else { 'InfrastructureFailure' }
    return [PSCustomObject]@{ Kind = $kind; ExitCode = $ExitCode }
}

function ConvertTo-HermesXApiTokenProbeResult {
    [CmdletBinding()]
    param([AllowNull()][object]$Result)

    if ($Result -is [bool]) {
        return [PSCustomObject]@{
            Kind     = $(if ($Result) { 'Success' } else { 'InfrastructureFailure' })
            ExitCode = $(if ($Result) { 0 } else { 1 })
        }
    }
    if ($null -ne $Result -and $Result.PSObject.Properties.Name -contains 'Kind' -and
        [string]$Result.Kind -in @('Success', 'AuthFailure', 'InfrastructureFailure')) {
        $exitCode = if ($Result.PSObject.Properties.Name -contains 'ExitCode') { [int]$Result.ExitCode } else { 1 }
        return [PSCustomObject]@{ Kind = [string]$Result.Kind; ExitCode = $exitCode }
    }
    return [PSCustomObject]@{ Kind = 'InfrastructureFailure'; ExitCode = 1 }
}

function Restore-HermesXApiAuthCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CachePath,
        [Parameter(Mandatory)][bool]$Existed,
        [AllowNull()][byte[]]$Content
    )

    if ($Existed) {
        [System.IO.File]::WriteAllBytes($CachePath, $Content)
    }
    else {
        Remove-Item -LiteralPath $CachePath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-HermesXApiCredentialScope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Action,
        [string]$DataDir = '',
        [scriptblock]$TokenProbe,
        [scriptblock]$InvokeOnePassword = $script:DefaultHermesXApiOnePasswordInvoker
    )

    $clientIdPath = 'Env:\X_API_CLIENT_ID'
    $clientSecretPath = 'Env:\X_API_CLIENT_SECRET'
    $clientIdExists = Test-Path -LiteralPath $clientIdPath
    $clientSecretExists = Test-Path -LiteralPath $clientSecretPath
    $clientIdValue = if ($clientIdExists) { (Get-Item -LiteralPath $clientIdPath).Value } else { $null }
    $clientSecretValue = if ($clientSecretExists) { (Get-Item -LiteralPath $clientSecretPath).Value } else { $null }
    $cachePath = $null
    $cacheExisted = $false
    $cacheContent = $null
    $cacheCommitted = $false

    if (-not [string]::IsNullOrWhiteSpace($DataDir)) {
        $cachePath = Join-Path ([System.IO.Path]::GetFullPath($DataDir)) '.xurl/auth.yml'
        $cacheExisted = Test-Path -LiteralPath $cachePath -PathType Leaf
        if ($cacheExisted) {
            $cacheContent = [System.IO.File]::ReadAllBytes($cachePath)
        }
        elseif (Test-Path -LiteralPath $cachePath) {
            throw [System.InvalidOperationException]::new('Hermes X API OAuth cache path must be a regular file.')
        }
    }

    try {
        $credential = Get-HermesXApiCredential -InvokeOnePassword $InvokeOnePassword
    }
    catch {
        throw [System.InvalidOperationException]::new('Hermes X API credential retrieval failed.')
    }

    try {
        Set-Item -LiteralPath $clientIdPath -Value $credential.ClientId
        Set-Item -LiteralPath $clientSecretPath -Value $credential.ClientSecret
        if (-not [string]::IsNullOrWhiteSpace($DataDir)) {
            $refreshToken = Get-HermesXApiRefreshToken -InvokeOnePassword $InvokeOnePassword
            Write-HermesXApiAuthCache `
                -DataDir $DataDir `
                -ClientId $credential.ClientId `
                -ClientSecret $credential.ClientSecret `
                -RefreshToken $refreshToken
            if ($null -ne $TokenProbe) {
                $tokenBeforeProbe = Get-HermesXApiRefreshTokenFromCache -DataDir $DataDir
                try {
                    $probe = ConvertTo-HermesXApiTokenProbeResult -Result (& $TokenProbe)
                }
                catch {
                    $probe = [PSCustomObject]@{ Kind = 'InfrastructureFailure'; ExitCode = 1 }
                }
                if ($probe.Kind -eq 'InfrastructureFailure') {
                    throw [System.InvalidOperationException]::new('Hermes X API token probe failed.')
                }
                if ($probe.Kind -eq 'AuthFailure') {
                    Write-HermesXApiAuthCache `
                        -DataDir $DataDir `
                        -ClientId $credential.ClientId `
                        -ClientSecret $credential.ClientSecret `
                        -RefreshToken $refreshToken `
                        -Force
                    $tokenBeforeProbe = Get-HermesXApiRefreshTokenFromCache -DataDir $DataDir
                    try {
                        $probe = ConvertTo-HermesXApiTokenProbeResult -Result (& $TokenProbe)
                    }
                    catch {
                        $probe = [PSCustomObject]@{ Kind = 'InfrastructureFailure'; ExitCode = 1 }
                    }
                    if ($probe.Kind -eq 'AuthFailure') {
                        throw [System.InvalidOperationException]::new(
                            'Hermes X API OAuth is invalid. Run task hermes:xapi:setup to reauthorize it.'
                        )
                    }
                    if ($probe.Kind -ne 'Success') {
                        throw [System.InvalidOperationException]::new('Hermes X API token probe failed.')
                    }
                }
                $cacheCommitted = $true
                Sync-HermesXApiRefreshTokenToOnePassword `
                    -DataDir $DataDir `
                    -InvokeOnePassword $InvokeOnePassword
            }
            $cacheCommitted = $true
        }
        return & $Action
    }
    catch {
        if ($null -ne $cachePath -and -not $cacheCommitted) {
            Restore-HermesXApiAuthCache `
                -CachePath $cachePath `
                -Existed $cacheExisted `
                -Content $cacheContent
        }
        throw
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
