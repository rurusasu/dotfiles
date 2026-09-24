$expectedRuntime = $env:DOTFILES_E2E_POWERSHELL_VERSION
$runtimeCommand = if ($expectedRuntime -eq '5.1') { 'powershell.exe' } else { 'pwsh.exe' }
$runtimeExecutable = Get-Command -Name $runtimeCommand -CommandType Application -ErrorAction Stop |
  Select-Object -First 1
$runtimePath = [string]$runtimeExecutable.Source

# The PowerShell 7 E2E host cannot safely update its own executable.
# Windows PowerShell 5.1 runs the same full install and verifies this package.
if ($expectedRuntime -eq '7') {
  $manifestPath = Join-Path $env:GITHUB_WORKSPACE 'windows\winget\packages.json'
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  $powerShellPackages = @(
    $manifest.Sources | ForEach-Object { $_.Packages } |
      Where-Object { $_.PackageIdentifier -eq 'Microsoft.PowerShell' }
  )
  if ($powerShellPackages.Count -ne 1) {
    throw "Expected one Microsoft.PowerShell manifest entry; found $($powerShellPackages.Count)."
  }
  $powerShellPackages[0] | Add-Member -NotePropertyName ciSkipInstall -NotePropertyValue $true -Force
  $manifest | ConvertTo-Json -Depth 100 |
    Set-Content -LiteralPath $manifestPath -Encoding utf8
  Write-Host 'Microsoft.PowerShell self-update is covered by the Windows PowerShell 5.1 E2E job'
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
$pwshExecutable = (Get-Command -Name 'pwsh.exe' -CommandType Application -ErrorAction Stop).Source
$env:DOTFILES_PS7_DIR = Split-Path -Parent $pwshExecutable
if ($isWindowsPowerShell) {
  # Keep PowerShell 7 visible so WinGet verifies its installed package;
  # the explicit flag forces only install.cmd to use Windows PowerShell.
  $env:DOTFILES_FORCE_WINDOWS_POWERSHELL = '1'
}
else {
  Remove-Item Env:\DOTFILES_FORCE_WINDOWS_POWERSHELL -ErrorAction SilentlyContinue
}

# The hosted image can contain pnpm already. Hide only its executable
# directory for the installer process so both shell jobs exercise the
# actual npm/corepack bootstrap path reported as failing by users.
$pnpmExecutableDirectories = @(
  Get-Command -Name 'pnpm' -CommandType Application -All -ErrorAction SilentlyContinue |
    ForEach-Object { Split-Path -Parent $_.Source } |
    Sort-Object -Unique
)

Push-Location $env:GITHUB_WORKSPACE
try {
  if ($pnpmExecutableDirectories.Count -gt 0) {
    $env:PATH = @(
      $env:PATH -split ';' |
        Where-Object { $_ -and $_ -notin $pnpmExecutableDirectories }
    ) -join ';'
  }
  if (Get-Command -Name 'pnpm' -CommandType Application -ErrorAction SilentlyContinue) {
    throw 'Could not isolate the preinstalled pnpm executable for the bootstrap E2E'
  }
  if (-not (Get-Command -Name 'npm' -CommandType Application -ErrorAction SilentlyContinue)) {
    throw 'Cannot exercise the pnpm bootstrap E2E because npm is unavailable after pnpm isolation'
  }

  $classicBefore = @(winget list --id 9NT1R1C2HH7J --exact --source msstore --accept-source-agreements --disable-interactivity 2>&1)
  $classicBeforeExitCode = $LASTEXITCODE
  $classicBeforeText = $classicBefore -join [Environment]::NewLine
  if ($classicBeforeExitCode -ne 0) {
    $classicBeforeExitCodeUnsigned = [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$classicBeforeExitCode), 0)
    if ($classicBeforeExitCodeUnsigned.ToString('X8') -ne '8A150014') {
      throw "Unable to inspect ChatGPT Classic E2E seed state (winget list exit=$($classicBeforeExitCodeUnsigned.ToString('X8'))): $classicBeforeText"
    }
  }
  if ($classicBeforeText -notmatch '(?im)^\s*.*\b9NT1R1C2HH7J\b') {
    $classicInstallOutput = @(winget install --id 9NT1R1C2HH7J --exact --source msstore --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1)
    $classicInstallExitCode = $LASTEXITCODE
    if ($classicInstallExitCode -ne 0) {
      throw "Could not seed the ChatGPT Classic uninstall E2E (winget exit=$classicInstallExitCode): $($classicInstallOutput -join ' ')"
    }
    $classicInstalled = @(winget list --id 9NT1R1C2HH7J --exact --source msstore --accept-source-agreements --disable-interactivity 2>&1)
    $classicInstalledText = $classicInstalled -join [Environment]::NewLine
    if ($classicInstalledText -notmatch '(?im)^\s*.*\b9NT1R1C2HH7J\b') {
      throw "ChatGPT Classic E2E seed install did not become visible in WinGet: $classicInstalledText"
    }
  }

  if ($isWindowsPowerShell) {
    if ($env:DOTFILES_FORCE_WINDOWS_POWERSHELL -ne '1') {
      throw 'The Windows PowerShell 5.1 E2E did not force the install.cmd fallback'
    }
    if (-not (Get-Command -Name 'pwsh.exe' -CommandType Application -ErrorAction SilentlyContinue)) {
      throw 'PowerShell 7 must remain discoverable so WinGet can verify the installed package'
    }
  }
  else {
    if (-not (Test-Path -LiteralPath (Join-Path $env:DOTFILES_PS7_DIR 'pwsh.exe'))) {
      throw 'PowerShell 7 executable is missing from DOTFILES_PS7_DIR'
    }
  }

  # Reproduce a stale/oversized inherited PATH before the real install.
  # install.user.ps1 must normalize it before its first child process.
  $oversizedPathEntries = 1..500 | ForEach-Object { "C:\dotfiles-ci-stale-path-entry-$_" }
  $env:PATH = (@($env:PATH -split ';') + @($oversizedPathEntries)) -join ';'
  if ($env:PATH.Length -le 8191 -or $env:PATH.Length -ge 32767) {
    throw "Could not seed a valid oversized process PATH for the installer E2E: $($env:PATH.Length) characters"
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

# install.cmd persists PATH and PNPM_HOME to the user environment in
# its child process. Re-read those values so post-install probes use
# the shims the installer just published, not only the runner PATH.
$npmPrefixOutput = @(Invoke-Npm -Arguments @('prefix', '--global'))
$npmPrefixExitCode = $LASTEXITCODE
$npmGlobalPrefix = if ($npmPrefixExitCode -eq 0) { [string]($npmPrefixOutput | Select-Object -Last 1) } else { '' }
$runnerPnpmDirectories = @($pnpmExecutableDirectories | Where-Object {
  [string]::IsNullOrWhiteSpace($npmGlobalPrefix) -or
  -not [System.StringComparer]::OrdinalIgnoreCase.Equals(
    [System.IO.Path]::GetFullPath($_).TrimEnd('\'),
    [System.IO.Path]::GetFullPath($npmGlobalPrefix.Trim()).TrimEnd('\')
  )
})
$env:PATH = $originalPath
Update-ProcessEnvironmentPath -ExcludePath $runnerPnpmDirectories
if ($env:PATH.Length -gt 8191) {
  throw "Post-install PATH exceeds the cmd.exe command environment limit: $($env:PATH.Length)"
}
$persistedPnpmHome = [Environment]::GetEnvironmentVariable('PNPM_HOME', 'User')
if (-not [string]::IsNullOrWhiteSpace($persistedPnpmHome)) {
  $env:PNPM_HOME = $persistedPnpmHome
}

Invoke-WindowsE2EValidation -Name 'installer evidence' -Validation {
. (Join-Path $env:GITHUB_WORKSPACE 'scripts/powershell/ci/Assert-WindowsInstallerSuccess.ps1')
$npmManifest = Get-Content -LiteralPath (Join-Path $env:GITHUB_WORKSPACE 'windows/npm/packages.json') -Raw | ConvertFrom-Json
$pnpmManifest = Get-Content -LiteralPath (Join-Path $env:GITHUB_WORKSPACE 'windows/pnpm/packages.json') -Raw | ConvertFrom-Json
$requiredPackageManagerMarkers = @('[Pnpm] npm で pnpm をインストールしました')
foreach ($package in $npmManifest.globalPackages) {
  $requiredPackageManagerMarkers += "[Npm] ✓ $($package.name)"
}
foreach ($package in $pnpmManifest.globalPackages) {
  $installFeature = $package.PSObject.Properties['installFeature']
  if ($null -eq $installFeature -or [string]::IsNullOrWhiteSpace([string]$installFeature.Value)) {
    $requiredPackageManagerMarkers += "[Pnpm] ✓ $($package.name)"
  }
}
Assert-WindowsInstallerSuccess `
  -Output $out `
  -ExitCode $exitCode `
  -CompletionMarker 'User Phase Complete!' `
  -RequiredOutputMarkers $requiredPackageManagerMarkers
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
. (Join-Path $env:GITHUB_WORKSPACE 'scripts/powershell/ci/Assert-WingetInstallSuccess.ps1')
$wingetManifest = Get-Content -LiteralPath (Join-Path $env:GITHUB_WORKSPACE 'windows/winget/packages.json') -Raw | ConvertFrom-Json
$wingetSource = @($wingetManifest.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
if ($null -eq $wingetSource) {
  throw 'Windows E2E manifest does not contain the winget source'
}

# This uses the normal install path, not WingetVerifyCommandOnly. Check
# every package the user phase normally applies, including packages
# marked ciSkipInstall for the separate verify-only CI mode.
$expectedWindowsPackageIds = @(
  $wingetSource.Packages |
    Where-Object {
      $properties = $_.PSObject.Properties
      $requiresAdmin = $properties['requiresAdmin']
      $installFeature = $properties['installFeature']
      $skipInstall = $properties['skipInstall']
      $ciSkipInstall = $properties['ciSkipInstall']
      ($null -eq $requiresAdmin -or -not [bool]$requiresAdmin.Value) -and
      ($null -eq $installFeature -or [string]::IsNullOrWhiteSpace([string]$installFeature.Value)) -and
      ($null -eq $skipInstall -or -not [bool]$skipInstall.Value) -and
      ($null -eq $ciSkipInstall -or -not [bool]$ciSkipInstall.Value)
    } |
    ForEach-Object { [string]$_.PackageIdentifier } |
    Sort-Object -Unique
)
if ($expectedWindowsPackageIds.Count -eq 0) {
  throw 'Windows E2E manifest has no eligible packages to install and verify'
}
Assert-WingetInstallSuccess -Output $out -ExpectedPackageIds $expectedWindowsPackageIds
}

Invoke-WindowsE2EValidation -Name 'pnpm bootstrap' -Validation {
$npmPrefixOutput = @(npm prefix --global 2>&1)
$npmPrefixExitCode = $LASTEXITCODE
$npmGlobalPrefix = if ($npmPrefixExitCode -eq 0) { [string]($npmPrefixOutput | Select-Object -Last 1) } else { '' }
if ([string]::IsNullOrWhiteSpace($npmGlobalPrefix)) {
  throw "Unable to resolve the npm global prefix for the pnpm bootstrap (exit=$npmPrefixExitCode): $($npmPrefixOutput -join ' ')"
}
$npmGlobalPrefix = [System.IO.Path]::GetFullPath($npmGlobalPrefix.Trim())
$npmPnpmShim = Join-Path $npmGlobalPrefix 'pnpm.cmd'
if (-not (Test-Path -LiteralPath $npmPnpmShim -PathType Leaf)) {
  throw "npm did not install the pnpm command shim under its global prefix: $npmPnpmShim"
}
$npmPnpmOutput = @(& $npmPnpmShim --version 2>&1)
$npmPnpmExitCode = $LASTEXITCODE
if ($npmPnpmExitCode -ne 0 -or ($npmPnpmOutput -join ' ') -notmatch '\d+\.\d+') {
  throw "npm-installed pnpm shim failed its version probe (exit=$npmPnpmExitCode): $($npmPnpmOutput -join ' ')"
}
}

Invoke-WindowsE2EValidation -Name 'ChatGPT Classic removal' -Validation {
if ($out -notmatch '(?m)RETIRED_PACKAGE_CLEANUP: id=9NT1R1C2HH7J status=(removed|absent)') {
  throw 'ChatGPT Classic retired-package cleanup did not complete successfully'
}

$classicListOutput = @(winget list --id 9NT1R1C2HH7J --exact --source msstore --accept-source-agreements --disable-interactivity 2>&1)
$classicListExitCode = $LASTEXITCODE
$classicListText = $classicListOutput -join [Environment]::NewLine
if ($classicListText -match '(?im)^\s*.*\b9NT1R1C2HH7J\b') {
  throw 'ChatGPT Classic is still installed after cleanup'
}
if ($classicListExitCode -ne 0) {
  $classicListExitCodeUnsigned = [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$classicListExitCode), 0)
  if ($classicListExitCodeUnsigned.ToString('X8') -ne '8A150014') {
    throw "Unable to verify ChatGPT Classic removal (winget list exit=$($classicListExitCodeUnsigned.ToString('X8'))): $classicListText"
  }
}
}

Invoke-WindowsE2EValidation -Name 'Codex package structure' -Validation {
$codexLinksPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
$codexShimPath = Join-Path $codexLinksPath 'codex.exe'
if (-not (Test-Path -LiteralPath $codexShimPath -PathType Leaf)) {
  throw "Codex CLI shim is missing after installation: $codexShimPath"
}
$codexPathCommand = Get-Command -Name 'codex.exe' -CommandType Application -ErrorAction SilentlyContinue |
  Select-Object -First 1
$codexPathCommandPath = Get-ExternalCommandPath -CommandInfo $codexPathCommand
if (-not $codexPathCommand -or
  -not ([System.IO.Path]::GetFullPath($codexPathCommandPath)).Equals(
    [System.IO.Path]::GetFullPath($codexShimPath),
    [System.StringComparison]::OrdinalIgnoreCase
  )) {
  throw "Codex CLI shim is not the command exposed on PATH: expected=$codexShimPath actual=$codexPathCommandPath"
}

. (Join-Path $env:GITHUB_WORKSPACE 'scripts/powershell/lib/SetupHandler.ps1')
. (Join-Path $env:GITHUB_WORKSPACE 'scripts/powershell/handlers/Handler.Codex.ps1')
$codexPackageExecutablePath = Resolve-CodexPackageExecutablePath -LocalAppData $env:LOCALAPPDATA
if (-not $codexPackageExecutablePath) {
  throw 'Codex executable with an adjacent code-mode host cannot be located in WinGet or Programs\Codex'
}
$codexShimHash = (Get-FileHash -LiteralPath $codexShimPath -Algorithm SHA256).Hash
$codexPackageHash = (Get-FileHash -LiteralPath $codexPackageExecutablePath -Algorithm SHA256).Hash
if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals($codexShimHash, $codexPackageHash)) {
  throw "Codex PATH shim does not match the selected installed package executable: shim=$codexShimPath package=$codexPackageExecutablePath"
}

$codexShim = Get-Item -LiteralPath $codexShimPath
$codexHostDirectory = $codexLinksPath
if (($codexShim.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
  # Resolve the package from known install roots. This works in Windows
  # PowerShell 5.1, where FileInfo does not expose LinkType or Target.
  $codexHostDirectory = Split-Path -Parent $codexPackageExecutablePath
}

$codexHostPath = Join-Path $codexHostDirectory 'codex-code-mode-host.exe'
if (-not (Test-Path -LiteralPath $codexHostPath -PathType Leaf)) {
  throw "Codex code-mode host is missing beside the selected Codex executable: $codexHostPath"
}
}

Invoke-WindowsE2EValidation -Name 'required command smoke tests' -Validation {
# A handler that cannot run its setup predicate is skipped, not failed.
# Require the key npm/pnpm/1Password tools themselves so a green phase
# cannot hide missing prerequisites or an unconfigured PATH.
$onePasswordPackagesPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
$persistedOnePasswordPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$onePasswordUserPathEntries = @($persistedOnePasswordPath -split ';' | Where-Object { $_ } | ForEach-Object { [System.IO.Path]::GetFullPath($_.Trim()) })
$onePasswordPackageRoot = [System.IO.Path]::GetFullPath($onePasswordPackagesPath).TrimEnd('\') + '\'
$onePasswordPackageDirectory = $onePasswordUserPathEntries |
  Where-Object {
    $_.StartsWith($onePasswordPackageRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
    (Split-Path -Leaf $_) -like 'AgileBits.1Password.CLI_*' -and
    (Test-Path -LiteralPath (Join-Path $_ 'op.exe') -PathType Leaf)
  } |
  Select-Object -First 1
if (-not $onePasswordPackageDirectory) {
  throw 'Persisted user PATH does not identify an installed AgileBits.1Password.CLI package directory containing op.exe'
}
$onePasswordExecutablePath = Join-Path $onePasswordPackageDirectory 'op.exe'
$resolvedOnePassword = Get-Command -Name 'op.exe' -CommandType Application -ErrorAction Stop | Select-Object -First 1
$resolvedOnePasswordPath = Get-ExternalCommandPath -CommandInfo $resolvedOnePassword
$installedOnePasswordHash = (Get-FileHash -LiteralPath $onePasswordExecutablePath -Algorithm SHA256).Hash
$resolvedOnePasswordHash = (Get-FileHash -LiteralPath $resolvedOnePasswordPath -Algorithm SHA256).Hash
if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals($installedOnePasswordHash, $resolvedOnePasswordHash)) {
  throw "PATH-resolved op.exe does not match the configured WinGet package binary: resolved=$resolvedOnePasswordPath installed=$onePasswordExecutablePath"
}
$onePasswordVersion = @(& $resolvedOnePasswordPath --version 2>&1)
$onePasswordExitCode = $LASTEXITCODE
if ($onePasswordExitCode -ne 0) {
  throw "Installed 1Password CLI failed its version probe (exit=$onePasswordExitCode): $($onePasswordVersion -join ' ')"
}
$winGetLinksPath = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'))
if ($onePasswordUserPathEntries -contains $winGetLinksPath -and -not (Test-Path -LiteralPath (Join-Path $winGetLinksPath 'op.exe') -PathType Leaf)) {
  throw 'WinGet Links op.exe shim is missing after OnePasswordCli setup'
}
$nodeVersionOutput = @(node --version 2>&1)
$nodeVersionExitCode = $LASTEXITCODE
if ($nodeVersionExitCode -ne 0 -or $nodeVersionOutput.Count -eq 0) {
  throw "Cannot determine the active Node.js version required by agent-browser@0.38.1 (exit=$nodeVersionExitCode): $($nodeVersionOutput -join ' ')"
}
$nodeVersionText = ([string]($nodeVersionOutput | Select-Object -Last 1)).Trim() -replace '^v', ''
$nodeVersion = $null
if (-not [version]::TryParse($nodeVersionText, [ref]$nodeVersion) -or $nodeVersion -lt [version]'24.0.0') {
  throw "agent-browser@0.38.1 requires Node.js >=24.0.0; active Node.js version is '$nodeVersionText'"
}

$requiredCommands = @(
  @{ Name = 'npm'; Arguments = @('--version') }
  @{ Name = 'agent-browser'; Arguments = @('--version') }
  @{ Name = 'herdr'; Arguments = @('--version') }
  @{ Name = 'pnpm'; Arguments = @('--version') }
  @{ Name = 'gemini'; Arguments = @('--version') }
  @{ Name = 'op.exe'; Arguments = @('--version') }
)
foreach ($requiredCommand in $requiredCommands) {
  $resolvedCommand = Get-Command -Name $requiredCommand.Name -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if (-not $resolvedCommand) {
    throw "Windows installer did not expose required command '$($requiredCommand.Name)'"
  }

  if ($requiredCommand.Name -eq 'pnpm') {
    $resolvedPnpmPath = [System.IO.Path]::GetFullPath((Get-ExternalCommandPath -CommandInfo $resolvedCommand))
    $expectedPnpmPath = [System.IO.Path]::GetFullPath($npmPnpmShim)
    if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals($resolvedPnpmPath, $expectedPnpmPath)) {
      throw "PATH-resolved pnpm is not the npm-installed pnpm shim: resolved=$resolvedPnpmPath expected=$expectedPnpmPath"
    }
  }

  $commandArguments = @($requiredCommand.Arguments)
  $resolvedCommandPath = Get-ExternalCommandPath -CommandInfo $resolvedCommand
  $commandOutput = @(& $resolvedCommandPath @commandArguments 2>&1)
  $commandExitCode = $LASTEXITCODE
  if ($commandExitCode -ne 0) {
    throw "Windows installer command '$($requiredCommand.Name)' failed (exit=$commandExitCode): $($commandOutput -join ' ')"
  }
}
}
}
catch {
  $validationErrors.Add("Windows installer E2E setup: $($_.Exception.Message)")
}
finally {
  try {
    $codexShimPath = Join-Path (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links') 'codex.exe'
    if (-not (Test-Path -LiteralPath $codexShimPath -PathType Leaf)) {
      throw "Codex CLI shim is missing: $codexShimPath"
    }
    $codexCliOutput = @(& $codexShimPath --help 2>&1)
    $codexCliExitCode = $LASTEXITCODE
    if ($codexCliExitCode -ne 0) {
      throw "Codex CLI --help failed (exit=$codexCliExitCode): $($codexCliOutput -join ' ')"
    }
    Write-Host 'Codex CLI launch probe passed'
  }
  catch {
    $validationErrors.Add("Codex CLI launch probe: $($_.Exception.Message)")
  }

  try {
    . (Join-Path $env:GITHUB_WORKSPACE 'scripts/powershell/lib/SetupHandler.ps1')
    . (Join-Path $env:GITHUB_WORKSPACE 'scripts/powershell/handlers/Handler.Codex.ps1')
    $codexPackageExecutablePath = Resolve-CodexPackageExecutablePath -LocalAppData $env:LOCALAPPDATA
    if (-not $codexPackageExecutablePath) {
      throw 'Codex executable with an adjacent code-mode host cannot be located in WinGet, Programs\Codex, or OpenAI\Codex'
    }

    $codexLinksPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
    $codexShimPath = Join-Path $codexLinksPath 'codex.exe'
    $codexHostDirectory = $codexLinksPath
    if (Test-Path -LiteralPath $codexShimPath -PathType Leaf) {
      $codexShim = Get-Item -LiteralPath $codexShimPath
      if (($codexShim.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        $codexHostDirectory = Split-Path -Parent $codexPackageExecutablePath
      }
    }

    $codexHostPath = Join-Path $codexHostDirectory 'codex-code-mode-host.exe'
    if (-not (Test-Path -LiteralPath $codexHostPath -PathType Leaf)) {
      throw "Codex code-mode host is missing beside the selected Codex executable: $codexHostPath"
    }
    $codexHostOutput = @(& $codexHostPath --help 2>&1)
    $codexHostExitCode = $LASTEXITCODE
    if ($codexHostExitCode -ne 0) {
      throw "Codex code-mode host --help failed (exit=$codexHostExitCode): $($codexHostOutput -join ' ')"
    }
    Write-Host 'Codex code-mode host launch probe passed'
  }
  catch {
    $validationErrors.Add("Codex code-mode host launch probe: $($_.Exception.Message)")
  }
}

if ($validationErrors.Count -gt 0) {
  $failureSummary = "Windows installer E2E validation failed:`n - $($validationErrors -join "`n - ")"
  Write-Host $failureSummary -ForegroundColor Red
  throw $failureSummary
}
'@
$installerE2EScriptPath = Join-Path $env:RUNNER_TEMP "windows-installer-e2e-$expectedRuntime-$PID.ps1"
[System.IO.File]::WriteAllText($installerE2EScriptPath, $installerE2EScript, [System.Text.Encoding]::Unicode)
Write-Host "Running the complete Windows installer E2E under $expectedRuntime ($($runtimeExecutable.Source))"
try {
  & $runtimePath -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installerE2EScriptPath
  $installerE2EExitCode = $LASTEXITCODE
}
finally {
  Remove-Item -LiteralPath $installerE2EScriptPath -Force -ErrorAction SilentlyContinue
}
if ($installerE2EExitCode -ne 0) {
  exit $installerE2EExitCode
}
