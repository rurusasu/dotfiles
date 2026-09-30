function Invoke-WslForChezmoi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    $output = & wsl.exe @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = @($output)
    }
}

function Invoke-OptionalWslChezmoiApply {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Distro
    )

    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        Write-Warning 'WSL is unavailable; skipping the WSL chezmoi apply.'
        return 0
    }

    $result = Invoke-WslForChezmoi -Arguments @('-d', $Distro, '--', 'chezmoi', 'apply', '--force')
    $message = (($result.Output | ForEach-Object { [string] $_ }) -join [Environment]::NewLine) -replace [char] 0, ''

    if ($result.ExitCode -eq 0) {
        foreach ($line in $result.Output) {
            Write-Host $line
        }
        return 0
    }

    if ($message -match 'WSL_E_DISTRO_NOT_FOUND') {
        Write-Warning "WSL distro '$Distro' is not installed; skipping the WSL chezmoi apply."
        return 0
    }

    foreach ($line in ($message -split "`r?`n")) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            Write-Host $line
        }
    }
    return [int] $result.ExitCode
}
