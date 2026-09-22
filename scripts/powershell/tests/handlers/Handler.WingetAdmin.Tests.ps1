#Requires -Module Pester

BeforeAll {
    $script:handlerPath = Join-Path $PSScriptRoot "../../handlers/Handler.WingetAdmin.ps1"
    . (Join-Path $PSScriptRoot "../../lib/SetupHandler.ps1")
    . (Join-Path $PSScriptRoot "../../lib/Invoke-ExternalCommand.ps1")
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
                                PackageIdentifier = "AutoHotkey.AutoHotkey"
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
}
