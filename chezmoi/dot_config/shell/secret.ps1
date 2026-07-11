# Secret environment variables - lazy 1Password loader.
# Sourced by PowerShell profile at shell startup.
#
# Plain shell startup should not prompt for 1Password. Explicit command wrappers
# such as Invoke-CodexCli set DOTFILES_FORCE_SECRET_LOAD before sourcing this
# file so missing values can be read with bounded op read calls.

if (-not $env:GITHUB_PAT_TOKEN -and $env:GH_TOKEN) { $env:GITHUB_PAT_TOKEN = $env:GH_TOKEN }
if (-not $env:GH_TOKEN -and $env:GITHUB_PAT_TOKEN) { $env:GH_TOKEN = $env:GITHUB_PAT_TOKEN }

if ($env:GITHUB_PAT_TOKEN -and $env:GH_TOKEN -and $env:TAVILY_API_KEY -and $env:GITHUB_WORK_TOKEN) { return }
if (-not $env:DOTFILES_FORCE_SECRET_LOAD) {
    return
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

    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()

    try {
        $process = Start-Process `
            -FilePath $opBin `
            -ArgumentList @('--cache=false', 'read', $Reference, '--account', $Account) `
            -PassThru `
            -WindowStyle Hidden `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr

        if ($process.WaitForExit($TimeoutSeconds * 1000) -and $process.ExitCode -eq 0) {
            $value = Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue
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
            $errorContent = Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue
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
        Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
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

    $value = Invoke-DotfilesOpRead -Reference $Reference -Account $Account -TimeoutSeconds $TimeoutSeconds
    if ($value) {
        [Environment]::SetEnvironmentVariable($Name, $value, 'Process')
    }
}

try {
    $timeoutSeconds = Get-DotfilesSecretLoadTimeoutSeconds
    $personalAccount = if ($env:OP_ACCOUNT) { $env:OP_ACCOUNT } else { 'EJLA3HRAVZBCXIQ7SRSFGQBTNU' }
    $workAccount = 'aimatecoltd.1password.com'

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
}
finally {
    Remove-Item Function:\Resolve-DotfilesOpCli -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-DotfilesSecretLoadTimeoutSeconds -ErrorAction SilentlyContinue
    Remove-Item Function:\Invoke-DotfilesOpRead -ErrorAction SilentlyContinue
    Remove-Item Function:\Set-DotfilesSecretEnvironmentValue -ErrorAction SilentlyContinue

    Remove-Variable timeoutSeconds, personalAccount, workAccount -ErrorAction SilentlyContinue
}
