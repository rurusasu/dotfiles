BeforeAll {
    . $PSScriptRoot/../../lib/WindowsEnvironment.ps1
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.Winget.ps1
}

Describe 'Windows setup with missing command directories in PATH' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    BeforeEach {
        $script:originalPath = $env:PATH
        $script:originalLocalAppData = $env:LOCALAPPDATA
        $env:PATH = "$PSHOME;$env:SystemRoot\System32"
        $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $env:LOCALAPPDATA = Join-Path $caseRoot 'local'
        New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force | Out-Null
        $script:ctx = [SetupContext]::new($TestDrive)
        $script:logs = @()
        Mock Write-Host { param($Object) $script:logs += [string]($Object -join ' ') }
        Mock Get-UserEnvironmentPath { return $env:PATH }
        Mock Set-UserEnvironmentPath { throw 'The test must not persist PATH changes' }
        Mock Get-ExternalCommand {
            param($Name)
            Get-Command -Name $Name -ErrorAction SilentlyContinue
        }
    }

    AfterEach {
        $env:PATH = $script:originalPath
        $env:LOCALAPPDATA = $script:originalLocalAppData
    }

    It 'should restore the existing WindowsApps directory without duplicating or replacing PATH entries' {
        $windowsApps = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
        New-Item -ItemType Directory -Path $windowsApps -Force | Out-Null
        $before = $env:PATH

        Repair-WindowsSetupEnvironment
        Repair-WindowsSetupEnvironment

        @($env:PATH -split ';' | Where-Object { $_ -eq $windowsApps }).Count | Should -Be 1
        $env:PATH | Should -Match ([regex]::Escape($before))
    }

    It 'should recover an installed portable command without a WinGet link or explicit pathEntries' -ForEach @(
        @{ RelativeDirectory = ''; CommandName = 'fzf' }
        @{ RelativeDirectory = 'ghq_windows_amd64'; CommandName = 'ghq' }
        @{ RelativeDirectory = 'bin'; CommandName = 'lua-language-server' }
    ) {
        $packageRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\Recovery.Tool_test'
        $commandDirectory = if ($RelativeDirectory) { Join-Path $packageRoot $RelativeDirectory } else { $packageRoot }
        New-Item -ItemType Directory -Path $commandDirectory -Force | Out-Null
        Copy-Item -LiteralPath $env:ComSpec -Destination (Join-Path $commandDirectory "$CommandName.exe")
        $script:persistedPath = $env:PATH
        Mock Get-UserEnvironmentPath { return $script:persistedPath }
        Mock Set-UserEnvironmentPath { param($Path) $script:persistedPath = $Path }
        $pkg = [PSCustomObject]@{
            Id            = 'Recovery.Tool'
            PathEntries   = @()
            VerifyCommand = [PSCustomObject]@{ command = $CommandName; args = @('/d', '/c', 'exit 0') }
        }
        $wingetHandler = [WingetHandler]::new()

        $wingetHandler.EnsurePathEntries($pkg)

        $wingetHandler.TestPackageVerification($pkg.VerifyCommand) | Should -BeTrue
        $script:persistedPath -split ';' | Should -Contain $commandDirectory
        (Get-Command "$CommandName.exe" | Select-Object -First 1).Source | Should -Be (Join-Path $commandDirectory "$CommandName.exe")
    }

    It 'should not recover a command from another package directory' {
        $otherPackage = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\Recovery.Other_test'
        New-Item -ItemType Directory -Path $otherPackage -Force | Out-Null
        Copy-Item -LiteralPath $env:ComSpec -Destination (Join-Path $otherPackage 'missing-tool.exe')
        $before = $env:PATH
        $pkg = [PSCustomObject]@{
            Id            = 'Recovery.Tool'
            PathEntries   = @()
            VerifyCommand = [PSCustomObject]@{ command = 'missing-tool'; args = @('/d', '/c', 'exit 0') }
        }

        [WingetHandler]::new().EnsurePathEntries($pkg)

        $env:PATH | Should -Be $before
    }

    It 'should recover an installed portable package before deciding to reinstall (verify-only: <VerifyOnly>)' -ForEach @(
        @{ VerifyOnly = $false }
        @{ VerifyOnly = $true }
    ) {
        $script:ctx.Options['WingetVerifyCommandOnly'] = $VerifyOnly
        $retiredDirectory = Join-Path $TestDrive 'windows/winget'
        New-Item -ItemType Directory -Path $retiredDirectory -Force | Out-Null
        '{"packages":[]}' | Set-Content -LiteralPath (Join-Path $retiredDirectory 'retired-packages.json')
        $commandDirectory = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\Recovery.Tool_test\bin'
        New-Item -ItemType Directory -Path $commandDirectory -Force | Out-Null
        Copy-Item -LiteralPath $env:ComSpec -Destination (Join-Path $commandDirectory 'recovery-tool.exe')
        Mock Get-JsonContent {
            return [PSCustomObject]@{ Sources = @([PSCustomObject]@{
                        SourceDetails = [PSCustomObject]@{ Name = 'winget' }
                        Packages      = @([PSCustomObject]@{
                                PackageIdentifier = 'Recovery.Tool'
                                verifyCommand     = [PSCustomObject]@{ command = 'recovery-tool'; args = @('/d', '/c', 'exit 0') }
                            })
                    }) 
            }
        }
        Mock Invoke-Winget {
            param($Arguments)
            if ($Arguments[0] -eq 'list') {
                $global:LASTEXITCODE = 0
                return @('Name Id Version Source', '----------------------', 'Recovery Recovery.Tool 1.0 winget')
            }
            if ($Arguments[0] -eq 'install') {
                if ($Arguments -contains '--force') { throw 'PATH recovery must precede the reinstall decision' }
                $global:LASTEXITCODE = 1
                return 'No applicable update found'
            }
            throw "Unexpected winget operation: $Arguments"
        }
        Mock Update-ProcessEnvironmentPath { }
        Mock Set-UserEnvironmentPath { }
        Mock Test-Path { return $false } -ParameterFilter { $Path -like '*\.cargo\bin' }

        $result = [WingetHandler]::new().Apply($script:ctx)

        $result.Success | Should -BeTrue -Because $result.Message
        (Get-Command recovery-tool.exe | Select-Object -First 1).Source | Should -Be (Join-Path $commandDirectory 'recovery-tool.exe')
        if ($VerifyOnly) {
            Should -Invoke Invoke-Winget -Times 0 -Exactly -ParameterFilter { $Arguments[0] -eq 'install' }
        }
        else {
            $script:logs -join "`n" | Should -Match 'Recovery.Tool.*no-op'
        }
    }

    It 'should leave PATH unchanged when multiple executables match the same package' {
        $packageRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\Recovery.Tool_test'
        foreach ($arch in @('x64', 'arm64')) {
            $directory = Join-Path $packageRoot $arch
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            Copy-Item -LiteralPath $env:ComSpec -Destination (Join-Path $directory 'ambiguous-tool.exe')
        }
        $before = $env:PATH
        $pkg = [PSCustomObject]@{
            Id            = 'Recovery.Tool'
            PathEntries   = @()
            VerifyCommand = [PSCustomObject]@{ command = 'ambiguous-tool'; args = @('/d', '/c', 'exit 0') }
        }

        [WingetHandler]::new().EnsureProcessPathEntries($pkg)

        $env:PATH | Should -Be $before
        $script:logs -join "`n" | Should -Match 'Multiple package executables'
    }
}
