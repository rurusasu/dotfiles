#Requires -Module Pester

<#
.SYNOPSIS
    Handler.Pnpm.ps1 のユニットテスト

.DESCRIPTION
    PnpmHandler クラスのテスト
#>

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.Pnpm.ps1
    $script:projectRoot = (Resolve-Path -LiteralPath "$PSScriptRoot/../../../..").Path
    $script:testPathCmdlet = Get-Command -Name Test-Path -CommandType Cmdlet
}

Describe 'PnpmHandler' {
    Context 'Invoke-Pnpm package install timeout routing' {
        BeforeEach {
            $script:originalInstallTimeout = $env:DOTFILES_INSTALL_TIMEOUT_SECONDS
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'pnpm.cmd' }
        }
        AfterEach {
            if ($null -eq $script:originalInstallTimeout) {
                Remove-Item Env:\DOTFILES_INSTALL_TIMEOUT_SECONDS -ErrorAction SilentlyContinue
            }
            else {
                $env:DOTFILES_INSTALL_TIMEOUT_SECONDS = $script:originalInstallTimeout
            }
        }

        It 'should invoke global adds through the shared 3600-second timeout by default' {
            Remove-Item Env:\DOTFILES_INSTALL_TIMEOUT_SECONDS -ErrorAction SilentlyContinue
            Mock Get-Command { return @{ Source = 'C:\tools\pnpm.cmd' } } -ParameterFilter { $Name -eq 'pnpm.cmd' }
            Mock Invoke-ExternalCommandWithTimeout { $global:LASTEXITCODE = 0; return 'add ok' }
            Mock Invoke-NativeCommand { throw 'global add must use the timeout wrapper' }

            $result = Invoke-Pnpm -Arguments @('add', '-g', 'example-package')

            $result | Should -Contain 'add ok'
            Should -Invoke Invoke-ExternalCommandWithTimeout -Times 1 -ParameterFilter {
                $Command -eq 'C:\tools\pnpm.cmd' -and $Arguments -contains 'example-package' -and $TimeoutSeconds -eq 3600
            }
            Should -Invoke Invoke-NativeCommand -Times 0
        }

        It 'should honor DOTFILES_INSTALL_TIMEOUT_SECONDS for global adds' {
            $env:DOTFILES_INSTALL_TIMEOUT_SECONDS = '73'
            Mock Invoke-ExternalCommandWithTimeout { $global:LASTEXITCODE = 0; return 'add ok' }
            Mock Invoke-NativeCommand { throw 'global add must use the timeout wrapper' }

            $result = Invoke-Pnpm -Arguments @('add', '--global', 'example-package')

            $result | Should -Contain 'add ok'
            Should -Invoke Invoke-ExternalCommandWithTimeout -Times 1 -ParameterFilter {
                $Command -eq 'pnpm' -and $TimeoutSeconds -eq 73
            }
            Should -Invoke Invoke-NativeCommand -Times 0
        }

        It 'should leave version, list, and root commands on the native path' {
            Mock Invoke-ExternalCommandWithTimeout { throw 'non-install pnpm commands must not be timed' }
            Mock Invoke-NativeCommand { $global:LASTEXITCODE = 0; return 'native pnpm' }

            Invoke-Pnpm -Arguments @('--version') | Should -Contain 'native pnpm'
            Invoke-Pnpm -Arguments @('list', '-g') | Should -Contain 'native pnpm'
            Invoke-Pnpm -Arguments @('root', '-g') | Should -Contain 'native pnpm'

            Should -Invoke Invoke-ExternalCommandWithTimeout -Times 0
            Should -Invoke Invoke-NativeCommand -Times 3
        }
    }

    Context 'Apply - pnpm bootstrap diagnostics' {
        BeforeEach {
            $script:loggedOutput = @()
            Mock Get-ExternalCommand {
                param($Name)
                if ($Name -eq 'npm') { return @{ Source = 'C:\npm.cmd' } }
                return $null
            }
            Mock Invoke-Npm {
                $global:LASTEXITCODE = 1
                return 'npm ERR! ECONNRESET registry connection closed'
            }
            Mock Write-Host { $script:loggedOutput += [string]$Object }
        }

        It 'should include npm bootstrap output and exit code when pnpm setup fails' {
            $result = $handler.Apply($ctx)

            $result.Success | Should -BeFalse
            ($script:loggedOutput -join "`n") | Should -Match 'npm ERR! ECONNRESET registry connection closed'
            ($script:loggedOutput -join "`n") | Should -Match 'npm install -g pnpm@latest exited with code 1'
        }
    }

    Context 'TryBootstrapPnpm - npm global prefix' {
        It 'should reject a bootstrap shim that fails, reports an old version, or emits diagnostic numbers' -ForEach @(
            @{ Output = 'global target points back at shim'; ExitCode = 1 }
            @{ Output = '12.3.4'; ExitCode = 0 }
            @{ Output = '12.4.0-rc.1'; ExitCode = 0 }
            @{ Output = 'error while loading pnpm 12.6.0'; ExitCode = 0 }
        ) {
            $script:bootstrapOutput = $Output
            $script:bootstrapExitCode = $ExitCode
            $script:bootstrapPrefix = Join-Path $TestDrive 'failed-bootstrap'
            New-Item -Path (Join-Path $script:bootstrapPrefix 'pnpm.cmd') -ItemType File -Force | Out-Null
            Mock Get-ExternalCommand {
                param($Name)
                if ($Name -eq 'npm') { return @{ Source = 'C:\npm.cmd' } }
                return $null
            }
            Mock Invoke-Npm {
                param($Arguments)
                $global:LASTEXITCODE = 0
                if ($Arguments -contains 'prefix') { return $script:bootstrapPrefix }
                return 'installed'
            }
            Mock Invoke-NativeCommand { $global:LASTEXITCODE = $script:bootstrapExitCode; return $script:bootstrapOutput }
            Mock Get-UserEnvironmentPath { return '' }
            Mock Set-UserEnvironmentPath { }
            Mock Invoke-Pnpm { throw 'failed bootstrap must stop before package commands' }
            Mock Write-Host { }
            $savedPath = $env:PATH
            try {
                $result = $handler.Apply($ctx)
                $result.Success | Should -BeFalse
                Should -Invoke Invoke-Npm -Times 1 -ParameterFilter { $Arguments -contains 'install' }
                Should -Invoke Invoke-Pnpm -Times 0
            }
            finally { $env:PATH = $savedPath }
        }

        It 'should resolve npm commands that expose Path without a Source property' {
            $script:originalProcessPath = $env:PATH
            $script:originalPnpmHome = $env:PNPM_HOME
            $script:npmGlobalPrefix = Join-Path $TestDrive 'npm-global-path-only'
            $script:npmRuntimeDirectory = Join-Path $TestDrive 'npm-node-runtime-path-only'
            $script:npmPath = Join-Path $script:npmRuntimeDirectory 'npm.cmd'
            New-Item -Path (Join-Path $script:npmGlobalPrefix 'pnpm.cmd') -ItemType File -Force | Out-Null
            New-Item -Path $script:npmPath -ItemType File -Force | Out-Null
            New-Item -Path (Join-Path $script:npmRuntimeDirectory 'node.exe') -ItemType File -Force | Out-Null
            $env:PNPM_HOME = $null
            $env:PATH = 'C:\Windows\System32'
            Mock Get-ExternalCommand {
                param($Name)
                if ($Name -eq 'npm') { return [pscustomobject]@{ Path = $script:npmPath } }
                return $null
            }
            Mock Invoke-Npm {
                param($Arguments)
                if ($Arguments -contains 'prefix') { $global:LASTEXITCODE = 0; return $script:npmGlobalPrefix }
                $global:LASTEXITCODE = 0
                return 'added pnpm'
            }
            Mock Invoke-NativeCommand { $global:LASTEXITCODE = 0; return '12.6.0' }
            Mock Get-UserEnvironmentPath { return '' }
            Mock Set-UserEnvironmentPath { }

            try {
                Set-StrictMode -Version Latest
                $result = $handler.TryBootstrapPnpm()

                $result | Should -BeTrue
                $handler.BootstrapPnpmDirectory | Should -Be $script:npmGlobalPrefix
            }
            finally {
                Set-StrictMode -Off
                $env:PATH = $script:originalProcessPath
                $env:PNPM_HOME = $script:originalPnpmHome
            }
        }

        It 'should add npm global prefix to PATH before checking the installed pnpm shim' {
            $script:originalProcessPath = $env:PATH
            $script:originalPnpmHome = $env:PNPM_HOME
            $script:npmGlobalPrefix = Join-Path $TestDrive 'npm-global'
            New-Item -Path (Join-Path $script:npmGlobalPrefix 'pnpm.cmd') -ItemType File -Force | Out-Null
            $script:npmRuntimeDirectory = Join-Path $TestDrive 'npm-node-runtime'
            $script:npmPath = Join-Path $script:npmRuntimeDirectory 'npm.cmd'
            New-Item -Path $script:npmPath -ItemType File -Force | Out-Null
            New-Item -Path (Join-Path $script:npmRuntimeDirectory 'node.exe') -ItemType File -Force | Out-Null
            $env:PNPM_HOME = $null
            $env:PATH = 'C:\Windows\System32'
            Mock Get-ExternalCommand {
                param($Name)
                if ($Name -eq 'npm') { return @{ Source = $script:npmPath } }
                return $null
            }
            Mock Invoke-Npm {
                param($Arguments)
                $env:PATH -split ';' | Should -Contain $script:npmRuntimeDirectory
                if ($Arguments -contains 'prefix') {
                    $global:LASTEXITCODE = 0
                    return $script:npmGlobalPrefix
                }
                $global:LASTEXITCODE = 0
                return 'added pnpm'
            }
            Mock Invoke-NativeCommand {
                param($Command, $Arguments)
                $Command | Should -Be (Join-Path $script:npmGlobalPrefix 'pnpm.cmd')
                $Arguments | Should -Be @('--version')
                $global:LASTEXITCODE = 0
                return '12.6.0'
            }
            Mock Get-UserEnvironmentPath { return '' }
            Mock Set-UserEnvironmentPath { }

            try {
                $result = $handler.TryBootstrapPnpm()

                $result | Should -BeTrue
                ($env:PATH -split ';') | Should -Contain $script:npmGlobalPrefix
            }
            finally {
                $env:PATH = $script:originalProcessPath
                $env:PNPM_HOME = $script:originalPnpmHome
            }
        }

        It 'should verify the pnpm shim installed by npm even when another pnpm resolves first' {
            $script:originalProcessPath = $env:PATH
            $script:originalPnpmHome = $env:PNPM_HOME
            $script:npmGlobalPrefix = Join-Path $TestDrive 'npm-prefix-with-new-pnpm'
            $script:pnpmShimPath = Join-Path $script:npmGlobalPrefix 'pnpm.cmd'
            New-Item -Path $script:pnpmShimPath -ItemType File -Force | Out-Null
            $env:PNPM_HOME = $null
            $script:nativeCalls = @()
            Mock Get-ExternalCommand {
                param($Name)
                if ($Name -eq 'npm') { return @{ Source = 'C:\node-install\npm.cmd' } }
                if ($Name -eq 'pnpm') { return @{ Source = 'C:\old-pnpm\pnpm.cmd' } }
                return $null
            }
            Mock Invoke-Npm {
                param($Arguments)
                if ($Arguments -contains 'prefix') {
                    $global:LASTEXITCODE = 0
                    return $script:npmGlobalPrefix
                }
                $global:LASTEXITCODE = 0
                return 'added pnpm@latest'
            }
            Mock Invoke-Pnpm { throw 'the pnpm on PATH must not be used to validate the npm install' }
            Mock Invoke-NativeCommand {
                param($Command, $Arguments)
                $script:nativeCalls += , ([pscustomobject]@{ Command = $Command; Arguments = @($Arguments) })
                $global:LASTEXITCODE = 0
                return '12.6.0'
            }
            Mock Get-UserEnvironmentPath { return '' }
            Mock Set-UserEnvironmentPath { }

            try {
                $result = $handler.TryBootstrapPnpm()

                $result | Should -BeTrue
                $script:nativeCalls | Should -HaveCount 1
                $script:nativeCalls[0].Command | Should -Be $script:pnpmShimPath
                $script:nativeCalls[0].Arguments | Should -Be @('--version')
                ($env:PATH -split ';')[0] | Should -Be $script:npmGlobalPrefix
            }
            finally {
                $env:PATH = $script:originalProcessPath
                $env:PNPM_HOME = $script:originalPnpmHome
            }
        }
    }

    Context 'TryBootstrapPnpm - corepack Node runtime path' {
        It 'should add the Node directory beside corepack to PATH and activate pnpm@latest' {
            $script:originalProcessPath = $env:PATH
            $script:originalPnpmHome = $env:PNPM_HOME
            $script:corepackDirectory = Join-Path $TestDrive 'corepack-node-install'
            $script:corepackPath = Join-Path $script:corepackDirectory 'corepack.cmd'
            $script:corepackPnpmPath = Join-Path $script:corepackDirectory 'pnpm.cmd'
            New-Item -Path $script:corepackPath -ItemType File -Force | Out-Null
            New-Item -Path (Join-Path $script:corepackDirectory 'node.exe') -ItemType File -Force | Out-Null
            New-Item -Path $script:corepackPnpmPath -ItemType File -Force | Out-Null
            $env:PNPM_HOME = $null
            $env:PATH = 'C:\Windows\System32'
            $script:corepackCalls = @()
            Mock Get-ExternalCommand {
                param($Name)
                if ($Name -eq 'corepack') { return @{ Source = $script:corepackPath } }
                return $null
            }
            Mock Invoke-Corepack {
                param($Arguments)
                $script:corepackCalls += , @($Arguments)
                $env:PATH -split ';' | Should -Contain $script:corepackDirectory
                $global:LASTEXITCODE = 0
                return 'corepack ok'
            }
            Mock Invoke-NativeCommand {
                param($Command, $Arguments)
                $Command | Should -Be $script:corepackPnpmPath
                $Arguments | Should -Be @('--version')
                $global:LASTEXITCODE = 0
                return '12.6.0'
            }

            try {
                $result = $handler.TryBootstrapPnpm()

                $result | Should -BeTrue
                $script:corepackCalls | Should -HaveCount 2
                $script:corepackCalls[0] | Should -Be @('enable')
                $script:corepackCalls[1] | Should -Be @('prepare', 'pnpm@latest', '--activate')
            }
            finally {
                $env:PATH = $script:originalProcessPath
                $env:PNPM_HOME = $script:originalPnpmHome
            }
        }
    }

    Context 'Apply - supported pnpm PATH precedence' {
        It 'should keep policy commands on supported pnpm after home bin changes command resolution' -ForEach @(
            @{ ExistingExtension = '.cmd'; ExpectedBootstrapCalls = 0 }
            @{ ExistingExtension = '.exe'; ExpectedBootstrapCalls = 1 }
        ) {
            $savedPath = $env:PATH
            $savedHome = $env:PNPM_HOME
            $script:workingPnpmDirectory = Join-Path $TestDrive "supported-pnpm-$ExistingExtension"
            $script:workingPnpmShim = Join-Path $script:workingPnpmDirectory "pnpm$ExistingExtension"
            $script:recoveryDirectory = Join-Path $TestDrive 'recovery-prefix'
            $script:recoveryShim = Join-Path $script:recoveryDirectory 'pnpm.cmd'
            $ctx.Options['NpmGlobalPrefix'] = $script:recoveryDirectory
            $script:oldPnpmHome = Join-Path $TestDrive 'old-pnpm-home'
            $script:oldPnpmBin = Join-Path $script:oldPnpmHome 'bin'
            New-Item -Path $script:workingPnpmShim -ItemType File -Force | Out-Null
            New-Item -Path (Join-Path $script:oldPnpmBin 'pnpm.cmd') -ItemType File -Force | Out-Null
            $env:PNPM_HOME = $script:oldPnpmHome
            $env:PATH = "$script:workingPnpmDirectory;$env:SystemRoot\System32"
            $script:policyCommandPaths = @()
            Mock Get-ExternalCommand {
                param($Name)
                Get-Command -Name $Name -ErrorAction SilentlyContinue
            }
            Mock Get-ExternalCommand { return @{ Source = 'C:\npm.cmd' } } -ParameterFilter { $Name -eq 'npm' }
            Mock Get-UserEnvironmentPath { return $script:workingPnpmDirectory }
            Mock Set-UserEnvironmentPath { }
            Mock Get-JsonContent {
                return @{ globalPackages = @(@{ name = 'example'; installArgs = @('--allow-build=!node-pty') }) }
            }
            Mock Invoke-Npm {
                New-Item -Path $script:recoveryShim -ItemType File -Force | Out-Null
                $global:LASTEXITCODE = 0
                return 'pnpm repaired'
            }
            Mock Invoke-Corepack { throw 'supported pnpm must not bootstrap' }
            Mock Invoke-NativeCommand {
                param($Command, $Arguments)
                if ($Command -eq 'pnpm') { $Command = (Get-Command pnpm -CommandType Application | Select-Object -First 1).Source }
                if ($Arguments -contains '--version') {
                    $global:LASTEXITCODE = 0
                    if ($Command -in @($script:workingPnpmShim, $script:recoveryShim)) { return '12.6.0' }
                    return '12.3.4'
                }
                if ($Arguments -contains 'approve-builds') {
                    $script:policyCommandPaths += $Command
                    if ($Command -notin @($script:workingPnpmShim, $script:recoveryShim)) { $global:LASTEXITCODE = 1; return 'old pnpm cannot persist denial' }
                }
                $global:LASTEXITCODE = 0
                return ''
            }
            Mock Invoke-ExternalCommandWithTimeout { $global:LASTEXITCODE = 0; return 'installed' }
            Mock Write-Host { }
            try {
                $result = $handler.Apply($ctx)
                $result.Success | Should -BeTrue
                $expectedShim = if ($ExpectedBootstrapCalls -eq 0) { $script:workingPnpmShim } else { $script:recoveryShim }
                $script:policyCommandPaths | Should -Be @($expectedShim)
                ($env:PATH -split ';')[0] | Should -Be (Split-Path -Parent $expectedShim)
                Should -Invoke Invoke-Npm -Times $ExpectedBootstrapCalls -Exactly
            }
            finally {
                $env:PATH = $savedPath
                $env:PNPM_HOME = $savedHome
            }
        }
    }

    Context 'Apply - existing pnpm is unusable' {
        It 'should bootstrap through npm for a broken shim or unsupported version' -ForEach @(
            @{ VersionOutput = 'global target points back at shim'; VersionExit = 1 }
            @{ VersionOutput = '12.3.4'; VersionExit = 0 }
        ) {
            $script:existingVersionOutput = $VersionOutput
            $script:existingVersionExit = $VersionExit
            $script:originalPnpmHome = $env:PNPM_HOME
            $env:PNPM_HOME = Join-Path $TestDrive 'pnpm-home'
            $script:npmGlobalPrefix = Join-Path $TestDrive 'npm-prefix-for-broken-pnpm'
            $script:brokenPnpmPath = Join-Path $TestDrive 'broken-pnpm\pnpm.cmd'
            New-Item -Path $script:brokenPnpmPath -ItemType File -Force | Out-Null
            New-Item -Path (Join-Path $script:npmGlobalPrefix 'pnpm.cmd') -ItemType File -Force | Out-Null
            $script:pnpmVersionChecks = 0
            Mock Get-ExternalCommand {
                param($Name)
                if ($Name -eq 'pnpm') { return @{ Source = $script:brokenPnpmPath } }
                if ($Name -eq 'npm') { return @{ Source = 'C:\node-install\npm.cmd' } }
                return $null
            }
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains '--version') {
                    $script:pnpmVersionChecks++
                    if ($script:pnpmVersionChecks -eq 1) {
                        $global:LASTEXITCODE = $script:existingVersionExit
                        return $script:existingVersionOutput
                    }
                    $global:LASTEXITCODE = 0
                    return '12.6.0'
                }
                $global:LASTEXITCODE = 0
                return ''
            }
            Mock Invoke-Npm {
                param($Arguments)
                if ($Arguments -contains 'prefix') {
                    $global:LASTEXITCODE = 0
                    return $script:npmGlobalPrefix
                }
                $global:LASTEXITCODE = 0
                return 'added pnpm@latest'
            }
            Mock Invoke-NativeCommand { $global:LASTEXITCODE = 0; return '12.6.0' }
            Mock Get-JsonContent { return @{ globalPackages = @() } }
            Mock Get-UserEnvironmentPath { return '' }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }

            try {
                $result = $handler.Apply($ctx)

                $result.Success | Should -BeTrue
                Should -Invoke Invoke-Npm -Times 1 -ParameterFilter { $Arguments -contains 'pnpm@latest' }
                ($env:PATH -split ';')[0] | Should -Be $script:npmGlobalPrefix
            }
            finally {
                $env:PNPM_HOME = $script:originalPnpmHome
            }
        }
    }

    Context 'Apply - setup failure with a usable existing runtime' {
        It 'should continue when pnpm setup fails but the existing runtime remains usable' {
            $savedPnpmHome = $env:PNPM_HOME
            $env:PNPM_HOME = ''
            $existingPnpmPath = Join-Path $TestDrive 'existing-pnpm\pnpm.cmd'
            New-Item -Path $existingPnpmPath -ItemType File -Force | Out-Null

            Mock Get-ExternalCommand {
                param($Name)
                if ($Name -in @('pnpm.cmd', 'pnpm')) { return @{ Source = $existingPnpmPath } }
                return $null
            }
            Mock Get-ExternalCommandPath { return $existingPnpmPath }
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains 'setup') {
                    $global:LASTEXITCODE = 1
                    return 'ERR_PNPM_BAD_ENV_FOUND'
                }
                if ($Arguments -contains '--version') {
                    $global:LASTEXITCODE = 0
                    return '12.6.0'
                }
                $global:LASTEXITCODE = 0
                return ''
            }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent { return @{ globalPackages = @() } }
            Mock Write-Host { }

            try {
                $result = $handler.Apply($ctx)

                $result.Success | Should -BeTrue
                $result.Message | Should -Match '空'
            }
            finally {
                $env:PNPM_HOME = $savedPnpmHome
            }
        }
    }

    BeforeEach {
        $script:handler = [PnpmHandler]::new()
        Mock Update-NpmGlobalCommandPath { }
        Mock Test-Path {
            param($Path, $LiteralPath, $PathType)
            & $script:testPathCmdlet @PSBoundParameters
        }
        $script:ctx = [SetupContext]::new($script:projectRoot)
    }

    Context 'Constructor' {
        It 'should set <property> correctly' -ForEach @(
            @{ property = "Name"; expected = "Pnpm"; checkType = "Be" }
            @{ property = "Description"; expected = $null; checkType = "Not -BeNullOrEmpty" }
            @{ property = "Order"; expected = 7; checkType = "Be" }
            @{ property = "RequiresAdmin"; expected = $false; checkType = "Be" }
        ) {
            if ($checkType -eq "Be") {
                $handler.$property | Should -Be $expected
            }
            else {
                $handler.$property | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Package command timeout budgets' {
        BeforeEach {
            $script:savedInstallTimeout = $env:DOTFILES_INSTALL_TIMEOUT_SECONDS
            Remove-Item Env:\DOTFILES_INSTALL_TIMEOUT_SECONDS -ErrorAction SilentlyContinue
            Mock Invoke-VerifyCommand { $global:LASTEXITCODE = 0; return 'ok' }
            Mock Write-Host { }
        }
        AfterEach { $env:DOTFILES_INSTALL_TIMEOUT_SECONDS = $script:savedInstallTimeout }

        It 'should use the shared installation budget for post-install with no explicit timeout' {
            $handler.InvokePackagePostInstall(@{ command = 'playwright'; args = @('install', 'chromium') }) | Should -BeTrue
            Should -Invoke Invoke-VerifyCommand -Times 1 -ParameterFilter { $TimeoutSeconds -eq 3600 }
        }

        It 'should honor the install timeout environment override for post-install' {
            $env:DOTFILES_INSTALL_TIMEOUT_SECONDS = '73'
            $handler.InvokePackagePostInstall(@{ command = 'playwright'; args = @('install'); timeoutSeconds = 600 }) | Should -BeTrue
            Should -Invoke Invoke-VerifyCommand -Times 1 -ParameterFilter { $TimeoutSeconds -eq 73 }
        }

        It 'should preserve an explicitly longer verification timeout' {
            $handler.TestPackageVerification(@{ command = 'gemini'; args = @('--version'); timeoutSeconds = 240 }, '') | Should -BeTrue
            Should -Invoke Invoke-VerifyCommand -Times 1 -ParameterFilter { $TimeoutSeconds -eq 240 }
        }

        It 'should preserve explicit post-install metadata when the environment override is invalid' -ForEach @(
            @{ InvalidTimeout = 'invalid' }
            @{ InvalidTimeout = '2147483648' }
            @{ InvalidTimeout = '-1' }
        ) {
            $env:DOTFILES_INSTALL_TIMEOUT_SECONDS = $InvalidTimeout
            $handler.InvokePackagePostInstall(@{ command = 'playwright'; args = @('install'); timeoutSeconds = 7200 }) | Should -BeTrue
            Should -Invoke Invoke-VerifyCommand -Times 1 -ParameterFilter { $TimeoutSeconds -eq 7200 }
        }

        It 'should use the shared default without metadata when the environment override is malformed' {
            $env:DOTFILES_INSTALL_TIMEOUT_SECONDS = 'invalid'
            $handler.InvokePackagePostInstall(@{ command = 'playwright'; args = @('install') }) | Should -BeTrue
            Should -Invoke Invoke-VerifyCommand -Times 1 -ParameterFilter { $TimeoutSeconds -eq 3600 }
        }

        It 'should allow a valid zero environment override to disable the post-install timeout' {
            $env:DOTFILES_INSTALL_TIMEOUT_SECONDS = '0'
            $handler.InvokePackagePostInstall(@{ command = 'playwright'; args = @('install'); timeoutSeconds = 7200 }) | Should -BeTrue
            Should -Invoke Invoke-VerifyCommand -Times 1 -ParameterFilter { $TimeoutSeconds -eq 0 }
        }
    }

    Context 'CanApply - pnpm not found, npm is available' {
        BeforeEach {
            Mock Get-ExternalCommand {
                param($Name)
                if ($Name -eq "npm") { return @{ Source = "C:\npm.cmd" } }
                return $null
            }
            Mock Invoke-Corepack { $global:LASTEXITCODE = 1 }
            Mock Invoke-Npm { $global:LASTEXITCODE = 1 }
            Mock Write-Host { }
        }

        It 'should return true without bootstrapping' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
            Should -Invoke Invoke-Corepack -Times 0
            Should -Invoke Invoke-Npm -Times 0
        }
    }

    Context 'CanApply - pnpm not found, corepack is available' {
        BeforeEach {
            $script:callCount = 0
            Mock Get-ExternalCommand {
                param($Name)
                if ($Name -eq "pnpm") {
                    # 初回は null、bootstrap 後は見つかる
                    $script:callCount++
                    if ($script:callCount -le 1) { return $null }
                    return @{ Source = "C:\pnpm.cmd" }
                }
                if ($Name -eq "corepack") { return @{ Source = "C:\corepack.cmd" } }
                return $null
            }
            Mock Invoke-Corepack { $global:LASTEXITCODE = 0 }
            Mock Invoke-Pnpm {
                $global:LASTEXITCODE = 0
                return "9.15.0"
            }
            Mock Test-PathExist { return $true }
            Mock Write-Host { }
        }

        It 'should return true without bootstrapping' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
            Should -Invoke Invoke-Corepack -Times 0
        }
    }

    Context 'CanApply - pnpm not found, npm is available' {
        BeforeEach {
            Mock Get-ExternalCommand {
                param($Name)
                if ($Name -eq "pnpm") { return $null }
                if ($Name -eq "corepack") { return $null }
                if ($Name -eq "npm") { return @{ Source = "C:\npm.cmd" } }
                return $null
            }
            Mock Invoke-Npm { $global:LASTEXITCODE = 0 }
            Mock Invoke-Pnpm {
                $global:LASTEXITCODE = 0
                return "9.15.0"
            }
            Mock Test-PathExist { return $true }
            Mock Write-Host { }
        }

        It 'should return true without invoking installers' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
            Should -Invoke Invoke-Npm -Times 0
        }
    }

    Context 'CanApply - npm and corepack are available' {
        BeforeEach {
            Mock Get-ExternalCommand {
                param($Name)
                if ($Name -eq "pnpm") { return $null }
                if ($Name -eq "corepack") { return @{ Source = "C:\\corepack.cmd" } }
                if ($Name -eq "npm") { return @{ Source = "C:\\npm.cmd" } }
                return $null
            }
            Mock Invoke-Npm { $global:LASTEXITCODE = 0 }
            Mock Invoke-Corepack { throw "corepack should not be used when npm is available" }
            Mock Invoke-Pnpm {
                $global:LASTEXITCODE = 0
                return "10.0.0"
            }
            Mock Test-PathExist { return $true }
            Mock Write-Host { }
        }

        It 'should return true without invoking installers' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
            Should -Invoke Invoke-Npm -Times 0
            Should -Invoke Invoke-Corepack -Times 0
        }
    }

    Context 'CanApply - package file missing' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\pnpm.cmd" } }
            Mock Invoke-Pnpm {
                $global:LASTEXITCODE = 0
                return "9.15.0"
            }
            Mock Test-PathExist { return $false }
            Mock Write-Host { }
        }

        It 'should return false' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - all conditions met' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\pnpm.cmd" } }
            Mock Invoke-Pnpm {
                $global:LASTEXITCODE = 0
                return "9.15.0"
            }
            Mock Test-PathExist { return $true }
        }

        It 'should return true' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }
    }

    Context 'EnsurePnpmSetup - PNPM_HOME already set' {
        BeforeEach {
            $script:origPnpmHome = $env:PNPM_HOME
            $script:pnpmBin = Join-Path $TestDrive "pnpm-bin"
            $env:PNPM_HOME = $script:pnpmBin
            Mock Invoke-Pnpm { }
            Mock Write-Host { }
        }
        AfterEach {
            $env:PNPM_HOME = $script:origPnpmHome
        }

        It 'should return the bin directory without changing PNPM_HOME' {
            $result = $handler.EnsurePnpmSetup()
            $result | Should -Be (Join-Path $script:pnpmBin 'bin')
            $env:PNPM_HOME | Should -Be $script:pnpmBin
        }

        It 'should not call pnpm setup or pnpm bin' {
            $handler.EnsurePnpmSetup()
            Should -Invoke Invoke-Pnpm -Times 0
        }
    }

    Context 'EnsurePnpmSetup - PNPM_HOME unset, setup succeeds' {
        BeforeEach {
            $script:origPnpmHome = $env:PNPM_HOME
            $script:origRegistryPnpmHome = [System.Environment]::GetEnvironmentVariable('PNPM_HOME', 'User')
            $env:PNPM_HOME = ""
            [System.Environment]::SetEnvironmentVariable('PNPM_HOME', '', 'User')
            $script:pnpmBin = Join-Path $TestDrive "pnpm-bin-after-setup"
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "setup") {
                    # pnpm setup がレジストリに PNPM_HOME を設定する動作をシミュレート
                    [System.Environment]::SetEnvironmentVariable('PNPM_HOME', $script:pnpmBin, 'User')
                    $global:LASTEXITCODE = 0
                    return ""
                }
                $global:LASTEXITCODE = 0
                return ""
            }
            Mock Write-Host { }
        }
        AfterEach {
            $env:PNPM_HOME = $script:origPnpmHome
            [System.Environment]::SetEnvironmentVariable('PNPM_HOME', $script:origRegistryPnpmHome, 'User')
        }

        It 'should call pnpm setup' {
            $handler.EnsurePnpmSetup()
            Should -Invoke Invoke-Pnpm -ParameterFilter { $Arguments -contains "setup" } -Times 1
        }

        It 'should return the bin directory under PNPM_HOME set by pnpm setup' {
            $result = $handler.EnsurePnpmSetup()
            $result | Should -Be (Join-Path $script:pnpmBin 'bin')
        }

        It 'should set PNPM_HOME for current process' {
            $handler.EnsurePnpmSetup()
            $env:PNPM_HOME | Should -Be $script:pnpmBin
        }
    }

    Context 'EnsurePnpmSetup - PNPM_HOME unset, setup fails' {
        BeforeEach {
            $script:origPnpmHome = $env:PNPM_HOME
            $script:origRegistryPnpmHome = [System.Environment]::GetEnvironmentVariable('PNPM_HOME', 'User')
            $env:PNPM_HOME = ""
            [System.Environment]::SetEnvironmentVariable('PNPM_HOME', '', 'User')
            Mock Invoke-Pnpm {
                $global:LASTEXITCODE = 1
                return ""
            }
            Mock Write-Host { }
        }
        AfterEach {
            $env:PNPM_HOME = $script:origPnpmHome
            [System.Environment]::SetEnvironmentVariable('PNPM_HOME', $script:origRegistryPnpmHome, 'User')
        }

        It 'should return null' {
            $result = $handler.EnsurePnpmSetup()
            $result | Should -BeNullOrEmpty
        }

        It 'should not throw' {
            { $handler.EnsurePnpmSetup() } | Should -Not -Throw
        }

        It 'should report setup diagnostics but continue when the existing runtime remains usable' {
            $script:setupLogs = @()
            Mock Get-ExternalCommand { return @{ Source = 'C:\pnpm.cmd' } }
            Mock Write-Host { $script:setupLogs += [string]$Object }
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains 'setup') {
                    $global:LASTEXITCODE = 1
                    return 'ERR_PNPM_BAD_ENVIRONMENT setup failed'
                }
                $global:LASTEXITCODE = 0
                return '12.6.0'
            }
            Mock Get-JsonContent { return @{ globalPackages = @('example-package') } }

            $result = $handler.Apply($ctx)

            $result.Success | Should -BeTrue
            ($script:setupLogs -join "`n") | Should -Match 'ERR_PNPM_BAD_ENVIRONMENT setup failed'
            ($script:setupLogs -join "`n") | Should -Match 'exited with code 1'
            Should -Invoke Invoke-Pnpm -Times 1 -ParameterFilter { $Arguments -contains 'add' }
        }
    }

    Context 'EnsurePnpmSetup - PNPM_HOME restored from registry' {
        BeforeEach {
            $script:origPnpmHome = $env:PNPM_HOME
            $script:origRegistryPnpmHome = [System.Environment]::GetEnvironmentVariable('PNPM_HOME', 'User')
            $env:PNPM_HOME = ""
            $script:pnpmBin = Join-Path $TestDrive "pnpm-restored"
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "bin") {
                    $global:LASTEXITCODE = 0
                    return $script:pnpmBin
                }
                $global:LASTEXITCODE = 0
                return ""
            }
            Mock Write-Host { }
            # [System.Environment]::GetEnvironmentVariable をモック不可のため、
            # 実際のレジストリ値を一時的にセットしてテスト
            [System.Environment]::SetEnvironmentVariable('PNPM_HOME', $script:pnpmBin, 'User')
        }
        AfterEach {
            $env:PNPM_HOME = $script:origPnpmHome
            [System.Environment]::SetEnvironmentVariable('PNPM_HOME', $script:origRegistryPnpmHome, 'User')
        }

        It 'should restore PNPM_HOME from registry when env is empty' {
            $handler.EnsurePnpmSetup()
            $env:PNPM_HOME | Should -Be $script:pnpmBin
        }

        It 'should not call pnpm setup when bin path is available after restore' {
            $handler.EnsurePnpmSetup()
            Should -Invoke Invoke-Pnpm -ParameterFilter { $Arguments -contains "setup" } -Times 0
        }
    }

    Context 'AddPnpmBinToPath - empty bin path' {
        BeforeEach {
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }

        It 'should do nothing without throwing' {
            { $handler.AddPnpmBinToPath("") } | Should -Not -Throw
        }

        It 'should not call Set-UserEnvironmentPath' {
            $handler.AddPnpmBinToPath("")
            Should -Invoke Set-UserEnvironmentPath -Times 0
        }
    }

    Context 'AddPnpmBinToPath - already in user PATH' {
        BeforeEach {
            $script:pnpmBin = Join-Path $TestDrive "pnpm-global-bin"
            $script:pnpmBinChild = Join-Path $script:pnpmBin "bin"
            New-Item $script:pnpmBin -ItemType Directory -Force | Out-Null
            New-Item $script:pnpmBinChild -ItemType Directory -Force | Out-Null
            $script:origPath = $env:PATH
            $env:PATH = "C:\Windows\System32"
            Mock Get-UserEnvironmentPath { return "$script:pnpmBin;$script:pnpmBinChild" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }
        AfterEach {
            $env:PATH = $script:origPath
        }

        It 'should not call Set-UserEnvironmentPath' {
            $handler.AddPnpmBinToPath($script:pnpmBin)
            Should -Invoke Set-UserEnvironmentPath -Times 0
        }

        It 'should add bin path to current process PATH' {
            $handler.AddPnpmBinToPath($script:pnpmBin)
            $env:PATH -split ";" | Should -Contain $script:pnpmBin
            $env:PATH -split ";" | Should -Not -Contain $script:pnpmBinChild
        }
    }

    Context 'AddPnpmBinToPath - not yet in user PATH or process PATH' {
        BeforeEach {
            $script:pnpmBin = Join-Path $TestDrive "pnpm-global-bin"
            New-Item $script:pnpmBin -ItemType Directory -Force | Out-Null
            $script:origPath = $env:PATH
            $env:PATH = "C:\Windows\System32"
            Mock Get-UserEnvironmentPath { return "C:\Windows\System32" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }
        AfterEach {
            $env:PATH = $script:origPath
        }

        It 'should call Set-UserEnvironmentPath once' {
            $handler.AddPnpmBinToPath($script:pnpmBin)
            Should -Invoke Set-UserEnvironmentPath -Times 1
        }

        It 'should add bin path to current process PATH' {
            $handler.AddPnpmBinToPath($script:pnpmBin)
            $env:PATH -split ";" | Should -Contain $script:pnpmBin
            $env:PATH -split ";" | Should -Not -Contain (Join-Path $script:pnpmBin "bin")
            Test-Path -LiteralPath (Join-Path $script:pnpmBin 'bin') | Should -BeFalse
        }
    }

    Context 'IsPackageInstalled - package exists' {
        BeforeEach {
            $script:globalRoot = Join-Path $TestDrive "pnpm-global\node_modules"
            New-Item (Join-Path $script:globalRoot "typescript") -ItemType Directory -Force | Out-Null
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "root") {
                    $global:LASTEXITCODE = 0
                    return $script:globalRoot
                }
                $global:LASTEXITCODE = 0
                return ""
            }
        }

        It 'should return true for installed package' {
            $result = $handler.IsPackageInstalled("typescript")
            $result | Should -Be $true
        }
    }

    Context 'IsPackageInstalled - package not installed' {
        BeforeEach {
            $script:globalRoot = Join-Path $TestDrive "pnpm-global\node_modules"
            New-Item $script:globalRoot -ItemType Directory -Force | Out-Null
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "root") {
                    $global:LASTEXITCODE = 0
                    return $script:globalRoot
                }
                $global:LASTEXITCODE = 0
                return ""
            }
        }

        It 'should return false for missing package' {
            $result = $handler.IsPackageInstalled("nonexistent-pkg")
            $result | Should -Be $false
        }
    }

    Context 'IsPackageInstalled - 2-arg overload with pre-computed root' {
        BeforeEach {
            $script:globalRoot = Join-Path $TestDrive "pnpm-global\node_modules"
            New-Item (Join-Path $script:globalRoot "typescript") -ItemType Directory -Force | Out-Null
            Mock Invoke-Pnpm { $global:LASTEXITCODE = 0; return "" }
        }

        It 'should return true when package directory exists under given root' {
            $result = $handler.IsPackageInstalled("typescript", $script:globalRoot)
            $result | Should -Be $true
        }

        It 'should return false when package directory does not exist' {
            $result = $handler.IsPackageInstalled("nonexistent-pkg", $script:globalRoot)
            $result | Should -Be $false
        }

        It 'should return false when root is empty' {
            $result = $handler.IsPackageInstalled("typescript", "")
            $result | Should -Be $false
        }

        It 'should not call pnpm when root is provided' {
            $handler.IsPackageInstalled("typescript", $script:globalRoot)
            Should -Invoke Invoke-Pnpm -Times 0
        }
    }

    Context 'pkgName version stripping regex' {
        It 'should strip simple version suffix' {
            $pkgName = "typescript@5.0.0" -replace '(?<=.)@[^\s@]+$', ''
            $pkgName | Should -Be "typescript"
        }

        It 'should strip pre-release version suffix' {
            $pkgName = "typescript@5.0.0-beta.1" -replace '(?<=.)@[^\s@]+$', ''
            $pkgName | Should -Be "typescript"
        }

        It 'should strip dist-tag specifier (@latest, @next)' {
            $pkgName = "typescript@latest" -replace '(?<=.)@[^\s@]+$', ''
            $pkgName | Should -Be "typescript"
        }

        It 'should preserve scoped package name without version' {
            $pkgName = "@google/gemini-cli" -replace '(?<=.)@[^\s@]+$', ''
            $pkgName | Should -Be "@google/gemini-cli"
        }

        It 'should strip version from scoped package' {
            $pkgName = "@google/gemini-cli@1.0.0" -replace '(?<=.)@[^\s@]+$', ''
            $pkgName | Should -Be "@google/gemini-cli"
        }

        It 'should strip dist-tag from scoped package' {
            $pkgName = "@google/gemini-cli@latest" -replace '(?<=.)@[^\s@]+$', ''
            $pkgName | Should -Be "@google/gemini-cli"
        }

        It 'should leave bare package name unchanged' {
            $pkgName = "typescript" -replace '(?<=.)@[^\s@]+$', ''
            $pkgName | Should -Be "typescript"
        }
    }

    Context 'IsPackageInstalled - scoped package path resolution' {
        BeforeEach {
            $script:globalRoot = Join-Path $TestDrive "pnpm-global\node_modules"
            # pnpm は Windows でスコープ付きパッケージを @org\pkg として配置する
            New-Item (Join-Path $script:globalRoot "@google\gemini-cli") -ItemType Directory -Force | Out-Null
            Mock Invoke-Pnpm { $global:LASTEXITCODE = 0; return "" }
        }

        It 'should find scoped package when directory exists (Join-Path normalizes forward slash)' {
            # pkgName は "@google/gemini-cli" (forward slash)
            # Join-Path が Windows で \ に正規化するため正しく検出される
            $result = $handler.IsPackageInstalled("@google/gemini-cli", $script:globalRoot)
            $result | Should -Be $true
        }

        It 'should return false for missing scoped package' {
            $result = $handler.IsPackageInstalled("@google/missing-pkg", $script:globalRoot)
            $result | Should -Be $false
        }
    }

    Context 'Apply - packages already installed (skip via 2-arg root check)' {
        BeforeEach {
            $script:origPath = $env:PATH
            $script:pnpmBin = Join-Path $TestDrive "pnpm-bin"
            New-Item $script:pnpmBin -ItemType Directory -Force | Out-Null
            $script:globalRoot = Join-Path $TestDrive "pnpm-global\node_modules"
            New-Item (Join-Path $script:globalRoot "@google\gemini-cli") -ItemType Directory -Force | Out-Null
            New-Item (Join-Path $script:globalRoot "typescript") -ItemType Directory -Force | Out-Null
            Mock Get-ExternalCommand { return @{ Source = "C:\pnpm.cmd" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return @{
                    globalPackages = @(
                        @{ name = "@google/gemini-cli"; verifyCommand = @{ command = "gemini"; args = @("--version") } },
                        @{ name = "typescript" }
                    )
                }
            }
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "root") { $global:LASTEXITCODE = 0; return $script:globalRoot }
                if ($Arguments -contains "outdated") {
                    $global:LASTEXITCODE = 0
                    return '{"@google/gemini-cli":{"current":"1.0.0","latest":"1.1.0"},"typescript":{"current":"5.0.0","latest":"5.1.0"}}'
                }
                if ($Arguments -contains "bin") { $global:LASTEXITCODE = 0; return $script:pnpmBin }
                $global:LASTEXITCODE = 0; return ""
            }
            Mock Write-Host { }
            Mock Get-UserEnvironmentPath { return $script:pnpmBin }
            Mock Set-UserEnvironmentPath { }
            Mock Invoke-VerifyCommand { $global:LASTEXITCODE = 0; return "1.0.0" }
        }
        AfterEach { $env:PATH = $script:origPath }

        It 'should update installed packages reported as outdated' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個検証済み"
            $result.Message | Should -Match "2 個インストール"
        }

        It 'should call pnpm add for installed outdated packages' {
            $handler.Apply($ctx)
            Should -Invoke Invoke-Pnpm -ParameterFilter { $Arguments -contains "add" } -Times 2
        }
    }

    Context 'Apply - installed package verification fails' {
        BeforeEach {
            $script:origPath = $env:PATH
            $script:verifyCalls = 0
            $script:pnpmBin = Join-Path $TestDrive "pnpm-bin"
            New-Item $script:pnpmBin -ItemType Directory -Force | Out-Null
            $script:globalRoot = Join-Path $TestDrive "pnpm-global\node_modules"
            New-Item (Join-Path $script:globalRoot "broken-pkg") -ItemType Directory -Force | Out-Null
            Mock Get-ExternalCommand { return @{ Source = "C:\pnpm.cmd" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return @{
                    globalPackages = @(
                        @{ name = "broken-pkg"; verifyCommand = @{ command = "broken"; args = @("--version") } }
                    )
                }
            }
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "root") { $global:LASTEXITCODE = 0; return $script:globalRoot }
                if ($Arguments -contains "bin") { $global:LASTEXITCODE = 0; return $script:pnpmBin }
                if ($Arguments -contains "add") { $global:LASTEXITCODE = 0; return "installed" }
                $global:LASTEXITCODE = 0; return ""
            }
            Mock Invoke-VerifyCommand {
                $script:verifyCalls++
                if ($script:verifyCalls -eq 1) {
                    $global:LASTEXITCODE = 1
                    throw "broken"
                }
                $global:LASTEXITCODE = 0
                return "1.0.0"
            }
            Mock Write-Host { }
            Mock Get-UserEnvironmentPath { return $script:pnpmBin }
            Mock Set-UserEnvironmentPath { }
        }
        AfterEach { $env:PATH = $script:origPath }

        It 'should reinstall when installed package verification fails' {
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個インストール"
            Should -Invoke Invoke-Pnpm -ParameterFilter { $Arguments -contains "add" } -Times 1
            Should -Invoke Invoke-VerifyCommand -Times 2
        }
    }

    Context 'Apply - update failure with a verified existing package' {
        BeforeEach {
            $script:originalPnpmHome = $env:PNPM_HOME
            $script:pnpmHome = Join-Path $TestDrive 'pnpm-home-preserve'
            $script:pnpmBin = Join-Path $script:pnpmHome 'bin'
            $script:globalRoot = Join-Path $TestDrive 'pnpm-global-preserve\node_modules'
            New-Item -Path $script:pnpmBin -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path $script:globalRoot 'existing-pkg') -ItemType Directory -Force | Out-Null
            $env:PNPM_HOME = $script:pnpmHome

            Mock Get-ExternalCommand { return @{ Source = 'C:\pnpm.cmd' } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return @{
                    globalPackages = @(
                        @{ name = 'existing-pkg'; verifyCommand = @{ command = 'existing'; args = @('--version') } }
                    )
                }
            }
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains 'root') {
                    $global:LASTEXITCODE = 0
                    return $script:globalRoot
                }
                if ($Arguments -contains 'outdated') {
                    $global:LASTEXITCODE = 0
                    return '{"existing-pkg":{"current":"1.0.0","latest":"2.0.0"}}'
                }
                if ($Arguments -contains 'bin') {
                    $global:LASTEXITCODE = 0
                    return $script:pnpmBin
                }
                if ($Arguments -contains '--version') {
                    $global:LASTEXITCODE = 0
                    return '12.6.0'
                }
                if ($Arguments -contains 'add') {
                    $global:LASTEXITCODE = 1
                    return 'network failure'
                }
                $global:LASTEXITCODE = 0
                return ''
            }
            Mock Invoke-VerifyCommand { $global:LASTEXITCODE = 0; return 'existing 1.0.0' }
            Mock Get-UserEnvironmentPath { return $script:pnpmBin }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }

        AfterEach {
            $env:PNPM_HOME = $script:originalPnpmHome
        }

        It 'should preserve the existing package when its update fails' {
            $result = $handler.Apply($ctx)

            $result.Success | Should -BeTrue
            $result.Message | Should -Match '1 個更新失敗（既存を維持）'
            Should -Invoke Invoke-VerifyCommand -Times 2
        }
    }

    Context 'Apply - pnpm root fails (installs all packages)' {
        BeforeEach {
            $script:origPath = $env:PATH
            $script:pnpmBin = Join-Path $TestDrive "pnpm-bin"
            New-Item $script:pnpmBin -ItemType Directory -Force | Out-Null
            Mock Get-ExternalCommand { return @{ Source = "C:\pnpm.cmd" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return @{
                    globalPackages = @(
                        @{ name = "pkg-a" },
                        @{ name = "pkg-b" }
                    )
                }
            }
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "root") { $global:LASTEXITCODE = 1; return "" }
                if ($Arguments -contains "bin") { $global:LASTEXITCODE = 0; return $script:pnpmBin }
                if ($Arguments -contains "add") { $global:LASTEXITCODE = 0; return "installed" }
                $global:LASTEXITCODE = 0; return ""
            }
            Mock Invoke-VerifyCommand { }
            Mock Write-Host { }
            Mock Get-UserEnvironmentPath { return $script:pnpmBin }
            Mock Set-UserEnvironmentPath { }
        }
        AfterEach { $env:PATH = $script:origPath }

        It 'should attempt to install all packages when root check fails' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            Should -Invoke Invoke-Pnpm -ParameterFilter { $Arguments -contains "add" } -Times 2
        }
    }

    Context 'Apply - all new packages' {
        BeforeEach {
            $script:origPath = $env:PATH
            $script:pnpmBin = Join-Path $TestDrive "pnpm-bin"
            New-Item $script:pnpmBin -ItemType Directory -Force | Out-Null
            Mock Get-ExternalCommand { return @{ Source = "C:\pnpm.cmd" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return @{
                    globalPackages = @(
                        @{ name = "@google/gemini-cli"; verifyCommand = @{ command = "gemini"; args = @("--version") } },
                        @{ name = "typescript" }
                    )
                }
            }
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "root") {
                    $global:LASTEXITCODE = 0
                    return (Join-Path $TestDrive "nonexistent-root")
                }
                if ($Arguments -contains "bin") {
                    $global:LASTEXITCODE = 0
                    return $script:pnpmBin
                }
                $global:LASTEXITCODE = 0
                return "installed"
            }
            Mock Test-Path { return $false } -ParameterFilter {
                ($LiteralPath -and $LiteralPath -like '*nonexistent-root*')
            }
            Mock Invoke-VerifyCommand { $global:LASTEXITCODE = 0; return "1.0.0" }
            Mock Write-Host { }
            Mock Get-UserEnvironmentPath { return $script:pnpmBin }
            Mock Set-UserEnvironmentPath { }
        }
        AfterEach {
            $env:PATH = $script:origPath
        }

        It 'should return success result' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "2 個インストール"
        }

        It 'should stream pnpm install output to the CLI' {
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "root") {
                    $global:LASTEXITCODE = 0
                    return (Join-Path $TestDrive "nonexistent-root")
                }
                if ($Arguments -contains "bin") {
                    $global:LASTEXITCODE = 0
                    return $script:pnpmBin
                }
                if ($Arguments -contains "add") {
                    $global:LASTEXITCODE = 0
                    return @("Progress: resolved 1", "Done in 1s")
                }
                $global:LASTEXITCODE = 0
                return ""
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            Should -Invoke Write-Host -ParameterFilter {
                $ForegroundColor -eq "Gray" -and ([string]$Object) -match "Progress: resolved 1"
            } -Times 2
            Should -Invoke Write-Host -ParameterFilter {
                $ForegroundColor -eq "Gray" -and ([string]$Object) -match "Done in 1s"
            } -Times 2
        }

        It 'should install every configured Windows pnpm tool' {
            $script:addCalls = @()
            Mock Get-JsonContent {
                return @{
                    globalPackages = @(
                        @{ name = "@prisma/language-server" },
                        @{ name = "@agentclientprotocol/claude-agent-acp" },
                        @{ name = "typescript-language-server" },
                        @{
                            name        = "@google/gemini-cli"
                            installArgs = @("--allow-build=@github/keytar")
                        }
                    )
                }
            }
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "root") {
                    $global:LASTEXITCODE = 0
                    return (Join-Path $TestDrive "nonexistent-root")
                }
                if ($Arguments -contains "bin") {
                    $global:LASTEXITCODE = 0
                    return $script:pnpmBin
                }
                if ($Arguments -contains "add") {
                    $script:addCalls += , @($Arguments)
                    $global:LASTEXITCODE = 0
                    return "installed"
                }
                $global:LASTEXITCODE = 0
                return ""
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $script:addCalls.Count | Should -Be 4
            ($script:addCalls | ForEach-Object { $_ -join " " }) -join "`n" | Should -Match "@prisma/language-server"
            ($script:addCalls | ForEach-Object { $_ -join " " }) -join "`n" | Should -Match "@agentclientprotocol/claude-agent-acp"
            ($script:addCalls | ForEach-Object { $_ -join " " }) -join "`n" | Should -Match "typescript-language-server"
            ($script:addCalls | ForEach-Object { $_ -join " " }) -join "`n" | Should -Match "@google/gemini-cli"
            foreach ($call in $script:addCalls) {
                $call | Should -Contain "--reporter=append-only"
                $call | Should -Contain "--yes"
                $call | Should -Not -Contain "timeout"
            }
            $geminiCall = $script:addCalls | Where-Object { $_ -contains "@google/gemini-cli" } | Select-Object -First 1
            $geminiCall | Should -Contain "--allow-build=@github/keytar"
            $geminiCall | Should -Not -Contain "--allow-build=node-pty"
        }
    }

    Context 'Apply - empty package list' {
        BeforeEach {
            $script:origPath = $env:PATH
            $script:pnpmBin = Join-Path $TestDrive "pnpm-bin"
            New-Item $script:pnpmBin -ItemType Directory -Force | Out-Null
            Mock Get-ExternalCommand { return @{ Source = "C:\pnpm.cmd" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return @{
                    globalPackages = @()
                }
            }
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "bin") {
                    $global:LASTEXITCODE = 0
                    return $script:pnpmBin
                }
                $global:LASTEXITCODE = 0
                return ""
            }
            Mock Write-Host { }
            Mock Get-UserEnvironmentPath { return $script:pnpmBin }
            Mock Set-UserEnvironmentPath { }
        }
        AfterEach {
            $env:PATH = $script:origPath
        }

        It 'should return success with empty message' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "空"
        }
    }

    Context 'Apply - partial install failure' {
        BeforeEach {
            $script:origPath = $env:PATH
            $script:pnpmBin = Join-Path $TestDrive "pnpm-bin"
            New-Item $script:pnpmBin -ItemType Directory -Force | Out-Null
            Mock Get-ExternalCommand { return @{ Source = "C:\pnpm.cmd" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return @{
                    globalPackages = @(
                        @{ name = "good-pkg" },
                        @{ name = "bad-pkg" }
                    )
                }
            }
            $script:installCount = 0
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "root") {
                    $global:LASTEXITCODE = 0
                    return (Join-Path $TestDrive "nonexistent-root")
                }
                if ($Arguments -contains "bin") {
                    $global:LASTEXITCODE = 0
                    return $script:pnpmBin
                }
                if ($Arguments -contains "add") {
                    $script:installCount++
                    if ($Arguments -contains "bad-pkg") {
                        $global:LASTEXITCODE = 1
                        return ""
                    }
                    $global:LASTEXITCODE = 0
                    return "installed"
                }
                $global:LASTEXITCODE = 0
                return ""
            }
            Mock Test-Path { return $false } -ParameterFilter {
                ($LiteralPath -and $LiteralPath -like '*nonexistent-root*')
            }
            Mock Invoke-VerifyCommand { }
            Mock Write-Host { }
            Mock Get-UserEnvironmentPath { return $script:pnpmBin }
            Mock Set-UserEnvironmentPath { }
        }
        AfterEach {
            $env:PATH = $script:origPath
        }

        It 'should return failure with mixed success/failure counts' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $false
            $result.Message | Should -Match "1 個インストール"
            $result.Message | Should -Match "1 個失敗"
        }
    }

    Context 'Apply - exception thrown' {
        BeforeEach {
            $script:origPath = $env:PATH
            $script:pnpmBin = Join-Path $TestDrive "pnpm-bin"
            New-Item $script:pnpmBin -ItemType Directory -Force | Out-Null
            Mock Get-ExternalCommand { return @{ Source = "C:\pnpm.cmd" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent { throw "pnpm error" }
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "bin") {
                    $global:LASTEXITCODE = 0
                    return $script:pnpmBin
                }
                $global:LASTEXITCODE = 0
                return ""
            }
            Mock Write-Host { }
            Mock Get-UserEnvironmentPath { return $script:pnpmBin }
            Mock Set-UserEnvironmentPath { }
        }
        AfterEach {
            $env:PATH = $script:origPath
        }

        It 'should return failure result' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $false
            $result.Message | Should -Match "pnpm error"
        }
    }

    Context 'Apply - verifyCommand succeeds' {
        BeforeEach {
            $script:origPath = $env:PATH
            $script:pnpmBin = Join-Path $TestDrive "pnpm-bin"
            New-Item $script:pnpmBin -ItemType Directory -Force | Out-Null
            Mock Get-ExternalCommand { return @{ Source = "C:\pnpm.cmd" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return @{
                    globalPackages = @(
                        @{
                            name          = "pkg-with-verify"
                            installArgs   = @("--allow-build", "native-addon")
                            verifyCommand = @{ command = "pkg-cmd"; args = @("--version") }
                        }
                    )
                }
            }
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "root") {
                    $global:LASTEXITCODE = 0
                    return (Join-Path $TestDrive "nonexistent-root")
                }
                if ($Arguments -contains "bin") { $global:LASTEXITCODE = 0; return $script:pnpmBin }
                if ($Arguments -contains "add") { $global:LASTEXITCODE = 0; return "installed" }
                $global:LASTEXITCODE = 0; return ""
            }
            Mock Test-Path { return $false } -ParameterFilter {
                ($LiteralPath -and $LiteralPath -like '*nonexistent-root*')
            }
            Mock Invoke-VerifyCommand { $global:LASTEXITCODE = 0; return "1.0.0" }
            Mock Write-Host { }
            Mock Get-UserEnvironmentPath { return $script:pnpmBin }
            Mock Set-UserEnvironmentPath { }
        }
        AfterEach { $env:PATH = $script:origPath }

        It 'should count as installed when verify succeeds' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個インストール"
            $result.Message | Should -Not -Match "検証失敗"
        }

        It 'should call Invoke-VerifyCommand with correct args' {
            $handler.Apply($ctx)
            Should -Invoke Invoke-VerifyCommand -Times 1 -ParameterFilter {
                $Command -eq "pkg-cmd" -and $Arguments -contains "--version" -and $TimeoutSeconds -eq 120
            }
        }

        It 'should log verify command before running it' {
            $handler.Apply($ctx)
            Should -Invoke Write-Host -ParameterFilter {
                $ForegroundColor -eq "Gray" -and ([string]$Object) -match "検証中: pkg-cmd --version"
            } -Times 1
        }

        It 'should pass package installArgs to pnpm add' {
            $handler.Apply($ctx)
            Should -Invoke Invoke-Pnpm -ParameterFilter {
                $Arguments -contains "add" -and
                $Arguments -contains "--allow-build" -and
                $Arguments -contains "native-addon"
            } -Times 1
        }
    }

    Context 'Apply - postInstallCommand succeeds' {
        BeforeEach {
            $script:origPath = $env:PATH
            $script:pnpmBin = Join-Path $TestDrive "pnpm-bin"
            New-Item $script:pnpmBin -ItemType Directory -Force | Out-Null
            Mock Get-ExternalCommand { return @{ Source = "C:\pnpm.cmd" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return @{
                    globalPackages = @(
                        @{
                            name               = "playwright@1.63.0"
                            postInstallCommand = @{
                                command        = "playwright"
                                args           = @("install", "chromium")
                                timeoutSeconds = 600
                            }
                            verifyCommand      = @{ command = "playwright"; args = @("--version") }
                        }
                    )
                }
            }
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "root") {
                    $global:LASTEXITCODE = 0
                    return (Join-Path $TestDrive "nonexistent-root")
                }
                if ($Arguments -contains "bin") { $global:LASTEXITCODE = 0; return $script:pnpmBin }
                if ($Arguments -contains "add") { $global:LASTEXITCODE = 0; return "installed" }
                $global:LASTEXITCODE = 0; return ""
            }
            Mock Test-Path { return $false } -ParameterFilter {
                ($LiteralPath -and $LiteralPath -like '*nonexistent-root*')
            }
            Mock Invoke-VerifyCommand {
                param($Command, $Arguments, $TimeoutSeconds)
                $null = $Command
                $null = $TimeoutSeconds
                $global:LASTEXITCODE = 0
                if ($Arguments -contains "install") { return "Chromium installed" }
                return "1.0.0"
            }
            Mock Write-Host { }
            Mock Get-UserEnvironmentPath { return $script:pnpmBin }
            Mock Set-UserEnvironmentPath { }
        }
        AfterEach { $env:PATH = $script:origPath }

        It 'should run post-install before verification' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個インストール"
            $result.Message | Should -Not -Match "post-install失敗"
            Should -Invoke Invoke-VerifyCommand -ParameterFilter {
                $Command -eq "playwright" -and
                $Arguments -contains "install" -and
                $Arguments -contains "chromium" -and
                $TimeoutSeconds -eq 600
            } -Times 1
            Should -Invoke Invoke-VerifyCommand -ParameterFilter {
                $Command -eq "playwright" -and
                $Arguments -contains "--version" -and
                $TimeoutSeconds -eq 120
            } -Times 1
            Should -Invoke Write-Host -ParameterFilter {
                $ForegroundColor -eq "Gray" -and ([string]$Object) -match "post-install 実行中: playwright install chromium"
            } -Times 1
        }
    }

    Context 'Apply - postInstallCommand fails' {
        BeforeEach {
            $script:origPath = $env:PATH
            $script:pnpmBin = Join-Path $TestDrive "pnpm-bin"
            New-Item $script:pnpmBin -ItemType Directory -Force | Out-Null
            Mock Get-ExternalCommand { return @{ Source = "C:\pnpm.cmd" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return @{
                    globalPackages = @(
                        @{
                            name               = "playwright@1.63.0"
                            postInstallCommand = @{
                                command        = "playwright"
                                args           = @("install", "chromium")
                                timeoutSeconds = 600
                            }
                            verifyCommand      = @{ command = "playwright"; args = @("--version") }
                        }
                    )
                }
            }
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "root") {
                    $global:LASTEXITCODE = 0
                    return (Join-Path $TestDrive "nonexistent-root")
                }
                if ($Arguments -contains "bin") { $global:LASTEXITCODE = 0; return $script:pnpmBin }
                if ($Arguments -contains "add") { $global:LASTEXITCODE = 0; return "installed" }
                $global:LASTEXITCODE = 0; return ""
            }
            Mock Test-Path { return $false } -ParameterFilter {
                ($LiteralPath -and $LiteralPath -like '*nonexistent-root*')
            }
            Mock Invoke-VerifyCommand {
                param($Command, $Arguments, $TimeoutSeconds)
                $null = $Command
                $null = $TimeoutSeconds
                if ($Arguments -contains "install") {
                    $global:LASTEXITCODE = 1
                    throw "download failed"
                }
                $global:LASTEXITCODE = 0
                return "1.0.0"
            }
            Mock Write-Host { }
            Mock Get-UserEnvironmentPath { return $script:pnpmBin }
            Mock Set-UserEnvironmentPath { }
        }
        AfterEach { $env:PATH = $script:origPath }

        It 'should fail without running verification' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $false
            $result.Message | Should -Match "1 個post-install失敗"
            $result.Message | Should -Not -Match "1 個インストール"
            Should -Invoke Invoke-VerifyCommand -ParameterFilter {
                $Command -eq "playwright" -and $Arguments -contains "--version"
            } -Times 0
        }
    }

    Context 'Apply - verifyCommand fails' {
        BeforeEach {
            $script:origPath = $env:PATH
            $script:pnpmBin = Join-Path $TestDrive "pnpm-bin"
            New-Item $script:pnpmBin -ItemType Directory -Force | Out-Null
            Mock Get-ExternalCommand { return @{ Source = "C:\pnpm.cmd" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return @{
                    globalPackages = @(
                        @{ name = "native-pkg"; verifyCommand = @{ command = "native-cmd"; args = @("status") } }
                    )
                }
            }
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "root") {
                    $global:LASTEXITCODE = 0
                    return (Join-Path $TestDrive "nonexistent-root")
                }
                if ($Arguments -contains "bin") { $global:LASTEXITCODE = 0; return $script:pnpmBin }
                if ($Arguments -contains "add") { $global:LASTEXITCODE = 0; return "installed" }
                $global:LASTEXITCODE = 0; return ""
            }
            Mock Test-Path { return $false } -ParameterFilter {
                ($LiteralPath -and $LiteralPath -like '*nonexistent-root*')
            }
            Mock Invoke-VerifyCommand { $global:LASTEXITCODE = 1; throw "binding not found" }
            Mock Write-Host { }
            Mock Get-UserEnvironmentPath { return $script:pnpmBin }
            Mock Set-UserEnvironmentPath { }
        }
        AfterEach { $env:PATH = $script:origPath }

        It 'should return failure and count as verify failed' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $false
            $result.Message | Should -Match "1 個検証失敗"
            $result.Message | Should -Not -Match "1 個インストール"
        }
    }

    Context 'Apply - verifyCommand timeout' {
        BeforeEach {
            $script:origPath = $env:PATH
            $script:pnpmBin = Join-Path $TestDrive "pnpm-bin"
            New-Item $script:pnpmBin -ItemType Directory -Force | Out-Null
            Mock Get-ExternalCommand { return @{ Source = "C:\pnpm.cmd" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return @{
                    globalPackages = @(
                        @{ name = "@agentclientprotocol/claude-agent-acp"; verifyCommand = @{ command = "claude-agent-acp"; args = @("--version") } }
                    )
                }
            }
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "root") {
                    $global:LASTEXITCODE = 0
                    return (Join-Path $TestDrive "nonexistent-root")
                }
                if ($Arguments -contains "bin") { $global:LASTEXITCODE = 0; return $script:pnpmBin }
                if ($Arguments -contains "add") { $global:LASTEXITCODE = 0; return "installed" }
                $global:LASTEXITCODE = 0; return ""
            }
            Mock Test-Path { return $false } -ParameterFilter {
                ($LiteralPath -and $LiteralPath -like '*nonexistent-root*')
            }
            Mock Invoke-VerifyCommand {
                $global:LASTEXITCODE = 124
                return "検証コマンドがタイムアウトしました (30s): claude-agent-acp --version"
            }
            Mock Write-Host { }
            Mock Get-UserEnvironmentPath { return $script:pnpmBin }
            Mock Set-UserEnvironmentPath { }
        }
        AfterEach { $env:PATH = $script:origPath }

        It 'should fail verification clearly instead of hanging indefinitely' {
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "1 個検証失敗"
            Should -Invoke Invoke-VerifyCommand -ParameterFilter {
                $Command -eq "claude-agent-acp" -and $TimeoutSeconds -eq 120
            } -Times 1
            Should -Invoke Write-Host -ParameterFilter {
                $ForegroundColor -eq "Yellow" -and ([string]$Object) -match "タイムアウト"
            } -Times 1
        }
    }

    Context 'Apply - verifyCommand commandExists' {
        BeforeEach {
            $script:origPath = $env:PATH
            $script:pnpmBin = Join-Path $TestDrive "pnpm-bin"
            New-Item $script:pnpmBin -ItemType Directory -Force | Out-Null
            Mock Get-ExternalCommand {
                param($Name)
                if ($Name -eq "pnpm") { return @{ Source = "C:\pnpm.cmd" } }
                if ($Name -eq "claude-agent-acp") { return @{ Source = (Join-Path $script:pnpmBin "claude-agent-acp.CMD") } }
                return $null
            }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return @{
                    globalPackages = @(
                        @{ name = "@agentclientprotocol/claude-agent-acp"; verifyCommand = @{ type = "commandExists"; command = "claude-agent-acp" } }
                    )
                }
            }
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "root") {
                    $global:LASTEXITCODE = 0
                    return (Join-Path $TestDrive "nonexistent-root")
                }
                if ($Arguments -contains "bin") { $global:LASTEXITCODE = 0; return $script:pnpmBin }
                if ($Arguments -contains "add") { $global:LASTEXITCODE = 0; return "installed" }
                $global:LASTEXITCODE = 0; return ""
            }
            Mock Test-Path { return $false } -ParameterFilter {
                ($LiteralPath -and $LiteralPath -like '*nonexistent-root*')
            }
            Mock Invoke-VerifyCommand { throw "commandExists should not run the command" }
            Mock Write-Host { }
            Mock Get-UserEnvironmentPath { return $script:pnpmBin }
            Mock Set-UserEnvironmentPath { }
        }
        AfterEach { $env:PATH = $script:origPath }

        It 'should verify stdio tools by command existence without executing them' {
            Mock Get-ExternalCommand {
                param($Name)
                if ($Name -eq "pnpm") { return @{ Source = "C:\pnpm.cmd" } }
                if ($Name -eq "claude-agent-acp") { return [pscustomobject]@{ Path = (Join-Path $script:pnpmBin "claude-agent-acp.CMD") } }
                return $null
            }

            Set-StrictMode -Version Latest
            try {
                $result = $handler.Apply($ctx)

                $result.Success | Should -Be $true
                $result.Message | Should -Match "1 個インストール"
                Should -Invoke Invoke-VerifyCommand -Times 0
                Should -Invoke Write-Host -ParameterFilter {
                    $ForegroundColor -eq "Gray" -and ([string]$Object) -match "検証中: command -v claude-agent-acp"
                } -Times 1
            }
            finally {
                Set-StrictMode -Off
            }
        }

        It 'should fail when commandExists target is missing' {
            Mock Get-ExternalCommand {
                param($Name)
                if ($Name -eq "pnpm") { return @{ Source = "C:\pnpm.cmd" } }
                if ($Name -eq "prisma-language-server") { return @{ Source = "C:\prisma-language-server.cmd" } }
                return $null
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "1 個検証失敗"
            Should -Invoke Write-Host -ParameterFilter {
                $ForegroundColor -eq "Yellow" -and ([string]$Object) -match "検証コマンドが見つかりません: claude-agent-acp"
            } -Times 1
        }
    }

    Context 'Apply - package without verifyCommand' {
        BeforeEach {
            $script:origPath = $env:PATH
            $script:pnpmBin = Join-Path $TestDrive "pnpm-bin"
            New-Item $script:pnpmBin -ItemType Directory -Force | Out-Null
            Mock Get-ExternalCommand { return @{ Source = "C:\pnpm.cmd" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return @{
                    globalPackages = @(
                        @{ name = "simple-pkg" }
                    )
                }
            }
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "root") {
                    $global:LASTEXITCODE = 0
                    return (Join-Path $TestDrive "nonexistent-root")
                }
                if ($Arguments -contains "bin") { $global:LASTEXITCODE = 0; return $script:pnpmBin }
                if ($Arguments -contains "add") { $global:LASTEXITCODE = 0; return "installed" }
                $global:LASTEXITCODE = 0; return ""
            }
            Mock Test-Path { return $false } -ParameterFilter {
                ($LiteralPath -and $LiteralPath -like '*nonexistent-root*')
            }
            Mock Invoke-VerifyCommand { }
            Mock Write-Host { }
            Mock Get-UserEnvironmentPath { return $script:pnpmBin }
            Mock Set-UserEnvironmentPath { }
        }
        AfterEach { $env:PATH = $script:origPath }

        It 'should count as installed without running verify' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個インストール"
            Should -Invoke Invoke-VerifyCommand -Times 0
        }
    }

    Context 'Apply - explicit custom pnpm manifest contracts' {
        It 'should verify Gemini by executing the installed CLI without probing an optional module' {
            $script:pnpmRoot = Join-Path $TestDrive 'pnpm-module-root'
            New-Item -Path (Join-Path $script:pnpmRoot '@google\gemini-cli') -ItemType Directory -Force | Out-Null
            $script:originalNodePath = $env:NODE_PATH
            $env:NODE_PATH = 'prior-node-modules'
            Mock Get-JsonContent {
                return @{
                    globalPackages = @(
                        @{
                            name          = '@google/gemini-cli'
                            verifyCommand = @{
                                args    = @('--version')
                                command = 'gemini'
                            }
                        }
                    )
                }
            }
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains 'root') {
                    $global:LASTEXITCODE = 0
                    return $script:pnpmRoot
                }
                $global:LASTEXITCODE = 0
                return 'installed'
            }
            Mock Invoke-VerifyCommand {
                param($Command, $Arguments, $TimeoutSeconds)
                $script:pnpmVerifyCalls += , ([PSCustomObject]@{
                        Command   = $Command
                        Arguments = @($Arguments)
                        NodePath  = $env:NODE_PATH
                        Timeout   = $TimeoutSeconds
                    })
                $global:LASTEXITCODE = 0
                return 'module loaded'
            }

            try {
                $result = $handler.Apply($ctx)

                $result.Success | Should -BeTrue
                $result.Message | Should -Match '1 個インストール'
                $script:pnpmVerifyCalls | Should -HaveCount 2
                foreach ($call in $script:pnpmVerifyCalls) {
                    $call.Command | Should -Be 'gemini'
                    $call.Arguments | Should -Be @('--version')
                }
                $env:NODE_PATH | Should -Be 'prior-node-modules'
            }
            finally {
                $env:NODE_PATH = $script:originalNodePath
            }
        }

        BeforeEach {
            $script:originalProcessPath = $env:PATH
            $script:originalPnpmHome = $env:PNPM_HOME
            $script:pnpmBin = Join-Path $TestDrive "manifest-pnpm-bin"
            $script:customPnpmManifest = @{
                globalPackages = @(
                    @{
                        name          = '@deepseek-ai/dsh'
                        installArgs   = @('--allow-build=@deepseek-ai/dsh-subprocess-local', '--allow-build=@google/genai', '--allow-build=koffi', '--allow-build=protobufjs', '--allow-build=!node-pty')
                        verifyCommand = @{ command = 'dsh'; args = @('--version') }
                    }
                )
            }
            Mock Get-JsonContent { return $script:customPnpmManifest }
            $script:pnpmRoot = Join-Path $TestDrive ("manifest-pnpm-root-" + [guid]::NewGuid().ToString("N"))
            New-Item $script:pnpmRoot -ItemType Directory -Force | Out-Null
            $env:PNPM_HOME = $script:pnpmBin
            $script:pnpmAddCalls = @()
            $script:pnpmPolicyCalls = @()
            $script:policyExitCode = 0
            $script:pnpmVerifyCalls = @()
            $script:verifyExitCodeByCommand = @{}
            $script:outdatedJson = "{}"

            Mock Get-ExternalCommand {
                param($Name)
                if ($Name -eq "pnpm") { return @{ Source = "C:\pnpm.cmd" } }
                if ($Name -eq "prisma-language-server") { return @{ Source = "C:\prisma-language-server.cmd" } }
                return $null
            }
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "root") {
                    $global:LASTEXITCODE = 0
                    return $script:pnpmRoot
                }
                if ($Arguments -contains "outdated") {
                    $global:LASTEXITCODE = 0
                    return $script:outdatedJson
                }
                if ($Arguments -contains "add") {
                    $script:pnpmAddCalls += , @($Arguments)
                }
                if ($Arguments -contains 'approve-builds') {
                    $script:pnpmPolicyCalls += , @($Arguments)
                    $global:LASTEXITCODE = $script:policyExitCode
                    return 'policy diagnostic'
                }
                $global:LASTEXITCODE = 0
                return "installed"
            }
            Mock Invoke-VerifyCommand {
                param($Command, $Arguments, $TimeoutSeconds)
                $key = (@($Command) + @($Arguments)) -join " "
                $script:pnpmVerifyCalls += , ([PSCustomObject]@{
                        Command        = $Command
                        Arguments      = @($Arguments)
                        TimeoutSeconds = $TimeoutSeconds
                    })
                if ($script:verifyExitCodeByCommand.ContainsKey($key)) {
                    $global:LASTEXITCODE = $script:verifyExitCodeByCommand[$key]
                }
                else {
                    $global:LASTEXITCODE = 0
                }
                return "command output"
            }
            Mock Get-UserEnvironmentPath { return $script:pnpmBin }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }
        AfterEach {
            $env:PATH = $script:originalProcessPath
            $env:PNPM_HOME = $script:originalPnpmHome
        }

        It 'should install and verify the manifest DSH package with declared options' {
            $expected = @(
                @{ Spec = "@deepseek-ai/dsh"; Command = "dsh"; Arguments = @("--version") }
            )
            $manifest = Get-JsonContent -Path (Join-Path $script:projectRoot "windows\pnpm\packages.json")
            (@($manifest.globalPackages | ForEach-Object { $_.name } | Sort-Object) -join "|") |
                Should -Be ((@($expected | ForEach-Object { $_.Spec } | Sort-Object) -join "|"))

            $result = $handler.Apply($ctx)

            $result.Success | Should -BeTrue
            $script:pnpmAddCalls.Count | Should -Be 1
            (@($script:pnpmAddCalls | ForEach-Object { $_[-1] } | Sort-Object) -join "|") |
                Should -Be ((@($expected | ForEach-Object { $_.Spec } | Sort-Object) -join "|"))
            foreach ($entry in $expected) {
                $script:pnpmVerifyCalls | Where-Object {
                    $_.Command -eq $entry.Command -and ($_.Arguments -join "|") -eq ($entry.Arguments -join "|")
                } | Should -HaveCount 1
            }
            $script:pnpmVerifyCalls | ForEach-Object { $_.TimeoutSeconds | Should -Be 120 }

            $dshCall = $script:pnpmAddCalls | Where-Object { $_ -contains "@deepseek-ai/dsh" } | Select-Object -First 1
            $dshCall | Should -Contain "--allow-build=@deepseek-ai/dsh-subprocess-local"
            $dshCall | Should -Contain "--allow-build=@google/genai"
            $dshCall | Should -Contain "--allow-build=koffi"
            $dshCall | Should -Not -Contain "--allow-build=node-pty"
            $dshCall | Should -Contain "--allow-build=protobufjs"
        }

        It 'should update outdated DSH and verify its version' {
            $installedPackagePaths = @(
                "@deepseek-ai\dsh"
            )
            foreach ($relativePath in $installedPackagePaths) {
                New-Item -Path (Join-Path $script:pnpmRoot $relativePath) -ItemType Directory -Force | Out-Null
            }
            $script:outdatedJson = '{"@deepseek-ai/dsh":{"current":"0.1.0","latest":"0.2.0"}}'

            $result = $handler.Apply($ctx)

            $result.Success | Should -BeTrue
            $script:pnpmPolicyCalls | Should -HaveCount 1
            $script:pnpmPolicyCalls[0] | Should -Be @('approve-builds', '-g', '!node-pty')
            $script:pnpmAddCalls.Count | Should -Be 1
            $script:pnpmAddCalls | ForEach-Object { $_[-1] } | Should -Contain "@deepseek-ai/dsh"
            $script:pnpmVerifyCalls | Where-Object {
                $_.Command -eq "dsh" -and ($_.Arguments -join "|") -eq "--version"
            } | Should -HaveCount 2
        }

        It 'should fail before installing packages when persisted build denial cannot be updated' {
            $script:policyExitCode = 1
            $result = $handler.Apply($ctx)
            $result.Success | Should -BeFalse
            $script:pnpmAddCalls | Should -HaveCount 0
            $script:pnpmVerifyCalls | Should -HaveCount 0
            Should -Invoke Write-Host -ParameterFilter { ([string]$Object) -match 'policy diagnostic' } -Times 1
        }

        It 'should classify a manifest package verification timeout as a verification failure' {
            $script:verifyExitCodeByCommand["dsh --version"] = 124

            $result = $handler.Apply($ctx)

            $result.Success | Should -BeFalse
            $result.Message | Should -Match "1 個検証失敗"
            $script:pnpmAddCalls | ForEach-Object { $_[-1] } | Should -Contain "@deepseek-ai/dsh"
        }

        It 'should fail Gemini verification when gemini --version exits nonzero' {
            New-Item -Path (Join-Path $script:pnpmRoot '@google\gemini-cli') -ItemType Directory -Force | Out-Null
            $script:originalNodePath = $env:NODE_PATH
            $env:NODE_PATH = 'prior-node-modules'
            Mock Get-JsonContent {
                return @{
                    globalPackages = @(
                        @{
                            name          = '@google/gemini-cli'
                            verifyCommand = @{
                                args    = @('--version')
                                command = 'gemini'
                            }
                        }
                    )
                }
            }
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains 'root') {
                    $global:LASTEXITCODE = 0
                    return $script:pnpmRoot
                }
                $global:LASTEXITCODE = 0
                return 'installed'
            }
            Mock Invoke-VerifyCommand {
                param($Command, $Arguments, $TimeoutSeconds)
                $script:pnpmVerifyCalls += , ([PSCustomObject]@{
                        Command   = $Command
                        Arguments = @($Arguments)
                        NodePath  = $env:NODE_PATH
                        Timeout   = $TimeoutSeconds
                    })
                $global:LASTEXITCODE = 1
                return 'Gemini CLI failed'
            }

            try {
                $result = $handler.Apply($ctx)

                $result.Success | Should -BeFalse
                $result.Message | Should -Match '1 個検証失敗'
                $script:pnpmVerifyCalls | Should -HaveCount 2
                foreach ($call in $script:pnpmVerifyCalls) {
                    $call.Command | Should -Be 'gemini'
                    $call.Arguments | Should -Be @('--version')
                }
            }
            finally {
                $env:NODE_PATH = $script:originalNodePath
            }
        }
    }
}
