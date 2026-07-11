[CmdletBinding()]
param(
    [Parameter()]
    [string]$LocalAddress = '127.0.0.1',

    [Parameter()]
    [int]$LocalPort = 1457,

    [Parameter()]
    [switch]$CleanFailedOrcaHomes,

    [Parameter()]
    [switch]$AdoptRuntimeCodexAuth,

    [Parameter()]
    [switch]$InitializeManagedCodexHomeFromRuntimeAuth,

    [Parameter()]
    [string]$ManagedHomePath = $env:CODEX_HOME,

    [Parameter()]
    [int]$StaleAfterSeconds = 0,

    [Parameter()]
    [switch]$SkipCleanupWhenLoginActive,

    [Parameter()]
    [switch]$Watch,

    [Parameter()]
    [switch]$SingleInstance,

    [Parameter()]
    [int]$WatchIntervalSeconds = 5,

    [Parameter()]
    [int]$WatchDurationSeconds = 900,

    [Parameter()]
    [string]$OrcaDataRoot = (Join-Path $env:APPDATA 'orca')
)

function Test-CodexLoginProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Process
    )

    $processName = [string]$Process.Name
    $executableName = [System.IO.Path]::GetFileName([string]$Process.ExecutablePath)
    $commandLine = [string]$Process.CommandLine
    $codexExecutablePattern = '^codex(?:-x86_64-pc-windows-msvc)?\.exe$'
    $isCodex = $processName -imatch $codexExecutablePattern -or $executableName -imatch $codexExecutablePattern
    $isLogin = $commandLine -match '(?i)\blogin\b'

    return $isCodex -and $isLogin
}

function Get-CodexProcessCreationDate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Process
    )

    $creationDate = $Process.CreationDate
    if ($null -eq $creationDate) {
        return $null
    }

    if ($creationDate -is [datetime]) {
        return $creationDate
    }

    try {
        return [System.Management.ManagementDateTimeConverter]::ToDateTime([string]$creationDate)
    }
    catch {
        try {
            return [datetime]$creationDate
        }
        catch {
            return $null
        }
    }
}

function Test-CodexLoginProcessStale {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Process,

        [Parameter()]
        [int]$StaleAfterSeconds = 0
    )

    if ($StaleAfterSeconds -le 0) {
        return $true
    }

    $creationDate = Get-CodexProcessCreationDate -Process $Process
    if ($null -eq $creationDate) {
        return $false
    }

    return ((Get-Date) - $creationDate).TotalSeconds -ge $StaleAfterSeconds
}

function Get-CodexLoginProcesses {
    [CmdletBinding()]
    param()

    $processes = @(
        Get-CimInstance `
            -ClassName Win32_Process `
            -Filter "Name = 'codex.exe'" `
            -ErrorAction SilentlyContinue
    )

    foreach ($process in $processes) {
        if (Test-CodexLoginProcess -Process $process) {
            $process
        }
    }
}

function Test-ActiveCodexLoginProcess {
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$StaleAfterSeconds = 0
    )

    foreach ($process in @(Get-CodexLoginProcesses)) {
        if (-not (Test-CodexLoginProcessStale -Process $process -StaleAfterSeconds $StaleAfterSeconds)) {
            return $true
        }
    }

    return $false
}

function Test-CodexLoginWatcherAlreadyRunning {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ScriptName = 'stop-stale-codex-login.ps1'
    )

    $escapedScriptName = [regex]::Escape($ScriptName)
    $processes = @(
        Get-CimInstance `
            -ClassName Win32_Process `
            -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" `
            -ErrorAction SilentlyContinue
    )

    foreach ($process in $processes) {
        if ([int]$process.ProcessId -eq $PID) {
            continue
        }

        $commandLine = [string]$process.CommandLine
        $runsThisScript = $commandLine -match "(?i)\s-File\s+`"?[^`"]*$escapedScriptName`"?"
        $runsWatcher = $commandLine -match '(?i)(^|\s)-Watch(\s|$)'
        if ($runsThisScript -and $runsWatcher) {
            return $true
        }
    }

    return $false
}

function Get-JsonPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Set-JsonPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        $InputObject | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
        return
    }

    $property.Value = $Value
}

function Get-NormalizedStringProperty {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $value = Get-JsonPropertyValue -InputObject $InputObject -Name $Name
    if ($value -isnot [string]) {
        return $null
    }

    $trimmed = $value.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return $null
    }

    return $trimmed
}

function ConvertFrom-Base64UrlJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $base64 = $Value.Replace('-', '+').Replace('_', '/')
    switch ($base64.Length % 4) {
        2 { $base64 = "$base64==" }
        3 { $base64 = "$base64=" }
        0 { }
        default { return $null }
    }

    try {
        $json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($base64))
        return $json | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function ConvertFrom-JwtPayload {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [string]$Token
    )

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    $parts = $Token.Split('.')
    if ($parts.Count -lt 2) {
        return $null
    }

    return ConvertFrom-Base64UrlJson -Value $parts[1]
}

function Get-OrcaCodexAuthIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AuthJsonPath
    )

    if (-not (Test-Path -LiteralPath $AuthJsonPath -PathType Leaf)) {
        return $null
    }

    try {
        $raw = Get-Content -LiteralPath $AuthJsonPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Warning "Unable to parse Codex auth file at $AuthJsonPath."
        return $null
    }

    $tokens = Get-JsonPropertyValue -InputObject $raw -Name 'tokens'
    $idToken = Get-NormalizedStringProperty -InputObject $tokens -Name 'id_token'
    if (-not $idToken) {
        $idToken = Get-NormalizedStringProperty -InputObject $tokens -Name 'idToken'
    }

    $payload = ConvertFrom-JwtPayload -Token $idToken
    $authClaims = Get-JsonPropertyValue -InputObject $payload -Name 'https://api.openai.com/auth'
    $profileClaims = Get-JsonPropertyValue -InputObject $payload -Name 'https://api.openai.com/profile'

    $accountId = Get-NormalizedStringProperty -InputObject $tokens -Name 'account_id'
    if (-not $accountId) {
        $accountId = Get-NormalizedStringProperty -InputObject $tokens -Name 'accountId'
    }
    if (-not $accountId) {
        $accountId = Get-NormalizedStringProperty -InputObject $authClaims -Name 'chatgpt_account_id'
    }
    if (-not $accountId) {
        $accountId = Get-NormalizedStringProperty -InputObject $payload -Name 'chatgpt_account_id'
    }

    $email = Get-NormalizedStringProperty -InputObject $payload -Name 'email'
    if (-not $email) {
        $email = Get-NormalizedStringProperty -InputObject $profileClaims -Name 'email'
    }

    $workspaceLabel = Get-NormalizedStringProperty -InputObject $authClaims -Name 'workspace_name'
    if (-not $workspaceLabel) {
        $workspaceLabel = Get-NormalizedStringProperty -InputObject $profileClaims -Name 'workspace_name'
    }

    $workspaceAccountId = Get-NormalizedStringProperty -InputObject $authClaims -Name 'workspace_account_id'
    if (-not $workspaceAccountId) {
        $workspaceAccountId = $accountId
    }
    if (-not $workspaceAccountId) {
        $workspaceAccountId = Get-NormalizedStringProperty -InputObject $payload -Name 'chatgpt_account_id'
    }

    [pscustomobject]@{
        Email              = $email
        ProviderAccountId  = $accountId
        WorkspaceLabel     = $workspaceLabel
        WorkspaceAccountId = $workspaceAccountId
    }
}

function Test-OrcaCodexAccountIdentityMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Account,

        [Parameter(Mandatory)]
        [object]$Identity
    )

    $accountEmail = Get-NormalizedStringProperty -InputObject $Account -Name 'email'
    $accountProviderId = Get-NormalizedStringProperty -InputObject $Account -Name 'providerAccountId'
    $accountWorkspaceId = Get-NormalizedStringProperty -InputObject $Account -Name 'workspaceAccountId'

    if ($accountEmail -and $Identity.Email -and $accountEmail -ne $Identity.Email) {
        return $false
    }

    if ($accountProviderId -and $Identity.ProviderAccountId -and $accountProviderId -ne $Identity.ProviderAccountId) {
        return $false
    }

    if ($accountWorkspaceId -and $Identity.WorkspaceAccountId -and $accountWorkspaceId -ne $Identity.WorkspaceAccountId) {
        return $false
    }

    return [bool](
        ($accountEmail -and $Identity.Email -and $accountEmail -eq $Identity.Email) -or
        ($accountProviderId -and $Identity.ProviderAccountId -and $accountProviderId -eq $Identity.ProviderAccountId) -or
        ($accountWorkspaceId -and $Identity.WorkspaceAccountId -and $accountWorkspaceId -eq $Identity.WorkspaceAccountId)
    )
}

function Copy-OrcaRuntimeCodexHomeSeedFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RuntimeHomePath,

        [Parameter(Mandatory)]
        [string]$ManagedHomePath
    )

    foreach ($fileName in @('auth.json', 'config.toml', 'hooks.json', '.orca-hook-trust-provenance.json')) {
        $sourcePath = Join-Path $RuntimeHomePath $fileName
        if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
            Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $ManagedHomePath $fileName) -Force
        }
    }
}

function Get-OrcaManagedCodexHomeAccountId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManagedHomePath,

        [Parameter(Mandatory)]
        [string]$OrcaDataRoot
    )

    if ([string]::IsNullOrWhiteSpace($ManagedHomePath) -or [string]::IsNullOrWhiteSpace($OrcaDataRoot)) {
        return $null
    }

    $accountRoot = Join-Path $OrcaDataRoot 'codex-accounts'
    try {
        $resolvedHome = [System.IO.Path]::GetFullPath($ManagedHomePath).TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
        $resolvedRoot = [System.IO.Path]::GetFullPath($accountRoot).TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
    }
    catch {
        return $null
    }

    $rootWithSeparator = $resolvedRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedHome.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    $relativePath = $resolvedHome.Substring($rootWithSeparator.Length)
    $parts = @($relativePath -split '[\\/]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($parts.Count -ne 2 -or $parts[1] -ne 'home') {
        return $null
    }

    $parsedGuid = [guid]::Empty
    if (-not [guid]::TryParse($parts[0], [ref]$parsedGuid)) {
        return $null
    }

    return $parts[0]
}

function Test-ReparsePointPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    return $null -ne $item -and (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Initialize-OrcaManagedCodexHomeFromRuntimeAuth {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$OrcaDataRoot = (Join-Path $env:APPDATA 'orca'),

        [Parameter()]
        [string]$ManagedHomePath = $env:CODEX_HOME
    )

    $accountId = Get-OrcaManagedCodexHomeAccountId -ManagedHomePath $ManagedHomePath -OrcaDataRoot $OrcaDataRoot
    if (-not $accountId) {
        return $false
    }

    $runtimeHomePath = Join-Path $OrcaDataRoot 'codex-runtime-home\home'
    $runtimeAuthPath = Join-Path $runtimeHomePath 'auth.json'
    if (-not (Test-Path -LiteralPath $runtimeAuthPath -PathType Leaf)) {
        return $false
    }

    $identity = Get-OrcaCodexAuthIdentity -AuthJsonPath $runtimeAuthPath
    if ($null -eq $identity -or [string]::IsNullOrWhiteSpace($identity.Email)) {
        return $false
    }

    $accountDirectory = Split-Path -Path $ManagedHomePath -Parent
    if ((Test-ReparsePointPath -Path $accountDirectory) -or (Test-ReparsePointPath -Path $ManagedHomePath)) {
        Write-Warning "Skipping Orca Codex managed home initialization for reparse point: $ManagedHomePath"
        return $false
    }

    New-Item -ItemType Directory -Path $ManagedHomePath -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $ManagedHomePath '.orca-managed-home') -Encoding ascii -Value $accountId
    Copy-OrcaRuntimeCodexHomeSeedFiles -RuntimeHomePath $runtimeHomePath -ManagedHomePath $ManagedHomePath

    return (Test-Path -LiteralPath (Join-Path $ManagedHomePath 'auth.json') -PathType Leaf)
}

function Write-OrcaJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [object]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 100
    $tempPath = "$Path.tmp"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tempPath, "$json`n", $utf8NoBom)
    Move-Item -LiteralPath $tempPath -Destination $Path -Force
}

function Adopt-OrcaRuntimeCodexAuthAsManagedAccount {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$OrcaDataRoot = (Join-Path $env:APPDATA 'orca')
    )

    if ([string]::IsNullOrWhiteSpace($OrcaDataRoot)) {
        return $false
    }

    $runtimeHomePath = Join-Path $OrcaDataRoot 'codex-runtime-home\home'
    $runtimeAuthPath = Join-Path $runtimeHomePath 'auth.json'
    if (-not (Test-Path -LiteralPath $runtimeAuthPath -PathType Leaf)) {
        return $false
    }

    $identity = Get-OrcaCodexAuthIdentity -AuthJsonPath $runtimeAuthPath
    if ($null -eq $identity -or [string]::IsNullOrWhiteSpace($identity.Email)) {
        Write-Warning 'Codex runtime auth exists, but Orca could not resolve an account email from it.'
        return $false
    }

    $dataPath = Join-Path $OrcaDataRoot 'orca-data.json'
    if (-not (Test-Path -LiteralPath $dataPath -PathType Leaf)) {
        Write-Warning "Orca data file does not exist: $dataPath"
        return $false
    }

    try {
        $data = Get-Content -LiteralPath $dataPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Warning "Unable to parse Orca data at $dataPath."
        return $false
    }

    $settings = Get-JsonPropertyValue -InputObject $data -Name 'settings'
    if ($null -eq $settings) {
        $settings = [pscustomobject]@{}
        Set-JsonPropertyValue -InputObject $data -Name 'settings' -Value $settings
    }

    $accounts = @(Get-JsonPropertyValue -InputObject $settings -Name 'codexManagedAccounts')
    $matchingAccount = $accounts | Where-Object { Test-OrcaCodexAccountIdentityMatch -Account $_ -Identity $identity } | Select-Object -First 1

    if ($null -ne $matchingAccount) {
        $managedHomePath = [string](Get-JsonPropertyValue -InputObject $matchingAccount -Name 'managedHomePath')
        if (-not [string]::IsNullOrWhiteSpace($managedHomePath)) {
            New-Item -ItemType Directory -Path $managedHomePath -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $managedHomePath '.orca-managed-home') -Encoding ascii -Value ([string]$matchingAccount.id)
            Copy-OrcaRuntimeCodexHomeSeedFiles -RuntimeHomePath $runtimeHomePath -ManagedHomePath $managedHomePath
        }

        Set-OrcaCodexActiveAccountSelection -Settings $settings -AccountId ([string]$matchingAccount.id)
        Write-OrcaJsonFile -Path $dataPath -Value $data
        return $true
    }

    $accountId = ([guid]::NewGuid()).ToString()
    $managedHomePath = Join-Path $OrcaDataRoot "codex-accounts\$accountId\home"
    New-Item -ItemType Directory -Path $managedHomePath -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $managedHomePath '.orca-managed-home') -Encoding ascii -Value $accountId
    Copy-OrcaRuntimeCodexHomeSeedFiles -RuntimeHomePath $runtimeHomePath -ManagedHomePath $managedHomePath

    $now = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
    $account = [pscustomobject][ordered]@{
        id                  = $accountId
        email               = $identity.Email
        managedHomePath     = $managedHomePath
        managedHomeRuntime  = 'host'
        wslDistro           = $null
        wslLinuxHomePath    = $null
        providerAccountId   = $identity.ProviderAccountId
        workspaceLabel      = $identity.WorkspaceLabel
        workspaceAccountId  = $identity.WorkspaceAccountId
        createdAt           = $now
        updatedAt           = $now
        lastAuthenticatedAt = $now
    }

    Set-JsonPropertyValue -InputObject $settings -Name 'codexManagedAccounts' -Value @($accounts + $account)
    Set-OrcaCodexActiveAccountSelection -Settings $settings -AccountId $accountId

    $backupPath = "$dataPath.bak.codex-adopt-$(Get-Date -Format 'yyyyMMddHHmmss')"
    Copy-Item -LiteralPath $dataPath -Destination $backupPath -Force
    Write-OrcaJsonFile -Path $dataPath -Value $data
    Write-Host "Adopted Codex runtime auth as Orca managed account: $($identity.Email)"
    return $true
}

function Set-OrcaCodexActiveAccountSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Settings,

        [Parameter(Mandatory)]
        [string]$AccountId
    )

    Set-JsonPropertyValue -InputObject $Settings -Name 'activeCodexManagedAccountId' -Value $AccountId

    $selection = Get-JsonPropertyValue -InputObject $Settings -Name 'activeCodexManagedAccountIdsByRuntime'
    if ($null -eq $selection) {
        $selection = [pscustomobject]@{
            host = $null
            wsl  = [pscustomobject]@{}
        }
        Set-JsonPropertyValue -InputObject $Settings -Name 'activeCodexManagedAccountIdsByRuntime' -Value $selection
    }

    Set-JsonPropertyValue -InputObject $selection -Name 'host' -Value $AccountId
    if ($null -eq (Get-JsonPropertyValue -InputObject $selection -Name 'wsl')) {
        Set-JsonPropertyValue -InputObject $selection -Name 'wsl' -Value ([pscustomobject]@{})
    }
}

function Stop-StaleCodexLoginListener {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$LocalAddress = '127.0.0.1',

        [Parameter()]
        [int]$LocalPort = 1457,

        [Parameter()]
        [int]$StaleAfterSeconds = 0
    )

    $listeners = @(
        Get-NetTCPConnection `
            -LocalAddress $LocalAddress `
            -LocalPort $LocalPort `
            -State Listen `
            -ErrorAction SilentlyContinue
    )

    foreach ($owningProcess in @($listeners | Select-Object -ExpandProperty OwningProcess -Unique)) {
        if (-not $owningProcess) {
            continue
        }

        $process = Get-CimInstance `
            -ClassName Win32_Process `
            -Filter "ProcessId = $owningProcess" `
            -ErrorAction SilentlyContinue
        if ($null -eq $process) {
            continue
        }

        if (-not (Test-CodexLoginProcess -Process $process)) {
            $processName = [string]$process.Name
            Write-Warning "Codex OAuth callback port ${LocalAddress}:$LocalPort is in use by $processName (PID $owningProcess); not stopping it."
            continue
        }

        if (-not (Test-CodexLoginProcessStale -Process $process -StaleAfterSeconds $StaleAfterSeconds)) {
            Write-Warning "Codex OAuth callback listener on ${LocalAddress}:$LocalPort is still within the login grace period (PID $owningProcess); not stopping it."
            continue
        }

        Write-Host "Stopping stale Codex login listener on ${LocalAddress}:$LocalPort (PID $owningProcess)"
        Stop-Process -Id $owningProcess -Force -ErrorAction SilentlyContinue
    }
}

function Get-OrcaRegisteredCodexAccountIds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrcaDataRoot
    )

    $dataPath = Join-Path $OrcaDataRoot 'orca-data.json'
    if (-not (Test-Path -LiteralPath $dataPath)) {
        return @()
    }

    try {
        $rawData = Get-Content -LiteralPath $dataPath -Raw
    }
    catch {
        Write-Warning "Unable to read Orca data at $dataPath; not assuming registered Codex account ids."
        return @()
    }

    try {
        $data = $rawData | ConvertFrom-Json
    }
    catch {
        $fallbackIds = @(Get-OrcaRegisteredCodexAccountIdsFromText -JsonText $rawData)
        if ($fallbackIds.Count -gt 0 -or $rawData -match '(?s)"codexManagedAccounts"\s*:\s*\[') {
            return $fallbackIds
        }

        Write-Warning "Unable to parse Orca Codex account ids at $dataPath."
        return @()
    }

    $ids = @()
    foreach ($account in @($data.settings.codexManagedAccounts)) {
        foreach ($propertyName in @('id', 'accountId')) {
            $id = Get-NormalizedStringProperty -InputObject $account -Name $propertyName
            if (-not [string]::IsNullOrWhiteSpace($id)) {
                $ids += $id.ToLowerInvariant()
            }
        }
    }

    return @($ids | Select-Object -Unique)
}

function Get-OrcaRegisteredCodexAccountIdsFromText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JsonText
    )

    if ([string]::IsNullOrWhiteSpace($JsonText)) {
        return @()
    }

    $ids = @()
    $guidPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
    $managedAccountsMatch = [regex]::Match(
        $JsonText,
        '(?s)"codexManagedAccounts"\s*:\s*\[(?<accounts>.*?)\]'
    )

    if ($managedAccountsMatch.Success) {
        $accountText = $managedAccountsMatch.Groups['accounts'].Value
        foreach ($match in [regex]::Matches($accountText, "(?i)""(?:id|accountId)""\s*:\s*""(?<id>$guidPattern)""")) {
            $ids += $match.Groups['id'].Value.ToLowerInvariant()
        }
    }

    foreach ($match in [regex]::Matches($JsonText, "(?i)""activeCodexManagedAccountId""\s*:\s*""(?<id>$guidPattern)""")) {
        $ids += $match.Groups['id'].Value.ToLowerInvariant()
    }

    $activeByRuntimeMatch = [regex]::Match(
        $JsonText,
        '(?s)"activeCodexManagedAccountIdsByRuntime"\s*:\s*\{(?<accounts>.*?)\}'
    )
    if ($activeByRuntimeMatch.Success) {
        foreach ($match in [regex]::Matches($activeByRuntimeMatch.Groups['accounts'].Value, "(?i)""(?<id>$guidPattern)""")) {
            $ids += $match.Groups['id'].Value.ToLowerInvariant()
        }
    }

    return @($ids | Select-Object -Unique)
}

function Test-OrcaCodexAccountInUse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AccountPath
    )

    $escapedAccountPath = [regex]::Escape($AccountPath)
    $matchingProcesses = @(
        Get-CimInstance `
            -ClassName Win32_Process `
            -Filter "Name = 'codex.exe'" `
            -ErrorAction SilentlyContinue |
            Where-Object { [string]$_.CommandLine -match $escapedAccountPath }
    )

    return $matchingProcesses.Count -gt 0
}

function Remove-FailedOrcaCodexAccountHomes {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$OrcaDataRoot = (Join-Path $env:APPDATA 'orca'),

        [Parameter()]
        [switch]$SkipWhenCodexLoginActive,

        [Parameter()]
        [int]$StaleAfterSeconds = 0
    )

    if ([string]::IsNullOrWhiteSpace($OrcaDataRoot)) {
        return
    }

    if ($SkipWhenCodexLoginActive -and (Test-ActiveCodexLoginProcess -StaleAfterSeconds $StaleAfterSeconds)) {
        Write-Warning 'Skipping Orca Codex account cleanup while a Codex login process is still active.'
        return
    }

    $accountRoot = Join-Path $OrcaDataRoot 'codex-accounts'
    if (-not (Test-Path -LiteralPath $accountRoot -PathType Container)) {
        return
    }

    $resolvedAccountRoot = [System.IO.Path]::GetFullPath($accountRoot)
    $rootWithSeparator = $resolvedAccountRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar
    $registeredIds = @(Get-OrcaRegisteredCodexAccountIds -OrcaDataRoot $OrcaDataRoot)

    foreach ($accountDirectory in Get-ChildItem -LiteralPath $accountRoot -Directory -Force) {
        $accountId = [string]$accountDirectory.Name
        $parsedGuid = [guid]::Empty
        if (-not [guid]::TryParse($accountId, [ref]$parsedGuid)) {
            continue
        }

        if ($registeredIds -contains $accountId.ToLowerInvariant()) {
            continue
        }

        if (($accountDirectory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            Write-Warning "Skipping Orca Codex account reparse point: $($accountDirectory.FullName)"
            continue
        }

        $homePath = Join-Path $accountDirectory.FullName 'home'
        $authJson = Join-Path $homePath 'auth.json'
        $markerPath = Join-Path $homePath '.orca-managed-home'
        $hasAuthJson = Test-Path -LiteralPath $authJson
        $hasMatchingManagedMarker = $false
        if (Test-Path -LiteralPath $markerPath -PathType Leaf) {
            try {
                $hasMatchingManagedMarker = ((Get-Content -LiteralPath $markerPath -Raw).Trim() -eq $accountId)
            }
            catch {
                $hasMatchingManagedMarker = $false
            }
        }

        if ($hasAuthJson -and -not $hasMatchingManagedMarker) {
            continue
        }

        $resolvedAccountPath = [System.IO.Path]::GetFullPath($accountDirectory.FullName)
        if (-not $resolvedAccountPath.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Warning "Skipping Orca Codex account outside expected root: $resolvedAccountPath"
            continue
        }

        if (Test-OrcaCodexAccountInUse -AccountPath $resolvedAccountPath) {
            Write-Warning "Skipping Orca Codex account still referenced by a codex.exe process: $resolvedAccountPath"
            continue
        }

        Write-Host "Removing failed Orca Codex account home: $resolvedAccountPath"
        Remove-Item -LiteralPath $resolvedAccountPath -Recurse -Force
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    if ($Watch -and $SingleInstance -and (Test-CodexLoginWatcherAlreadyRunning)) {
        Write-Host 'Codex login cleanup watcher is already running; exiting.'
        return
    }

    if ($InitializeManagedCodexHomeFromRuntimeAuth) {
        if (Initialize-OrcaManagedCodexHomeFromRuntimeAuth -OrcaDataRoot $OrcaDataRoot -ManagedHomePath $ManagedHomePath) {
            exit 0
        }

        exit 1
    }

    if ($AdoptRuntimeCodexAuth) {
        Adopt-OrcaRuntimeCodexAuthAsManagedAccount -OrcaDataRoot $OrcaDataRoot | Out-Null
    }

    $startedAt = Get-Date
    do {
        Stop-StaleCodexLoginListener `
            -LocalAddress $LocalAddress `
            -LocalPort $LocalPort `
            -StaleAfterSeconds $StaleAfterSeconds

        if ($CleanFailedOrcaHomes) {
            Remove-FailedOrcaCodexAccountHomes `
                -OrcaDataRoot $OrcaDataRoot `
                -SkipWhenCodexLoginActive:$SkipCleanupWhenLoginActive `
                -StaleAfterSeconds $StaleAfterSeconds
        }

        if (-not $Watch) {
            break
        }

        if (((Get-Date) - $startedAt).TotalSeconds -ge $WatchDurationSeconds) {
            break
        }

        Start-Sleep -Seconds $WatchIntervalSeconds
    }
    while ($true)
}
