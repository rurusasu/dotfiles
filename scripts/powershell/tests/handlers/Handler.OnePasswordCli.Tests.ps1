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

    Context 'CanApply - shims are current and PATH configured' {
        BeforeEach {
            Set-OnePasswordCliPackageInstalled
            Mock Test-Path {
                if ($Path -like "*op.exe") { return $true }
                if ($LiteralPath -like "*op.exe") { return $true }
                return $false
            }
            Mock Get-Item {
                return [PSCustomObject]@{ LinkType = "SymbolicLink"; Target = $script:opExe }
            } -ParameterFilter { $LiteralPath -like "*op.exe" }
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:expectedWindowsApps;$script:expectedLinks" }
            Mock Write-Host { }
        }

        It 'should return false when both shims and PATH are already set' {
            $handler.CanApply($ctx) | Should -Be $false
        }
    }

    Context 'CanApply - WindowsApps shim missing' {
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

        It 'should return true so old VS Code processes can resolve op through WindowsApps' {
            $handler.CanApply($ctx) | Should -Be $true
        }
    }

    Context 'CanApply - link is stale copy from old version' {
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

        It 'should return true so stale shims are refreshed after winget upgrade' {
            $handler.CanApply($ctx) | Should -Be $true
        }
    }

    Context 'Apply - creates WindowsApps and WinGet Links shims' {
        BeforeEach {
            Set-OnePasswordCliPackageInstalled
            Mock Test-Path {
                if ($Path -like "*AgileBits.1Password.CLI*op.exe") { return $true }
                if ($Path -like "*WindowsApps") { return $true }
                if ($Path -like "*WinGet\Links") { return $true }
                if ($LiteralPath -like "*op.exe") { return $false }
                return $false
            }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "SymbolicLink" }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "HardLink" }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock Remove-Item { }
            Mock Copy-Item { }
            Mock Get-UserEnvironmentPath { return "C:\Windows" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }

        It 'should create both shims and add stable PATH entries' {
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            Should -Invoke New-Item -Times 2 -ParameterFilter { $ItemType -eq "SymbolicLink" }
            Should -Invoke Set-UserEnvironmentPath -Times 2
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

        It 'should only add PATH entries without recreating shims' {
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            Should -Invoke Set-UserEnvironmentPath -Times 2
            Should -Invoke New-Item -Times 0 -ParameterFilter {
                $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink"
            }
        }
    }
}
