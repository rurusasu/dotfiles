$expectedRuntime = $env:DOTFILES_E2E_POWERSHELL_VERSION
$runtimeCommand = if ($expectedRuntime -eq '5.1') { 'powershell.exe' } else { 'pwsh.exe' }
$runtimeExecutable = Get-Command -Name $runtimeCommand -CommandType Application -ErrorAction Stop |
    Select-Object -First 1
$runtimePath = [string]$runtimeExecutable.Source

function Get-WindowsInstallerUserPathSnapshot {
    $snapshot = [pscustomobject]@{ Exists = $false; Value = $null; Kind = [Microsoft.Win32.RegistryValueKind]::ExpandString }
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
    if ($key) {
        try {
            $snapshot.Exists = $key.GetValueNames() -contains 'PATH'
            if ($snapshot.Exists) {
                $snapshot.Value = $key.GetValue('PATH', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                $snapshot.Kind = $key.GetValueKind('PATH')
            }
        }
        finally { $key.Dispose() }
    }
    return $snapshot
}

function Set-WindowsInstallerUserPathSeed {
    param([Parameter(Mandatory)]$Snapshot)
    $oversizedUserPathEntries = 1..1000 | ForEach-Object { "C:\dotfiles-ci-stale-path-entry-$_" }
    $seededUserPath = (@($oversizedUserPathEntries) + @([string]$Snapshot.Value -split ';' | Where-Object { $_ })) -join ';'
    if ($seededUserPath.Length -le 32767) { throw 'Could not seed an over-limit User PATH for the installer E2E' }
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    if (-not $key) { throw 'Could not open the current user Environment registry key for the PATH E2E' }
    try { $key.SetValue('PATH', $seededUserPath, [Microsoft.Win32.RegistryValueKind]::ExpandString) }
    finally { $key.Dispose() }
}

function Restore-WindowsInstallerUserPath {
    param([Parameter(Mandatory)]$Snapshot)
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    if (-not $key) { throw 'Could not open the current user Environment registry key to restore PATH' }
    try {
        if ($Snapshot.Exists) { $key.SetValue('PATH', $Snapshot.Value, $Snapshot.Kind) }
        else { $key.DeleteValue('PATH', $false) }
    }
    finally { $key.Dispose() }
    Write-Host 'Restored the original User PATH after the Windows installer E2E'
}

$installerE2EScript = @'
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$validationErrors = [System.Collections.Generic.List[string]]::new()
function Invoke-WindowsE2EValidation {
  param(
    [Parameter(Mandatory)]
    [string]$Name,
    [Parameter(Mandatory)]
    [scriptblock]$Validation
  )

  try {
    & $Validation
  }
  catch {
    $validationError = "${Name}: $($_.Exception.Message)"
    $validationErrors.Add($validationError)
    Write-Host "Windows installer E2E validation failed: $validationError" -ForegroundColor Red
  }
}

try {
$expectedVersion = $env:DOTFILES_E2E_POWERSHELL_VERSION
$expectedMajorVersion = if ($expectedVersion -eq '5.1') { 5 } else { 7 }
if ($PSVersionTable.PSVersion.Major -ne $expectedMajorVersion) {
  throw "Windows installer E2E must run under PowerShell $expectedVersion, got $($PSVersionTable.PSVersion)"
}

$originalPath = $env:PATH
$originalPs7Dir = $env:DOTFILES_PS7_DIR
$originalForceWindowsPowerShell = $env:DOTFILES_FORCE_WINDOWS_POWERSHELL
$isWindowsPowerShell = $expectedVersion -eq '5.1'
$pwshExecutable = Get-Command -Name 'pwsh.exe' -CommandType Application -ErrorAction Stop |
  Select-Object -First 1
$pwshExecutable = [string]$pwshExecutable.Source
$env:DOTFILES_PS7_DIR = Split-Path -Parent $pwshExecutable
if ($isWindowsPowerShell) {
  # The explicit flag selects Windows PowerShell for install.cmd while
  # keeping the pre-existing PowerShell 7 runtime available.
  $env:DOTFILES_FORCE_WINDOWS_POWERSHELL = '1'
}
else {
  Remove-Item Env:\DOTFILES_FORCE_WINDOWS_POWERSHELL -ErrorAction SilentlyContinue
}

Push-Location $env:GITHUB_WORKSPACE
try {
  if ($isWindowsPowerShell) {
    if ($env:DOTFILES_FORCE_WINDOWS_POWERSHELL -ne '1') {
      throw 'The Windows PowerShell 5.1 E2E did not force the install.cmd fallback'
    }
    if (-not (Get-Command -Name 'pwsh.exe' -CommandType Application -ErrorAction SilentlyContinue)) {
      throw 'PowerShell 7 must remain discoverable for the runtime selection check'
    }
  }
  else {
    if (-not (Test-Path -LiteralPath (Join-Path $env:DOTFILES_PS7_DIR 'pwsh.exe'))) {
      throw 'PowerShell 7 executable is missing from DOTFILES_PS7_DIR'
    }
  }

  $ErrorActionPreference = 'Continue'
  $output = & cmd.exe /d /c install.cmd -NoPause -UserPhaseOnly 2>&1 |
    ForEach-Object {
      $line = [string]$_
      Write-Host $line
      $line
    }
  $exitCode = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
}
finally {
  $env:PATH = $originalPath
  if ($null -eq $originalForceWindowsPowerShell) {
    Remove-Item Env:\DOTFILES_FORCE_WINDOWS_POWERSHELL -ErrorAction SilentlyContinue
  }
  else {
    $env:DOTFILES_FORCE_WINDOWS_POWERSHELL = $originalForceWindowsPowerShell
  }
  if ($null -eq $originalPs7Dir) {
    Remove-Item Env:\DOTFILES_PS7_DIR -ErrorAction SilentlyContinue
  }
  else {
    $env:DOTFILES_PS7_DIR = $originalPs7Dir
  }
  Pop-Location
}

$out = $output -join [Environment]::NewLine

. (Join-Path $env:GITHUB_WORKSPACE 'scripts/powershell/lib/Invoke-ExternalCommand.ps1')

Invoke-WindowsE2EValidation -Name 'installer evidence' -Validation {
. (Join-Path $env:GITHUB_WORKSPACE 'scripts/powershell/ci/Assert-WindowsInstallerSuccess.ps1')
Assert-WindowsInstallerSuccess `
  -Output $out `
  -ExitCode $exitCode `
  -CompletionMarker 'User Phase Complete!' `
  -RequiredOutputMarkers @('[Winget] CI_VERIFICATION_INVENTORY:')
if ($out -match '(?im)^\s*\[(?:Npm|Pnpm)\]') {
  throw 'The GUI installer performed npm/pnpm activity'
}
if ($isWindowsPowerShell -and $out -notmatch 'Using Windows PowerShell') {
  throw 'The full Windows installer E2E did not exercise the forced Windows PowerShell 5.1 path'
}
if (-not $isWindowsPowerShell -and $out -match '(Using Windows PowerShell|Falling back to Windows PowerShell)') {
  throw 'The PowerShell 7 installer E2E unexpectedly used the Windows PowerShell 5.1 path'
}
if ($out -notmatch '\[INFO\] Process PATH normalized: removed \d+ missing directories and omitted \d+ over-limit entries; final length \d+/8191\.') {
  throw 'The real installer E2E did not remove stale PATH entries before starting package commands'
}
}

Invoke-WindowsE2EValidation -Name 'WinGet package inventory' -Validation {
$inventoryRecords = [regex]::Matches($out, '(?m)^\[Winget\][ \t]+CI_VERIFICATION_INVENTORY:')
if ($inventoryRecords.Count -ne 1) {
  throw "The GUI installer must report exactly one WinGet verification inventory; found $($inventoryRecords.Count)"
}
. (Join-Path $env:GITHUB_WORKSPACE 'scripts/powershell/ci/Assert-WingetInstallSuccess.ps1')
$wingetManifest = Get-Content -LiteralPath (Join-Path $env:GITHUB_WORKSPACE 'windows/winget/packages.json') -Raw | ConvertFrom-Json
$wingetSources = @(
  $wingetManifest.Sources |
    Where-Object { $_.SourceDetails.Name -in @('winget', 'msstore', 'direct') }
)
if ($wingetSources.Count -eq 0) {
  throw 'Windows E2E manifest does not contain a supported WinGet source'
}

# CI-skipped packages are still verify-only obligations. Include every
# source the user phase applies, and omit only admin or
# explicitly skipped packages.
$expectedWindowsPackageIds = @(
  $wingetSources |
    ForEach-Object { $_.Packages } |
    Where-Object {
      $properties = $_.PSObject.Properties
      $requiresAdmin = $properties['requiresAdmin']
      $skipInstall = $properties['skipInstall']
      ($null -eq $requiresAdmin -or -not [bool]$requiresAdmin.Value) -and
      ($null -eq $skipInstall -or -not [bool]$skipInstall.Value)
    } |
    ForEach-Object { [string]$_.PackageIdentifier } |
    Sort-Object -Unique
)
if ($expectedWindowsPackageIds.Count -eq 0) {
  throw 'Windows E2E manifest has no eligible packages to install and verify'
}
Assert-WingetInstallSuccess -Output $out -ExpectedPackageIds $expectedWindowsPackageIds
}

Invoke-WindowsE2EValidation -Name 'WezTerm install PATH and version' -Validation {
# Refresh only this process so GUI installation can expose its executable.
Update-ProcessEnvironmentPath -ProcessOnly
if ($env:PATH.Length -gt 8191) {
  throw "Post-install PATH exceeds the cmd.exe command environment limit: $($env:PATH.Length)"
}
$weztermManifest = Get-Content -LiteralPath (Join-Path $env:GITHUB_WORKSPACE 'windows/winget/packages.json') -Raw | ConvertFrom-Json
$weztermPackages = @(
  $weztermManifest.Sources | Where-Object { $_.SourceDetails.Name -in @('winget', 'msstore') } |
    ForEach-Object { $_.Packages } |
    Where-Object { $_.PackageIdentifier -match '^wez\.wezterm(?:\.nightly)?$' }
)
if ($weztermPackages.Count -ne 1) {
  throw "Expected exactly one WezTerm package in the generated manifest; found $($weztermPackages.Count)"
}
$weztermCommand = Get-Command -Name 'wezterm' -CommandType Application -ErrorAction Stop |
  Select-Object -First 1
$weztermTimer = [System.Diagnostics.Stopwatch]::StartNew()
$weztermVersionOutput = @(Invoke-VerifyCommand -Command 'wezterm' -Arguments @('--version') -TimeoutSeconds 120)
$weztermVersionExitCode = $LASTEXITCODE
$weztermTimer.Stop()
$weztermVersionText = $weztermVersionOutput -join [Environment]::NewLine
. (Join-Path $env:GITHUB_WORKSPACE 'scripts/powershell/ci/Assert-WezTermInstallEvidence.ps1')
Assert-WezTermInstallEvidence -Output $out -PackageId $weztermPackages[0].PackageIdentifier `
  -VersionOutput $weztermVersionText -VersionExitCode $weztermVersionExitCode
Write-Host "WEZTERM_E2E: runtime=$($PSVersionTable.PSVersion) package=$($weztermPackages[0].PackageIdentifier) executable=$($weztermCommand.Source) elapsedMs=$($weztermTimer.ElapsedMilliseconds) exitCode=$weztermVersionExitCode version=$weztermVersionText"
}

# Later Actions steps run in new processes, after the seeded User PATH is
# restored below. Export the installed command directories for the full suite.
if ($validationErrors.Count -eq 0 -and $env:GITHUB_PATH) {
  $inheritedPath = @($originalPath -split ';')
  $env:PATH -split ';' | Where-Object { $_ -and $inheritedPath -notcontains $_ } |
    Add-Content -LiteralPath $env:GITHUB_PATH -Encoding UTF8
}

}
catch {
  $validationErrors.Add("Windows installer E2E setup: $($_.Exception.Message)")
}
if ($validationErrors.Count -gt 0) {
  $failureSummary = "Windows installer E2E validation failed:`n - $($validationErrors -join "`n - ")"
  Write-Host $failureSummary -ForegroundColor Red
  throw $failureSummary
}
Write-Host "WINDOWS_INSTALLER_E2E_COMPLETE: runtime=$expectedVersion"
'@
$installerE2EScriptPath = Join-Path $env:RUNNER_TEMP "windows-installer-e2e-$expectedRuntime-$PID.ps1"
$installerE2ELogPath = Join-Path $env:RUNNER_TEMP "windows-installer-$expectedRuntime.log"
[System.IO.File]::WriteAllText($installerE2EScriptPath, $installerE2EScript, [System.Text.Encoding]::Unicode)
Write-Host "Running the complete Windows installer E2E under $expectedRuntime ($($runtimeExecutable.Source))"
$previousErrorActionPreference = $ErrorActionPreference
try {
    $installerUserPathSeeded = $false
    $installerUserPathSnapshot = $null
    $installerE2EOutput = [Collections.Generic.List[string]]::new()
    # Open the exact required sink before starting any installer child.
    $prelaunchLog = [IO.File]::Open($installerE2ELogPath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $prelaunchLog.Dispose()
    # The stable Windows PowerShell supervisor owns persisted state even if
    # an MSI terminates the selected runtime before its finally can execute.
    $installerUserPathSnapshot = Get-WindowsInstallerUserPathSnapshot
    $installerUserPathSeeded = $true
    Set-WindowsInstallerUserPathSeed -Snapshot $installerUserPathSnapshot
    $ErrorActionPreference = 'Continue'
    & $runtimePath -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installerE2EScriptPath 2>&1 |
        ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message }
            else { [string]$_ }
        } | Tee-Object -LiteralPath $installerE2ELogPath -ErrorAction Stop | ForEach-Object {
            $installerE2EOutput.Add([string]$_)
            $_
        } | Out-Host
    $installerE2EExitCode = $LASTEXITCODE
    if ($installerE2EExitCode -eq 0 -and @($installerE2EOutput | Where-Object {
                $_ -ceq "WINDOWS_INSTALLER_E2E_COMPLETE: runtime=$expectedRuntime"
            }).Count -ne 1) {
        throw 'Windows installer child exited without the required completion attestation'
    }
}
catch {
    Write-Error ("Windows installer output capture/invocation failed: " + $_.Exception.Message) -ErrorAction Continue
    exit 1
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
    if ($installerUserPathSeeded) {
        try { Restore-WindowsInstallerUserPath -Snapshot $installerUserPathSnapshot }
        catch {
            Write-Error ("Windows installer User PATH cleanup failed: " + $_.Exception.Message) -ErrorAction Continue
            $installerE2EExitCode = 1
        }
    }
    Remove-Item -LiteralPath $installerE2EScriptPath -Force -ErrorAction SilentlyContinue
}
if ($installerE2EExitCode -ne 0) {
    exit $installerE2EExitCode
}
