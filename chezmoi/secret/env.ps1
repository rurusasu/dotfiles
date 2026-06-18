# Secret environment variables — 1Password op run pattern
# Sourced by PowerShell profile at shell startup.
#
# Preferred usage: launch WezTerm via ~/.local/bin/wezterm-launch.cmd
#   op run --env-file injects GH_TOKEN/TAVILY_API_KEY/GITHUB_WORK_TOKEN once at WezTerm startup;
#   all tabs inherit them and this guard exits immediately.
#
# Fallback: standalone pwsh attempts bounded op inject calls when values are missing.

if ($env:GH_TOKEN -and $env:TAVILY_API_KEY -and $env:GITHUB_WORK_TOKEN) { return }
if (-not $env:DOTFILES_FORCE_SECRET_LOAD) {
    $dotfilesPowerShellArgs = [Environment]::GetCommandLineArgs()
    $dotfilesSecretLoadIsCommandMode = $false
    foreach ($arg in $dotfilesPowerShellArgs) {
        if ($arg -match '^-{1,2}(command|c|encodedcommand|ec|file|f|noninteractive)$') {
            $dotfilesSecretLoadIsCommandMode = $true
            break
        }
    }

    Remove-Variable dotfilesPowerShellArgs -ErrorAction SilentlyContinue
    if ($dotfilesSecretLoadIsCommandMode) {
        Remove-Variable dotfilesSecretLoadIsCommandMode -ErrorAction SilentlyContinue
        return
    }
    Remove-Variable dotfilesSecretLoadIsCommandMode -ErrorAction SilentlyContinue
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

    $timeoutSeconds = 8
    if ($env:DOTFILES_SECRET_LOAD_TIMEOUT_SECONDS) {
        $parsedTimeout = 0
        if ([int]::TryParse($env:DOTFILES_SECRET_LOAD_TIMEOUT_SECONDS, [ref]$parsedTimeout) -and $parsedTimeout -gt 0) {
            $timeoutSeconds = $parsedTimeout
        }
    }

    return $timeoutSeconds
}

function Invoke-DotfilesOpInject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Template,

        [Parameter(Mandatory = $true)]
        [string]$Account,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds
    )

    $opBin = Resolve-DotfilesOpCli
    if (-not $opBin) {
        return $null
    }

    $stdin = [System.IO.Path]::GetTempFileName()
    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()

    try {
        Set-Content -LiteralPath $stdin -Value $Template -Encoding utf8 -NoNewline
        $process = Start-Process `
            -FilePath $opBin `
            -ArgumentList @('inject', '--in-file', $stdin, '--account', $Account) `
            -PassThru `
            -WindowStyle Hidden `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr

        if ($process.WaitForExit($TimeoutSeconds * 1000) -and $process.ExitCode -eq 0) {
            return Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue
        }

        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            Write-Warning "1Password secret injection timed out after $TimeoutSeconds seconds; continuing without injected secrets."
        }
        else {
            $errorContent = Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue
            $errorText = if ($null -ne $errorContent) { $errorContent.Trim() } else { '' }
            if ($errorText) {
                Write-Warning "1Password secret injection failed: $errorText"
            }
            else {
                Write-Warning "1Password secret injection failed with exit code $($process.ExitCode)."
            }
        }
    }
    catch {
        Write-Warning "1Password secret injection failed: $($_.Exception.Message)"
    }
    finally {
        Remove-Item -LiteralPath $stdin, $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }

    return $null
}

function Set-DotfilesSecretEnvironment {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Content
    )

    if (-not $Content) {
        return
    }

    $allowedNames = @('GH_TOKEN', 'TAVILY_API_KEY', 'GITHUB_WORK_TOKEN')
    foreach ($line in ($Content -split '\r?\n')) {
        if ($line -notmatch '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            continue
        }

        $name = $Matches[1]
        if ($name -notin $allowedNames) {
            continue
        }

        [Environment]::SetEnvironmentVariable($name, $Matches[2], 'Process')
    }
}

try {
    $timeoutSeconds = Get-DotfilesSecretLoadTimeoutSeconds
    $personalAccount = if ($env:OP_ACCOUNT) { $env:OP_ACCOUNT } else { 'EJLA3HRAVZBCXIQ7SRSFGQBTNU' }
    $workAccount = 'aimatecoltd.1password.com'

    if (-not ($env:GH_TOKEN -and $env:TAVILY_API_KEY)) {
        $personalTemplate = @'
GH_TOKEN={{ op://Private/GitHubUsedUserPAT/credential }}
TAVILY_API_KEY={{ op://Private/TavilyUsedUserPAT/credential }}
'@
        Set-DotfilesSecretEnvironment -Content (Invoke-DotfilesOpInject -Template $personalTemplate -Account $personalAccount -TimeoutSeconds $timeoutSeconds)
    }

    if (-not $env:GITHUB_WORK_TOKEN) {
        $workTemplate = @'
GITHUB_WORK_TOKEN={{ op://devcontainer/GITHUB_PERSONAL_ACCESS_TOKEN_KOHEI-MIKI-IM8/credential }}
'@
        Set-DotfilesSecretEnvironment -Content (Invoke-DotfilesOpInject -Template $workTemplate -Account $workAccount -TimeoutSeconds $timeoutSeconds)
    }
}
finally {
    Remove-Item Function:\Resolve-DotfilesOpCli -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-DotfilesSecretLoadTimeoutSeconds -ErrorAction SilentlyContinue
    Remove-Item Function:\Invoke-DotfilesOpInject -ErrorAction SilentlyContinue
    Remove-Item Function:\Set-DotfilesSecretEnvironment -ErrorAction SilentlyContinue

    Remove-Variable timeoutSeconds, personalAccount, workAccount, personalTemplate, workTemplate -ErrorAction SilentlyContinue
}
