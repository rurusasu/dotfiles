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
        [string]$VolumeName,

        [Parameter(Mandatory)]
        [string]$VolumeToken
    )

    $arguments = @(
        'run', '--rm',
        '--entrypoint', 'python',
        '--mount', "type=volume,source=$VolumeName,target=/target,readonly",
        'local/hermes-agent-gh:latest',
        '-c', 'import pathlib, stat, sys; marker=pathlib.Path("/target/.dotfiles-hermes-storage-ready-v1"); expected=f"version=1\nvolume_token={sys.argv[1]}\n";
try:
 mode=marker.lstat().st_mode
except FileNotFoundError:
 raise SystemExit(3)
except OSError as error:
 print(f"Hermes ready marker could not be inspected: {error}", file=sys.stderr); raise SystemExit(2)
if stat.S_ISLNK(mode) or not stat.S_ISREG(mode): raise SystemExit(3)
try:
 actual=marker.read_text(encoding="utf-8")
except (OSError, UnicodeError) as error:
 print(f"Hermes ready marker could not be read: {error}", file=sys.stderr); raise SystemExit(2)
raise SystemExit(0 if actual == expected else 3)',
        $VolumeToken
    )
    $null = @(Invoke-Docker -Arguments $arguments 2>$null)
    $status = $LASTEXITCODE
    return [PSCustomObject]@{ Status = $status; Ready = $status -eq 0 }
}

function Get-HermesStorageLockName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VolumeName
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($VolumeName)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    $hex = [System.Convert]::ToHexString($hash).ToLowerInvariant()
    return 'dotfiles-hermes-storage-' + $hex.Substring(0, 20)
}

function Get-HermesStorageUnixTime {
    [CmdletBinding()]
    param()

    return [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
}

function Get-HermesStorageLockState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LockName,

        [Parameter(Mandatory)]
        [string]$LockLabel,

        [Parameter(Mandatory)]
        [string]$TokenLabel,

        [Parameter(Mandatory)]
        [string]$CreatedLabel
    )

    $format = '{{ .Id }}|{{ index .Config.Labels "' + $LockLabel + '" }}|{{ index .Config.Labels "' + $TokenLabel + '" }}|{{ index .Config.Labels "' + $CreatedLabel + '" }}|{{ .State.Status }}'
    $output = @(Invoke-Docker -Arguments @('inspect', '--format', $format, $LockName) 2>$null)
    return [PSCustomObject]@{ Status = $LASTEXITCODE; Value = (($output -join "`n").Trim()) }
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
    $lockLabel = 'com.rurusasu.dotfiles.hermes-storage.lock'
    $lockCreatedLabel = 'com.rurusasu.dotfiles.hermes-storage.lock-created-at'
    $existing = $true
    $schema = Get-HermesStorageVolumeLabel -VolumeName $volumeName -Label $schemaLabel
    if ($schema.Status -eq 0) {
        if ($schema.Value -ne '1') {
            return [PSCustomObject]@{ Success = $true; Existing = $true; Message = '' }
        }
        $owner = Get-HermesStorageVolumeLabel -VolumeName $volumeName -Label $tokenLabel
        if ($owner.Status -ne 0) {
            return [PSCustomObject]@{ Success = $false; Existing = $true; Message = 'Hermes data volume token inspection failed.' }
        }
        $volumeToken = $owner.Value
    }
    elseif ($schema.Status -ne 1) {
        return [PSCustomObject]@{ Success = $false; Existing = $false; Message = 'Hermes data volume inspection failed.' }
    }
    else {
        $existing = $false
        $volumeToken = [guid]::NewGuid().ToString('N')
        $createArguments = @(
            'volume', 'create',
            '--label', "$schemaLabel=1",
            '--label', "$tokenLabel=$volumeToken",
            $volumeName
        )
        $null = @(Invoke-Docker -Arguments $createArguments 2>$null)
        if ($LASTEXITCODE -ne 0) {
            return [PSCustomObject]@{ Success = $false; Existing = $false; Message = 'Hermes data volume creation failed.' }
        }
    }

    if ($volumeToken -notmatch '^[0-9a-f]{32}$') {
        return [PSCustomObject]@{ Success = $false; Existing = $existing; Message = 'Hermes data volume has an invalid initialization token.' }
    }

    $lockName = Get-HermesStorageLockName -VolumeName $volumeName
    $lockCreatedAt = Get-HermesStorageUnixTime
    $seedArguments = @(
        'create',
        '--name', $lockName,
        '--label', "$lockLabel=1",
        '--label', "$tokenLabel=$volumeToken",
        '--label', "$lockCreatedLabel=$lockCreatedAt",
        '--entrypoint', '/usr/local/bin/hermes-storage-seed',
        '--mount', "type=bind,source=$DataDir,target=/source,readonly",
        '--mount', "type=volume,source=$volumeName,target=/target",
        'local/hermes-agent-gh:latest',
        '--source', '/source',
        '--destination', '/target',
        '--ready-token', $volumeToken,
        '--replace-incomplete'
    )
    $lockCreatedArgument = "$lockCreatedLabel=$lockCreatedAt"
    $lockOutput = @(Invoke-Docker -Arguments $seedArguments 2>$null)
    $lockCreateStatus = $LASTEXITCODE
    $lockId = ($lockOutput -join "`n").Trim()
    if ($lockCreateStatus -ne 0) {
        $lockState = Get-HermesStorageLockState -LockName $lockName -LockLabel $lockLabel -TokenLabel $tokenLabel -CreatedLabel $lockCreatedLabel
        $parts = $lockState.Value -split '\|', 5
        $reclaimStale = $false
        if ($lockState.Status -eq 0 -and $parts.Count -eq 5 -and
            $parts[0] -match '^[0-9a-f]{12,64}$' -and $parts[1] -eq '1' -and
            $parts[2] -eq $volumeToken) {
            if ($parts[4] -in @('exited', 'dead')) {
                $reclaimStale = $true
            }
            elseif ($parts[4] -eq 'created' -and $parts[3] -match '^[0-9]{1,12}$') {
                $age = (Get-HermesStorageUnixTime) - [long]$parts[3]
                $reclaimStale = $age -ge 30
            }
        }
        if ($reclaimStale) {
            $staleLockId = $parts[0]
            $null = @(Invoke-Docker -Arguments @('rm', '-f', $staleLockId) 2>$null)
            if ($LASTEXITCODE -ne 0) {
                return [PSCustomObject]@{ Success = $false; Existing = $existing; Message = 'Hermes data volume stale lock could not be reclaimed.' }
            }
            $lockCreatedArgumentIndex = $seedArguments.IndexOf($lockCreatedArgument)
            if ($lockCreatedArgumentIndex -lt 0) {
                return [PSCustomObject]@{ Success = $false; Existing = $existing; Message = 'Hermes data volume lock timestamp could not be refreshed.' }
            }
            $lockCreatedAt = Get-HermesStorageUnixTime
            $lockCreatedArgument = "$lockCreatedLabel=$lockCreatedAt"
            $seedArguments[$lockCreatedArgumentIndex] = $lockCreatedArgument
            $lockOutput = @(Invoke-Docker -Arguments $seedArguments 2>$null)
            $lockCreateStatus = $LASTEXITCODE
            $lockId = ($lockOutput -join "`n").Trim()
            if ($lockCreateStatus -ne 0) {
                return [PSCustomObject]@{ Success = $false; Existing = $existing; Message = 'Hermes data volume lock could not be acquired after stale-lock cleanup.' }
            }
        }
        else {
            return [PSCustomObject]@{ Success = $false; Existing = $existing; Message = 'Hermes data volume initialization is already locked.' }
        }
    }
    if ($lockId -notmatch '^[0-9a-f]{12,64}$') {
        return [PSCustomObject]@{ Success = $false; Existing = $existing; Message = 'Hermes data volume lock returned an invalid container ID.' }
    }

    $lockedSchema = Get-HermesStorageVolumeLabel -VolumeName $volumeName -Label $schemaLabel
    $lockedOwner = Get-HermesStorageVolumeLabel -VolumeName $volumeName -Label $tokenLabel
    if ($lockedSchema.Status -ne 0 -or $lockedOwner.Status -ne 0 -or
        $lockedSchema.Value -ne '1' -or $lockedOwner.Value -ne $volumeToken) {
        $result = [PSCustomObject]@{
            Success  = $false
            Existing = $existing
            Message  = 'Hermes data volume changed before its lock was acquired; refusing access.'
        }
    }
    else {
        $probe = Test-HermesStorageVolumeReady -VolumeName $volumeName -VolumeToken $volumeToken
    }
    if ($null -ne $result) {
        # The locked volume identity check already produced the result.
    }
    elseif ($probe.Status -eq 0) {
        $result = [PSCustomObject]@{ Success = $true; Existing = $true; Message = '' }
    }
    elseif ($probe.Status -ne 3) {
        $result = [PSCustomObject]@{
            Success  = $false
            Existing = $existing
            Message  = "Hermes data volume ready marker probe failed with status $($probe.Status); preserving it unchanged."
        }
    }
    else {
        $null = @(Invoke-Docker -Arguments @('start', '-a', $lockId) 2>$null)
        $seedStatus = $LASTEXITCODE
        if ($seedStatus -eq 0) {
            $postSeedProbe = Test-HermesStorageVolumeReady -VolumeName $volumeName -VolumeToken $volumeToken
            if ($postSeedProbe.Status -eq 0) {
                $result = [PSCustomObject]@{ Success = $true; Existing = $existing; Message = '' }
            }
            elseif ($postSeedProbe.Status -eq 3) {
                $result = [PSCustomObject]@{
                    Success  = $false
                    Existing = $existing
                    Message  = 'Hermes data volume seed completed without its valid ready marker.'
                }
            }
            else {
                $result = [PSCustomObject]@{
                    Success  = $false
                    Existing = $existing
                    Message  = "Hermes data volume post-seed ready marker probe failed with status $($postSeedProbe.Status)."
                }
            }
        }
        else {
            $result = [PSCustomObject]@{
                Success  = $false
                Existing = $existing
                Message  = "Hermes data volume initialization failed with status $seedStatus; it remains incomplete for a safe retry."
            }
        }
    }

    $null = @(Invoke-Docker -Arguments @('rm', '-f', $lockId) 2>$null)
    $releaseStatus = $LASTEXITCODE
    if ($releaseStatus -ne 0) {
        return [PSCustomObject]@{
            Success  = $false
            Existing = $existing
            Message  = "Hermes data volume operation completed but its lock could not be released (status $releaseStatus)."
        }
    }
    return $result
}
