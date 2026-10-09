BeforeDiscovery {
    $captureWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    $captureRuntimes = if ($captureWindows) { @('5.1', '7') } else { @('current') }
    $captureNormalCases = @(
        foreach ($childRuntime in $captureRuntimes) {
            foreach ($preference in @('Continue', 'Stop')) {
                foreach ($expectedExit in @(0, 7)) {
                    @{ ChildRuntime = $childRuntime; Preference = $preference; ExpectedExit = $expectedExit }
                }
            }
        }
    )
    $captureFailureCases = @(
        foreach ($childRuntime in $captureRuntimes) {
            foreach ($preference in @('Continue', 'Stop')) {
                @{ ChildRuntime = $childRuntime; Preference = $preference }
            }
        }
    )
}

BeforeAll {
    function Invoke-InstallerCaptureFixture {
        param([string]$Directory, [string]$ChildRuntime, [string]$Preference,
            [int]$ExpectedExit = 0, [ValidateSet('normal', 'unavailable', 'pipe')][string]$Sink = 'normal')

        $windowsFixture = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
        $parentRuntime = if ($windowsFixture) {
            (Get-Command powershell.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
        }
        else { (Get-Process -Id $PID).Path }
        $childRuntimePath = if ($windowsFixture) {
            $childCommand = if ($ChildRuntime -eq '5.1') { 'powershell.exe' } else { 'pwsh.exe' }
            (Get-Command $childCommand -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
        }
        else { $parentRuntime }
        $expectedRuntime = if ($ChildRuntime -eq '5.1') { '5.1' } else { '7' }
        # A wildcard-bearing directory must still capture to the exact log file.
        $caseRoot = Join-Path $Directory ('capture [GUI] ' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $caseRoot | Out-Null
        $tokens = $null
        $parseErrors = $null
        $repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
        $ast = [Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $repositoryRoot 'scripts/powershell/ci/Invoke-WindowsInstallerE2E.ps1'),
            [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count) { throw ($parseErrors -join "`n") }
        $boundary = @($ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.TryStatementAst] })
        if ($boundary.Count -ne 1) { throw 'Expected one shipped outer capture boundary' }
        $scriptPathAssignment = $ast.EndBlock.Statements | Where-Object {
            $_ -is [Management.Automation.Language.AssignmentStatementAst] -and
            $_.Left.VariablePath.UserPath -eq 'installerE2EScriptPath'
        }
        $logPathAssignment = $ast.EndBlock.Statements | Where-Object {
            $_ -is [Management.Automation.Language.AssignmentStatementAst] -and
            $_.Left.VariablePath.UserPath -eq 'installerE2ELogPath'
        }
        $preferenceAssignment = $ast.EndBlock.Statements | Where-Object {
            $_ -is [Management.Automation.Language.AssignmentStatementAst] -and
            $_.Left.VariablePath.UserPath -eq 'previousErrorActionPreference'
        }
        $finalExit = $ast.EndBlock.Statements[-1]
        if ($finalExit -isnot [Management.Automation.Language.IfStatementAst]) { throw 'Expected the shipped final native-exit branch' }

        # Insert only passive observations in the real finally: no extra parent
        # StrictMode, exit initialization, error conversion, or capture mock.
        $cleanup = $boundary[0].Finally.Find({ param($node)
                $node -is [Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Remove-Item'
            }, $true)
        $lifecycleObserver = @'
$fixturePidPath = Join-Path $CaseRoot 'child-pid.txt'
$fixtureChildAliveAtCleanup = $false
if (Test-Path -LiteralPath $fixturePidPath) {
    try {
        $fixtureProcess = [Diagnostics.Process]::GetProcessById([int][IO.File]::ReadAllText($fixturePidPath))
        $fixtureChildAliveAtCleanup = -not $fixtureProcess.HasExited
    }
    catch [ArgumentException] { $fixtureChildAliveAtCleanup = $false }
}
'@
        $stateObserver = @'
$fixtureState = [pscustomobject]@{
    parentVersion = [string]$PSVersionTable.PSVersion
    restoredPreference = [string]$ErrorActionPreference
    nativeExit = $installerE2EExitCode
    childAliveAtCleanup = $fixtureChildAliveAtCleanup
    childFileRemoved = -not (Test-Path -LiteralPath $installerE2EScriptPath)
}
[IO.File]::WriteAllText((Join-Path $CaseRoot 'parent-state.json'), ($fixtureState | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
'@
        $body = $boundary[0].Extent.Text
        $stateOffset = $boundary[0].Finally.Extent.EndOffset - $boundary[0].Extent.StartOffset - 1
        $body = $body.Insert($stateOffset, "`n" + $stateObserver + "`n")
        $cleanupOffset = $cleanup.Extent.StartOffset - $boundary[0].Extent.StartOffset
        $body = $body.Insert($cleanupOffset, $lifecycleObserver + "`n")

        $prefix = @'
param([string]$CaseRoot, [string]$runtimePath, [string]$expectedRuntime, [string]$Preference)
$ErrorActionPreference = $Preference
$env:RUNNER_TEMP = $CaseRoot
'@
        $child = @'
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$caseRoot = $env:DOTFILES_CAPTURE_FIXTURE_ROOT
[IO.File]::WriteAllText((Join-Path $caseRoot 'child-pid.txt'), [string]$PID)
Write-Host "FIXTURE_CHILD_MAJOR=$($PSVersionTable.PSVersion.Major)"
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
Write-Output 'MARK_STDOUT'
[Console]::Out.WriteLine('MARK_RAWOUT 日本語')
[Console]::Error.WriteLine('MARK_STDERR 日本語')
Write-Host 'MARK_HOST'
Start-Sleep -Milliseconds 1500
if ($env:DOTFILES_CAPTURE_FIXTURE_SINK -eq 'pipe') {
    1..256 | ForEach-Object { [Console]::Out.WriteLine(('MIDDLE_' + $_ + '_' + ('x' * 512))) }
    Start-Sleep -Milliseconds 1500
}
[Console]::Out.WriteLine('MARK_TAIL')
[IO.File]::WriteAllText((Join-Path $caseRoot 'child-finished.txt'), 'finished')
exit [int]$env:DOTFILES_CAPTURE_FIXTURE_EXIT
'@
        $fixtureBody = Join-Path $caseRoot 'fixture-body.txt'
        [IO.File]::WriteAllText($fixtureBody, $child, [Text.Encoding]::Unicode)
        $writeChild = '[IO.File]::WriteAllText($installerE2EScriptPath, [IO.File]::ReadAllText((Join-Path $CaseRoot ''fixture-body.txt'')), [Text.Encoding]::Unicode)'
        $parentPath = Join-Path $caseRoot 'fixture-parent.ps1'
        $parentSource = @($prefix, $scriptPathAssignment.Extent.Text,
            $(if ($logPathAssignment) { $logPathAssignment.Extent.Text }), $writeChild,
            $(if ($preferenceAssignment) { $preferenceAssignment.Extent.Text }), $body, $finalExit.Extent.Text) -join "`n"
        [IO.File]::WriteAllText($parentPath, $parentSource, [Text.UTF8Encoding]::new($true))
        $logPath = Join-Path $caseRoot "windows-installer-$expectedRuntime.log"
        $reader = $null
        if ($Sink -eq 'unavailable') { New-Item -ItemType Directory -Path $logPath | Out-Null }
        elseif ($Sink -eq 'pipe') {
            & mkfifo $logPath
            if ($LASTEXITCODE -ne 0) { throw 'Private FIFO creation failed' }
            $readerInfo = [Diagnostics.ProcessStartInfo]::new('/bin/sh')
            $readerInfo.Arguments = '-c "dd if=\"$1\" of=/dev/null bs=1 count=64; exec dd if=\"$1\" of=/dev/null bs=1 count=64" capture-reader "' + $logPath + '"'
            $readerInfo.UseShellExecute = $false
            $readerInfo.RedirectStandardError = $true
            $reader = [Diagnostics.Process]::Start($readerInfo)
        }
        $info = [Diagnostics.ProcessStartInfo]::new($parentRuntime)
        # Arguments (not ArgumentList) works on the Windows 5.1 .NET Framework.
        $arguments = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $parentPath,
            '-CaseRoot', $caseRoot, '-runtimePath', $childRuntimePath, '-expectedRuntime', $expectedRuntime, '-Preference', $Preference)
        $info.Arguments = ($arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
        $info.UseShellExecute = $false
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $info.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
        $info.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
        $info.EnvironmentVariables['DOTFILES_CAPTURE_FIXTURE_ROOT'] = $caseRoot
        $info.EnvironmentVariables['DOTFILES_CAPTURE_FIXTURE_EXIT'] = [string]$ExpectedExit
        $info.EnvironmentVariables['DOTFILES_CAPTURE_FIXTURE_SINK'] = $Sink
        $process = [Diagnostics.Process]::Start($info)
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $output = [Text.StringBuilder]::new()
        $liveBeforeExit = $false
        $deadline = [DateTime]::UtcNow.AddSeconds(20)
        try {
            while ($true) {
                $lineTask = $process.StandardOutput.ReadLineAsync()
                while (-not $lineTask.IsCompleted) {
                    if ([DateTime]::UtcNow -gt $deadline) { throw 'Bounded native capture fixture timed out' }
                    [Threading.Thread]::Sleep(10)
                }
                $line = $lineTask.GetAwaiter().GetResult()
                if ($null -eq $line) { break }
                [void]$output.AppendLine($line)
                if ($line.Contains('MARK_HOST') -and -not $process.HasExited -and
                    -not (Test-Path -LiteralPath (Join-Path $caseRoot 'child-finished.txt'))) {
                    $liveBeforeExit = $true
                }
            }
            if (-not $process.WaitForExit(5000)) { throw 'Bounded capture parent did not exit' }
            $stderr = $stderrTask.GetAwaiter().GetResult()
            $statePath = Join-Path $caseRoot 'parent-state.json'
            $stateRecorded = Test-Path -LiteralPath $statePath
            $state = if ($stateRecorded) {
                Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
            }
            else {
                # Missing observation is an explicit failed consumer outcome,
                # not a setup error or an invented native/cleanup result.
                [pscustomobject]@{ nativeExit = $null; parentVersion = $null; restoredPreference = $null
                    childAliveAtCleanup = $null; childFileRemoved = $null
                }
            }
            $childStarted = Test-Path -LiteralPath (Join-Path $caseRoot 'child-pid.txt')
            $childAlive = $false
            if ($childStarted) {
                try {
                    $childProcess = [Diagnostics.Process]::GetProcessById([int][IO.File]::ReadAllText((Join-Path $caseRoot 'child-pid.txt')))
                    $childAlive = -not $childProcess.HasExited
                }
                catch [ArgumentException] { $childAlive = $false }
            }
            $log = $null
            $closed = $false
            if ($Sink -eq 'normal') {
                $log = Get-Content -LiteralPath $logPath -Raw
                $handle = [IO.File]::Open($logPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
                $handle.Dispose()
                $closed = $true
            }
            return [pscustomobject]@{
                ExitCode = $process.ExitCode; NativeExit = $state.nativeExit; Stdout = $output.ToString(); Stderr = $stderr
                ParentVersion = $state.parentVersion; Preference = $state.restoredPreference
                StateRecorded = $stateRecorded
                LiveBeforeExit = $liveBeforeExit; ChildStarted = $childStarted; ChildAlive = $childAlive
                ChildAliveAtCleanup = $state.childAliveAtCleanup; ChildRemoved = $state.childFileRemoved
                ChildFinished = Test-Path -LiteralPath (Join-Path $caseRoot 'child-finished.txt')
                Log = $log; LogClosed = $closed
            }
        }
        finally {
            if (-not $process.HasExited) { $process.Kill(); [void]$process.WaitForExit(5000) }
            # A failing fixture remains bounded; wait only for its own PID.
            if ($childAlive) { [void]$childProcess.WaitForExit(5000) }
            if ($reader) {
                if (-not $reader.WaitForExit(5000)) { $reader.Kill(); [void]$reader.WaitForExit(5000) }
                $reader.Dispose()
            }
            $process.Dispose()
        }
    }
}

Describe 'Windows installer outer native capture consumer' {
    It 'should capture <ChildRuntime> stdout stderr host Unicode live output and exact exit <ExpectedExit> with <Preference>' -TestCases $captureNormalCases {
        param($ChildRuntime, $Preference, $ExpectedExit)
        $result = Invoke-InstallerCaptureFixture -Directory $TestDrive -ChildRuntime $ChildRuntime -Preference $Preference -ExpectedExit $ExpectedExit
        $result.ExitCode | Should -Be $ExpectedExit -Because $result.Stderr
        $result.NativeExit | Should -Be $ExpectedExit
        foreach ($marker in @('MARK_STDOUT', 'MARK_RAWOUT', 'MARK_STDERR', 'MARK_HOST', 'MARK_TAIL', '日本語')) {
            $result.Log | Should -Match ([regex]::Escape($marker))
            ($result.Stdout + $result.Stderr) | Should -Match ([regex]::Escape($marker))
        }
        $childMajor = if ($ChildRuntime -eq '5.1') { 5 } else { 7 }
        $result.Stdout | Should -Match "FIXTURE_CHILD_MAJOR=$childMajor"
        if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { $result.ParentVersion | Should -Match '^5\.1\.' }
        $result.LiveBeforeExit | Should -BeTrue
        $result.StateRecorded | Should -BeTrue
        $result.Preference | Should -Be $Preference
        $result.ChildFinished | Should -BeTrue
        $result.ChildAliveAtCleanup | Should -BeFalse
        $result.ChildAlive | Should -BeFalse
        $result.ChildRemoved | Should -BeTrue
        $result.LogClosed | Should -BeTrue
    }

    It 'should not launch <ChildRuntime> for an unavailable log with <Preference>' -TestCases $captureFailureCases {
        param($ChildRuntime, $Preference)
        $result = Invoke-InstallerCaptureFixture -Directory $TestDrive -ChildRuntime $ChildRuntime -Preference $Preference -Sink unavailable
        $result.ExitCode | Should -Be 1 -Because $result.Stderr
        $result.Stderr | Should -Match 'Windows\s+installer\s+output\s+capture/invocation\s+failed:'
        $result.StateRecorded | Should -BeTrue
        $result.NativeExit | Should -BeNullOrEmpty
        $result.ChildStarted | Should -BeFalse
        $result.ChildAliveAtCleanup | Should -BeFalse
        $result.ChildAlive | Should -BeFalse
        $result.ChildRemoved | Should -BeTrue
        $result.Preference | Should -Be $Preference
    }

    # Real POSIX FIFO coverage is not a Windows filesystem/descendant guarantee.
    It 'should fail visibly on a real POSIX midstream broken pipe after stopping the direct child' -Skip:$captureWindows {
        $result = Invoke-InstallerCaptureFixture -Directory $TestDrive -ChildRuntime current -Preference Stop -Sink pipe
        $result.ExitCode | Should -Be 1
        $result.Stderr | Should -Match 'Windows installer output capture/invocation failed:.*[Bb]roken pipe'
        $result.StateRecorded | Should -BeTrue
        $result.NativeExit | Should -BeNullOrEmpty
        $result.ChildStarted | Should -BeTrue
        $result.ChildFinished | Should -BeFalse
        $result.ChildAliveAtCleanup | Should -BeFalse
        $result.ChildAlive | Should -BeFalse
        $result.ChildRemoved | Should -BeTrue
        $result.Preference | Should -Be 'Stop'
    }
}
