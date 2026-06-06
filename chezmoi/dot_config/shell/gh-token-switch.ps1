# GitHub CLI token switching for personal/work repositories.
# Sourced by the PowerShell profile after 1Password-managed secrets are loaded.

function Test-DotfilesWorkGitHubRepository {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path = (Get-Location).Path
    )

    if ($Path) {
        $normalizedPath = $Path -replace '/', '\'
        if (
            $normalizedPath.Equals('D:\my_programing', [System.StringComparison]::OrdinalIgnoreCase) -or
            $normalizedPath.StartsWith('D:\my_programing\', [System.StringComparison]::OrdinalIgnoreCase)
        ) {
            return $true
        }
    }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        return $false
    }

    $insideWorkTree = (& git rev-parse --is-inside-work-tree 2>$null)
    if ($LASTEXITCODE -ne 0 -or $insideWorkTree -ne 'true') {
        return $false
    }

    $remoteUrls = (& git config --get-regexp '^remote\..*\.url$' 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $remoteUrls) {
        return $false
    }

    return [bool]($remoteUrls -match 'git@github-work:')
}

function Resolve-DotfilesGitHubCli {
    [CmdletBinding()]
    param()

    if ($env:DOTFILES_GH_BIN) {
        return $env:DOTFILES_GH_BIN
    }

    $command = Get-Command gh.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) {
        $command = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    }

    if (-not $command) {
        throw "gh executable not found"
    }

    return $command.Source
}

function Invoke-DotfilesGitHubCli {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $originalGhToken = [Environment]::GetEnvironmentVariable('GH_TOKEN', 'Process')

    try {
        if (Test-DotfilesWorkGitHubRepository) {
            if ($env:GITHUB_WORK_TOKEN) {
                $env:GH_TOKEN = $env:GITHUB_WORK_TOKEN
            }
            else {
                Write-Warning "work repo detected, but GITHUB_WORK_TOKEN is not set; using existing GH_TOKEN"
            }
        }

        $ghBin = Resolve-DotfilesGitHubCli
        & $ghBin @Arguments
    }
    finally {
        if ($null -eq $originalGhToken) {
            Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue
        }
        else {
            $env:GH_TOKEN = $originalGhToken
        }
    }
}

function gh {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    Invoke-DotfilesGitHubCli @Arguments
}
