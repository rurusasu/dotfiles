<##
.SYNOPSIS
    Initializes the Docker-managed Hermes runtime data volume.
#>

function Get-HermesStorageVolumeName {
    [CmdletBinding()]
    param()

    $name = if ([string]::IsNullOrWhiteSpace($env:HERMES_DATA_VOLUME)) {
        'hermes-data'
    }
    else {
        $env:HERMES_DATA_VOLUME.Trim()
    }
    if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') {
        throw [System.ArgumentException]::new('HERMES_DATA_VOLUME contains an invalid Docker volume name.')
    }
    return $name
}

function Initialize-HermesStorageVolume {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DataDir
    )

    $volumeName = Get-HermesStorageVolumeName
    $null = @(Invoke-Docker -Arguments @('volume', 'inspect', $volumeName) 2>$null)
    if ($LASTEXITCODE -eq 0) {
        return [PSCustomObject]@{ Success = $true; Existing = $true; Message = '' }
    }
    if ($LASTEXITCODE -ne 1) {
        return [PSCustomObject]@{ Success = $false; Existing = $false; Message = 'Hermes data volume inspection failed.' }
    }

    $null = @(Invoke-Docker -Arguments @('volume', 'create', $volumeName) 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return [PSCustomObject]@{ Success = $false; Existing = $false; Message = 'Hermes data volume creation failed.' }
    }

    $seedArguments = @(
        'run', '--rm',
        '--mount', "type=bind,source=$DataDir,target=/source,readonly",
        '--mount', "type=volume,source=$volumeName,target=/target",
        'local/hermes-agent-gh:latest',
        '/usr/local/bin/hermes-storage-seed',
        '--source', '/source',
        '--destination', '/target'
    )
    $null = @(Invoke-Docker -Arguments $seedArguments 2>$null)
    if ($LASTEXITCODE -eq 0) {
        return [PSCustomObject]@{ Success = $true; Existing = $false; Message = '' }
    }

    $null = @(Invoke-Docker -Arguments @('volume', 'rm', $volumeName) 2>$null)
    return [PSCustomObject]@{ Success = $false; Existing = $false; Message = 'Hermes data volume initialization failed.' }
}
