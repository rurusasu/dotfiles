#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $script:runsOnWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT

    function Stop-TestProcessTree {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [int]$ProcessId
        )

        if (Get-Command taskkill.exe -ErrorAction SilentlyContinue) {
            & taskkill.exe /PID $ProcessId /T /F | Out-Null
            return
        }

        Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
    }

    function Invoke-TestCmdProcess {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$WorkingDirectory,

            [Parameter(Mandatory)]
            [string]$CommandLine,

            [int]$TimeoutMilliseconds = 60000
        )

        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = "cmd.exe"
        $psi.Arguments = "/d /c $CommandLine"
        $psi.WorkingDirectory = $WorkingDirectory
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $psi

        try {
            [void]$process.Start()
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()

            $finished = $process.WaitForExit($TimeoutMilliseconds)
            if (-not $finished) {
                Stop-TestProcessTree -ProcessId $process.Id
                [void]$process.WaitForExit(5000)
            }
            [void]$process.WaitForExit()

            $stdout = $stdoutTask.Result
            $stderr = $stderrTask.Result
            if (-not $finished) {
                throw "cmd.exe timed out. stdout=[$stdout] stderr=[$stderr]"
            }

            [pscustomobject]@{
                ExitCode = $process.ExitCode
                Stdout   = $stdout
                Stderr   = $stderr
            }
        }
        finally {
            $process.Dispose()
        }
    }

    function Invoke-TestPowerShellProcess {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$WorkingDirectory,

            [Parameter(Mandatory)]
            [string]$ScriptPath,

            [int]$TimeoutMilliseconds = 60000
        )

        $executable = if ($PSVersionTable.PSVersion.Major -ge 6) {
            Join-Path $PSHOME 'pwsh.exe'
        }
        else {
            Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        }

        if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
            throw "PowerShell executable was not found: $executable"
        }

        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $executable
        $quotedScriptPath = $ScriptPath.Replace('"', '\"')
        $psi.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$quotedScriptPath`" -NoPause"
        $psi.WorkingDirectory = $WorkingDirectory
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $psi

        try {
            [void]$process.Start()
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()

            $finished = $process.WaitForExit($TimeoutMilliseconds)
            if (-not $finished) {
                Stop-TestProcessTree -ProcessId $process.Id
                [void]$process.WaitForExit(5000)
            }
            [void]$process.WaitForExit()

            $stdout = $stdoutTask.Result
            $stderr = $stderrTask.Result
            if (-not $finished) {
                throw "$executable timed out. stdout=[$stdout] stderr=[$stderr]"
            }

            [pscustomobject]@{
                ExitCode = $process.ExitCode
                Stdout   = $stdout
                Stderr   = $stderr
            }
        }
        finally {
            $process.Dispose()
        }
    }

    function New-PhaseIntegrationFixture {
        param(
            [Parameter(Mandatory)]
            [string]$Name
        )

        $workDir = Join-Path $TestDrive $Name
        $scriptDir = Join-Path $workDir 'scripts\powershell'
        $libDir = Join-Path $scriptDir 'lib'
        $handlersDir = Join-Path $scriptDir 'handlers'
        New-Item -ItemType Directory -Path $libDir -Force | Out-Null
        New-Item -ItemType Directory -Path $handlersDir -Force | Out-Null

        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'install.cmd') -Destination (Join-Path $workDir 'install.cmd')
        foreach ($scriptName in 'install.ps1', 'install.user.ps1', 'install.admin.ps1') {
            Copy-Item -LiteralPath (Join-Path $script:repoRoot "scripts\powershell\$scriptName") -Destination (Join-Path $scriptDir $scriptName)
        }
        foreach ($library in 'WindowsEnvironment.ps1', 'SetupHandler.ps1', 'Invoke-ExternalCommand.ps1') {
            Copy-Item -LiteralPath (Join-Path $script:repoRoot "scripts\powershell\lib\$library") -Destination (Join-Path $libDir $library)
        }

        $phaseOneHandler = @'
class PhaseOneHandler : SetupHandlerBase {
    PhaseOneHandler() {
        $this.Name = 'FixturePhase1'
        $this.Description = 'Deterministic Phase 1 fixture handler'
        $this.Order = 10
        $this.Phase = 1
        $this.RequiresAdmin = $false
    }

    [bool] CanApply([SetupContext]$ctx) {
        return $true
    }

    [SetupResult] Apply([SetupContext]$ctx) {
        [System.IO.File]::AppendAllText(
            (Join-Path $ctx.DotfilesPath 'phase-markers.txt'),
            "PHASE1_APPLIED`n"
        )
        return $this.CreateSuccessResult('FIXTURE_PHASE1_APPLIED')
    }
}
'@
        $phaseTwoHandler = @'
class PhaseTwoHandler : SetupHandlerBase {
    PhaseTwoHandler() {
        $this.Name = 'FixturePhase2a'
        $this.Description = 'Deterministic Phase 2a fixture handler'
        $this.Order = 20
        $this.Phase = 2
        $this.RequiresAdmin = $false
    }

    [bool] CanApply([SetupContext]$ctx) {
        return $true
    }

    [SetupResult] Apply([SetupContext]$ctx) {
        [System.IO.File]::AppendAllText(
            (Join-Path $ctx.DotfilesPath 'phase-markers.txt'),
            "PHASE2A_APPLIED`n"
        )
        return $this.CreateSuccessResult('FIXTURE_PHASE2A_APPLIED')
    }
}
'@
        $adminProbeHandler = @'
class PhaseTwoAdminProbeHandler : SetupHandlerBase {
    PhaseTwoAdminProbeHandler() {
        $this.Name = 'FixtureAdminProbe'
        $this.Description = 'Deterministic admin phase probe'
        $this.Order = 30
        $this.Phase = 2
        $this.RequiresAdmin = $true
    }

    [bool] CanApply([SetupContext]$ctx) {
        return $false
    }

    [SetupResult] Apply([SetupContext]$ctx) {
        return $this.CreateSuccessResult('FIXTURE_ADMIN_PROBE_APPLIED')
    }
}
'@
        [System.IO.File]::WriteAllText(
            (Join-Path $handlersDir 'Handler.PhaseOne.ps1'),
            $phaseOneHandler,
            [System.Text.UTF8Encoding]::new($false)
        )
        [System.IO.File]::WriteAllText(
            (Join-Path $handlersDir 'Handler.PhaseTwo.ps1'),
            $phaseTwoHandler,
            [System.Text.UTF8Encoding]::new($false)
        )
        [System.IO.File]::WriteAllText(
            (Join-Path $handlersDir 'Handler.PhaseTwoAdminProbe.ps1'),
            $adminProbeHandler,
            [System.Text.UTF8Encoding]::new($false)
        )

        $acceptance = @'
function Test-DotfilesEnvironment {
    [CmdletBinding()]
    param(
        [switch]$Docker,
        [switch]$Runtime
    )

    Write-Host 'FIXTURE_ACCEPTANCE_COMPLETE'
    return [pscustomobject]@{
        Success = $true
        Message = 'Fixture acceptance passed'
    }
}
'@
        [System.IO.File]::WriteAllText(
            (Join-Path $scriptDir 'Test-Environment.ps1'),
            $acceptance,
            [System.Text.UTF8Encoding]::new($false)
        )

        return [pscustomobject]@{
            WorkDirectory = $workDir
            InstallScript = Join-Path $scriptDir 'install.ps1'
            MarkerFile    = Join-Path $workDir 'phase-markers.txt'
        }
    }

    function New-InstallCmdSelectionFixture {
        param(
            [Parameter(Mandatory)]
            [string]$Name
        )

        $workDir = Join-Path $TestDrive $Name
        $scriptDir = Join-Path $workDir 'scripts\powershell'
        New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'install.cmd') -Destination (Join-Path $workDir 'install.cmd')
        $stub = @'
$marker = Join-Path $PSScriptRoot 'selection.txt'
$content = "PS_MAJOR=$($PSVersionTable.PSVersion.Major)`nPATH=$env:PATH"
[System.IO.File]::WriteAllText($marker, $content, [System.Text.UTF8Encoding]::new($false))
exit 0
'@
        [System.IO.File]::WriteAllText(
            (Join-Path $scriptDir 'install.ps1'),
            $stub,
            [System.Text.UTF8Encoding]::new($false)
        )

        return $workDir
    }
}

Describe 'install.cmd entrypoint' {
    It 'should normalize the inherited PATH before discovering or running setup handlers' {
        $userPhase = Get-Content -LiteralPath (Join-Path $script:repoRoot 'scripts/powershell/install.user.ps1') -Raw

        $userPhase | Should -Match '(?s)Invoke-ExternalCommand\.ps1.*?Update-ProcessEnvironmentPath\s+-ReportStatus.*?Get-SetupHandler'
    }

    It 'should execute install.ps1 directly and return before timeout' {
        if (-not $script:runsOnWindows) {
            Set-ItResult -Skipped -Because "install.cmd is a Windows entrypoint"
            return
        }

        $workDir = Join-Path $TestDrive "install-cmd"
        $scriptDir = Join-Path $workDir "scripts\powershell"
        New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:repoRoot "install.cmd") -Destination (Join-Path $workDir "install.cmd")

        $stubInstall = @'
[CmdletBinding()]
param(
    [switch]$NoPause,
    [switch]$UserPhaseOnly,
    [string]$Sentinel = ""
)

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$marker = Join-Path $repoRoot "install-marker.txt"
$message = "STUB_INSTALL_COMPLETE NoPause=$NoPause UserPhaseOnly=$UserPhaseOnly Sentinel=$Sentinel"
[System.IO.File]::WriteAllText($marker, $message, [System.Text.UTF8Encoding]::new($false))
Write-Host $message
exit 0
'@
        [System.IO.File]::WriteAllText(
            (Join-Path $scriptDir "install.ps1"),
            $stubInstall,
            [System.Text.UTF8Encoding]::new($false)
        )

        $result = Invoke-TestCmdProcess `
            -WorkingDirectory $workDir `
            -CommandLine "install.cmd -NoPause -UserPhaseOnly -Sentinel ok"

        $result.ExitCode | Should -Be 0
        $marker = Get-Content -LiteralPath (Join-Path $workDir "install-marker.txt") -Raw
        $marker | Should -Match "STUB_INSTALL_COMPLETE"
        $marker | Should -Match "NoPause=True"
        $marker | Should -Match "UserPhaseOnly=True"
        $marker | Should -Match "Sentinel=ok"

        $installBytes = [System.IO.File]::ReadAllBytes((Join-Path $scriptDir "install.ps1"))
        $hasBom = $installBytes.Length -ge 3 -and
        $installBytes[0] -eq 0xEF -and
        $installBytes[1] -eq 0xBB -and
        $installBytes[2] -eq 0xBF
        $hasBom | Should -BeFalse
    }

    It 'should preserve an overlong inherited PATH when using the explicit PowerShell 7 path' {
        if (-not $script:runsOnWindows) {
            Set-ItResult -Skipped -Because "install.cmd is a Windows entrypoint"
            return
        }

        $pwshExe = Join-Path $PSHOME "pwsh.exe"
        if (-not (Test-Path -LiteralPath $pwshExe -PathType Leaf)) {
            Set-ItResult -Skipped -Because "PowerShell 7 executable is unavailable"
            return
        }

        $workDir = Join-Path $TestDrive "install-cmd-long-path"
        $scriptDir = Join-Path $workDir "scripts\powershell"
        New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:repoRoot "install.cmd") -Destination (Join-Path $workDir "install.cmd")
        [System.IO.File]::WriteAllText(
            (Join-Path $scriptDir "install.ps1"),
            'Write-Host "PS_MAJOR=$($PSVersionTable.PSVersion.Major) PATH_CHARS=$($env:PATH.Length)"; exit 37',
            [System.Text.UTF8Encoding]::new($false)
        )

        $oldDotfilesPs7Dir = $env:DOTFILES_PS7_DIR
        $oldPath = $env:PATH
        try {
            Remove-Item Env:\DOTFILES_PS7_DIR -ErrorAction SilentlyContinue
            $env:PATH = @(
                $oldPath
                (Split-Path -Parent $pwshExe)
                (0..500 | ForEach-Object { "C:\missing-path-entry-$_" })
            ) -join ";"
            $expectedPathLength = $env:PATH.Length
            $expectedPathLength | Should -BeGreaterThan 8191

            $result = Invoke-TestCmdProcess -WorkingDirectory $workDir -CommandLine "install.cmd -NoPause"
        }
        finally {
            if ($null -eq $oldDotfilesPs7Dir) {
                Remove-Item Env:\DOTFILES_PS7_DIR -ErrorAction SilentlyContinue
            }
            else {
                $env:DOTFILES_PS7_DIR = $oldDotfilesPs7Dir
            }
            $env:PATH = $oldPath
        }

        $outputText = @($result.Stdout, $result.Stderr) -join [Environment]::NewLine
        $result.ExitCode | Should -Be 37 -Because "stdout=[$($result.Stdout)] stderr=[$($result.Stderr)]"
        $outputText | Should -Match 'PS_MAJOR=7'
        $pathLengthMatch = [regex]::Match($outputText, 'PATH_CHARS=(\d+)')
        $pathLengthMatch.Success | Should -BeTrue
        [int]$pathLengthMatch.Groups[1].Value | Should -BeGreaterOrEqual $expectedPathLength
    }

    It 'should fall back to Windows PowerShell and still execute install.ps1 when pwsh is absent' {
        if (-not $script:runsOnWindows) {
            Set-ItResult -Skipped -Because "install.cmd is a Windows entrypoint"
            return
        }

        $workDir = Join-Path $TestDrive "install-cmd-windows-powershell-fallback"
        $scriptDir = Join-Path $workDir "scripts\powershell"
        New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:repoRoot "install.cmd") -Destination (Join-Path $workDir "install.cmd")

        Copy-Item -LiteralPath (Join-Path $script:repoRoot "scripts\powershell\install.ps1") -Destination (Join-Path $scriptDir "install.ps1")
        Copy-Item -LiteralPath (Join-Path $script:repoRoot "scripts\powershell\Test-Environment.ps1") -Destination (Join-Path $scriptDir "Test-Environment.ps1")
        $libDir = Join-Path $scriptDir "lib"
        New-Item -ItemType Directory -Path $libDir -Force | Out-Null
        foreach ($library in "WindowsEnvironment.ps1", "Invoke-ExternalCommand.ps1") {
            Copy-Item -LiteralPath (Join-Path $script:repoRoot "scripts\powershell\lib\$library") -Destination (Join-Path $scriptDir "lib\$library")
        }
        Set-Content -LiteralPath (Join-Path $scriptDir "install.user.ps1") -Value @'
[CmdletBinding()]
param(
    [string]$DistroName,
    [string]$InstallDir,
    [string]$ReleaseTag,
    [string]$PostInstallScript,
    [string]$StateVersion,
    [hashtable]$Options = @{},
    [string]$SyncMode,
    [string]$SyncBack
)
Write-Host 'STUB_USER_PHASE_COMPLETE'
exit 0
'@ -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $scriptDir "install.admin.ps1") -Value @'
[CmdletBinding()]
param()
exit 0
'@ -Encoding UTF8

        $oldDotfilesPs7Dir = $env:DOTFILES_PS7_DIR
        $oldPath = $env:PATH
        try {
            $env:DOTFILES_PS7_DIR = Join-Path $TestDrive "missing-pwsh"
            New-Item -ItemType Directory -Path $env:DOTFILES_PS7_DIR -Force | Out-Null
            $env:PATH = @(
                Join-Path $env:SystemRoot "System32"
                Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0"
                $env:SystemRoot
            ) -join ";"

            $result = Invoke-TestCmdProcess `
                -WorkingDirectory $workDir `
                -CommandLine "install.cmd -NoPause -UserPhaseOnly"
        }
        finally {
            if ($null -eq $oldDotfilesPs7Dir) {
                Remove-Item Env:\DOTFILES_PS7_DIR -ErrorAction SilentlyContinue
            }
            else {
                $env:DOTFILES_PS7_DIR = $oldDotfilesPs7Dir
            }
            $env:PATH = $oldPath
        }

        $outputText = @($result.Stdout, $result.Stderr) -join [Environment]::NewLine
        $result.ExitCode | Should -Be 0
        $outputText | Should -Match "Falling back to Windows PowerShell"
        $outputText | Should -Match "STUB_USER_PHASE_COMPLETE"
        $outputText | Should -Match "User Phase Complete!"
    }

    It 'should force Windows PowerShell 5.1 when pwsh is still available and preserve PATH' {
        if (-not $script:runsOnWindows) {
            Set-ItResult -Skipped -Because 'install.cmd is a Windows entrypoint'
            return
        }

        $powershell51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $pwshExe = Join-Path $PSHOME 'pwsh.exe'
        if (-not (Test-Path -LiteralPath $powershell51 -PathType Leaf)) {
            Set-ItResult -Skipped -Because 'Windows PowerShell 5.1 executable is unavailable'
            return
        }
        if (-not (Test-Path -LiteralPath $pwshExe -PathType Leaf)) {
            Set-ItResult -Skipped -Because 'PowerShell 7 executable is unavailable'
            return
        }

        $workDir = New-InstallCmdSelectionFixture -Name 'install-cmd-force-windows-powershell'
        $oldForce = $env:DOTFILES_FORCE_WINDOWS_POWERSHELL
        $oldDotfilesPs7Dir = $env:DOTFILES_PS7_DIR
        $oldPath = $env:PATH
        try {
            $env:DOTFILES_FORCE_WINDOWS_POWERSHELL = '1'
            $env:DOTFILES_PS7_DIR = Split-Path -Parent $pwshExe
            $env:PATH = "$oldPath;C:\dotfiles-e2e-path-preservation"
            $expectedPath = $env:PATH
            $result = Invoke-TestCmdProcess -WorkingDirectory $workDir -CommandLine 'install.cmd -NoPause'
        }
        finally {
            if ($null -eq $oldForce) { Remove-Item Env:\DOTFILES_FORCE_WINDOWS_POWERSHELL -ErrorAction SilentlyContinue }
            else { $env:DOTFILES_FORCE_WINDOWS_POWERSHELL = $oldForce }
            if ($null -eq $oldDotfilesPs7Dir) { Remove-Item Env:\DOTFILES_PS7_DIR -ErrorAction SilentlyContinue }
            else { $env:DOTFILES_PS7_DIR = $oldDotfilesPs7Dir }
            $env:PATH = $oldPath
        }

        $result.ExitCode | Should -Be 0
        $selection = Get-Content -LiteralPath (Join-Path $workDir 'scripts\powershell\selection.txt') -Raw
        $selection | Should -Match 'PS_MAJOR=5'
        $selection | Should -Match ([regex]::Escape("PATH=$expectedPath"))
    }

    It 'should auto-select PowerShell 7 from PATH by default' {
        if (-not $script:runsOnWindows) {
            Set-ItResult -Skipped -Because 'install.cmd is a Windows entrypoint'
            return
        }

        $pwshExe = Join-Path $PSHOME 'pwsh.exe'
        if (-not (Test-Path -LiteralPath $pwshExe -PathType Leaf)) {
            Set-ItResult -Skipped -Because 'PowerShell 7 executable is unavailable'
            return
        }

        $workDir = New-InstallCmdSelectionFixture -Name 'install-cmd-auto-powershell-7'
        $oldForce = $env:DOTFILES_FORCE_WINDOWS_POWERSHELL
        $oldDotfilesPs7Dir = $env:DOTFILES_PS7_DIR
        $oldPath = $env:PATH
        try {
            Remove-Item Env:\DOTFILES_FORCE_WINDOWS_POWERSHELL -ErrorAction SilentlyContinue
            $env:DOTFILES_PS7_DIR = Join-Path $TestDrive 'missing-pwsh'
            $env:PATH = "$(Split-Path -Parent $pwshExe);$oldPath"
            $result = Invoke-TestCmdProcess -WorkingDirectory $workDir -CommandLine 'install.cmd -NoPause'
        }
        finally {
            if ($null -eq $oldForce) { Remove-Item Env:\DOTFILES_FORCE_WINDOWS_POWERSHELL -ErrorAction SilentlyContinue }
            else { $env:DOTFILES_FORCE_WINDOWS_POWERSHELL = $oldForce }
            if ($null -eq $oldDotfilesPs7Dir) { Remove-Item Env:\DOTFILES_PS7_DIR -ErrorAction SilentlyContinue }
            else { $env:DOTFILES_PS7_DIR = $oldDotfilesPs7Dir }
            $env:PATH = $oldPath
        }

        $result.ExitCode | Should -Be 0
        $selection = Get-Content -LiteralPath (Join-Path $workDir 'scripts\powershell\selection.txt') -Raw
        $selection | Should -Match 'PS_MAJOR=7'
    }

    It 'should reject an invalid DOTFILES_FORCE_WINDOWS_POWERSHELL value before launching PowerShell' {
        if (-not $script:runsOnWindows) {
            Set-ItResult -Skipped -Because 'install.cmd is a Windows entrypoint'
            return
        }

        $workDir = New-InstallCmdSelectionFixture -Name 'install-cmd-invalid-force-windows-powershell'
        $oldForce = $env:DOTFILES_FORCE_WINDOWS_POWERSHELL
        try {
            $env:DOTFILES_FORCE_WINDOWS_POWERSHELL = 'true'
            $result = Invoke-TestCmdProcess -WorkingDirectory $workDir -CommandLine 'install.cmd -NoPause'
        }
        finally {
            if ($null -eq $oldForce) { Remove-Item Env:\DOTFILES_FORCE_WINDOWS_POWERSHELL -ErrorAction SilentlyContinue }
            else { $env:DOTFILES_FORCE_WINDOWS_POWERSHELL = $oldForce }
        }

        $result.ExitCode | Should -Be 2 -Because "stdout=[$($result.Stdout)] stderr=[$($result.Stderr)]"
        $outputText = @($result.Stdout, $result.Stderr) -join [Environment]::NewLine
        $outputText | Should -Match 'DOTFILES_FORCE_WINDOWS_POWERSHELL'
        Test-Path -LiteralPath (Join-Path $workDir 'scripts\powershell\selection.txt') | Should -BeFalse
    }

    It 'should drive the real install.ps1 orchestrator through Phase 2a and final completion' {
        if (-not $script:runsOnWindows) {
            Set-ItResult -Skipped -Because "install.cmd is a Windows entrypoint"
            return
        }

        $fixture = New-PhaseIntegrationFixture -Name 'install-phase-integration'
        $result = Invoke-TestPowerShellProcess `
            -WorkingDirectory $fixture.WorkDirectory `
            -ScriptPath $fixture.InstallScript

        $result.ExitCode | Should -Be 0 -Because "stdout=[$($result.Stdout)] stderr=[$($result.Stderr)]"
        $result.Stdout | Should -Match "Phase 1: User Scope Setup"
        $result.Stdout | Should -Match "Phase 2a: Non-Admin Setup"
        $result.Stdout | Should -Match "FIXTURE_PHASE1_APPLIED"
        $result.Stdout | Should -Match "FIXTURE_PHASE2A_APPLIED"
        $result.Stdout | Should -Match "FIXTURE_ACCEPTANCE_COMPLETE"
        $result.Stdout | Should -Not -Match "Cannot convert.*SetupContext"
        $result.Stdout | Should -Match "Setup Complete!"

        $markers = Get-Content -LiteralPath $fixture.MarkerFile
        $markers | Should -Contain 'PHASE1_APPLIED'
        $markers | Should -Contain 'PHASE2A_APPLIED'
    }
}
