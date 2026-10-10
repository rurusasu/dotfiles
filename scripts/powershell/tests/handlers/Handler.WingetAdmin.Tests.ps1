#Requires -Module Pester

BeforeAll {
    $script:handlerPath = Join-Path $PSScriptRoot "../../handlers/Handler.WingetAdmin.ps1"
    . (Join-Path $PSScriptRoot "../../lib/SetupHandler.ps1")
    . (Join-Path $PSScriptRoot "../../lib/Invoke-ExternalCommand.ps1")
    . (Join-Path $PSScriptRoot "../../handlers/Handler.Winget.ps1")
    . $script:handlerPath
}

Describe 'WingetAdminHandler' {
    It 'should provide an administrator-only winget handler' {
        $handler = [WingetAdminHandler]::new()
        $handler.RequiresAdmin | Should -BeTrue
        $handler.Phase | Should -Be 2
    }

    It 'should install only manifest packages marked for the administrator phase' {
        $handler = [WingetAdminHandler]::new()
        $ctx = [SetupContext]::new((Join-Path $TestDrive "dotfiles"))
        $ctx.Options["WingetMode"] = "import"
        Mock Get-JsonContent {
            return [PSCustomObject]@{
                Sources = @(
                    [PSCustomObject]@{
                        SourceDetails = [PSCustomObject]@{ Name = "winget" }
                        Packages = @(
                            [PSCustomObject]@{
                                PackageIdentifier = "Example.AdminPackage"
                                requiresAdmin = $true
                                installArgs = @("--scope", "machine")
                            }
                        )
                    }
                )
            }
        }
        Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
        Mock Test-PathExist { return $true }
        Mock Invoke-Winget {
            param($Arguments)
            $null = $Arguments
            $global:LASTEXITCODE = 0
            return "installed"
        }

        $result = $handler.Apply($ctx)

        $result.Success | Should -BeTrue
        Should -Invoke Invoke-Winget -Times 1 -ParameterFilter {
            $Arguments -contains "--scope" -and $Arguments -contains "machine" -and
            $Arguments -contains "--source" -and $Arguments -contains "winget"
        }
    }

        Context 'Apply - install result classification' {
        BeforeEach {
            $handler = [WingetAdminHandler]::new()
            $null = $handler.Name
            $ctx = [SetupContext]::new((Join-Path $TestDrive "dotfiles"))
            $ctx.Options["WingetMode"] = "import"
            Mock Get-JsonContent {
                return [PSCustomObject]@{
                    Sources = @(
                        [PSCustomObject]@{
                            SourceDetails = [PSCustomObject]@{ Name = "winget" }
                            Packages = @(
                                [PSCustomObject]@{
                                    PackageIdentifier = "Admin.Tool"
                                    requiresAdmin = $true
                                    verifyCommand = [PSCustomObject]@{
                                        command = "Admin.Tool"
                                        type = "commandExists"
                                    }
                                }
                            )
                        }
                    )
                }
            }
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
        }

        It 'should report a timeout as a failure without treating it as a no-op' {
            Mock Invoke-Winget {
                $global:LASTEXITCODE = 124
                return "winget install timed out"
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -BeFalse
            $result.Message | Should -Match "1 個失敗"
            $result.Message | Should -Not -Match "変更なし"
        }

        It 'should report a generic nonzero install result as a failure' {
            Mock Invoke-Winget {
                $global:LASTEXITCODE = 1
                return "fatal installer error"
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -BeFalse
            $result.Message | Should -Match "1 個失敗"
            $result.Message | Should -Not -Match "変更なし"
        }

        It 'should preserve an existing application when its update fails' {
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains 'install') {
                    $global:LASTEXITCODE = 1
                    return 'network failure'
                }
                $global:LASTEXITCODE = 0
                return 'Admin.Tool 1.0.0'
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -BeTrue
            $result.Message | Should -Match '1 個更新失敗（既存を維持）'
            Should -Invoke Invoke-Winget -Times 2
        }

        It 'should keep a new application install failure as a failure even when list succeeds' {
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains 'install') {
                    $global:LASTEXITCODE = 1
                    return 'network failure'
                }
                $global:LASTEXITCODE = 0
                return 'Other.Tool 1.0.0'
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -BeFalse
            $result.Message | Should -Match '1 個失敗'
            $result.Message | Should -Not -Match '既存を維持'
        }

        It 'should reject an existing inventory when runtime verification fails' {
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains 'install') {
                    $global:LASTEXITCODE = 1
                    return 'network failure'
                }
                $global:LASTEXITCODE = 0
                return 'Admin.Tool 1.0.0'
            }
            Mock Get-ExternalCommand { return $null }

            $result = $handler.Apply($ctx)

            $result.Success | Should -BeFalse
            $result.Message | Should -Match '1 個失敗'
        }

        It 'should classify explicit already-installed output as unchanged' {
            Mock Invoke-Winget {
                param($Arguments)
                if ($Arguments -contains 'list') {
                    $global:LASTEXITCODE = 0
                    return 'Admin.Tool 1.0.0'
                }
                $global:LASTEXITCODE = 1
                return "No applicable update found"
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -BeTrue
            $result.Message | Should -Match "1 個変更なし"
        }
    }
}
