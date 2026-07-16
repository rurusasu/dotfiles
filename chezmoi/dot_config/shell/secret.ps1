# Secret environment variables - lazy 1Password loader.
# Sourced by PowerShell profile at shell startup.
#
# Plain shell startup should not prompt for 1Password. Explicit command wrappers
# such as Invoke-CodexCli set DOTFILES_FORCE_SECRET_LOAD before sourcing this
# file so missing values can be read with bounded op read calls.

if (-not $env:GITHUB_PAT_TOKEN -and $env:GH_TOKEN) { $env:GITHUB_PAT_TOKEN = $env:GH_TOKEN }
if (-not $env:GH_TOKEN -and $env:GITHUB_PAT_TOKEN) { $env:GH_TOKEN = $env:GITHUB_PAT_TOKEN }

if (-not $env:DOTFILES_FORCE_SECRET_LOAD) {
    return
}

$script:DotfilesSecretLoadOnly = @()
if ($env:DOTFILES_SECRET_LOAD_ONLY) {
    $script:DotfilesSecretLoadOnly = @(
        $env:DOTFILES_SECRET_LOAD_ONLY -split '[,\s]+' |
            Where-Object { $_ }
    )
}

function Test-DotfilesShouldLoadSecret {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Name)

    if ($script:DotfilesSecretLoadOnly.Count -eq 0) {
        return $true
    }

    return $script:DotfilesSecretLoadOnly -contains $Name
}

function Resolve-DotfilesOpCli {
    [CmdletBinding()]
    param()

    if ($env:DOTFILES_OP_BIN) {
        return $env:DOTFILES_OP_BIN
    }

    $command = Get-Command op -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) {
        $command = Get-Command op.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    }

    if (-not $command) {
        return $null
    }

    return $command.Source
}

function Get-DotfilesSecretLoadTimeoutSeconds {
    [CmdletBinding()]
    param()

    $timeoutSeconds = 60
    if ($env:DOTFILES_SECRET_LOAD_TIMEOUT_SECONDS) {
        $parsedTimeout = 0
        if ([int]::TryParse($env:DOTFILES_SECRET_LOAD_TIMEOUT_SECONDS, [ref]$parsedTimeout) -and $parsedTimeout -gt 0) {
            $timeoutSeconds = $parsedTimeout
        }
    }

    return $timeoutSeconds
}

function Invoke-DotfilesOpRead {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Reference,

        [Parameter(Mandatory = $true)]
        [string]$Account,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds
    )

    $opBin = Resolve-DotfilesOpCli
    if (-not $opBin) {
        return $null
    }

    $process = $null

    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $opBin
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        foreach ($argument in @('--cache=false', '--account', $Account, 'read', $Reference)) {
            $startInfo.ArgumentList.Add($argument)
        }

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        [void]$process.Start()

        if ($process.WaitForExit($TimeoutSeconds * 1000) -and $process.ExitCode -eq 0) {
            $value = $process.StandardOutput.ReadToEnd()
            if ($null -eq $value) {
                return $null
            }
            return ([string]$value).Trim()
        }

        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            Write-Warning "1Password secret read timed out after $TimeoutSeconds seconds; continuing without '$Reference'."
        }
        else {
            $errorContent = $process.StandardError.ReadToEnd()
            $errorText = if ($null -ne $errorContent) { $errorContent.Trim() } else { '' }
            if ($errorText) {
                Write-Warning "1Password secret read failed for '$Reference': $errorText"
            }
            else {
                Write-Warning "1Password secret read failed for '$Reference' with exit code $($process.ExitCode)."
            }
        }
    }
    catch {
        Write-Warning "1Password secret read failed for '$Reference': $($_.Exception.Message)"
    }
    finally {
        if ($process) {
            $process.Dispose()
        }
    }

    return $null
}

function Set-DotfilesSecretEnvironmentValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Reference,

        [Parameter(Mandatory = $true)]
        [string]$Account,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds
    )

    if ([Environment]::GetEnvironmentVariable($Name, 'Process')) {
        return
    }
    if (-not (Test-DotfilesShouldLoadSecret -Name $Name)) {
        return
    }

    $value = Invoke-DotfilesOpRead -Reference $Reference -Account $Account -TimeoutSeconds $TimeoutSeconds
    if ($value) {
        [Environment]::SetEnvironmentVariable($Name, $value, 'Process')
    }
}

try {
    $timeoutSeconds = Get-DotfilesSecretLoadTimeoutSeconds
    $personalAccount = if ($env:OP_ACCOUNT) { $env:OP_ACCOUNT } else { 'EJLA3HRAVZBCXIQ7SRSFGQBTNU' }
    $workAccount = 'aimatecoltd.1password.com'
    $serviceAccountTokenRef = if ($env:DOTFILES_OP_SERVICE_ACCOUNT_TOKEN_REF) {
        $env:DOTFILES_OP_SERVICE_ACCOUNT_TOKEN_REF
    }
    else {
        'op://Employee/1password Service Account/password'
    }

    Set-DotfilesSecretEnvironmentValue `
        -Name 'GITHUB_PAT_TOKEN' `
        -Reference 'op://Private/GitHubUsedUserPAT/credential' `
        -Account $personalAccount `
        -TimeoutSeconds $timeoutSeconds

    Set-DotfilesSecretEnvironmentValue `
        -Name 'TAVILY_API_KEY' `
        -Reference 'op://Private/TavilyUsedUserPAT/credential' `
        -Account $personalAccount `
        -TimeoutSeconds $timeoutSeconds

    if (-not $env:GITHUB_PAT_TOKEN -and $env:GH_TOKEN) { $env:GITHUB_PAT_TOKEN = $env:GH_TOKEN }
    if (-not $env:GH_TOKEN -and $env:GITHUB_PAT_TOKEN) { $env:GH_TOKEN = $env:GITHUB_PAT_TOKEN }

    Set-DotfilesSecretEnvironmentValue `
        -Name 'GITHUB_WORK_TOKEN' `
        -Reference 'op://devcontainer/GITHUB_PERSONAL_ACCESS_TOKEN_KOHEI-MIKI-IM8/credential' `
        -Account $workAccount `
        -TimeoutSeconds $timeoutSeconds

    Set-DotfilesSecretEnvironmentValue `
        -Name 'OP_SERVICE_ACCOUNT_TOKEN' `
        -Reference $serviceAccountTokenRef `
        -Account $workAccount `
        -TimeoutSeconds $timeoutSeconds
}
finally {
    Remove-Item Function:\Resolve-DotfilesOpCli -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-DotfilesSecretLoadTimeoutSeconds -ErrorAction SilentlyContinue
    Remove-Item Function:\Test-DotfilesShouldLoadSecret -ErrorAction SilentlyContinue
    Remove-Item Function:\Invoke-DotfilesOpRead -ErrorAction SilentlyContinue
    Remove-Item Function:\Set-DotfilesSecretEnvironmentValue -ErrorAction SilentlyContinue

    Remove-Variable timeoutSeconds, personalAccount, workAccount, serviceAccountTokenRef -ErrorAction SilentlyContinue
    Remove-Variable DotfilesSecretLoadOnly -Scope Script -ErrorAction SilentlyContinue
}
