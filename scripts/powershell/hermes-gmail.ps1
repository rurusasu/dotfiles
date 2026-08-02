<#
.SYNOPSIS
    Hermes 全プロフィールで共有する Gmail MCP OAuth と接続確認を実行する。
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('auth', 'test')]
    [string]$Action,

    [Alias('Profile')]
    [string]$HermesProfile = '',

    [string]$ComposeFile = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/Invoke-ExternalCommand.ps1')

function Get-HermesGmailDataDir {
    if (-not [string]::IsNullOrWhiteSpace($env:HERMES_DATA_DIR)) {
        return [System.IO.Path]::GetFullPath($env:HERMES_DATA_DIR)
    }
    $homePath = if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $env:USERPROFILE
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:HOME)) {
        $env:HOME
    }
    else {
        [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $homePath '.hermes'))
}

function Get-HermesGmailComposeFile {
    param([string]$Requested)
    if (-not [string]::IsNullOrWhiteSpace($Requested)) {
        return [System.IO.Path]::GetFullPath($Requested)
    }
    if (-not [string]::IsNullOrWhiteSpace($env:HERMES_COMPOSE_FILE)) {
        return [System.IO.Path]::GetFullPath($env:HERMES_COMPOSE_FILE)
    }
    $root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    return Join-Path $root 'docker/hermes-agent/compose.yml'
}

function Test-HermesGmailWindows {
    return [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

function Set-HermesGmailPrivateAcl {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet('File', 'Directory')][string]$PathType
    )
    if (-not (Test-HermesGmailWindows)) { return }
    $expectedType = if ($PathType -eq 'Directory') { 'Container' } else { 'Leaf' }
    if (-not (Test-Path -LiteralPath $Path -PathType $expectedType)) {
        throw "Gmail credential $($PathType.ToLowerInvariant()) is missing."
    }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Gmail credential $($PathType.ToLowerInvariant()) is invalid."
    }

    $acl = Get-Acl -LiteralPath $Path
    $owner = $acl.GetOwner([System.Security.Principal.SecurityIdentifier])
    if ($null -eq $owner) { throw 'Gmail credential owner is unavailable.' }
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    if ($null -eq $currentUser) { throw 'Current Windows identity is unavailable.' }
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($access in @($acl.Access)) {
        $null = $acl.RemoveAccessRuleSpecific($access)
    }

    $inheritance = if ($PathType -eq 'Directory') {
        [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
        [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    }
    else {
        [System.Security.AccessControl.InheritanceFlags]::None
    }
    foreach ($sidValue in @(
            $owner.Value,
            $currentUser.Value,
            'S-1-5-18',
            'S-1-5-32-544'
        ) | Select-Object -Unique) {
        $identity = [System.Security.Principal.SecurityIdentifier]::new($sidValue)
        $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
            $identity,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            $inheritance,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}

function Test-HermesGmailPrivateFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        return $false
    }
    if (Test-HermesGmailWindows) {
        $acl = Get-Acl -LiteralPath $Path
        $owner = $acl.GetOwner([System.Security.Principal.SecurityIdentifier])
        if ($null -eq $owner) { return $false }
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        if ($null -eq $currentUser -or -not $acl.AreAccessRulesProtected) { return $false }
        $allowedSids = @(
            $owner.Value,
            $currentUser.Value,
            'S-1-5-18',
            'S-1-5-32-544'
        )
        foreach ($access in $acl.Access) {
            $grantsRead =
            $access.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow -and
                (($access.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::ReadData) -ne 0)
            if (-not $grantsRead) { continue }
            try {
                $identity = $access.IdentityReference.Translate(
                    [System.Security.Principal.SecurityIdentifier]
                ).Value
            }
            catch { return $false }
            if ($allowedSids -notcontains $identity) { return $false }
        }
        return $true
    }
    $mode = & stat -c '%a' $Path 2>$null
    if ($LASTEXITCODE -ne 0) { $mode = & stat -f '%Lp' $Path 2>$null }
    return $LASTEXITCODE -eq 0 -and $mode -eq '600'
}

function Get-HermesGmailSharedContext {
    $dataDir = Get-HermesGmailDataDir
    if (-not (Test-Path -LiteralPath $dataDir -PathType Container)) {
        throw 'Hermes data directory is not installed.'
    }
    $dataItem = Get-Item -LiteralPath $dataDir -Force
    if (($dataItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Hermes data directory is invalid.'
    }
    $directory = Join-Path $dataDir 'google-gmail-mcp'
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw 'Shared Gmail credential directory is missing or invalid.'
    }
    $directoryItem = Get-Item -LiteralPath $directory -Force
    if (($directoryItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Shared Gmail credential directory is missing or invalid.'
    }
    Set-HermesGmailPrivateAcl -Path $directory -PathType Directory
    $oauth = Join-Path $directory 'gcp-oauth.keys.json'
    Set-HermesGmailPrivateAcl -Path $oauth -PathType File
    if (-not (Test-HermesGmailPrivateFile -Path $oauth)) {
        throw 'Shared Gmail OAuth client is missing or not private.'
    }
    return [PSCustomObject]@{
        DataDir     = $dataDir
        OAuth       = $oauth
        Credentials = Join-Path $directory 'credentials.json'
    }
}

function Get-HermesGmailProfileContext {
    param(
        [Parameter(Mandatory)][string]$ProfileName,
        [Parameter(Mandatory)][string]$DataDir
    )
    if ($ProfileName -notmatch '^[a-z0-9][a-z0-9_-]*$') {
        throw "Invalid Hermes profile: $ProfileName"
    }
    if ($ProfileName -eq 'default') {
        $hostHome = $DataDir
        $containerHome = '/opt/data'
    }
    else {
        $hostHome = Join-Path (Join-Path $DataDir 'profiles') $ProfileName
        $containerHome = "/opt/data/profiles/$ProfileName"
    }
    if (-not (Test-Path -LiteralPath $hostHome -PathType Container)) {
        throw "Hermes profile is not installed: $ProfileName"
    }
    return [PSCustomObject]@{ ContainerHome = $containerHome }
}

try {
    $shared = Get-HermesGmailSharedContext
    if ($Action -eq 'auth') {
        if (-not [string]::IsNullOrWhiteSpace($HermesProfile)) {
            throw 'Gmail authentication is shared; do not specify a profile.'
        }
        $oldOAuth = $env:GMAIL_OAUTH_PATH
        $oldCredentials = $env:GMAIL_CREDENTIALS_PATH
        try {
            $env:GMAIL_OAUTH_PATH = $shared.OAuth
            $env:GMAIL_CREDENTIALS_PATH = $shared.Credentials
            Invoke-NativeCommand -Command 'npx' -Arguments @(
                '--yes', '@artymclabin/gmail-mcp@1.2.3', 'auth',
                '--scopes=gmail.readonly,gmail.compose'
            ) | Out-Host
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        }
        finally {
            $env:GMAIL_OAUTH_PATH = $oldOAuth
            $env:GMAIL_CREDENTIALS_PATH = $oldCredentials
        }
        if (Test-HermesGmailWindows) {
            Set-HermesGmailPrivateAcl -Path $shared.Credentials -PathType File
        }
        else {
            & chmod 600 $shared.Credentials
        }
        if (-not (Test-HermesGmailPrivateFile -Path $shared.Credentials)) {
            throw 'Shared Gmail OAuth credentials are missing or not private.'
        }
        exit 0
    }

    if ([string]::IsNullOrWhiteSpace($HermesProfile)) {
        throw 'A Hermes profile is required for Gmail MCP testing.'
    }
    Set-HermesGmailPrivateAcl -Path $shared.Credentials -PathType File
    if (-not (Test-HermesGmailPrivateFile -Path $shared.Credentials)) {
        throw 'Shared Gmail OAuth credentials are missing or not private.'
    }
    $profileContext = Get-HermesGmailProfileContext `
        -ProfileName $HermesProfile -DataDir $shared.DataDir
    $arguments = @(
        'compose', '-f', (Get-HermesGmailComposeFile -Requested $ComposeFile),
        'run', '--rm', '--no-deps', '-T',
        '-e', "HERMES_HOME=$($profileContext.ContainerHome)",
        'hermes', 'hermes', 'mcp', 'test', 'gmail'
    )
    Invoke-Docker -Arguments $arguments | Out-Host
    exit $global:LASTEXITCODE
}
catch {
    [Console]::Error.WriteLine('Hermes Gmail MCP command failed.')
    exit 1
}
