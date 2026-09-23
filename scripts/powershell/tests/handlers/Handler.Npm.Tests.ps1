BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.Npm.ps1
    $script:projectRoot = (Resolve-Path -LiteralPath "$PSScriptRoot/../../../..").Path
}

Describe 'NpmHandler' {
    Context 'Invoke-Npm package install timeout routing' {
        BeforeEach {
            $script:originalInstallTimeout = $env:DOTFILES_INSTALL_TIMEOUT_SECONDS
        }
        AfterEach {
            if ($null -eq $script:originalInstallTimeout) {
                Remove-Item Env:\DOTFILES_INSTALL_TIMEOUT_SECONDS -ErrorAction SilentlyContinue
            }
            else {
                $env:DOTFILES_INSTALL_TIMEOUT_SECONDS = $script:originalInstallTimeout
            }
        }

        It 'should invoke global installs through the shared 900-second timeout by default' {
            Remove-Item Env:\DOTFILES_INSTALL_TIMEOUT_SECONDS -ErrorAction SilentlyContinue
            Mock Invoke-ExternalCommandWithTimeout { $global:LASTEXITCODE = 0; return 'install ok' }
            Mock Invoke-NativeCommand { throw 'global install must use the timeout wrapper' }

            $result = Invoke-Npm -Arguments @('install', '-g', 'example-package')

            $result | Should -Contain 'install ok'
            Should -Invoke Invoke-ExternalCommandWithTimeout -Times 1 -ParameterFilter {
                $Command -eq 'npm' -and $Arguments -contains 'example-package' -and $TimeoutSeconds -eq 900
            }
            Should -Invoke Invoke-NativeCommand -Times 0
        }

        It 'should honor DOTFILES_INSTALL_TIMEOUT_SECONDS for global installs' {
            $env:DOTFILES_INSTALL_TIMEOUT_SECONDS = '73'
            Mock Invoke-ExternalCommandWithTimeout { $global:LASTEXITCODE = 0; return 'install ok' }
            Mock Invoke-NativeCommand { throw 'global install must use the timeout wrapper' }

            $result = Invoke-Npm -Arguments @('install', '--global', 'example-package')

            $result | Should -Contain 'install ok'
            Should -Invoke Invoke-ExternalCommandWithTimeout -Times 1 -ParameterFilter {
                $Command -eq 'npm' -and $TimeoutSeconds -eq 73
            }
            Should -Invoke Invoke-NativeCommand -Times 0
        }

        It 'should leave version and global list commands on the native path' {
            Mock Invoke-ExternalCommandWithTimeout { throw 'non-install npm commands must not be timed' }
            Mock Invoke-NativeCommand { $global:LASTEXITCODE = 0; return 'native npm' }

            Invoke-Npm -Arguments @('--version') | Should -Contain 'native npm'
            Invoke-Npm -Arguments @('list', '-g', '--depth=0') | Should -Contain 'native npm'

            Should -Invoke Invoke-ExternalCommandWithTimeout -Times 0
            Should -Invoke Invoke-NativeCommand -Times 2 -ParameterFilter { $Command -eq 'npm' }
        }
    }

    BeforeEach {
        $script:handler = [NpmHandler]::new()
        $script:ctx = [SetupContext]::new($script:projectRoot)
    }

    Context 'Constructor' {
        It 'should set <property> correctly' -ForEach @(
            @{ property = "Name"; expected = "Npm"; checkType = "Be" }
            @{ property = "Description"; expected = $null; checkType = "Not -BeNullOrEmpty" }
            @{ property = "Order"; expected = 6; checkType = "Be" }
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

    Context 'CanApply - npm not found' {
        BeforeEach {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist { return $true }
        }

        It 'should return false' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - npm not executable' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\npm.cmd" } }
            Mock Invoke-Npm {
                $global:LASTEXITCODE = 1
                return ""
            }
            Mock Write-Host { }
        }

        It 'should return false' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - import mode without package file' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\npm.cmd" } }
            Mock Invoke-Npm {
                $global:LASTEXITCODE = 0
                return "10.0.0"
            }
            Mock Test-PathExist { return $false }
        }

        It 'should return false' {
            $ctx.Options["NpmMode"] = "import"
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - import mode with all conditions met' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\npm.cmd" } }
            Mock Invoke-Npm {
                $global:LASTEXITCODE = 0
                return "10.0.0"
            }
            Mock Test-PathExist { return $true }
        }

        It 'should return true' {
            $ctx.Options["NpmMode"] = "import"
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }
    }

    Context 'CanApply - list mode with npm available' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\npm.cmd" } }
            Mock Invoke-Npm {
                $global:LASTEXITCODE = 0
                return "10.0.0"
            }
        }

        It 'should return true even without package file' {
            $ctx.Options["NpmMode"] = "list"
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }
    }

    Context 'Apply - import mode success (all new packages)' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\npm.cmd" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return @{
                    globalPackages = @("@google/gemini-cli", "typescript")
                }
            }
            Mock Invoke-Npm {
                param($Arguments)
                if ($Arguments -contains "list") {
                    $global:LASTEXITCODE = 0
                    return '{"dependencies":{}}'
                }
                $global:LASTEXITCODE = 0
                return "installed"
            }
        }

        It 'should return success result' {
            $ctx.Options["NpmMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "2 個インストール"
        }

        It 'should pass a bounded timeout to every npm verify command' {
            Mock Get-JsonContent {
                return @{
                    globalPackages = @(
                        @{ name = "tool-with-check"; verifyCommand = @{ command = "tool-with-check"; args = @("--version") } }
                    )
                }
            }
            Mock Invoke-VerifyCommand {
                param($Command, $Arguments, $TimeoutSeconds)
                $null = $Command
                $null = $Arguments
                $null = $TimeoutSeconds
                $global:LASTEXITCODE = 0
                return "1.0.0"
            }

            $ctx.Options["NpmMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -BeTrue
            Should -Invoke Invoke-VerifyCommand -Times 1 -ParameterFilter {
                $Command -eq "tool-with-check" -and $TimeoutSeconds -eq 30
            }
        }
    }

    Context 'Apply - import mode with already installed packages' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\npm.cmd" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return @{
                    globalPackages = @("@google/gemini-cli", "typescript")
                }
            }
            Mock Invoke-Npm {
                param($Arguments)
                if ($Arguments -contains "list") {
                    $global:LASTEXITCODE = 0
                    return '{"dependencies":{"@google/gemini-cli":{}}}'
                }
                $global:LASTEXITCODE = 0
                return "installed"
            }
        }

        It 'should install already installed packages so they can update to latest' {
            $ctx.Options["NpmMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "2 個インストール"
        }
    }

    Context 'Apply - import mode all packages already installed' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\npm.cmd" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return @{
                    globalPackages = @("@google/gemini-cli", "typescript")
                }
            }
            Mock Invoke-Npm {
                param($Arguments)
                if ($Arguments -contains "list") {
                    $global:LASTEXITCODE = 0
                    return '{"dependencies":{"@google/gemini-cli":{},"typescript":{}}}'
                }
                $global:LASTEXITCODE = 0
                return "installed"
            }
        }

        It 'should reinstall all installed packages so npm selects latest' {
            $ctx.Options["NpmMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "2 個インストール"
        }
    }

    Context 'Apply - import mode with empty packages' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\npm.cmd" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return @{
                    globalPackages = @()
                }
            }
        }

        It 'should return success with empty message' {
            $ctx.Options["NpmMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "空"
        }
    }

    Context 'Apply - import mode partial failure' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\npm.cmd" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return @{
                    globalPackages = @("pkg1", "pkg2")
                }
            }
            $script:installCallCount = 0
            Mock Invoke-Npm {
                param($Arguments)
                if ($Arguments -contains "list") {
                    $global:LASTEXITCODE = 0
                    return '{"dependencies":{}}'
                }
                $script:installCallCount++
                if ($script:installCallCount -eq 1) {
                    $global:LASTEXITCODE = 0
                }
                else {
                    $global:LASTEXITCODE = 1
                }
                return "output"
            }
        }

        It 'should return failure with partial failure info' {
            $ctx.Options["NpmMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $false
            $result.Message | Should -Match "1 個インストール"
            $result.Message | Should -Match "1 個失敗"
        }

        It 'should retain npm diagnostics and exit code for failed package installs' {
            $script:loggedOutput = @()
            Mock Write-Host { $script:loggedOutput += [string]$Object }
            Mock Invoke-Npm {
                param($Arguments)
                if ($Arguments -contains 'list') {
                    $global:LASTEXITCODE = 0
                    return '{"dependencies":{}}'
                }
                $global:LASTEXITCODE = 1
                return 'npm ERR! E403 package access denied'
            }

            $ctx.Options['NpmMode'] = 'import'
            $result = $handler.Apply($ctx)

            $result.Success | Should -BeFalse
            ($script:loggedOutput -join "`n") | Should -Match 'npm ERR! E403 package access denied'
            ($script:loggedOutput -join "`n") | Should -Match 'npm install exited with code 1'
        }
    }

    Context 'Apply - list mode success' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\npm.cmd" } }
            Mock Invoke-Npm {
                $global:LASTEXITCODE = 0
                return "@google/gemini-cli@1.0.0"
            }
        }

        It 'should return success result' {
            $ctx.Options["NpmMode"] = "list"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "表示"
        }
    }

    Context 'Apply - unknown mode' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\npm.cmd" } }
            Mock Test-PathExist { return $true }
        }

        It 'should return failure result' {
            $ctx.Options["NpmMode"] = "unknown"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $false
            $result.Message | Should -Match "不明なモード"
        }
    }

    Context 'Apply - exception thrown' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\npm.cmd" } }
            Mock Test-PathExist { return $true }
            Mock Get-JsonContent {
                return @{
                    globalPackages = @("pkg1")
                }
            }
            Mock Invoke-Npm {
                param($Arguments)
                if ($Arguments -contains "list") {
                    $global:LASTEXITCODE = 0
                    return '{"dependencies":{}}'
                }
                throw "npm error"
            }
        }

        It 'should return failure result' {
            $ctx.Options["NpmMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $false
            $result.Message | Should -Match "npm error"
        }
    }

    Context 'Apply - Windows npm manifest contracts' {
        BeforeEach {
            $script:npmInstallCalls = @()
            $script:npmVerifyCalls = @()
            Mock Get-ExternalCommand { return @{ Source = "C:\npm.cmd" } }
            Mock Test-PathExist { return $true }
            Mock Invoke-Npm {
                param($Arguments)
                if ($Arguments -contains "list") {
                    $global:LASTEXITCODE = 0
                    return '{"dependencies":{"@devcontainers/cli":{},"agent-browser":{}}}'
                }
                $script:npmInstallCalls += , @($Arguments)
                $global:LASTEXITCODE = 0
                return "installed"
            }
            Mock Invoke-VerifyCommand {
                param($Command, $Arguments, $TimeoutSeconds)
                $script:npmVerifyCalls += , ([PSCustomObject]@{
                        Command        = $Command
                        Arguments      = @($Arguments)
                        TimeoutSeconds = $TimeoutSeconds
                    })
                $global:LASTEXITCODE = 0
                return "1.0.0"
            }
        }

        It 'should install and verify every current manifest package using its declared command' {
            $manifest = Get-JsonContent -Path (Join-Path $script:projectRoot "windows\npm\packages.json")
            $expected = @(
                @{ Spec = "@devcontainers/cli"; Command = "devcontainer"; Arguments = @("--version") }
                @{ Spec = "agent-browser@0.38.1"; Command = "agent-browser"; Arguments = @("--version") }
            )
            $actualSpecs = @($manifest.globalPackages | ForEach-Object { $_.name })
            ($actualSpecs | Sort-Object) -join "|" | Should -Be "@devcontainers/cli|agent-browser@0.38.1"

            $ctx.Options["NpmMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -BeTrue
            $script:npmInstallCalls.Count | Should -Be 2
            foreach ($entry in $expected) {
                $script:npmInstallCalls | Where-Object { $_ -contains $entry.Spec } | Should -HaveCount 1
                $script:npmVerifyCalls | Where-Object {
                    $_.Command -eq $entry.Command -and ($_.Arguments -join "|") -eq ($entry.Arguments -join "|")
                } | Should -HaveCount 2
            }
            $script:npmVerifyCalls | Where-Object { $_.TimeoutSeconds -ne 30 } | Should -BeNullOrEmpty
        }

        It 'should classify verification timeouts for the current manifest packages as failures' {
            Mock Invoke-VerifyCommand {
                param($Command, $Arguments, $TimeoutSeconds)
                $script:npmVerifyCalls += , ([PSCustomObject]@{
                        Command        = $Command
                        Arguments      = @($Arguments)
                        TimeoutSeconds = $TimeoutSeconds
                    })
                $global:LASTEXITCODE = 124
                return "verification timed out"
            }

            $ctx.Options["NpmMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -BeFalse
            $result.Message | Should -Match "2 個検証失敗"
            $script:npmInstallCalls.Count | Should -Be 2
            $script:npmVerifyCalls | Where-Object { $_.TimeoutSeconds -ne 30 } | Should -BeNullOrEmpty
        }

        It 'should retain diagnostics when the pinned agent-browser install fails' {
            $script:loggedOutput = @()
            Mock Write-Host { $script:loggedOutput += [string]$Object }
            Mock Invoke-Npm {
                param($Arguments)
                if ($Arguments -contains "list") {
                    $global:LASTEXITCODE = 0
                    return '{"dependencies":{}}'
                }

                $script:npmInstallCalls += , @($Arguments)
                if ($Arguments -contains "agent-browser@0.38.1") {
                    $global:LASTEXITCODE = 1
                    return 'npm ERR! agent-browser@0.38.1 pinned package install failed'
                }

                $global:LASTEXITCODE = 0
                return "installed"
            }

            $ctx.Options["NpmMode"] = "import"
            $result = $handler.Apply($ctx)

            $result.Success | Should -BeFalse
            $script:npmInstallCalls | Where-Object { $_ -contains "agent-browser@0.38.1" } | Should -HaveCount 1
            ($script:loggedOutput -join "`n") | Should -Match 'npm ERR! agent-browser@0\.38\.1 pinned package install failed'
            ($script:loggedOutput -join "`n") | Should -Match 'npm install exited with code 1 for agent-browser@0\.38\.1'
            $script:npmVerifyCalls | Where-Object { $_.Command -eq "agent-browser" } | Should -BeNullOrEmpty
        }
    }
}
