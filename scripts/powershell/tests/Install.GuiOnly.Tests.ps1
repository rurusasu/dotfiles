#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    function Invoke-GuiSetupFixture {
        param([bool]$Available = $true, [bool]$Success = $true)

        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $adapter = Join-Path $root 'scripts/powershell'
        $library = Join-Path $adapter 'lib'
        $handlers = Join-Path $adapter 'handlers'
        New-Item -ItemType Directory -Path $library, $handlers -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'install.cmd') -Destination $root
        foreach ($file in 'install.ps1', 'install.user.ps1') {
            Copy-Item -LiteralPath (Join-Path $script:repoRoot "scripts/powershell/$file") -Destination $adapter
        }
        foreach ($file in 'WindowsEnvironment.ps1', 'SetupHandler.ps1', 'Invoke-ExternalCommand.ps1') {
            Copy-Item -LiteralPath (Join-Path $script:repoRoot "scripts/powershell/lib/$file") -Destination $library
        }
        foreach ($file in 'install.admin.ps1', 'Test-Environment.ps1') {
            Set-Content -LiteralPath (Join-Path $adapter $file) -Encoding UTF8 -Value "throw 'GUI setup must not load $file'"
        }
        foreach ($name in 'Npm', 'Pnpm', 'Bun', 'NixosWsl', 'Chezmoi', 'Herdr') {
            Set-Content -LiteralPath (Join-Path $handlers "Handler.$name.ps1") -Encoding UTF8 -Value "throw 'GUI setup must not load $name'"
        }
        $fixture = @'
class WingetHandler : SetupHandlerBase {
    WingetHandler() {
        $this.Name = 'Winget'
        $this.Description = 'GUI fixture'
        $this.Order = 5
        $this.Phase = 1
    }
    [bool] CanApply([SetupContext]$ctx) { return __AVAILABLE__ }
    [SetupResult] Apply([SetupContext]$ctx) {
        if (-not $ctx.GetOption('SkipRetiredPackageCleanup', $false)) {
            return $this.CreateFailureResult('GUI setup must preserve existing installations')
        }
        if (__SUCCESS__) { return $this.CreateSuccessResult('GUI_FIXTURE_APPLIED') }
        return $this.CreateFailureResult('GUI_FIXTURE_FAILED')
    }
}
'@
        $fixture = $fixture.Replace('__AVAILABLE__', ('$' + $Available.ToString().ToLowerInvariant())).Replace('__SUCCESS__', ('$' + $Success.ToString().ToLowerInvariant()))
        Set-Content -LiteralPath (Join-Path $handlers 'Handler.Winget.ps1') -Encoding UTF8 -Value $fixture
        $info = New-Object System.Diagnostics.ProcessStartInfo
        $info.FileName = 'cmd.exe'
        $info.Arguments = '/d /c install.cmd -NoPause'
        $info.WorkingDirectory = $root
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        if ($PSVersionTable.PSVersion.Major -lt 6) {
            $info.EnvironmentVariables['DOTFILES_FORCE_WINDOWS_POWERSHELL'] = '1'
        }
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $info
        try {
            [void]$process.Start()
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(30000)) {
                & taskkill.exe /PID $process.Id /T /F | Out-Null
                throw 'GUI setup fixture timed out'
            }
            [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $stdout.Result + $stderr.Result }
        }
        finally { $process.Dispose() }
    }
}

Describe 'GUI-only Windows setup execution' {
    It 'should run only WinGet without loading CLI, WSL, admin or chezmoi code' {
        $result = Invoke-GuiSetupFixture
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'GUI_FIXTURE_APPLIED'
        $result.Output | Should -Match 'Setup Complete!'
        $result.Output | Should -Not -Match 'Phase 2|Environment Acceptance|\[Npm\]|\[Pnpm\]'
    }

    It 'should propagate a GUI installer failure to install.cmd' {
        $result = Invoke-GuiSetupFixture -Success $false
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'GUI_FIXTURE_FAILED'
        $result.Output | Should -Not -Match 'Setup Complete!'
    }

    It 'should fail when WinGet cannot run instead of reporting a successful skip' {
        $result = Invoke-GuiSetupFixture -Available $false
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'WinGet.*not available'
        $result.Output | Should -Not -Match 'Setup Complete!'
    }
}
