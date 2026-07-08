[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OpExe,

    [Parameter(Mandatory = $true)]
    [string]$PersonalAccount,

    [Parameter(Mandatory = $true)]
    [string]$PersonalEnvFile,

    [Parameter()]
    [string]$WorkAccount,

    [Parameter()]
    [string]$WorkEnvFile,

    [Parameter()]
    [int]$TimeoutSeconds = 60,

    [Parameter(Mandatory = $true)]
    [string]$Target,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$TargetArgs
)

$ErrorActionPreference = 'Stop'

if ($TimeoutSeconds -le 0) {
    $TimeoutSeconds = 60
}

function ConvertTo-DotfilesCmdQuoted {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    '"' + ($Value -replace '"', '""') + '"'
}

function Start-DotfilesGuiTarget {
    try {
        $startArgs = @{
            FilePath = $Target
        }
        if ($TargetArgs.Count -gt 0) {
            $startArgs.ArgumentList = $TargetArgs
        }

        Start-Process @startArgs
        return 0
    }
    catch {
        Write-Warning "Failed to start GUI target '$Target': $($_.Exception.Message)"
        return 1
    }
}

function New-DotfilesGuiStartCommand {
    $comSpec = if ($env:ComSpec) {
        $env:ComSpec
    }
    else {
        Join-Path $env:SystemRoot 'System32\cmd.exe'
    }

    $cmdLineParts = @('start', '""', (ConvertTo-DotfilesCmdQuoted $Target))
    foreach ($arg in $TargetArgs) {
        $cmdLineParts += ConvertTo-DotfilesCmdQuoted $arg
    }

    @($comSpec, '/d', '/c', ($cmdLineParts -join ' '))
}

function New-DotfilesOpProcessStartInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true

    if ($FilePath -match '\.(cmd|bat)$') {
        $comSpec = if ($env:ComSpec) {
            $env:ComSpec
        }
        else {
            Join-Path $env:SystemRoot 'System32\cmd.exe'
        }

        $startInfo.FileName = $comSpec
        [void]$startInfo.ArgumentList.Add('/d')
        [void]$startInfo.ArgumentList.Add('/c')
        [void]$startInfo.ArgumentList.Add($FilePath)
    }
    else {
        $startInfo.FileName = $FilePath
    }

    foreach ($arg in $Arguments) {
        [void]$startInfo.ArgumentList.Add($arg)
    }

    $startInfo
}

if (-not (Test-Path -LiteralPath $PersonalEnvFile -PathType Leaf)) {
    exit (Start-DotfilesGuiTarget)
}

$opArgs = @('run', '--account', $PersonalAccount, '--env-file', $PersonalEnvFile, '--')
if ($WorkAccount -and $WorkEnvFile -and (Test-Path -LiteralPath $WorkEnvFile -PathType Leaf)) {
    $opArgs += @($OpExe, 'run', '--account', $WorkAccount, '--env-file', $WorkEnvFile, '--')
}
$opArgs += New-DotfilesGuiStartCommand

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = New-DotfilesOpProcessStartInfo -FilePath $OpExe -Arguments $opArgs

try {
    [void]$process.Start()
}
catch {
    Write-Warning "1Password GUI launch injection could not start: $($_.Exception.Message). Starting without injected secrets."
    exit (Start-DotfilesGuiTarget)
}

if ($process.WaitForExit($TimeoutSeconds * 1000)) {
    if ($process.ExitCode -eq 0) {
        exit 0
    }

    Write-Warning "1Password GUI launch injection failed with exit code $($process.ExitCode). Starting without injected secrets."
    exit (Start-DotfilesGuiTarget)
}

try {
    $process.Kill($true)
}
catch {
    try {
        $process.Kill()
    }
    catch {
    }
}

Write-Warning "1Password GUI launch injection timed out after $TimeoutSeconds seconds. Starting without injected secrets."
exit (Start-DotfilesGuiTarget)
