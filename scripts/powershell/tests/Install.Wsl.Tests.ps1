#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    . "$script:repoRoot/scripts/powershell/lib/Invoke-ExternalCommand.ps1"
    . "$script:repoRoot/scripts/powershell/lib/Invoke-WindowsInstallTask.ps1"
    $script:previousPath = $env:PATH
    $taskRuntime = Resolve-WindowsInstallTask
    $env:PATH = (Split-Path -Parent $taskRuntime) + ';' + $env:PATH
    function Invoke-WslInstallerFixture {
        param(
            [bool]$Existing = $true,
            [string]$Arguments = '',
            [bool]$SetupFailure = $false,
            [bool]$InstallFailure = $false,
            [bool]$WslAvailable = $true,
            [int]$ElevationExitCode = 3010,
            [string]$InstallDirectory = '',
            [switch]$WindowsPowerShell
        )
        $root = Join-Path $TestDrive ('wsl installer ' + [guid]::NewGuid().ToString('N'))
        $adapter = Join-Path $root 'scripts/powershell'
        New-Item -ItemType Directory -Path "$adapter/lib", "$adapter/handlers", "$root/taskfiles/install", "$root/temp" -Force | Out-Null
        if (-not $InstallDirectory) { $InstallDirectory = Join-Path $root 'NixOS' }
        Copy-Item "$script:repoRoot/install.cmd" $root
        foreach ($name in 'install.ps1', 'install.user.ps1', 'Invoke-WindowsInstallPhase.ps1') {
            $source = Join-Path $script:repoRoot "scripts/powershell/$name"
            if (Test-Path $source) { Copy-Item $source $adapter }
        }
        Copy-Item "$script:repoRoot/scripts/powershell/lib/*.ps1" "$adapter/lib"
        Copy-Item "$script:repoRoot/scripts/powershell/handlers/Handler.NixOSWSL.ps1" "$adapter/handlers"
        Copy-Item "$script:repoRoot/scripts/powershell/handlers/Handler.WslInstall.ps1" "$adapter/handlers"
        Copy-Item "$script:repoRoot/taskfiles/install/taskfile.yml" "$root/taskfiles/install"
        Set-Content "$root/Taskfile.yml" -Value @'
version: '3'
includes:
  install:
    taskfile: ./taskfiles/install/taskfile.yml
    flatten: true
'@
        Set-Content "$adapter/handlers/Handler.Winget.ps1" -Value @'
class WingetHandler : SetupHandlerBase {
    WingetHandler() { $this.Name = 'Winget' }
    [bool] CanApply([SetupContext]$ctx) { return $true }
    [SetupResult] Apply([SetupContext]$ctx) {
        Add-Content (Join-Path $ctx.DotfilesPath 'events.txt') 'gui'
        return $this.CreateSuccessResult('GUI fixture applied')
    }
}
'@
        # Keep the real install handler and intercept only OS/network/setup boundaries.
        Add-Content "$adapter/lib/Invoke-ExternalCommand.ps1" -Value @'
function Test-WslAvailable { return $env:FIXTURE_WSL_AVAILABLE -eq 'True' }
function Invoke-Wsl {
    param([string[]]$Arguments, [int]$TimeoutSeconds)
    $global:LASTEXITCODE = 0
    $root = $env:FIXTURE_ROOT
    if ($Arguments -contains '--list') {
        if ($env:FIXTURE_EXISTING -eq 'True' -or (Test-Path "$root/installed.txt")) {
            return "N`0i`0x`0O`0S`0"
        }
    }
    elseif ($Arguments -contains '--install' -or $Arguments -contains '--import') {
        Add-Content "$root/events.txt" 'install'
        if ($env:FIXTURE_INSTALL_FAILURE -eq 'True') { $global:LASTEXITCODE = 1 }
        else { Set-Content "$root/installed.txt" 'registered' }
    }
    elseif ($Arguments -contains '--version') { return 'WSL version: 2.4.4.0' }
    elseif ($Arguments -contains '--help') { return '--install --from-file' }
}
function Invoke-RestMethodSafe {
    param($Uri, $Headers)
    return @{ tag_name = 'fixture'; assets = @(@{ name = 'nixos.wsl'; browser_download_url = 'https://example.invalid/nixos.wsl' }) }
}
function Invoke-WebRequestSafe {
    param($Uri, $OutFile)
    Set-Content $OutFile 'fixture'
}
function Invoke-WslBaseElevation {
    param($ScriptPath)
    Add-Content "$env:FIXTURE_ROOT/events.txt" 'elevate'
    return [int]$env:FIXTURE_ELEVATION_EXIT_CODE
}
'@
        Set-Content "$adapter/lib/Invoke-NixosWslSetup.ps1" -Value @'
function Invoke-NixosWslSetup {
    param($Context)
    Add-Content "$env:FIXTURE_ROOT/events.txt" 'setup'
    $Context | ConvertTo-Json -Depth 10 | Set-Content "$env:FIXTURE_ROOT/context.json"
    if ($env:FIXTURE_SETUP_FAILURE -eq 'True') { throw 'FIXTURE_SETUP_FAILURE' }
}
'@
        $info = New-Object System.Diagnostics.ProcessStartInfo
        $info.FileName = 'cmd.exe'
        $info.Arguments = "/d /c install.cmd -NoPause -InstallDir `"$InstallDirectory`" $Arguments"
        $info.WorkingDirectory = $root
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $info.EnvironmentVariables['FIXTURE_ROOT'] = $root
        $info.EnvironmentVariables['FIXTURE_EXISTING'] = [string]$Existing
        $info.EnvironmentVariables['FIXTURE_SETUP_FAILURE'] = [string]$SetupFailure
        $info.EnvironmentVariables['FIXTURE_INSTALL_FAILURE'] = [string]$InstallFailure
        $info.EnvironmentVariables['FIXTURE_WSL_AVAILABLE'] = [string]$WslAvailable
        $info.EnvironmentVariables['FIXTURE_ELEVATION_EXIT_CODE'] = [string]$ElevationExitCode
        $info.EnvironmentVariables['TEMP'] = Join-Path $root 'temp'
        $info.EnvironmentVariables['TMP'] = Join-Path $root 'temp'
        if ($WindowsPowerShell -or $PSVersionTable.PSVersion.Major -lt 6) { $info.EnvironmentVariables['DOTFILES_FORCE_WINDOWS_POWERSHELL'] = '1' }
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $info
        try {
            [void]$process.Start()
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(60000)) {
                & taskkill.exe /PID $process.Id /T /F | Out-Null
                throw 'WSL installer fixture timed out'
            }
            $events = if (Test-Path "$root/events.txt") { @(Get-Content "$root/events.txt") } else { @() }
            $context = if (Test-Path "$root/context.json") { Get-Content "$root/context.json" -Raw | ConvertFrom-Json } else { $null }
            return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $stdout.Result + $stderr.Result; Events = $events; Context = $context }
        }
        finally { $process.Dispose() }
    }
}

AfterAll { $env:PATH = $script:previousPath }

Describe 'Windows installer WSL integration' -Skip:($env:OS -ne 'Windows_NT') {
    It 'should apply existing NixOS once after GUI setup without reinstalling' {
        $result = Invoke-WslInstallerFixture
        $result.ExitCode | Should -Be 0 -Because $result.Output
        ($result.Events -join ',') | Should -Be 'gui,setup'
        $result.Context.Options.PSObject.Properties.Name | Should -Not -Contain 'StateVersion'
        $result.Output | Should -Match 'Setup Complete!'
    }

    It 'should install a missing distro and apply its configuration only once' {
        $result = Invoke-WslInstallerFixture -Existing $false
        $result.ExitCode | Should -Be 0 -Because $result.Output
        ($result.Events -join ',') | Should -Be 'gui,install,setup'
    }

    It 'should forward synchronization and explicit state version options' {
        $result = Invoke-WslInstallerFixture -Arguments '-SyncMode none -SyncBack none -StateVersion 25.05 -ForcePostInstall'
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Context.Options.SyncMode | Should -Be 'none'
        $result.Context.Options.SyncBack | Should -Be 'none'
        $result.Context.Options.StateVersion | Should -Be '25.05'
        $result.Context.Options.ForcePostInstall | Should -BeTrue
    }

    It 'should run GUI setup alone when UserPhaseOnly is requested' {
        $result = Invoke-WslInstallerFixture -Arguments '-UserPhaseOnly'
        $result.ExitCode | Should -Be 0 -Because $result.Output
        ($result.Events -join ',') | Should -Be 'gui'
    }

    It 'should preserve an explicitly disabled force option across processes' {
        $result = Invoke-WslInstallerFixture -Arguments '-ForcePostInstall:$false'
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Context.Options.ForcePostInstall | Should -BeFalse
    }

    It 'should forward the selected distro and installation location' {
        $customLocation = Join-Path $TestDrive 'Custom WSL location'
        $result = Invoke-WslInstallerFixture -Existing $false -InstallDirectory $customLocation -Arguments '-DistroName WorkNix -ReleaseTag fixture'
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Context.DistroName | Should -Be 'WorkNix'
        $result.Context.InstallDir | Should -Be $customLocation
        $result.Context.Options.ReleaseTag | Should -Be 'fixture'
        ($result.Events -join ',') | Should -Be 'gui,install,setup'
    }

    It 'should propagate configuration failure without reporting completion' {
        $result = Invoke-WslInstallerFixture -SetupFailure $true
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'FIXTURE_SETUP_FAILURE'
        $result.Output | Should -Not -Match 'Setup Complete!'
    }

    It 'should stop before configuration when distro installation fails' {
        $result = Invoke-WslInstallerFixture -Existing $false -InstallFailure $true
        $result.ExitCode | Should -Not -Be 0 -Because ($result.Output + ($result.Events -join ','))
        $result.Events | Should -Not -Contain 'setup'
        $result.Output | Should -Not -Match 'Setup Complete!'
    }

    It 'should stop with restart instructions after enabling the WSL foundation' {
        $result = Invoke-WslInstallerFixture -WslAvailable $false
        $result.ExitCode | Should -Be 3010 -Because $result.Output
        ($result.Events -join ',') | Should -Be 'gui,elevate'
        $result.Output | Should -Match 'restart|再起動'
        $result.Output | Should -Not -Match 'Windows setup failed|task: Failed|CategoryInfo|FullyQualifiedErrorId'
        $result.Output | Should -Not -Match 'Setup Complete!'
    }

    It 'should handle restart instructions without failure through Windows PowerShell 5.1' {
        $result = Invoke-WslInstallerFixture -WindowsPowerShell -WslAvailable $false
        $result.ExitCode | Should -Be 3010 -Because $result.Output
        ($result.Events -join ',') | Should -Be 'gui,elevate'
        $result.Output | Should -Match 'restart|再起動'
        $result.Output | Should -Not -Match 'Windows setup failed|task: Failed|CategoryInfo|Setup Complete!'
    }

    It 'should preserve a real WSL foundation failure' {
        $result = Invoke-WslInstallerFixture -WslAvailable $false -ElevationExitCode 5
        $result.ExitCode | Should -Not -Be 0
        ($result.Events -join ',') | Should -Be 'gui,elevate'
        $result.Output | Should -Match 'failed or was cancelled'
        $result.Output | Should -Not -Match 'Setup Complete!'
    }

    It 'should apply an existing distro with explicit options through Windows PowerShell 5.1' {
        $result = Invoke-WslInstallerFixture -WindowsPowerShell -Arguments '-SyncMode none -SyncBack none -StateVersion 25.05'
        $result.ExitCode | Should -Be 0 -Because $result.Output
        ($result.Events -join ',') | Should -Be 'gui,setup'
        $result.Context.Options.StateVersion | Should -Be '25.05'
        $result.Context.Options.SyncMode | Should -Be 'none'
        $result.Output | Should -Match 'Using Windows PowerShell'
    }

    It 'should install a missing distro only once through Windows PowerShell 5.1' {
        $result = Invoke-WslInstallerFixture -WindowsPowerShell -Existing $false
        $result.ExitCode | Should -Be 0 -Because $result.Output
        ($result.Events -join ',') | Should -Be 'gui,install,setup'
    }

    It 'should propagate setup failure through Windows PowerShell 5.1' {
        $result = Invoke-WslInstallerFixture -WindowsPowerShell -SetupFailure $true
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'FIXTURE_SETUP_FAILURE'
        $result.Output | Should -Not -Match 'Setup Complete!'
    }
}
