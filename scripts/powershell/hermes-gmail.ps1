<#
.SYNOPSIS
    Hermes Gmail MCP の OAuth と接続確認を、プロファイル単位で実行する。
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('auth', 'test')]
    [string]$Action,

    [Parameter(Mandatory)]
    [Alias('Profile')]
    [string]$HermesProfile,

    [string]$ComposeFile = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/Invoke-ExternalCommand.ps1')

function Get-HermesGmailComposeFile {
    [CmdletBinding()]
    param([string]$ComposeFile = '')

    if (-not [string]::IsNullOrWhiteSpace($ComposeFile)) {
        return [System.IO.Path]::GetFullPath($ComposeFile)
    }
    if (-not [string]::IsNullOrWhiteSpace($env:HERMES_COMPOSE_FILE)) {
        return [System.IO.Path]::GetFullPath($env:HERMES_COMPOSE_FILE)
    }

    $repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    return [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot 'docker/hermes-agent/compose.yml'))
}

function Get-HermesGmailDataDir {
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace($env:HERMES_DATA_DIR)) {
        return [System.IO.Path]::GetFullPath($env:HERMES_DATA_DIR)
    }
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        return [System.IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.hermes'))
    }
    if (-not [string]::IsNullOrWhiteSpace($env:HOME)) {
        return [System.IO.Path]::GetFullPath((Join-Path $env:HOME '.hermes'))
    }

    $userProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    if ([string]::IsNullOrWhiteSpace($userProfile)) {
        throw [System.InvalidOperationException]::new('Unable to resolve the current user profile.')
    }
    return [System.IO.Path]::GetFullPath((Join-Path $userProfile '.hermes'))
}

function Get-HermesGmailProfileContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$HermesProfile,
        [Parameter(Mandatory)]
        [string]$DataDir
    )

    if ($HermesProfile -notmatch '^[a-z0-9][a-z0-9_-]*$') {
        throw [System.InvalidOperationException]::new("Invalid Hermes profile: $HermesProfile")
    }

    if ($HermesProfile -eq 'default') {
        $hostHome = $DataDir
        $containerHome = '/opt/data'
    }
    else {
        $hostHome = Join-Path (Join-Path $DataDir 'profiles') $HermesProfile
        $containerHome = "/opt/data/profiles/$HermesProfile"
    }

    if (-not (Test-Path -LiteralPath $hostHome -PathType Container)) {
        throw [System.InvalidOperationException]::new("Hermes profile is not installed: $HermesProfile")
    }
    $item = Get-Item -LiteralPath $hostHome -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw [System.InvalidOperationException]::new("Hermes profile must not be a symbolic link: $HermesProfile")
    }

    return [PSCustomObject]@{
        HostHome      = $hostHome
        ContainerHome = $containerHome
        TokenCache    = Join-Path $hostHome 'mcp-tokens/gmail.json'
    }
}

function Test-HermesGmailPathUnderRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Root
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $rootWithSeparator = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
    return $fullPath.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
    $fullPath.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-HermesGmailTokenCacheContext {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$HostHome)

    $tokenCacheParent = Join-Path $HostHome 'mcp-tokens'
    if (-not (Test-Path -LiteralPath $tokenCacheParent)) {
        $null = New-Item -ItemType Directory -Path $tokenCacheParent -Force
    }
    $parent = Get-Item -LiteralPath $tokenCacheParent -Force
    if (($parent.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
        -not $parent.PSIsContainer) {
        throw [System.InvalidOperationException]::new('Gmail token cache parent is invalid.')
    }

    $resolvedHostHome = (Resolve-Path -LiteralPath $HostHome).ProviderPath
    $resolvedParent = (Resolve-Path -LiteralPath $tokenCacheParent).ProviderPath
    $expectedParent = Join-Path $resolvedHostHome 'mcp-tokens'
    if (-not $resolvedParent.Equals($expectedParent, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw [System.InvalidOperationException]::new('Gmail token cache parent is invalid.')
    }

    $tokenCache = Join-Path $resolvedParent 'gmail.json'
    if (-not (Test-HermesGmailPathUnderRoot -Path $tokenCache -Root $resolvedHostHome)) {
        throw [System.InvalidOperationException]::new('Gmail token cache parent is invalid.')
    }
    return [PSCustomObject]@{
        Parent     = $resolvedParent
        TokenCache = $tokenCache
    }
}

function Test-HermesGmailTokenCache {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TokenCache)

    if (-not (Test-Path -LiteralPath $TokenCache -PathType Leaf)) {
        return $false
    }
    $item = Get-Item -LiteralPath $TokenCache -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        return $false
    }

    if ($IsWindows) {
        $acl = Get-Acl -LiteralPath $TokenCache
        $owner = $acl.GetOwner([System.Security.Principal.SecurityIdentifier])
        if ($null -eq $owner) {
            return $false
        }
        $allowedSids = @(
            $owner.Value,
            'S-1-5-18',
            'S-1-5-32-544'
        )
        foreach ($access in $acl.Access) {
            $grantsRead = $access.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow -and
                (($access.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::ReadData) -ne 0)
            if (-not $grantsRead) {
                continue
            }
            try {
                $identity = $access.IdentityReference.Translate(
                    [System.Security.Principal.SecurityIdentifier]
                ).Value
            }
            catch {
                return $false
            }
            if ($allowedSids -notcontains $identity) {
                return $false
            }
        }
        return $true
    }

    $mode = & stat -f '%Lp' $TokenCache 2>$null
    if ($LASTEXITCODE -ne 0) {
        $mode = & stat -c '%a' $TokenCache 2>$null
    }
    return $LASTEXITCODE -eq 0 -and $mode -eq '600'
}

function Invoke-HermesGmailDocker {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Arguments)

    $global:LASTEXITCODE = 0
    Invoke-Docker -Arguments $Arguments | Out-Host
    return $global:LASTEXITCODE
}

try {
    $resolvedComposeFile = Get-HermesGmailComposeFile -ComposeFile $ComposeFile
    $context = Get-HermesGmailProfileContext -HermesProfile $HermesProfile -DataDir (Get-HermesGmailDataDir)
    $tokenCacheContext = Get-HermesGmailTokenCacheContext -HostHome $context.HostHome

    if ($Action -eq 'test' -and -not (Test-HermesGmailTokenCache -TokenCache $tokenCacheContext.TokenCache)) {
        throw [System.InvalidOperationException]::new("Gmail OAuth token cache is missing or not private for profile: $HermesProfile")
    }

    $dockerArguments = @(
        'compose', '-f', $resolvedComposeFile,
        'run', '--rm', '--no-deps'
    )
    if ($Action -eq 'test') {
        $dockerArguments += '-T'
    }
    $hermesAction = if ($Action -eq 'auth') { 'login' } else { 'test' }
    $dockerArguments += @(
        '-e', "HERMES_HOME=$($context.ContainerHome)",
        'hermes', 'hermes', 'mcp', $hermesAction, 'gmail'
    )

    $exitCode = Invoke-HermesGmailDocker -Arguments $dockerArguments
    if ($exitCode -ne 0) {
        exit $exitCode
    }
    $tokenCacheContext = Get-HermesGmailTokenCacheContext -HostHome $context.HostHome
    if ($Action -eq 'auth' -and -not (Test-HermesGmailTokenCache -TokenCache $tokenCacheContext.TokenCache)) {
        throw [System.InvalidOperationException]::new("Gmail OAuth token cache is missing or not private for profile: $HermesProfile")
    }
    exit 0
}
catch {
    [Console]::Error.WriteLine('Hermes Gmail MCP command failed.')
    exit 1
}
