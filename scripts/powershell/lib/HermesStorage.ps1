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

function Get-HermesStorageVolumeLabel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VolumeName,

        [Parameter(Mandatory)]
        [string]$Label
    )

    $format = '{{ index .Labels "' + $Label + '" }}'
    $output = @(Invoke-Docker -Arguments @('volume', 'inspect', '--format', $format, $VolumeName) 2>$null)
    $status = $LASTEXITCODE
    $value = ($output -join "`n").Trim()
    return [PSCustomObject]@{ Status = $status; Value = $value }
}

function Test-HermesStorageVolumeReady {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VolumeName
    )

    $arguments = @(
        'run', '--rm',
        '--entrypoint', 'test',
        '--mount', "type=volume,source=$VolumeName,target=/target,readonly",
        'local/hermes-agent-gh:latest',
        '-f', '/target/.dotfiles-hermes-storage-ready-v1'
    )
    $null = @(Invoke-Docker -Arguments $arguments 2>$null)
    return $LASTEXITCODE -eq 0
}

function Initialize-HermesStorageVolume {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DataDir
    )

    $volumeName = Get-HermesStorageVolumeName
    $schemaLabel = 'com.rurusasu.dotfiles.hermes-storage.schema'
    $tokenLabel = 'com.rurusasu.dotfiles.hermes-storage.init-token'
    $schema = Get-HermesStorageVolumeLabel -VolumeName $volumeName -Label $schemaLabel
    if ($schema.Status -eq 0) {
        if ($schema.Value -ne '1') {
            return [PSCustomObject]@{ Success = $true; Existing = $true; Message = '' }
        }
        if (Test-HermesStorageVolumeReady -VolumeName $volumeName) {
            return [PSCustomObject]@{ Success = $true; Existing = $true; Message = '' }
        }
        return [PSCustomObject]@{
            Success  = $false
            Existing = $true
            Message  = 'Hermes Docker data volume is managed but incomplete.'
        }
    }
    if ($schema.Status -ne 1) {
        return [PSCustomObject]@{ Success = $false; Existing = $false; Message = 'Hermes data volume inspection failed.' }
    }

    $initToken = [guid]::NewGuid().ToString('N')
    $createArguments = @(
        'volume', 'create',
        '--label', "$schemaLabel=1",
        '--label', "$tokenLabel=$initToken",
        $volumeName
    )
    $null = @(Invoke-Docker -Arguments $createArguments 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return [PSCustomObject]@{ Success = $false; Existing = $false; Message = 'Hermes data volume creation failed.' }
    }
    $owner = Get-HermesStorageVolumeLabel -VolumeName $volumeName -Label $tokenLabel
    if ($owner.Status -ne 0) {
        return [PSCustomObject]@{
            Success  = $false
            Existing = $true
            Message  = 'Hermes Docker data volume ownership could not be verified.'
        }
    }
    if ($owner.Value -ne $initToken) {
        return [PSCustomObject]@{
            Success  = $false
            Existing = $true
            Message  = 'Hermes Docker data volume was created concurrently; refusing to seed or remove it.'
        }
    }

    $seedArguments = @(
        'run', '--rm',
        '--entrypoint', '/usr/local/bin/hermes-storage-seed',
        '--mount', "type=bind,source=$DataDir,target=/source,readonly",
        '--mount', "type=volume,source=$volumeName,target=/target",
        'local/hermes-agent-gh:latest',
        '--source', '/source',
        '--destination', '/target'
    )
    $null = @(Invoke-Docker -Arguments $seedArguments 2>$null)
    $seedStatus = $LASTEXITCODE
    $failureMessage = 'Hermes data volume initialization failed.'
    if ($seedStatus -eq 0) {
        if (Test-HermesStorageVolumeReady -VolumeName $volumeName) {
            return [PSCustomObject]@{ Success = $true; Existing = $false; Message = '' }
        }
        $seedStatus = 1
        $failureMessage = 'Hermes Docker data volume seed completed without its ready marker.'
    }

    $owner = Get-HermesStorageVolumeLabel -VolumeName $volumeName -Label $tokenLabel
    if ($owner.Status -ne 0) {
        return [PSCustomObject]@{
            Success  = $false
            Existing = $true
            Message  = "$failureMessage Ownership could not be reverified; refusing removal."
        }
    }
    if ($owner.Value -ne $initToken) {
        return [PSCustomObject]@{
            Success  = $false
            Existing = $true
            Message  = "$failureMessage Ownership changed; refusing removal."
        }
    }
    $null = @(Invoke-Docker -Arguments @('volume', 'rm', $volumeName) 2>$null)
    $cleanupStatus = $LASTEXITCODE
    if ($cleanupStatus -ne 0) {
        return [PSCustomObject]@{
            Success  = $false
            Existing = $true
            Message  = "$failureMessage The owned partial volume could not be removed (seed status $seedStatus, cleanup status $cleanupStatus)."
        }
    }
    return [PSCustomObject]@{ Success = $false; Existing = $false; Message = $failureMessage }
}
