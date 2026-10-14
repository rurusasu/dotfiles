#Requires -Module Pester

BeforeAll {
    $script:target = Join-Path (Split-Path -Parent $PSScriptRoot) "install.ps1"
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $script:cmdTarget = Join-Path $script:repoRoot "install.cmd"
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/Invoke-ExternalCommand.ps1')
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/Invoke-WindowsInstallTask.ps1')
}

Describe 'Windows installer private Task runtime' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    BeforeEach {
        $script:environment = @{}
        foreach ($name in @('LOCALAPPDATA', 'TEMP', 'TMP', 'PROCESSOR_ARCHITECTURE', 'PROCESSOR_ARCHITEW6432')) {
            $script:environment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        }
        $script:caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:temporaryRoot = Join-Path $script:caseRoot 'task-temporary-root'
        $env:LOCALAPPDATA = Join-Path $script:caseRoot 'task-local-app-data'
        $env:TEMP = $script:temporaryRoot
        $env:TMP = $script:temporaryRoot
        $env:PROCESSOR_ARCHITECTURE = 'AMD64'
        $env:PROCESSOR_ARCHITEW6432 = ''
        [void][IO.Directory]::CreateDirectory($script:temporaryRoot)
        $script:downloadDirectory = $null
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'task' -and $CommandType -eq 'Application' }
        Mock Invoke-RestMethodSafe { throw 'Unexpected Task release lookup' }
        Mock Invoke-WebRequestSafe { throw 'Unexpected Task archive download' }
        Mock Expand-Archive { throw 'Unexpected Task archive extraction' }
        Mock Invoke-WindowsInstallTaskCommand { throw 'Resolver tests must not execute Task' }
    }

    AfterEach {
        foreach ($name in $script:environment.Keys) { [Environment]::SetEnvironmentVariable($name, $script:environment[$name], 'Process') }
    }

    It 'should reuse Task from PATH before consulting its private cache or release API' {
        Mock Get-Command { [pscustomobject]@{ Source = 'C:\installed tools\task.exe' } } -ParameterFilter { $Name -eq 'task' -and $CommandType -eq 'Application' }
        Resolve-WindowsInstallTask | Should -BeExactly 'C:\installed tools\task.exe'
        Should -Invoke Invoke-RestMethodSafe -Times 0 -Exactly
        Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'dotfiles/tools/task') | Should -BeFalse
    }

    It 'should reuse the private cached Task when PATH does not contain it' {
        $cache = Join-Path $env:LOCALAPPDATA 'dotfiles/tools/task'
        [void][IO.Directory]::CreateDirectory($cache)
        $executable = Join-Path $cache 'task.exe'
        [IO.File]::WriteAllText($executable, 'cached fixture')
        Resolve-WindowsInstallTask | Should -BeExactly $executable
        [IO.File]::ReadAllText($executable) | Should -BeExactly 'cached fixture'
        Should -Invoke Invoke-RestMethodSafe -Times 0 -Exactly
        Should -Invoke Invoke-WebRequestSafe -Times 0 -Exactly
    }

    It 'should select the matching Windows archive cache its executable and remove only its temporary directory' -ForEach @(
        @{ ProcessArchitecture = 'AMD64'; HostArchitecture = ''; ExpectedArchitecture = 'amd64' },
        @{ ProcessArchitecture = 'ARM64'; HostArchitecture = ''; ExpectedArchitecture = 'arm64' },
        @{ ProcessArchitecture = 'x86'; HostArchitecture = 'ARM64'; ExpectedArchitecture = 'arm64' }
    ) {
        $env:PROCESSOR_ARCHITECTURE = $ProcessArchitecture
        $env:PROCESSOR_ARCHITEW6432 = $HostArchitecture
        Mock Invoke-RestMethodSafe { [pscustomobject]@{ assets = @(
                    [pscustomobject]@{ name = 'task_windows_amd64.zip'; browser_download_url = 'https://fixture.invalid/task-amd64.zip' },
                    [pscustomobject]@{ name = 'task_windows_arm64.zip'; browser_download_url = 'https://fixture.invalid/task-arm64.zip' }
                ) } }
        Mock Invoke-WebRequestSafe {
            param($Uri, $OutFile)
            $script:downloadUri = $Uri
            $script:downloadDirectory = Split-Path -Parent $OutFile
            [IO.File]::WriteAllText($OutFile, 'archive fixture')
        }
        Mock Expand-Archive { param($LiteralPath, $DestinationPath) [IO.File]::ReadAllText($LiteralPath) | Should -BeExactly 'archive fixture'; [IO.File]::WriteAllText((Join-Path $DestinationPath 'task.exe'), 'downloaded Task fixture') }
        $unrelatedDirectory = Join-Path $script:temporaryRoot 'keep-this-directory'
        [void][IO.Directory]::CreateDirectory($unrelatedDirectory)
        $resolved = Resolve-WindowsInstallTask
        $script:downloadUri | Should -BeExactly "https://fixture.invalid/task-$ExpectedArchitecture.zip"
        $resolved | Should -BeExactly (Join-Path $env:LOCALAPPDATA 'dotfiles/tools/task/task.exe')
        [IO.File]::ReadAllText($resolved) | Should -BeExactly 'downloaded Task fixture'
        Split-Path -Parent $script:downloadDirectory | Should -BeExactly $script:temporaryRoot
        Split-Path -Leaf $script:downloadDirectory | Should -Match '^[a-f0-9]{32}$'
        Test-Path -LiteralPath $script:downloadDirectory | Should -BeFalse
        Test-Path -LiteralPath $unrelatedDirectory -PathType Container | Should -BeTrue
    }

    It 'should reject a release without a matching archive before creating a download directory' {
        Mock Invoke-RestMethodSafe { [pscustomobject]@{ assets = @() } }
        { Resolve-WindowsInstallTask } | Should -Throw '*no Windows amd64 archive*'
        Should -Invoke Invoke-WebRequestSafe -Times 0 -Exactly
        @(Get-ChildItem -LiteralPath $script:temporaryRoot -Directory).Count | Should -Be 0
    }

    It 'should clean its private temporary directory after a failed download or extraction' -ForEach @(
        @{ Failure = 'download' }, @{ Failure = 'extraction' }
    ) {
        Mock Invoke-RestMethodSafe { [pscustomobject]@{ assets = @([pscustomobject]@{ name = 'task_windows_amd64.zip'; browser_download_url = 'https://fixture.invalid/task-amd64.zip' }) } }
        Mock Invoke-WebRequestSafe {
            param($Uri, $OutFile)
            $script:downloadUri = $Uri
            $script:downloadDirectory = Split-Path -Parent $OutFile
            if ($Failure -eq 'download') { throw 'isolated Task download failure' }
            [IO.File]::WriteAllText($OutFile, 'archive fixture')
        }
        Mock Expand-Archive { throw 'isolated Task extraction failure' }
        { Resolve-WindowsInstallTask } | Should -Throw '*isolated Task*failure*'
        $script:downloadUri | Should -BeExactly 'https://fixture.invalid/task-amd64.zip'
        $script:downloadDirectory | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $script:downloadDirectory | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'dotfiles/tools/task/task.exe') | Should -BeFalse
    }
}

Describe 'Windows installer Task handoff lifecycle' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    BeforeEach {
        $script:previousConfiguration = $env:DOTFILES_INSTALL_CONFIGURATION
        $script:previousShell = $env:DOTFILES_INSTALL_POWERSHELL
        $script:previousExitCode = $global:LASTEXITCODE
        $env:DOTFILES_INSTALL_CONFIGURATION = 'previous configuration fixture'
        $env:DOTFILES_INSTALL_POWERSHELL = 'previous shell fixture'
        $script:configuration = @{ NoPause = $true; DistroName = 'NixOS'; Options = @{ Example = 'preserved' } }
        $script:repository = Join-Path $TestDrive 'checkout with spaces'
        $script:taskCalls = [Collections.Generic.List[object]]::new()
        $script:mode = 'success'
        Mock Resolve-WindowsInstallTask { Join-Path $TestDrive 'private task.exe' }
        Mock Invoke-WindowsInstallTaskCommand {
            param($Executable, $Arguments)
            $configuration = $env:DOTFILES_INSTALL_CONFIGURATION | ConvertFrom-Json
            $script:resultPath = $configuration.ResultPath
            $script:taskCalls.Add([pscustomobject]@{ Executable = $Executable; Arguments = $Arguments; Configuration = $configuration; Shell = $env:DOTFILES_INSTALL_POWERSHELL })
            $global:LASTEXITCODE = 0
            if ($script:mode -eq 'restart') { [IO.File]::WriteAllText($script:resultPath, 'RestartRequired'); $global:LASTEXITCODE = 3010 }
            if ($script:mode -eq 'install-failure') { $global:LASTEXITCODE = 9 }
            if ($script:mode -eq 'post-failure' -and $Arguments[-1] -eq 'install:windows:post') { $global:LASTEXITCODE = 7 }
            if ($script:mode -eq 'exception') { throw 'isolated Task command exception' }
        }
    }

    AfterEach {
        $env:DOTFILES_INSTALL_CONFIGURATION = $script:previousConfiguration
        $env:DOTFILES_INSTALL_POWERSHELL = $script:previousShell
        $global:LASTEXITCODE = $script:previousExitCode
    }

    It 'should honor phase exit and reboot results while restoring environment and deleting the result file' -ForEach @(
        @{ Mode = 'success'; ExpectedCalls = 2; RestartRequired = $false; ErrorPattern = '' },
        @{ Mode = 'restart'; ExpectedCalls = 1; RestartRequired = $true; ErrorPattern = '' },
        @{ Mode = 'install-failure'; ExpectedCalls = 1; RestartRequired = $false; ErrorPattern = '*Windows setup failed*exit=9*' },
        @{ Mode = 'post-failure'; ExpectedCalls = 2; RestartRequired = $false; ErrorPattern = '*Windows post-install setup failed*exit=7*' },
        @{ Mode = 'exception'; ExpectedCalls = 1; RestartRequired = $false; ErrorPattern = '*isolated Task command exception*' }
    ) {
        $script:mode = $Mode
        if ($ErrorPattern) { { Invoke-WindowsInstallTask -Repository $script:repository -Configuration $script:configuration } | Should -Throw $ErrorPattern }
        else { Invoke-WindowsInstallTask -Repository $script:repository -Configuration $script:configuration | Should -Be $RestartRequired }
        $script:taskCalls.Count | Should -Be $ExpectedCalls
        $script:taskCalls[0].Arguments | Should -Be @('--dir', $script:repository, '--taskfile', (Join-Path $script:repository 'Taskfile.yml'), 'install:windows')
        if ($ExpectedCalls -eq 2) { $script:taskCalls[1].Arguments[-1] | Should -Be 'install:windows:post' }
        foreach ($call in $script:taskCalls) {
            $call.Executable | Should -BeExactly (Join-Path $TestDrive 'private task.exe')
            $call.Configuration.NoPause | Should -BeTrue
            $call.Configuration.DistroName | Should -Be 'NixOS'
            $call.Configuration.Options.Example | Should -Be 'preserved'
            $call.Shell | Should -BeExactly ((Join-Path $PSHOME $(if ($PSVersionTable.PSVersion.Major -lt 6) { 'powershell.exe' } else { 'pwsh.exe' })).Replace('\', '/'))
            $call.Configuration.ResultPath | Should -BeExactly $script:resultPath
        }
        $script:configuration.ContainsKey('ResultPath') | Should -BeFalse
        $script:configuration.Options.Example | Should -Be 'preserved'
        $env:DOTFILES_INSTALL_CONFIGURATION | Should -BeExactly 'previous configuration fixture'
        $env:DOTFILES_INSTALL_POWERSHELL | Should -BeExactly 'previous shell fixture'
        $script:resultPath | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $script:resultPath | Should -BeFalse
    }
}

Describe 'install.ps1 (orchestrator)' {
    It 'should exist at scripts/powershell/install.ps1' {
        Test-Path -LiteralPath $script:target | Should -BeTrue
    }

    It 'should parse without syntax errors' {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($script:target, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
    }

    It 'should support noninteractive GUI verification and completion' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match '\[switch\]\$NoPause'
        $content | Should -Match '\[switch\]\$UserPhaseOnly'
        $content | Should -Match '\[switch\]\$WingetVerifyCommandOnly'
        $content | Should -Match 'WingetVerifyCommandOnly'
    }

    It 'should repair the Windows environment before invoking GUI setup' {
        $content = Get-Content -LiteralPath $script:target -Raw
        $content | Should -Match 'WindowsEnvironment\.ps1'
        $content | Should -Match 'Repair-WindowsSetupEnvironment'
    }

    It 'install.cmd should invoke the explicit PowerShell 7 path without changing PATH' {
        $content = Get-Content -LiteralPath $script:cmdTarget -Raw
        $content | Should -Match 'if defined DOTFILES_PS7_DIR'
        $content | Should -Match 'set "PS7_DIR=%DOTFILES_PS7_DIR%"'
        $content | Should -Match 'set "PS7_DIR=%ProgramFiles%\\PowerShell\\7"'
        $content | Should -Match 'if exist "%PS7_DIR%\\pwsh\.exe"'
        $content | Should -Not -Match 'set "PATH=%PS7_DIR%;%PATH%"'
        $content | Should -Match 'set "PS_CMD=%PS7_DIR%\\pwsh\.exe"'
        $content | Should -Match 'for %%I in \(pwsh\.exe\) do if not "%%~\$PATH:I"==""'
        $content | Should -Not -Match 'where\.exe.*pwsh'
        $content | Should -Match '%SystemRoot%\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe'
        $content | Should -Match 'Falling back to Windows PowerShell'
    }
}
