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
        $script:originalPath = $env:PATH
        $env:PATH = "C:\Windows"
    }

    AfterEach {
        $env:PATH = $script:originalPath
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
            Mock Get-UserEnvironmentPath { return "$script:opPkgDir;C:\Windows" }
            Mock Write-Host { }
        }

        It 'should return false when package directory is first and command shims are not active' {
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
            Mock Get-UserEnvironmentPath { return "$script:opPkgDir;C:\Windows" }
            Mock Write-Host { }
        }

        It 'should return false without requiring inactive WindowsApps or WinGet Links shims' {
            $handler.CanApply($ctx) | Should -Be $false
        }
    }

    Context 'CanApply - stale WindowsApps shim is ignored' {
        BeforeEach {
            Set-OnePasswordCliPackageInstalled
            Mock Test-Path {
                if ($Path -like "*AgileBits.1Password.CLI*op.exe") { return $true }
                if ($LiteralPath -like "*WindowsApps\op.exe") { return $true }
                return $false
            }
            Mock Get-Item {
                return [PSCustomObject]@{ LinkType = ""; Length = 100; LastWriteTimeUtc = [datetime]'2024-01-01' }
            }
            Mock Get-UserEnvironmentPath { return "$script:opPkgDir;C:\Windows;$script:expectedWindowsApps" }
            Mock Write-Host { }
        }

        It 'should return false instead of treating the OS-managed shim as required' {
            $handler.CanApply($ctx) | Should -Be $false
        }
    }

    Context 'Apply - adds package directory PATH' {
        BeforeEach {
            Set-OnePasswordCliPackageInstalled
            Mock Test-Path {
                if ($Path -like "*AgileBits.1Password.CLI*op.exe") { return $true }
                if ($Path -like "*WindowsApps" -or $LiteralPath -like "*WindowsApps") { return $true }
                if ($Path -like "*WinGet\Links" -or $LiteralPath -like "*WinGet\Links") { return $true }
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

        It 'should add the package directory without creating inactive compatibility shims' {
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            Should -Invoke New-Item -Times 0 -ParameterFilter { $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink" }
            Should -Invoke Copy-Item -Times 0
            Should -Invoke Set-UserEnvironmentPath -Times 1 -ParameterFilter { $Path -like "*$script:opPkgDir*" }
        }
    }

    Context 'Apply - WindowsApps is OS-managed' {
        BeforeEach {
            Set-OnePasswordCliPackageInstalled
            Mock Test-Path {
                if ($Path -like "*AgileBits.1Password.CLI*op.exe") { return $true }
                if ($Path -like "*WinGet\Links" -or $LiteralPath -like "*WinGet\Links") { return $false }
                if ($LiteralPath -like "*op.exe") { return $false }
                return $false
            }
            Mock New-Item {
                if ($Path -like "*WindowsApps*") {
                    throw "Administrator privilege required for this operation"
                }
            }
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:expectedWindowsApps" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }

        It 'should not write an op.exe shim to WindowsApps' {
            $env:PATH = "C:\Windows;$script:expectedWindowsApps"

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            Should -Invoke New-Item -Times 0 -ParameterFilter { $Path -like "*WindowsApps*" }
            Should -Invoke Set-UserEnvironmentPath -Times 1 -ParameterFilter { $Path -like "*$script:opPkgDir*" }
        }
    }

    Context 'Apply - existing unrelated WinGet Links alias' {
        BeforeEach {
            $script:previousOpPkgDir = $script:opPkgDir
            $script:previousOpExe = $script:opExe
            $script:previousExpectedLinks = $script:expectedLinks
            $script:previousLocalAppData = $env:LOCALAPPDATA

            $script:opPkgDir = Join-Path $TestDrive 'Packages\AgileBits.1Password.CLI_test'
            $script:opExe = Join-Path $script:opPkgDir 'op.exe'
            $script:expectedLinks = Join-Path $TestDrive 'Microsoft\WinGet\Links'
            $env:LOCALAPPDATA = $TestDrive
            New-Item -ItemType Directory -Path $script:opPkgDir, $script:expectedLinks -Force | Out-Null
            Set-Content -LiteralPath $script:opExe -Value 'installed 1Password CLI' -NoNewline
            $script:unrelatedAliasPath = Join-Path $script:expectedLinks 'op.exe'
            Set-Content -LiteralPath $script:unrelatedAliasPath -Value 'unrelated op alias' -NoNewline

            Set-OnePasswordCliPackageInstalled
            $script:mockUserPath = "C:\Windows;$script:expectedLinks"
            Mock Get-UserEnvironmentPath { return $script:mockUserPath }
            Mock Set-UserEnvironmentPath { $script:mockUserPath = $Path }
            Mock Write-Host { }
            $env:PATH = "$script:expectedLinks;C:\Windows"
        }

        AfterEach {
            $script:opPkgDir = $script:previousOpPkgDir
            $script:opExe = $script:previousOpExe
            $script:expectedLinks = $script:previousExpectedLinks
            $env:LOCALAPPDATA = $script:previousLocalAppData
        }

        It 'preserves an unrelated alias while making the installed executable win in a new shell' {
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            [System.IO.File]::ReadAllText($script:unrelatedAliasPath) | Should -Be 'unrelated op alias'
            ($script:mockUserPath -split ';')[0] | Should -Be $script:opPkgDir

            $shell = Join-Path $PSHOME $(if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' })
            $env:PATH = $script:mockUserPath
            $resolveCommand = '$ErrorActionPreference = ''Stop''; $command = Get-Command -Name ''op.exe'' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1; if (-not $command) { exit 1 }; [Console]::Out.WriteLine($command.Source); exit 0'
            $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($resolveCommand))
            $resolvedPath = & $shell -NoLogo -NoProfile -EncodedCommand $encodedCommand
            $childExitCode = $LASTEXITCODE
            $childExitCode | Should -Be 0 -Because "a new shell should resolve op.exe from the package directory; child output: $($resolvedPath -join ' ')"
            [System.IO.Path]::GetFullPath(($resolvedPath | Select-Object -Last 1).Trim()) |
                Should -Be ([System.IO.Path]::GetFullPath($script:opExe))
        }
    }

    Context 'Apply - required USER PATH update fails' {
        BeforeEach {
            Set-OnePasswordCliPackageInstalled
            Mock Test-Path {
                if ($Path -like "*AgileBits.1Password.CLI*op.exe") { return $true }
                return $false
            }
            Mock Get-UserEnvironmentPath { return "C:\Windows" }
            Mock Set-UserEnvironmentPath { throw "USER PATH write failed" }
            Mock Write-Host { }
        }

        It 'should return failure when the package directory cannot be persisted' {
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Error | Should -Match "USER PATH write failed"
        }
    }

    Context 'Apply - WinGet Links symlink privilege fallback' {
        BeforeEach {
            $script:previousOpPkgDir = $script:opPkgDir
            $script:previousOpExe = $script:opExe
            $script:previousExpectedLinks = $script:expectedLinks
            $script:previousExpectedWindowsApps = $script:expectedWindowsApps
            $script:previousLocalAppData = $env:LOCALAPPDATA

            $script:opPkgDir = Join-Path $TestDrive 'Packages\AgileBits.1Password.CLI_test'
            $script:opExe = Join-Path $script:opPkgDir 'op.exe'
            $script:expectedLinks = Join-Path $TestDrive 'Microsoft\WinGet\Links'
            $script:expectedWindowsApps = Join-Path $TestDrive 'Microsoft\WindowsApps'
            $env:LOCALAPPDATA = $TestDrive
            New-Item -ItemType Directory -Path $script:opPkgDir, $script:expectedLinks, $script:expectedWindowsApps -Force | Out-Null
            Set-Content -LiteralPath $script:opExe -Value 'version one' -NoNewline
            $script:windowsAppsMarker = Join-Path $script:expectedWindowsApps 'keep.txt'
            Set-Content -LiteralPath $script:windowsAppsMarker -Value 'WindowsApps is OS-managed' -NoNewline

            Set-OnePasswordCliPackageInstalled
            Mock New-Item { throw 'Administrator privilege required for this operation' } -ParameterFilter {
                $ItemType -eq 'SymbolicLink'
            }
            $script:mockUserPath = 'C:\Windows'
            Mock Get-UserEnvironmentPath { return $script:mockUserPath }
            Mock Set-UserEnvironmentPath { $script:mockUserPath = $Path }
            Mock Write-Host { }
            $env:PATH = "$script:expectedLinks;C:\Windows"
        }

        AfterEach {
            $script:opPkgDir = $script:previousOpPkgDir
            $script:opExe = $script:previousOpExe
            $script:expectedLinks = $script:previousExpectedLinks
            $script:expectedWindowsApps = $script:previousExpectedWindowsApps
            $env:LOCALAPPDATA = $script:previousLocalAppData
        }

        It 'should avoid WindowsApps and resolve the upgraded package executable after symlink creation is denied' {
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            [System.IO.File]::ReadAllText((Join-Path $script:expectedLinks 'op.exe')) | Should -Be 'version one'
            Test-Path -LiteralPath (Join-Path $script:expectedLinks 'op.exe.dotfiles-managed') | Should -Be $true
            $windowsAppsEntries = @(Get-ChildItem -LiteralPath $script:expectedWindowsApps -Force | Select-Object -ExpandProperty Name)
            $windowsAppsEntries | Should -HaveCount 1
            $windowsAppsEntries | Should -Contain 'keep.txt'
            [System.IO.File]::ReadAllText($script:windowsAppsMarker) | Should -Be 'WindowsApps is OS-managed'
            $handler.CanApply($ctx) | Should -Be $false

            Set-Content -LiteralPath $script:opExe -Value 'version two' -NoNewline
            $env:PATH = "$script:expectedLinks;C:\Windows"
            $handler.CanApply($ctx) | Should -Be $true
            $upgradeResult = if ($handler.CanApply($ctx)) { $handler.Apply($ctx) }

            $upgradeResult.Success | Should -Be $true
            [System.IO.File]::ReadAllText((Join-Path $script:expectedLinks 'op.exe')) | Should -Be 'version two'
            $windowsAppsEntries = @(Get-ChildItem -LiteralPath $script:expectedWindowsApps -Force | Select-Object -ExpandProperty Name)
            $windowsAppsEntries | Should -HaveCount 1
            $windowsAppsEntries | Should -Contain 'keep.txt'
            [System.IO.File]::ReadAllText($script:windowsAppsMarker) | Should -Be 'WindowsApps is OS-managed'
            $handler.CanApply($ctx) | Should -Be $false

            $shell = Join-Path $PSHOME $(if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' })
            $env:PATH = $script:mockUserPath
            $resolvedPath = & $shell -NoLogo -NoProfile -Command '& "$env:SystemRoot\System32\where.exe" op.exe | Select-Object -First 1'
            $LASTEXITCODE | Should -Be 0
            $resolvedPath = [System.IO.Path]::GetFullPath(($resolvedPath | Select-Object -Last 1).Trim())
            $resolvedPath | Should -Be ([System.IO.Path]::GetFullPath($script:opExe))
            [System.IO.File]::ReadAllText($resolvedPath) | Should -Be 'version two'

            Set-Content -LiteralPath (Join-Path $script:expectedLinks 'op.exe') -Value 'unrelated replacement' -NoNewline
            $env:PATH = "$script:expectedLinks;C:\Windows"
            $handler.CanApply($ctx) | Should -Be $false
            $handler.Apply($ctx).Success | Should -Be $true
            [System.IO.File]::ReadAllText((Join-Path $script:expectedLinks 'op.exe')) | Should -Be 'unrelated replacement'
        }
    }

    Context 'Apply - direct package directory PATH' {
        BeforeEach {
            Set-OnePasswordCliPackageInstalled
            Mock Test-Path {
                if ($Path -like "*AgileBits.1Password.CLI*op.exe") { return $true }
                if ($Path -like "*WindowsApps" -or $LiteralPath -like "*WindowsApps") { return $true }
                if ($Path -like "*WinGet\Links" -or $LiteralPath -like "*WinGet\Links") { return $true }
                if ($LiteralPath -like "*op.exe") { return $true }
                return $false
            }
            Mock Get-Item {
                return [PSCustomObject]@{ LinkType = ""; Length = 100; LastWriteTimeUtc = [datetime]'2024-01-01' }
            } -ParameterFilter { $LiteralPath -like "*op.exe" }
            Mock Get-FileHash {
                if ($LiteralPath -like "*WinGet\Links\op.exe") {
                    return [PSCustomObject]@{ Hash = "OLD-SHIM-HASH" }
                }
                return [PSCustomObject]@{ Hash = "PACKAGE-EXE-HASH" }
            }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "SymbolicLink" }
            Mock New-Item { throw "hardlink fallback must not be used" } -ParameterFilter { $ItemType -eq "HardLink" }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock Remove-Item { }
            Mock Move-Item { }
            Mock Copy-Item { throw "op should not copy command shims" }
            Mock Get-UserEnvironmentPath { return "C:\Windows" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }

        It 'should add the package directory without replacing an unknown WinGet Links shim' {
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            Should -Invoke Set-UserEnvironmentPath -Times 1 -ParameterFilter { $Path -like "*$script:opPkgDir*" }
            Should -Invoke New-Item -Times 0 -ParameterFilter { $ItemType -eq "SymbolicLink" }
            Should -Invoke New-Item -Times 0 -ParameterFilter { $ItemType -eq "HardLink" }
            Should -Invoke Move-Item -Times 0
            Should -Invoke Copy-Item -Times 0
        }
    }

    Context 'Apply - current shims but PATH missing' {
        BeforeEach {
            Set-OnePasswordCliPackageInstalled
            Mock Test-Path {
                if ($Path -like "*op.exe") { return $true }
                if ($Path -like "*WindowsApps" -or $LiteralPath -like "*WindowsApps") { return $true }
                if ($Path -like "*WinGet\Links" -or $LiteralPath -like "*WinGet\Links") { return $true }
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
            Mock Move-Item { throw "should not replace current shim" }
            Mock Copy-Item { }
            Mock Get-UserEnvironmentPath { return "C:\Windows" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }

        It 'should keep current symlink shims and add the package directory PATH' {
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            Should -Invoke Remove-Item -Times 0 -ParameterFilter { $LiteralPath -like "*op.exe" }
            Should -Invoke Move-Item -Times 0
            Should -Invoke Set-UserEnvironmentPath -Times 1 -ParameterFilter { $Path -like "*$script:opPkgDir*" }
            Should -Invoke New-Item -Times 0 -ParameterFilter {
                $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink"
            }
        }
    }
}
