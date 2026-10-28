#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $taskCommand = Get-Command task -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $taskCommand) { throw "Required test dependency 'task' is not installed or not on PATH. Prepare Task before running this suite." }
    $script:taskRuntime = $taskCommand.Source

    function Invoke-FixtureProcess {
        param([Diagnostics.ProcessStartInfo]$StartInfo, [int]$TimeoutMilliseconds = 60000)
        $StartInfo.UseShellExecute = $false
        $StartInfo.CreateNoWindow = $true
        $StartInfo.RedirectStandardOutput = $true
        $StartInfo.RedirectStandardError = $true
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $StartInfo
        try {
            [void]$process.Start()
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit($TimeoutMilliseconds)) {
                if (Get-Command taskkill.exe -ErrorAction SilentlyContinue) {
                    & taskkill.exe /PID $process.Id /T /F | Out-Null
                }
                else { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
                [void]$process.WaitForExit(5000)
                throw "Installer fixture timed out: $($StartInfo.FileName)"
            }
            return [pscustomobject]@{ ExitCode = $process.ExitCode; Stdout = $stdout.Result; Stderr = $stderr.Result }
        }
        finally { $process.Dispose() }
    }
}

Describe 'Windows installer entrypoint' {
    BeforeAll {
        $script:runsOnWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT

        function Invoke-TestCmdProcess {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$WorkingDirectory,

                [Parameter(Mandatory)]
                [string]$CommandLine
            )

            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName = "cmd.exe"
            $psi.Arguments = "/d /c $CommandLine"
            $psi.WorkingDirectory = $WorkingDirectory
            Invoke-FixtureProcess -StartInfo $psi
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

    Context 'install.cmd entrypoint' {


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
    [string]$Phase,
    [string]$DistroName,
    [string]$Sentinel = ""
)

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$marker = Join-Path $repoRoot "install-marker.txt"
$message = "STUB_INSTALL_COMPLETE Phase=$Phase DistroName=$DistroName Sentinel=$Sentinel"
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
                -CommandLine "install.cmd -Phase Winget -DistroName WorkNix -Sentinel ok"

            $result.ExitCode | Should -Be 0
            $marker = Get-Content -LiteralPath (Join-Path $workDir "install-marker.txt") -Raw
            $marker | Should -Match "STUB_INSTALL_COMPLETE"
            $marker | Should -Match "Phase=Winget"
            $marker | Should -Match "DistroName=WorkNix"
            $marker | Should -Match "Sentinel=ok"
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

                $result = Invoke-TestCmdProcess -WorkingDirectory $workDir -CommandLine "install.cmd"
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

            Set-Content -LiteralPath (Join-Path $scriptDir "install.ps1") -Value @'
[CmdletBinding()]
param([string]$Phase)
if ($PSVersionTable.PSVersion.Major -ne 5) { throw 'Expected Windows PowerShell 5.1' }
if ($Phase -ne 'Winget') { throw 'Installer arguments were not forwarded' }
Write-Host 'STUB_WINGET_COMPLETE'
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
                    -CommandLine "install.cmd -Phase Winget"
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
            $outputText | Should -Match "STUB_WINGET_COMPLETE"
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
                $result = Invoke-TestCmdProcess -WorkingDirectory $workDir -CommandLine 'install.cmd'
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
                $result = Invoke-TestCmdProcess -WorkingDirectory $workDir -CommandLine 'install.cmd'
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
                $result = Invoke-TestCmdProcess -WorkingDirectory $workDir -CommandLine 'install.cmd'
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

    }
}

Describe 'Windows installer Task visibility' {
    BeforeAll {
        $script:taskRoot = Join-Path $TestDrive 'private install tasks'
        New-Item -ItemType Directory -Path "$script:taskRoot/taskfiles/install", "$script:taskRoot/scripts/powershell" -Force | Out-Null
        Copy-Item "$script:repoRoot/taskfiles/install/taskfile.yml" "$script:taskRoot/taskfiles/install"
        Set-Content "$script:taskRoot/Taskfile.yml" @'
version: '3'
includes:
  install:
    taskfile: ./taskfiles/install/taskfile.yml
    flatten: true
'@
        # Even if a helper becomes public, this fixture cannot install anything.
        Set-Content "$script:taskRoot/scripts/powershell/install.ps1" "throw 'Private install adapter must never run directly'"
    }

    Context 'Windows installer Task visibility' -Skip:($env:OS -ne 'Windows_NT') {
        It 'should expose the install entry and hide every installation helper even from list-all' {
            $output = @(& $script:taskRuntime --dir $script:taskRoot --list-all --json 2>&1) -join "`n"
            $LASTEXITCODE | Should -Be 0 -Because $output
            $names = ($output | ConvertFrom-Json).tasks.name
            $names | Should -Contain 'install'
            $names | Where-Object { $_ -like 'install:*' } | Should -BeNullOrEmpty
        }

        It 'should reject direct invocation of the private <TaskName> task' -ForEach @(
            @{ TaskName = 'install:start' },
            @{ TaskName = 'install:apply' },
            @{ TaskName = 'install:wsl' },
            @{ TaskName = 'install:chezmoi' }
        ) {
            $previousPreference = $ErrorActionPreference
            try {
                # Windows PowerShell 5.1 turns native stderr into ErrorRecords.
                # Capture this expected rejection, then assert its exit code below.
                $ErrorActionPreference = 'Continue'
                $output = @(& $script:taskRuntime --dir $script:taskRoot $TaskName 2>&1) -join "`n"
            }
            finally { $ErrorActionPreference = $previousPreference }
            $LASTEXITCODE | Should -Not -Be 0
            $output | Should -Match 'internal'
            $output | Should -Not -Match 'Private install adapter must never run directly'
        }
    }
}

Describe 'Windows installer phases' {
    BeforeAll {
        function Invoke-WindowsPhaseFixture {
            param([bool]$Success = $true, [string]$Phase = 'Winget')

            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $adapter = Join-Path $root 'scripts/powershell'
            $library = Join-Path $adapter 'lib'
            New-Item -ItemType Directory -Path $library -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:repoRoot 'install.cmd') -Destination $root
            Copy-Item -LiteralPath (Join-Path $script:repoRoot 'scripts/powershell/install.ps1') -Destination $adapter
            Copy-Item -LiteralPath (Join-Path $script:repoRoot 'scripts/powershell/lib/Invoke-ExternalCommand.ps1') -Destination $library
            New-Item -ItemType Directory -Path "$root/windows/winget" -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:repoRoot 'windows/winget/packages.json') -Destination "$root/windows/winget/packages.json"
            New-Item -ItemType Directory -Path "$root/chezmoi", "$root/home" -Force | Out-Null
            Set-Content -LiteralPath "$root/chezmoi/dot_fixture" -Value 'managed fixture'
            $fixture = @'
function Invoke-ExternalCommandWithTimeout {
    param($Command, $Arguments, $TimeoutSeconds)
    if ($Arguments[0] -ne 'import') { throw 'Only native import is allowed' }
    $global:LASTEXITCODE = if (__SUCCESS__) { 0 } else { 1 }
    if (__SUCCESS__) { return 'GUI_FIXTURE_APPLIED' }
    return 'GUI_FIXTURE_FAILED'
}
function chezmoi {
    $Arguments = @($args)
    if ($Arguments -notcontains 'init' -or $Arguments -notcontains '--apply' -or $Arguments -notcontains '--force' -or $Arguments -notcontains '--no-tty') {
        throw 'Expected a single non-interactive chezmoi init --apply command'
    }
    Write-Host 'CHEZMOI_FIXTURE_CALL'
    $global:LASTEXITCODE = if (__SUCCESS__) { 0 } else { 7 }
    if (__SUCCESS__) {
        $command = Get-Command chezmoi -CommandType Application -ErrorAction Stop | Select-Object -First 1
        Invoke-NativeCommand -Command $command.Source -Arguments (@('--config', "$env:FIXTURE_ROOT/chezmoi.toml", '--destination', "$env:FIXTURE_ROOT/home") + $Arguments)
        if ($LASTEXITCODE -eq 0) { return 'CHEZMOI_FIXTURE_APPLIED' }
        return
    }
    return 'CHEZMOI_FIXTURE_FAILED'
}
'@
            $fixture = $fixture.Replace('__SUCCESS__', ('$' + $Success.ToString().ToLowerInvariant()))
            Add-Content -LiteralPath (Join-Path $library 'Invoke-ExternalCommand.ps1') -Value $fixture -Encoding UTF8
            $info = New-Object System.Diagnostics.ProcessStartInfo
            $info.FileName = 'cmd.exe'
            $info.Arguments = "/d /c install.cmd -Phase $Phase"
            $info.WorkingDirectory = $root
            $info.EnvironmentVariables['FIXTURE_ROOT'] = $root
            $info.EnvironmentVariables['LOCALAPPDATA'] = Join-Path $root 'localappdata'
            if ($PSVersionTable.PSVersion.Major -lt 6) {
                $info.EnvironmentVariables['DOTFILES_FORCE_WINDOWS_POWERSHELL'] = '1'
            }
            $capture = Invoke-FixtureProcess -StartInfo $info -TimeoutMilliseconds 30000
            [pscustomobject]@{ ExitCode = $capture.ExitCode; Output = $capture.Stdout + $capture.Stderr; Applied = (Test-Path -LiteralPath "$root/home/.fixture") }
        }
    }

    Context 'Windows configuration phase' {
        It 'should apply Windows settings once through native chezmoi init --apply' {
            $result = Invoke-WindowsPhaseFixture -Phase Chezmoi
            $result.ExitCode | Should -Be 0 -Because $result.Output
            ([regex]::Matches($result.Output, 'CHEZMOI_FIXTURE_CALL')).Count | Should -Be 1
            $result.Output | Should -Match 'CHEZMOI_FIXTURE_APPLIED'
            $result.Applied | Should -BeTrue
            $result.Output | Should -Not -Match 'GUI_FIXTURE|Setup Complete|Press Enter'
        }

        It 'should stop when native chezmoi fails' {
            $result = Invoke-WindowsPhaseFixture -Phase Chezmoi -Success $false
            $result.ExitCode | Should -Not -Be 0
            ([regex]::Matches($result.Output, 'CHEZMOI_FIXTURE_CALL')).Count | Should -Be 1
            $result.Output | Should -Match 'CHEZMOI_FIXTURE_FAILED'
            $result.Output | Should -Not -Match 'CHEZMOI_FIXTURE_APPLIED|Setup Complete'
        }
    }

    Context 'Windows package import execution' {
        It 'should import the master without loading WSL, admin or chezmoi code' {
            $result = Invoke-WindowsPhaseFixture
            $result.ExitCode | Should -Be 0 -Because $result.Output
            $result.Output | Should -Match 'GUI_FIXTURE_APPLIED'
            $result.Output | Should -Match 'WINGET_IMPORT_COMPLETED'
            $result.Output | Should -Not -Match 'CHEZMOI_FIXTURE|Setup Complete|Press Enter'
        }

        It 'should propagate a GUI installer failure to install.cmd' {
            $result = Invoke-WindowsPhaseFixture -Success $false
            $result.ExitCode | Should -Not -Be 0
            $result.Output | Should -Match 'GUI_FIXTURE_FAILED'
            $result.Output | Should -Not -Match 'Setup Complete!'
        }



    }
}

Describe 'Windows installer WSL integration' {
    BeforeAll {
        . "$script:repoRoot/scripts/powershell/lib/Invoke-ExternalCommand.ps1"
        $script:previousPath = $env:PATH
        $env:PATH = (Split-Path -Parent $script:taskRuntime) + ';' + $env:PATH
        function Invoke-WslInstallerFixture {
            param(
                [bool]$Existing = $true,
                [string]$Arguments = '',
                [bool]$SetupFailure = $false,
                [bool]$InstallFailure = $false,
                [bool]$GuiFailure = $false,
                [bool]$ChezmoiFailure = $false,
                [bool]$WslAvailable = $true,
                [switch]$TaskInitiallyMissing,
                [bool]$TaskAvailableAfterWinget = $true,
                [int]$ElevationExitCode = 3010,
                [string]$ElevationFault = '',
                [int]$InstallTimeoutSeconds = 3600,
                [string]$InstallDirectory = '',
                [switch]$DirectTask,
                [switch]$DirectWslPhase,
                [switch]$PassExitCode
            )
            $isWindowsPowerShell = $PSVersionTable.PSVersion.Major -lt 6
            $root = Join-Path $TestDrive ('wsl installer ' + [guid]::NewGuid().ToString('N'))
            $adapter = Join-Path $root 'scripts/powershell'
            $temporaryDirectory = Join-Path $root '日本語の一時フォルダー'
            New-Item -ItemType Directory -Path "$adapter/lib", "$root/taskfiles/install", $temporaryDirectory -Force | Out-Null
            if (-not $InstallDirectory) { $InstallDirectory = Join-Path $root 'NixOS' }
            Copy-Item "$script:repoRoot/install.cmd" $root
            Copy-Item -LiteralPath (Join-Path $script:repoRoot 'scripts/powershell/install.ps1') -Destination $adapter
            Copy-Item "$script:repoRoot/scripts/powershell/lib/*.ps1" "$adapter/lib"
            New-Item -ItemType Directory -Path "$root/chezmoi" -Force | Out-Null
            Copy-Item "$script:repoRoot/taskfiles/install/taskfile.yml" "$root/taskfiles/install"
            Set-Content "$root/Taskfile.yml" -Value @'
version: '3'
includes:
  install:
    taskfile: ./taskfiles/install/taskfile.yml
    flatten: true
'@
            # Keep the real registration operation and intercept OS/network/setup boundaries.
            Add-Content "$adapter/lib/Invoke-ExternalCommand.ps1" -Value @'
function Import-WindowsPackage {
    param($ManifestPath)
    Add-Content "$env:FIXTURE_ROOT/events.txt" 'gui'
    if ($env:FIXTURE_GUI_FAILURE -eq 'True') { throw 'FIXTURE_GUI_FAILURE' }
}
function Get-Command {
    [CmdletBinding()]
    param([string[]]$Name, [Management.Automation.CommandTypes]$CommandType = 'All')
    if ($Name -eq 'task' -and $env:FIXTURE_TASK_INITIALLY_MISSING -eq 'True') {
        $eventsPath = Join-Path $env:FIXTURE_ROOT 'events.txt'
        $masterApplied = (Test-Path $eventsPath) -and (@(Get-Content $eventsPath) -contains 'gui')
        $stage = if ($masterApplied) { 'after-master' } else { 'before-master' }
        Add-Content (Join-Path $env:FIXTURE_ROOT 'task-lookups.txt') $stage
        if ($masterApplied -and $env:FIXTURE_TASK_AFTER_WINGET -eq 'True') {
            return [pscustomobject]@{ Source = $env:FIXTURE_TASK_RUNTIME }
        }
        return $null
    }
    $cmdlet = $ExecutionContext.InvokeCommand.GetCommand('Get-Command', [Management.Automation.CommandTypes]::Cmdlet)
    & $cmdlet -Name $Name -CommandType $CommandType -ErrorAction SilentlyContinue
}
function Invoke-NativeCommand {
    param($Command, $Arguments)
    if ($Command -eq 'chezmoi') {
        if ($Arguments -notcontains 'init' -or $Arguments -notcontains '--apply') { throw 'Expected native chezmoi init --apply' }
        Add-Content "$env:FIXTURE_ROOT/events.txt" 'chezmoi'
        $global:LASTEXITCODE = 0
        if ($env:FIXTURE_CHEZMOI_FAILURE -eq 'True') { $global:LASTEXITCODE = 7; return 'FIXTURE_CHEZMOI_FAILURE' }
        return
    }
    if ($Arguments -notcontains 'INSTALL_STAGE=apply') { throw 'Task handoff must select only the remaining phases' }
    $handoffPath = Join-Path $env:FIXTURE_ROOT 'task-handoffs.txt'
    if (Test-Path $handoffPath) { throw 'Task handoff must happen only once' }
    Add-Content $handoffPath 'apply'
    & $Command @Arguments
}
function Test-WslAvailable { return $env:FIXTURE_WSL_AVAILABLE -eq 'True' }
function Invoke-Wsl {
    [CmdletBinding(PositionalBinding = $false)]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments)][string[]]$Arguments,
        [int]$TimeoutSeconds
    )
    $global:LASTEXITCODE = 0
    $root = $env:FIXTURE_ROOT
    if ($Arguments -contains '--list') {
        if ($env:FIXTURE_EXISTING -eq 'True' -or (Test-Path "$root/installed.txt")) {
            return @("N`0i`0x`0O`0S`0", 'WorkNix')
        }
    }
    elseif ($Arguments -contains '--install' -or $Arguments -contains '--import') {
        Add-Content "$root/events.txt" 'install'
        $Arguments | ConvertTo-Json | Set-Content "$root/install-arguments.json"
        if ($env:FIXTURE_INSTALL_FAILURE -eq 'True') { $global:LASTEXITCODE = 1 }
        else { Set-Content "$root/installed.txt" 'registered' }
    }
    elseif ($Arguments -contains '--version') { return 'WSL available' }
}
function Invoke-RestMethod {
    param($Uri, $Headers)
    Set-Content "$env:FIXTURE_ROOT/release-uri.txt" $Uri
    return @{ tag_name = 'fixture'; assets = @(@{ name = 'nixos.wsl'; browser_download_url = 'https://example.invalid/nixos.wsl' }) }
}
function Invoke-WebRequest {
    param($Uri, $OutFile)
    Set-Content $OutFile 'fixture'
}
function Start-Process {
    param($FilePath, $ArgumentList, $Verb, $WindowStyle, [switch]$PassThru)
    $systemDirectory = if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { 'Sysnative' } else { 'System32' }
    $expected = Join-Path (Join-Path $env:SystemRoot $systemDirectory) 'wsl.exe'
    if ($FilePath -ne $expected -or ($ArgumentList -join '|') -cne '--install|--no-distribution' -or
        $Verb -ne 'RunAs' -or $WindowStyle -ne 'Hidden' -or -not $PassThru) {
        throw 'Only the WSL foundation command may request elevation in this fixture'
    }
    Add-Content "$env:FIXTURE_ROOT/events.txt" 'elevate'
    if ($env:FIXTURE_ELEVATION_FAULT -eq 'cancel') { throw 'UAC_CANCELLED' }
    $process = [pscustomobject]@{ ExitCode = [int]$env:FIXTURE_ELEVATION_EXIT_CODE }
    $process | Add-Member ScriptMethod WaitForExit {
        param($Milliseconds)
        @{ Milliseconds = $Milliseconds } | ConvertTo-Json -Compress | Set-Content "$env:FIXTURE_ROOT/elevation-wait.json"
        return $env:FIXTURE_ELEVATION_FAULT -ne 'timeout'
    }
    $process | Add-Member ScriptMethod Dispose { Set-Content "$env:FIXTURE_ROOT/elevation-disposed.txt" 'disposed' }
    return $process
}
'@
            Add-Content "$adapter/lib/Invoke-NixosWslSetup.ps1" -Value @'
function Invoke-NixosWslSetup {
    param($Repository, $DistroName, $SyncMode, $SyncBack, [switch]$ForcePostInstall)
    Add-Content "$env:FIXTURE_ROOT/events.txt" 'setup'
    @{ Repository = $Repository; DistroName = $DistroName; SyncMode = $SyncMode; SyncBack = $SyncBack; ForcePostInstall = [bool]$ForcePostInstall } |
        ConvertTo-Json | Set-Content "$env:FIXTURE_ROOT/context.json"
    if ($env:FIXTURE_SETUP_FAILURE -eq 'True') { throw 'FIXTURE_SETUP_FAILURE' }
}
'@
            $info = New-Object System.Diagnostics.ProcessStartInfo
            $info.FileName = 'cmd.exe'
            $info.Arguments = "/d /c install.cmd -InstallDir `"$InstallDirectory`" $Arguments"
            if ($DirectTask -or $DirectWslPhase) {
                $shellPath = (Get-Process -Id $PID).Path.Replace('\', '/')
                if ($DirectTask) {
                    $info.FileName = $script:taskRuntime
                    $exitFlag = if ($PassExitCode) { ' --exit-code' } else { '' }
                    $info.Arguments = '--dir "' + $root + '"' + $exitFlag + ' install'
                }
                else {
                    $info.FileName = $shellPath
                    $info.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + "$adapter/install.ps1" + '" -Phase Wsl ' + $Arguments
                }
                $info.EnvironmentVariables.Remove('DOTFILES_INSTALL_CONFIGURATION')
                if (-not $Existing) {
                    # Keep the missing-distro fixture away from any real host VHD.
                    $info.EnvironmentVariables['DOTFILES_INSTALL_CONFIGURATION'] = @{
                        DistroName = 'NixOS'; InstallDir = $InstallDirectory
                    } | ConvertTo-Json -Depth 5 -Compress
                }
                $info.EnvironmentVariables['DOTFILES_INSTALL_POWERSHELL'] = $shellPath
            }
            $info.WorkingDirectory = $root
            $info.EnvironmentVariables['FIXTURE_ROOT'] = $root
            $info.EnvironmentVariables['FIXTURE_TASK_INITIALLY_MISSING'] = [string]$TaskInitiallyMissing
            $info.EnvironmentVariables['FIXTURE_TASK_AFTER_WINGET'] = [string]$TaskAvailableAfterWinget
            $info.EnvironmentVariables['FIXTURE_TASK_RUNTIME'] = $script:taskRuntime
            $info.EnvironmentVariables['FIXTURE_EXISTING'] = [string]$Existing
            $info.EnvironmentVariables['FIXTURE_SETUP_FAILURE'] = [string]$SetupFailure
            $info.EnvironmentVariables['FIXTURE_INSTALL_FAILURE'] = [string]$InstallFailure
            $info.EnvironmentVariables['FIXTURE_GUI_FAILURE'] = [string]$GuiFailure
            $info.EnvironmentVariables['FIXTURE_CHEZMOI_FAILURE'] = [string]$ChezmoiFailure
            $info.EnvironmentVariables['FIXTURE_WSL_AVAILABLE'] = [string]$WslAvailable
            $info.EnvironmentVariables['FIXTURE_ELEVATION_EXIT_CODE'] = [string]$ElevationExitCode
            $info.EnvironmentVariables['FIXTURE_ELEVATION_FAULT'] = $ElevationFault
            $info.EnvironmentVariables['DOTFILES_INSTALL_TIMEOUT_SECONDS'] = [string]$InstallTimeoutSeconds
            $info.EnvironmentVariables['LOCALAPPDATA'] = Join-Path $root 'localappdata'
            $info.EnvironmentVariables['TEMP'] = $temporaryDirectory
            $info.EnvironmentVariables['TMP'] = $temporaryDirectory
            if ($isWindowsPowerShell) { $info.EnvironmentVariables['DOTFILES_FORCE_WINDOWS_POWERSHELL'] = '1' }
            else {
                $info.EnvironmentVariables.Remove('DOTFILES_FORCE_WINDOWS_POWERSHELL')
                $info.EnvironmentVariables['DOTFILES_PS7_DIR'] = $PSHOME
            }
            $capture = Invoke-FixtureProcess -StartInfo $info
            $events = if (Test-Path "$root/events.txt") { @(Get-Content "$root/events.txt") } else { @() }
            $context = if (Test-Path "$root/context.json") { Get-Content "$root/context.json" -Raw | ConvertFrom-Json } else { $null }
            $taskLookups = if (Test-Path "$root/task-lookups.txt") { @(Get-Content "$root/task-lookups.txt") } else { @() }
            return [pscustomobject]@{
                ExitCode = $capture.ExitCode; Output = $capture.Stdout + $capture.Stderr; Events = $events; Context = $context
                InstallArguments = if (Test-Path "$root/install-arguments.json") { Get-Content "$root/install-arguments.json" -Raw | ConvertFrom-Json } else { @() }
                ReleaseUri = if (Test-Path "$root/release-uri.txt") { Get-Content "$root/release-uri.txt" -Raw } else { '' }
                TaskLookups = $taskLookups
                ElevationDisposed = Test-Path "$root/elevation-disposed.txt"
                ElevationWaitMilliseconds = if (Test-Path "$root/elevation-wait.json") { (Get-Content "$root/elevation-wait.json" -Raw | ConvertFrom-Json).Milliseconds } else { $null }
            }
        }
    }

    AfterAll { $env:PATH = $script:previousPath }

    Context 'Windows installer WSL integration' -Skip:($env:OS -ne 'Windows_NT') {
        It 'should apply the master before discovering Task and run each phase once under the parent runtime' {
            $result = Invoke-WslInstallerFixture -TaskInitiallyMissing
            $result.ExitCode | Should -Be 0 -Because $result.Output
            ($result.Events -join ',') | Should -Be 'gui,setup,chezmoi'
            @($result.TaskLookups) | Should -Be @('after-master')
            ([regex]::Matches($result.Output, 'Setup Complete!')).Count | Should -Be 1
            ($result.Output -match 'Using Windows PowerShell') | Should -Be ($PSVersionTable.PSVersion.Major -lt 6)
        }

        It 'should stop after the master if Task is still unavailable' {
            $result = Invoke-WslInstallerFixture -TaskInitiallyMissing -TaskAvailableAfterWinget $false
            $result.ExitCode | Should -Not -Be 0
            ($result.Events -join ',') | Should -Be 'gui'
            @($result.TaskLookups) | Should -Be @('after-master')
            $result.Output | Should -Not -Match 'Setup Complete!'
        }

        It 'should stop on master failure before looking for Task' {
            $result = Invoke-WslInstallerFixture -TaskInitiallyMissing -GuiFailure $true
            $result.ExitCode | Should -Not -Be 0
            ($result.Events -join ',') | Should -Be 'gui'
            @($result.TaskLookups).Count | Should -Be 0
            $result.Output | Should -Match 'FIXTURE_GUI_FAILURE'
        }

        It 'should run task install directly without re-entering bootstrap or applying WSL twice' -ForEach @(
            @{ Existing = $true; Expected = 'gui,setup,chezmoi' },
            @{ Existing = $false; Expected = 'gui,install,setup,chezmoi' }
        ) {
            $result = Invoke-WslInstallerFixture -DirectTask -Existing $Existing
            $result.ExitCode | Should -Be 0 -Because $result.Output
            ($result.Events -join ',') | Should -Be $Expected
            ([regex]::Matches($result.Output, 'Setup Complete!')).Count | Should -Be 1
        }

        It 'should stop direct task install on reboot with the selected native exit mode' -ForEach @(
            @{ PassExitCode = $false; ExpectedExitCode = 201 },
            @{ PassExitCode = $true; ExpectedExitCode = 194 }
        ) {
            $result = Invoke-WslInstallerFixture -DirectTask -WslAvailable $false -PassExitCode:$PassExitCode
            $result.ExitCode | Should -Be $ExpectedExitCode -Because $result.Output
            ($result.Events -join ',') | Should -Be 'gui,elevate'
            $result.Output | Should -Match 'restart|再起動'
            $result.Output | Should -Not -Match 'Setup Complete!'
        }

        It 'should return native reboot code 3010 from WSL foundation exit <ElevationExitCode>' -ForEach @(
            @{ ElevationExitCode = 0 }, @{ ElevationExitCode = 1641 }
        ) {
            $result = Invoke-WslInstallerFixture -DirectWslPhase -WslAvailable $false -ElevationExitCode $ElevationExitCode
            $result.ExitCode | Should -Be 3010 -Because $result.Output
            ($result.Events -join ',') | Should -Be 'elevate'
            $result.Output | Should -Match 'restart|再起動'
            $result.Output | Should -Not -Match 'Setup Complete!'
            $result.ElevationDisposed | Should -BeTrue
            $result.ElevationWaitMilliseconds | Should -Be 3600000
        }

        It 'should execute the WSL phase directly and forward explicit options without bootstrapping Task' {
            $result = Invoke-WslInstallerFixture -DirectWslPhase -Arguments '-DistroName WorkNix -SyncMode none -SyncBack none -ForcePostInstall'
            $result.ExitCode | Should -Be 0 -Because $result.Output
            ($result.Events -join ',') | Should -Be 'setup'
            $result.Context.DistroName | Should -Be 'WorkNix'
            $result.Context.SyncMode | Should -Be 'none'
            $result.Context.SyncBack | Should -Be 'none'
            $result.Context.ForcePostInstall | Should -BeTrue
            $result.Output | Should -Not -Match 'Press Enter|Setup Complete'
        }

        It 'should stop direct task install on a failed phase' -ForEach @(
            @{ GuiFailure = $true; SetupFailure = $false; ChezmoiFailure = $false; Expected = 'gui'; ErrorText = 'FIXTURE_GUI_FAILURE' },
            @{ GuiFailure = $false; SetupFailure = $true; ChezmoiFailure = $false; Expected = 'gui,setup'; ErrorText = 'FIXTURE_SETUP_FAILURE' },
            @{ GuiFailure = $false; SetupFailure = $false; ChezmoiFailure = $true; Expected = 'gui,setup,chezmoi'; ErrorText = 'FIXTURE_CHEZMOI_FAILURE' }
        ) {
            $result = Invoke-WslInstallerFixture -DirectTask -GuiFailure $GuiFailure -SetupFailure $SetupFailure -ChezmoiFailure $ChezmoiFailure
            $result.ExitCode | Should -Not -Be 0
            ($result.Events -join ',') | Should -Be $Expected
            $result.Output | Should -Match $ErrorText
            $result.Output | Should -Not -Match 'Setup Complete!'
        }

        It 'should apply existing NixOS once after GUI setup without reinstalling' {
            $result = Invoke-WslInstallerFixture
            $result.ExitCode | Should -Be 0 -Because $result.Output
            ($result.Events -join ',') | Should -Be 'gui,setup,chezmoi'
            $result.Output | Should -Match 'Setup Complete!'
        }

        It 'should install a missing distro and apply its configuration only once' {
            $result = Invoke-WslInstallerFixture -Existing $false
            $result.ExitCode | Should -Be 0 -Because $result.Output
            ($result.Events -join ',') | Should -Be 'gui,install,setup,chezmoi'
        }

        It 'should forward synchronization and force options' {
            $result = Invoke-WslInstallerFixture -Arguments '-SyncMode none -SyncBack none -ForcePostInstall'
            $result.ExitCode | Should -Be 0 -Because $result.Output
            $result.Context.SyncMode | Should -Be 'none'
            $result.Context.SyncBack | Should -Be 'none'
            $result.Context.ForcePostInstall | Should -BeTrue
        }

        # Windows PowerShell 5.1 -File treats this switch value as a string and cannot bind explicit false.
        It 'should preserve an explicitly disabled force option across processes' -Skip:($PSVersionTable.PSVersion.Major -lt 6) {
            $result = Invoke-WslInstallerFixture -Arguments '-ForcePostInstall:$false'
            $result.ExitCode | Should -Be 0 -Because $result.Output
            $result.Context.ForcePostInstall | Should -BeFalse
        }

        It 'should forward the selected distro and installation location' {
            $customLocation = Join-Path $TestDrive 'Custom WSL location'
            $result = Invoke-WslInstallerFixture -Existing $false -InstallDirectory $customLocation -Arguments '-DistroName WorkNix -ReleaseTag fixture'
            $result.ExitCode | Should -Be 0 -Because $result.Output
            $result.Context.DistroName | Should -Be 'WorkNix'
            $result.InstallArguments | Should -Contain $customLocation
            $result.ReleaseUri | Should -Match '/tags/fixture'
            ($result.Events -join ',') | Should -Be 'gui,install,setup,chezmoi'
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
            $result.Output | Should -Not -Match 'Windows setup failed|CategoryInfo|FullyQualifiedErrorId'
            $result.Output | Should -Not -Match 'Setup Complete!'
        }

        It 'should handle restart instructions when the WSL foundation timeout is disabled' {
            $result = Invoke-WslInstallerFixture -WslAvailable $false -InstallTimeoutSeconds 0
            $result.ExitCode | Should -Be 3010 -Because $result.Output
            ($result.Events -join ',') | Should -Be 'gui,elevate'
            $result.Output | Should -Match 'restart|再起動'
            $result.Output | Should -Not -Match 'Windows setup failed|CategoryInfo|Setup Complete!'
            $result.ElevationDisposed | Should -BeTrue
            $result.ElevationWaitMilliseconds | Should -BeNullOrEmpty
        }

        It 'should stop on WSL foundation <Failure> before registration or configuration' -ForEach @(
            @{ Failure = 'native failure'; ElevationExitCode = 5; ElevationFault = ''; ErrorText = 'WSL installation failed \(exit=5\)'; Disposed = $true }
            @{ Failure = 'UAC cancellation'; ElevationExitCode = 0; ElevationFault = 'cancel'; ErrorText = 'UAC_CANCELLED'; Disposed = $false }
            @{ Failure = 'timeout'; ElevationExitCode = 0; ElevationFault = 'timeout'; ErrorText = 'Timed out waiting for WSL installation'; Disposed = $true }
        ) {
            $result = Invoke-WslInstallerFixture -WslAvailable $false -ElevationExitCode $ElevationExitCode -ElevationFault $ElevationFault -InstallTimeoutSeconds 1
            $result.ExitCode | Should -Not -Be 0
            ($result.Events -join ',') | Should -Be 'gui,elevate'
            $result.Output | Should -Match $ErrorText
            $result.Output | Should -Not -Match 'Setup Complete!'
            $result.ElevationDisposed | Should -Be $Disposed
            if ($Disposed) { $result.ElevationWaitMilliseconds | Should -Be 1000 }
        }

    }
}

Describe 'Windows CI installer boundary' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    BeforeAll {
        . "$script:repoRoot/scripts/powershell/lib/Invoke-ExternalCommand.ps1"
        $workflow = [IO.File]::ReadAllText((Join-Path $script:repoRoot '.github/workflows/ci-nix.yml'))
        $step = [regex]::Match($workflow, '(?ms)^      - name: Run install\.cmd strict user phase\r?\n(?:(?!^      - name:).)*?^        run: \|\r?\n(?<body>(?:^          [^\r\n]*(?:\r?\n|$)|^\r?\n)+)')
        if (-not $step.Success) { throw 'Windows CI installer step was not found.' }
        $script:ciInstallerBody = $step.Groups['body'].Value -replace '(?m)^ {10}', ''

        function Invoke-CiInstallerFixture {
            param([string]$Outcome = 'complete', [switch]$DuplicateRuntime)
            $runtime = if ($PSVersionTable.PSVersion.Major -lt 6) { '5.1' } else { '7' }
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $library = Join-Path $root 'scripts/powershell/lib'
            [void][IO.Directory]::CreateDirectory($library)
            [void][IO.Directory]::CreateDirectory((Join-Path $root 'windows/winget'))
            $master = Get-Content -LiteralPath (Join-Path $script:repoRoot 'windows/winget/packages.json') -Raw | ConvertFrom-Json
            $package = @($master.Sources.Packages | Where-Object PackageIdentifier -EQ 'Microsoft.PowerShell')[0]
            $package | Add-Member -NotePropertyName Scope -NotePropertyValue machine -Force
            $package | Add-Member -NotePropertyName Version -NotePropertyValue '7.5.0' -Force
            if ($DuplicateRuntime) { $master.Sources[0].Packages += $package }
            $masterPath = Join-Path $root 'windows/winget/packages.json'
            [IO.File]::WriteAllText($masterPath, ($master | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
            $originalMaster = [IO.File]::ReadAllText($masterPath)
            [IO.File]::WriteAllText((Join-Path $library 'Invoke-ExternalCommand.ps1'), @'
function Import-WindowsPackage {
    param([string]$ManifestPath)
    Copy-Item -LiteralPath $ManifestPath -Destination (Join-Path $env:FIXTURE_ROOT 'runtime-import.json')
    Set-Content -LiteralPath (Join-Path $env:FIXTURE_ROOT 'temporary-manifest.txt') -Value $ManifestPath
    if ($env:FIXTURE_OUTCOME -eq 'runtime-failure') { throw 'Runtime import failed (exit=7).' }
}
function Invoke-NativeCommand {
    param([string]$Command, [string[]]$Arguments)
    if ([IO.Path]::GetFileName($Command) -eq 'pwsh.exe') {
        if (-not (Test-Path -LiteralPath (Join-Path $env:FIXTURE_ROOT 'runtime-import.json'))) { throw 'Runtime probe ran before preparation.' }
        Set-Content -LiteralPath (Join-Path $env:FIXTURE_ROOT 'runtime-probed.txt') -Value ($Command + ' ' + ($Arguments -join ' '))
        $global:LASTEXITCODE = if ($env:FIXTURE_OUTCOME -eq 'probe-failure') { 9 } else { 0 }
        if ($env:FIXTURE_OUTCOME -eq 'wrong-major') { '8' } else { '7' }
        return
    }
    if (-not (Test-Path -LiteralPath (Join-Path $env:FIXTURE_ROOT 'runtime-probed.txt'))) { throw 'Installer ran before the runtime probe.' }
    Set-Content -LiteralPath (Join-Path $env:FIXTURE_ROOT 'installer-invoked.txt') -Value ($Command + ' ' + ($Arguments -join ' '))
    $global:LASTEXITCODE = if ($env:FIXTURE_OUTCOME -eq 'nonzero') { 7 } else { 0 }
    if ($env:DOTFILES_FORCE_WINDOWS_POWERSHELL -eq '1') { '[INFO] Using Windows PowerShell.' }
    if ($env:FIXTURE_OUTCOME -eq 'early-zero') { return }
    '[Winget] WINGET_IMPORT_COMPLETED'
    if ($env:FIXTURE_OUTCOME -eq 'duplicate-marker') { '[Winget] WINGET_IMPORT_COMPLETED' }
}
function Update-ProcessEnvironmentPath {}
'@, [Text.UTF8Encoding]::new($true))
            $path = Join-Path $root 'inline-ci.ps1'
            [IO.File]::WriteAllText($path, $script:ciInstallerBody, [Text.UTF8Encoding]::new($true))
            $originalEnvironment = @{}
            foreach ($name in @('FIXTURE_ROOT', 'FIXTURE_OUTCOME', 'GITHUB_WORKSPACE', 'GITHUB_PATH', 'DOTFILES_E2E_POWERSHELL_VERSION')) {
                $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
            }
            try {
                $env:FIXTURE_ROOT = $root
                $env:FIXTURE_OUTCOME = $Outcome
                $env:GITHUB_WORKSPACE = $root
                $env:GITHUB_PATH = Join-Path $root 'github-path.txt'
                $env:DOTFILES_E2E_POWERSHELL_VERSION = $Runtime
                $output = @(Invoke-ExternalCommandWithTimeout -Command 'powershell.exe' -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $path) -TimeoutSeconds 30)
                $exitCode = $LASTEXITCODE
            }
            finally {
                foreach ($name in $originalEnvironment.Keys) {
                    [Environment]::SetEnvironmentVariable($name, $originalEnvironment[$name], 'Process')
                }
            }
            return @{ Root = $root; ExitCode = $exitCode; Output = ($output -join "`n"); OriginalMaster = $originalMaster }
        }
    }

    It 'should prepare only the declared runtime then complete the real inline checks for the parent runtime' {
        $result = Invoke-CiInstallerFixture
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $runtime = Get-Content -LiteralPath (Join-Path $result.Root 'runtime-import.json') -Raw | ConvertFrom-Json
        @($runtime.Sources).Count | Should -Be 1
        @($runtime.Sources[0].Packages).Count | Should -Be 1
        $runtime.Sources[0].Packages[0].PackageIdentifier | Should -Be 'Microsoft.PowerShell'
        $runtime.Sources[0].Packages[0].Scope | Should -Be 'machine'
        $runtime.Sources[0].Packages[0].Version | Should -Be '7.5.0'
        $master = $result.OriginalMaster | ConvertFrom-Json
        ($runtime.Sources[0].SourceDetails | ConvertTo-Json -Compress) | Should -BeExactly ($master.Sources[0].SourceDetails | ConvertTo-Json -Compress)
        [IO.File]::ReadAllText((Join-Path $result.Root 'windows/winget/packages.json')) | Should -BeExactly $result.OriginalMaster
        Test-Path -LiteralPath (Get-Content -LiteralPath (Join-Path $result.Root 'temporary-manifest.txt') -Raw).Trim() | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $result.Root 'runtime-probed.txt') | Should -BeTrue
        Get-Content -LiteralPath (Join-Path $result.Root 'installer-invoked.txt') -Raw | Should -Match 'cmd\.exe /d /c install\.cmd -Phase Winget'
    }

    It 'should reject <Outcome> instead of claiming that the full import completed' -ForEach @(
        @{ Outcome = 'early-zero'; ExitCode = 1; Diagnostic = 'exactly one native WinGet import completion marker' },
        @{ Outcome = 'duplicate-marker'; ExitCode = 1; Diagnostic = 'exactly one native WinGet import completion marker' },
        @{ Outcome = 'nonzero'; ExitCode = 7; Diagnostic = 'WINGET_IMPORT_COMPLETED' }
    ) {
        $result = Invoke-CiInstallerFixture -Outcome $Outcome
        Test-Path -LiteralPath (Join-Path $result.Root 'installer-invoked.txt') | Should -BeTrue -Because $result.Output
        $result.ExitCode | Should -Be $ExitCode -Because $result.Output
        $result.Output | Should -Match $Diagnostic
    }

    It 'should reject <Outcome> before starting the full installer' -ForEach @(
        @{ Outcome = 'wrong-major' }, @{ Outcome = 'probe-failure' }
    ) {
        $result = Invoke-CiInstallerFixture -Outcome $Outcome
        $result.ExitCode | Should -Be 1 -Because $result.Output
        $result.Output | Should -Match 'Selected pwsh.exe must report PowerShell 7 with exit code 0'
        Test-Path -LiteralPath (Join-Path $result.Root 'runtime-probed.txt') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $result.Root 'installer-invoked.txt') | Should -BeFalse
        Test-Path -LiteralPath (Get-Content -LiteralPath (Join-Path $result.Root 'temporary-manifest.txt') -Raw).Trim() | Should -BeFalse
    }

    It 'should stop before the full installer when runtime preparation fails and remove its temporary manifest' {
        $result = Invoke-CiInstallerFixture -Outcome runtime-failure
        $result.ExitCode | Should -Be 1 -Because $result.Output
        $result.Output | Should -Match 'Runtime import failed \(exit=7\)'
        Test-Path -LiteralPath (Join-Path $result.Root 'runtime-probed.txt') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $result.Root 'installer-invoked.txt') | Should -BeFalse
        Test-Path -LiteralPath (Get-Content -LiteralPath (Join-Path $result.Root 'temporary-manifest.txt') -Raw).Trim() | Should -BeFalse
    }

    It 'should reject duplicate runtime ownership before importing any package' {
        $result = Invoke-CiInstallerFixture -DuplicateRuntime
        $result.ExitCode | Should -Be 1 -Because $result.Output
        $result.Output | Should -Match 'Expected exactly one Microsoft.PowerShell declaration from winget'
        Test-Path -LiteralPath (Join-Path $result.Root 'runtime-import.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $result.Root 'installer-invoked.txt') | Should -BeFalse
    }
}

Describe 'NixOS-WSL E2E cleanup boundary' {
    BeforeAll {
        $workflow = [IO.File]::ReadAllText((Join-Path $script:repoRoot '.github/workflows/ci-nix.yml'))
        $step = [regex]::Match($workflow, '(?ms)^      - name: Run isolated NixOS-WSL switch\r?\n(?:(?!^      - name:).)*?^        run: \|\r?\n(?<body>(?:^          [^\r\n]*(?:\r?\n|$)|^\r?\n)+)')
        if (-not $step.Success) { throw 'WSL CI step was not found.' }
        $tokens = $null
        $parseErrors = $null
        $ast = [Management.Automation.Language.Parser]::ParseInput(($step.Groups['body'].Value -replace '(?m)^ {10}', ''), [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count) { throw ($parseErrors -join "`n") }
        $guard = $ast.Find({ param($node)
                $node -is [Management.Automation.Language.IfStatementAst] -and $node.Extent.Text -match 'Refusing an unsafe CI distro name'
            }, $true)
        $script:e2eCleanupGuard = [scriptblock]::Create($guard.Extent.Text)
    }

    It 'should reject unsafe distro names and cleanup paths with the actual workflow guard' {
        $tempRoot = Join-Path $TestDrive 'temp-root'
        $validName = 'NixOS-CI-' + ('a' * 32)
        foreach ($case in @(
                @{ Name = $validName; Path = $tempRoot; Allowed = $false }
                @{ Name = $validName; Path = $tempRoot + [IO.Path]::DirectorySeparatorChar; Allowed = $false }
                @{ Name = $validName; Path = (Join-Path $tempRoot $validName); Allowed = $true }
                @{ Name = 'NixOS'; Path = (Join-Path $tempRoot 'NixOS'); Allowed = $false }
                @{ Name = $validName; Path = $tempRoot + '-sibling'; Allowed = $false }
                @{ Name = $validName; Path = (Join-Path $tempRoot '../sibling'); Allowed = $false }
                @{ Name = $validName; Path = (Join-Path $tempRoot 'child/..'); Allowed = $false }
            )) {
            $distroName = $case.Name
            $installDir = [IO.Path]::GetFullPath($case.Path).TrimEnd('\', '/')
            if ($case.Allowed) { { & $script:e2eCleanupGuard } | Should -Not -Throw }
            else { { & $script:e2eCleanupGuard } | Should -Throw '*Refusing an unsafe CI distro*' }
        }
    }
}
