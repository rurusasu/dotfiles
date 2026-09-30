function Get-ChezmoiPersonalAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ChezmoiExe
    )

    $output = & $ChezmoiExe execute-template '{{ .op_account_personal }}' 2>$null
    if ($LASTEXITCODE -ne 0) {
        return ''
    }

    return ([string] ($output -join '')).Trim()
}

function Get-ChezmoiOpEnvironmentReference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ChezmoiExe
    )

    $output = & $ChezmoiExe execute-template '{{ toJson .mcp_servers }}' 2>$null
    if ($LASTEXITCODE -ne 0) {
        return @{}
    }

    try {
        $servers = ([string] ($output -join '') | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        return @{}
    }

    $references = @{}
    foreach ($server in @($servers)) {
        if (-not $server.op_env) {
            continue
        }

        foreach ($entry in $server.op_env.PSObject.Properties) {
            $reference = [string] $entry.Value
            if ($reference -match '^op://') {
                $references[$reference] = Get-ChezmoiSecretEnvironmentVariableName -Reference $reference
            }
        }
    }

    return $references
}

function Get-ChezmoiSecretEnvironmentVariableName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Reference
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Reference)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash($bytes)
    }
    finally {
        $sha256.Dispose()
    }
    $suffix = [BitConverter]::ToString($hash).Replace('-', '').ToLowerInvariant()
    return "DOTFILES_OP_PREFETCHED_REF_$suffix"
}

function Get-ChezmoiOpReadTimeout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ChezmoiExe
    )

    $output = & $ChezmoiExe execute-template '{{ .op_read_timeout_seconds }}' 2>$null
    $timeoutSeconds = 0
    if ($LASTEXITCODE -eq 0 -and [int]::TryParse(([string] ($output -join '')).Trim(), [ref] $timeoutSeconds) -and $timeoutSeconds -gt 0) {
        return $timeoutSeconds
    }

    return 180
}

function Get-ChezmoiOpFailureCategory {
    [CmdletBinding()]
    param(
        [string] $StandardError
    )

    if ($StandardError -match '(?i)context deadline exceeded|request timed out') {
        return 'request timed out'
    }
    if ($StandardError -match '(?i)invalid secret reference|invalid character in secret reference|invalid reference') {
        return 'invalid or unsupported secret reference'
    }
    if ($StandardError -match '(?i)delegated.session|session delegation|cannot setup session') {
        return 'delegated session could not be established'
    }
    if ($StandardError -match '(?i)no accounts configured|not signed in|authentication|authorization') {
        return 'account authentication or authorization failed'
    }
    if ($StandardError -match '(?i)(item|field|secret|reference).{0,40}(not found|does not exist|could not be found|could not resolve)') {
        return 'a secret reference could not be resolved'
    }

    return ''
}

function New-ChezmoiOpInjectManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $EnvironmentReferences
    )

    $manifestLines = [System.Collections.Generic.List[string]]::new()
    $manifestLines.Add('DOTFILES_OP_PREFETCHED_KAGGLE_API_TOKEN={{ op://Private/Kaggle/c4patuuzwob2vcwt43qqphoyeu }}')
    $manifestLines.Add('DOTFILES_OP_PREFETCHED_SSH_PUBLIC_KEY={{ op://Private/xnoq6xbcdktkph76e2bg37ou6y/public key }}')

    foreach ($reference in @($EnvironmentReferences.Keys | Sort-Object)) {
        $variableName = [string] $EnvironmentReferences[$reference]
        $manifestLines.Add("$variableName={{ $reference }}")
    }

    return ($manifestLines -join "`n")
}

function Invoke-OpInjectManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $OpExe,

        [Parameter(Mandatory)]
        [string] $Account,

        [Parameter(Mandatory)]
        [string] $Manifest,

        [int] $TimeoutSeconds = 180
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $OpExe
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $null = $startInfo.ArgumentList.Add('--cache=false')
    $null = $startInfo.ArgumentList.Add('inject')
    $null = $startInfo.ArgumentList.Add('--account')
    $null = $startInfo.ArgumentList.Add($Account)

    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.StandardInput.Write($Manifest)
    $process.StandardInput.Close()

    $timeoutMilliseconds = [Math]::Max(1, $TimeoutSeconds) * 1000
    if (-not $process.WaitForExit($timeoutMilliseconds)) {
        try {
            $process.Kill($true)
        }
        catch {
            $process.Kill()
        }
        return [pscustomobject]@{
            Output       = ''
            StandardError = ''
            ExitCode     = 124
            TimedOut     = $true
        }
    }

    $standardError = $stderrTask.GetAwaiter().GetResult()
    return [pscustomobject]@{
        Output        = $stdoutTask.GetAwaiter().GetResult()
        StandardError = $standardError
        ExitCode      = $process.ExitCode
        TimedOut      = $false
    }
}

function Get-ChezmoiPrefetchResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ChezmoiExe,

        [string] $OpExe
    )

    if ([string]::IsNullOrWhiteSpace($OpExe)) {
        Write-Warning '1Password CLI was not found; optional secret deployment will be skipped.'
        return [pscustomobject]@{ Success = $false; Secrets = @{} }
    }

    try {
        $account = Get-ChezmoiPersonalAccount -ChezmoiExe $ChezmoiExe
        if ([string]::IsNullOrWhiteSpace($account)) {
            Write-Warning 'Could not determine the configured 1Password account; optional secret deployment will be skipped.'
            return [pscustomobject]@{ Success = $false; Secrets = @{} }
        }

        $environmentReferences = Get-ChezmoiOpEnvironmentReference -ChezmoiExe $ChezmoiExe
        $manifest = New-ChezmoiOpInjectManifest -EnvironmentReferences $environmentReferences
        $timeoutSeconds = Get-ChezmoiOpReadTimeout -ChezmoiExe $ChezmoiExe
        $result = Invoke-OpInjectManifest `
            -OpExe $OpExe `
            -Account $account `
            -Manifest $manifest `
            -TimeoutSeconds $timeoutSeconds

        if ($result.ExitCode -ne 0) {
            if ($result.TimedOut) {
                Write-Warning "1Password batch read timed out after $timeoutSeconds seconds; optional secret deployment will be skipped."
            }
            else {
                $failureCategory = Get-ChezmoiOpFailureCategory -StandardError ([string] $result.StandardError)
                if ($failureCategory) {
                    Write-Warning "1Password batch read failed: $failureCategory; optional secret deployment will be skipped."
                }
                else {
                    Write-Warning "1Password batch read failed with exit code $($result.ExitCode); optional secret deployment will be skipped."
                }
            }
            return [pscustomobject]@{ Success = $false; Secrets = @{} }
        }

        $secrets = @{}
        foreach ($line in ([string] $result.Output -split "`r?`n")) {
            $separator = $line.IndexOf('=')
            if ($separator -lt 1) {
                continue
            }

            $name = $line.Substring(0, $separator)
            $value = $line.Substring($separator + 1).TrimEnd("`r")
            if ($value -and $value -notmatch 'op://') {
                $secrets[$name] = $value
            }
        }

        return [pscustomobject]@{ Success = $true; Secrets = $secrets }
    }
    catch {
        Write-Warning '1Password batch read failed; optional secret deployment will be skipped.'
        return [pscustomobject]@{ Success = $false; Secrets = @{} }
    }
}

