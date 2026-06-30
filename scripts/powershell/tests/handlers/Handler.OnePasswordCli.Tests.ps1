#Requires -Module Pester

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.OnePasswordCli.ps1
    $script:projectRoot = (Resolve-Path -LiteralPath "$PSScriptRoot/../../../..").Path

    $script:opPkgDir = "C:\Users\test\AppData\Local\Microsoft\WinGet\Packages\AgileBits.1Password.CLI_Microsoft.Winget.Source_8wekyb3d8bbwe"
    $script:opExe = Join-Path $script:opPkgDir "op.exe"
    $script:homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { [Environment]::GetFolderPath("UserProfile") }
    $script:localAppData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $script:homeDir "AppData\Local" }
    $script:expectedLinks = Join-Path $script:localAppData "Microsoft\WinGet\Links"
    $script:expectedWindowsApps = Join-Path $script:localAppData "Microsoft\WindowsApps"

    function script:Set-OnePasswordCliPackageInstalled {
        Mock Get-ChildItem {
            return [PSCustomObject]@{ FullName = $script:opPkgDir }
        } -ParameterFilter {
            $Path -like "*WinGet\Packages" -and $Filter -like "AgileBits.1Password.CLI_*"
        }
    }
}

Describe 'OnePasswordCliHandler' {
    BeforeEach {
        $script:handler = [OnePasswordCliHandler]::new()
        $script:ctx = [SetupContext]::new($script:projectRoot)
    }

    Context 'Constructor' {
        It 'should set <property> correctly' -ForEach @(
            @{ property = "Name"; expected = "OnePasswordCli"; checkType = "Be" }
            @{ property = "Description"; expected = $null; checkType = "Not -BeNullOrEmpty" }
            @{ property = "Order"; expected = 9; checkType = "Be" }
            @{ property = "RequiresAdmin"; expected = $false; checkType = "Be" }
            @{ property = "Phase"; expected = 1; checkType = "Be" }
        ) {
            if ($checkType -eq "Be") {
                $handler.$property | Should -Be $expected
            }
            else {
                $handler.$property | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'CanApply - 1Password CLI not installed' {
        BeforeEach {
            Mock Get-ChildItem { return $null } -ParameterFilter {
                $Path -like "*WinGet\Packages" -and $Filter -like "AgileBits.1Password.CLI_*"
            }
            Mock Write-Host { }
        }

        It 'should return false' {
            $handler.CanApply($ctx) | Should -Be $false
        }
    }

    Context 'CanApply - package directory PATH configured' {
        BeforeEach {
            Set-OnePasswordCliPackageInstalled
            Mock Test-Path {
                if ($Path -like "*AgileBits.1Password.CLI*op.exe") { return $true }
                if ($LiteralPath -like "*op.exe") { return $false }
                return $false
            }
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:opPkgDir" }
            Mock Write-Host { }
        }

        It 'should return false without requiring command shims' {
            $handler.CanApply($ctx) | Should -Be $false
        }
    }

    Context 'CanApply - package directory PATH missing' {
        BeforeEach {
            Set-OnePasswordCliPackageInstalled
            Mock Test-Path {
                if ($Path -like "*AgileBits.1Password.CLI*op.exe") { return $true }
                if ($LiteralPath -like "*WinGet\Links\op.exe") { return $true }
                if ($LiteralPath -like "*WindowsApps\op.exe") { return $false }
                return $false
            }
            Mock Get-Item {
                return [PSCustomObject]@{ LinkType = "SymbolicLink"; Target = $script:opExe }
            } -ParameterFilter { $LiteralPath -like "*WinGet\Links\op.exe" }
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:expectedWindowsApps;$script:expectedLinks" }
            Mock Write-Host { }
        }

        It 'should return true so Apply can switch to package directory PATH' {
            $handler.CanApply($ctx) | Should -Be $true
        }
    }

    Context 'CanApply - package directory is already on PATH' {
        BeforeEach {
            Set-OnePasswordCliPackageInstalled
            Mock Test-Path {
                if ($Path -like "*AgileBits.1Password.CLI*op.exe") { return $true }
                if ($LiteralPath -like "*op.exe") { return $false }
                return $false
            }
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:opPkgDir" }
            Mock Write-Host { }
        }

        It 'should return false without requiring WindowsApps or WinGet Links shims' {
            $handler.CanApply($ctx) | Should -Be $false
        }
    }

    Context 'CanApply - legacy shim is stale copy from old version' {
        BeforeEach {
            Set-OnePasswordCliPackageInstalled
            Mock Test-Path {
                if ($Path -like "*op.exe") { return $true }
                if ($LiteralPath -like "*op.exe") { return $true }
                return $false
            }
            Mock Get-Item {
                if ($LiteralPath -like "*WindowsApps\op.exe") {
                    return [PSCustomObject]@{ LinkType = ""; Length = 100; LastWriteTimeUtc = [datetime]'2024-01-01' }
                }
                return [PSCustomObject]@{ LinkType = ""; Length = 200; LastWriteTimeUtc = [datetime]'2024-06-01' }
            }
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:expectedWindowsApps;$script:expectedLinks" }
            Mock Write-Host { }
        }

        It 'should return true so stale shims are removed after winget upgrade' {
            $handler.CanApply($ctx) | Should -Be $true
        }
    }

    Context 'Apply - adds package directory PATH' {
        BeforeEach {
            Set-OnePasswordCliPackageInstalled
            Mock Test-Path {
                if ($Path -like "*AgileBits.1Password.CLI*op.exe") { return $true }
                if ($Path -like "*WindowsApps") { return $true }
                if ($Path -like "*WinGet\Links") { return $true }
                if ($LiteralPath -like "*op.exe") { return $false }
                return $false
            }
            Mock New-Item { throw "op should not create command shims" } -ParameterFilter {
                $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink"
            }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock Remove-Item { }
            Mock Copy-Item { throw "op should not copy command shims" }
            Mock Get-UserEnvironmentPath { return "C:\Windows" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }

        It 'should add the package directory without creating shims' {
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            Should -Invoke New-Item -Times 0 -ParameterFilter { $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink" }
            Should -Invoke Copy-Item -Times 0
            Should -Invoke Set-UserEnvironmentPath -Times 1 -ParameterFilter { $Path -like "*$script:opPkgDir*" }
        }
    }

    Context 'Apply - direct package directory PATH' {
        BeforeEach {
            Set-OnePasswordCliPackageInstalled
            Mock Test-Path {
                if ($Path -like "*AgileBits.1Password.CLI*op.exe") { return $true }
                if ($Path -like "*WindowsApps") { return $true }
                if ($Path -like "*WinGet\Links") { return $true }
                if ($LiteralPath -like "*op.exe") { return $true }
                return $false
            }
            Mock New-Item { throw "op should not create command shims" } -ParameterFilter {
                $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink"
            }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock Remove-Item { }
            Mock Copy-Item { throw "op should not copy command shims" }
            Mock Get-UserEnvironmentPath { return "C:\Windows" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }

        It 'should add the package directory and remove old shims without recreating them' {
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            Should -Invoke Remove-Item -Times 2 -ParameterFilter { $LiteralPath -like "*op.exe" }
            Should -Invoke Set-UserEnvironmentPath -Times 1 -ParameterFilter { $Path -like "*$script:opPkgDir*" }
            Should -Invoke New-Item -Times 0 -ParameterFilter {
                $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink"
            }
            Should -Invoke Copy-Item -Times 0
        }
    }

    Context 'Apply - current shims but PATH missing' {
        BeforeEach {
            Set-OnePasswordCliPackageInstalled
            Mock Test-Path {
                if ($Path -like "*op.exe") { return $true }
                if ($Path -like "*WindowsApps") { return $true }
                if ($Path -like "*WinGet\Links") { return $true }
                if ($LiteralPath -like "*op.exe") { return $true }
                return $false
            }
            Mock Get-Item {
                return [PSCustomObject]@{ LinkType = "SymbolicLink"; Target = $script:opExe }
            } -ParameterFilter { $LiteralPath -like "*op.exe" }
            Mock New-Item { throw "should not recreate current shim" } -ParameterFilter {
                $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink"
            }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock Remove-Item { }
            Mock Copy-Item { }
            Mock Get-UserEnvironmentPath { return "C:\Windows" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }

        It 'should remove shims and add only the package directory PATH' {
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            Should -Invoke Remove-Item -Times 2 -ParameterFilter { $LiteralPath -like "*op.exe" }
            Should -Invoke Set-UserEnvironmentPath -Times 1 -ParameterFilter { $Path -like "*$script:opPkgDir*" }
            Should -Invoke New-Item -Times 0 -ParameterFilter {
                $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink"
            }
        }
    }
}
