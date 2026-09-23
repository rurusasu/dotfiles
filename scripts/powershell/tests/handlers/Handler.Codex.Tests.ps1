#Requires -Module Pester

<#
.SYNOPSIS
    Handler.Codex.ps1 のユニットテスト

.DESCRIPTION
    CodexHandler クラスのテスト
#>

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.Codex.ps1
    $script:projectRoot = (Resolve-Path -LiteralPath "$PSScriptRoot/../../../..").Path

    # Official complete Codex package layout: bin contains the CLI and adjacent host.
    $script:testDriveRoot = $TestDrive
    $script:codexPkgDir = $null
    $script:codexBinDir = $null
    $script:codexExe = $null
    $script:homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { [Environment]::GetFolderPath("UserProfile") }
    $script:localAppData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $script:homeDir "AppData\Local" }
    $script:expectedLinks = Join-Path $script:localAppData "Microsoft\WinGet\Links"
    $script:expectedLocalBin = Join-Path $script:homeDir ".local\bin"

    # Codex パッケージが存在することにする共通モック
    function script:Set-CodexPackageInstalled {
        $script:codexPkgDir = Join-Path $script:testDriveRoot "WinGet\Packages\OpenAI.Codex_Microsoft.Winget.Source_8wekyb3d8bbwe"
        $script:codexBinDir = Join-Path $script:codexPkgDir "bin"
        $script:codexExe = Join-Path $script:codexBinDir "codex.exe"
        New-Item -ItemType Directory -Path $script:codexBinDir -Force | Out-Null
        [System.IO.File]::WriteAllText($script:codexExe, "codex CLI fixture")
        [System.IO.File]::WriteAllText((Join-Path $script:codexBinDir "codex-code-mode-host.exe"), "codex host fixture")
        Mock Get-ChildItem {
            return [PSCustomObject]@{ FullName = $script:codexPkgDir }
        } -ParameterFilter {
            $Path -like "*WinGet\Packages" -and $Filter -like "OpenAI.Codex_*"
        }
    }
}

Describe 'CodexHandler' {
    BeforeEach {
        $script:handler = [CodexHandler]::new()
        $script:ctx = [SetupContext]::new($script:projectRoot)
    }

    Context 'installer handler loader scope' {
        It 'resolves Codex through Get-SetupHandler in a clean PowerShell process' {
            $fixtureRoot = Join-Path $TestDrive 'codex-loader-scope'
            $localAppDataPath = Join-Path $fixtureRoot 'local-app-data'
            $codexBinPath = Join-Path $localAppDataPath 'Microsoft\WinGet\Packages\OpenAI.Codex_fixture\bin'
            $runnerPath = Join-Path $fixtureRoot 'run-handler-loader.ps1'
            New-Item -ItemType Directory -Path $codexBinPath -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $codexBinPath 'codex.exe') -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $codexBinPath 'codex-code-mode-host.exe') -Force | Out-Null

            @'
param([string]$RepositoryRoot, [string]$LocalAppDataPath)
$ErrorActionPreference = 'Stop'
$env:LOCALAPPDATA = $LocalAppDataPath
. (Join-Path $RepositoryRoot 'scripts\powershell\lib\SetupHandler.ps1')
. (Join-Path $RepositoryRoot 'scripts\powershell\lib\Invoke-ExternalCommand.ps1')
$handlers = Get-SetupHandler -HandlersPath (Join-Path $RepositoryRoot 'scripts\powershell\handlers')
$handler = $handlers | Where-Object Name -EQ 'Codex' | Select-Object -First 1
if (-not $handler -or -not $handler.CanApply([SetupContext]::new($RepositoryRoot))) {
    throw 'Get-SetupHandler did not resolve the installed Codex package.'
}
Write-Output 'Codex loader scope passed.'
'@ | Set-Content -LiteralPath $runnerPath -Encoding UTF8

            $enginePath = (Get-Process -Id $PID).Path
            $output = @(& $enginePath -NoLogo -NoProfile -NonInteractive -File $runnerPath $script:projectRoot $localAppDataPath 2>&1)
            $exitCode = $LASTEXITCODE

            $exitCode | Should -Be 0 -Because ($output -join [Environment]::NewLine)
            ($output -join [Environment]::NewLine) | Should -Match 'Codex loader scope passed\.'
        }
    }

    Context 'Constructor' {
        It 'should set <property> correctly' -ForEach @(
            @{ property = "Name"; expected = "Codex"; checkType = "Be" }
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

    Context 'Codex package executable path resolution' {
        It 'should prefer a complete nested Programs Codex package over a CLI-only WinGet package' {
            $testLocalAppData = Join-Path $TestDrive 'LocalAppData'
            $wingetPackage = Join-Path $testLocalAppData 'Microsoft\WinGet\Packages\OpenAI.Codex_Test'
            $directBin = Join-Path $testLocalAppData 'Programs\Codex\bin'
            New-Item -ItemType Directory -Path $wingetPackage -Force | Out-Null
            New-Item -ItemType Directory -Path $directBin -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $wingetPackage 'codex-x86_64-pc-windows-msvc.exe'), 'CLI only')
            [System.IO.File]::WriteAllText((Join-Path $directBin 'codex.exe'), 'complete package CLI')
            [System.IO.File]::WriteAllText((Join-Path $directBin 'codex-code-mode-host.exe'), 'adjacent code-mode host')

            $result = Resolve-CodexPackageExecutablePath -LocalAppData $testLocalAppData

            $result | Should -Be (Join-Path $directBin 'codex.exe')
        }

        It 'should resolve the nested package path using filesystem probes that work without LinkType or Target metadata' {
            $testLocalAppData = Join-Path $TestDrive 'PowerShell51LocalAppData'
            $directBin = Join-Path $testLocalAppData 'Programs\Codex\bin'
            New-Item -ItemType Directory -Path $directBin -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $directBin 'codex.exe'), 'complete package CLI')
            [System.IO.File]::WriteAllText((Join-Path $directBin 'codex-code-mode-host.exe'), 'adjacent code-mode host')

            $result = Resolve-CodexPackageExecutablePath -LocalAppData $testLocalAppData

            $result | Should -Be (Join-Path $directBin 'codex.exe')
        }
    }

    Context 'CanApply - Codex not installed' {
        BeforeEach {
            Mock Test-Path { return $false }
            Mock Get-ChildItem { return $null } -ParameterFilter {
                $Path -like "*WinGet\Packages" -and $Filter -like "OpenAI.Codex_*"
            }
            Mock Write-Host { }
        }

        It 'should return false' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - link is current AND PATH configured' {
        BeforeEach {
            Set-CodexPackageInstalled
            Mock Test-Path {
                if ($LiteralPath -like "*codex-code-mode-host.exe") { return $true }
                if ($LiteralPath -like "*bin\codex.exe" -or $Path -like "*bin\codex.exe") { return $true }
                if ($LiteralPath -like "*Links\codex.exe") { return $true }
                return $false
            }
            # 現行 exe を指すシンボリックリンク
            Mock Get-Item {
                return [PSCustomObject]@{ LinkType = "SymbolicLink"; Target = $script:codexExe }
            } -ParameterFilter { $LiteralPath -like "*Links\codex.exe" }
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:expectedLinks;$script:expectedLocalBin" }
            Mock Write-Host { }
        }

        It 'should return false when link and PATH are both set' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - link is stale copy from old version (winget upgrade)' {
        BeforeEach {
            Set-CodexPackageInstalled
            Mock Test-Path {
                if ($LiteralPath -like "*bin\codex.exe" -or $Path -like "*bin\codex.exe") { return $true }
                if ($LiteralPath -like "*Links\codex.exe") { return $true }
                return $false
            }
            # Links\codex.exe は旧バージョンのコピー（symlink ではない）。
            # 現行 exe とサイズ/更新日時が異なる。
            Mock Get-Item {
                if ($LiteralPath -like "*Links\codex.exe") {
                    return [PSCustomObject]@{ LinkType = ""; Length = 174106600; LastWriteTimeUtc = [datetime]'2024-01-01' }
                }
                return [PSCustomObject]@{ LinkType = ""; Length = 246156592; LastWriteTimeUtc = [datetime]'2024-06-01' }
            }
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:expectedLinks" }
            Mock Write-Host { }
        }

        It 'should return true so the stale link is refreshed' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }
    }

    Context 'CanApply - link is matching non-symlink portable link' {
        BeforeEach {
            Set-CodexPackageInstalled
            Mock Test-Path {
                if ($LiteralPath -like "*bin\codex.exe" -or $Path -like "*bin\codex.exe") { return $true }
                if ($LiteralPath -like "*Links\codex.exe") { return $true }
                return $false
            }
            # hardlink/copy は winget upgrade に追従しないため、現時点で一致していても置き換える。
            Mock Get-Item {
                return [PSCustomObject]@{ LinkType = ""; Length = 246156592; LastWriteTimeUtc = [datetime]'2024-06-01' }
            }
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:expectedLinks;$script:expectedLocalBin" }
            Mock Write-Host { }
        }

        It 'should return true so the non-symlink link is replaced with a symlink' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }
    }

    Context 'CanApply - link is current but PATH not configured' {
        BeforeEach {
            Set-CodexPackageInstalled
            Mock Test-Path {
                if ($LiteralPath -like "*bin\codex.exe" -or $Path -like "*bin\codex.exe") { return $true }
                if ($LiteralPath -like "*Links\codex.exe") { return $true }
                return $false
            }
            Mock Get-Item {
                return [PSCustomObject]@{ LinkType = "SymbolicLink"; Target = $script:codexExe }
            } -ParameterFilter { $LiteralPath -like "*Links\codex.exe" }
            Mock Get-UserEnvironmentPath { return "C:\Windows;C:\Windows\System32" }
            Mock Write-Host { }
        }

        It 'should return true so Apply can add PATH' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }
    }

    Context 'CanApply - link and WinGet PATH configured but local bin missing' {
        BeforeEach {
            Set-CodexPackageInstalled
            Mock Test-Path {
                if ($LiteralPath -like "*bin\codex.exe" -or $Path -like "*bin\codex.exe") { return $true }
                if ($LiteralPath -like "*Links\codex.exe") { return $true }
                return $false
            }
            Mock Get-Item {
                return [PSCustomObject]@{ LinkType = "SymbolicLink"; Target = $script:codexExe }
            } -ParameterFilter { $LiteralPath -like "*Links\codex.exe" }
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:expectedLinks" }
            Mock Write-Host { }
        }

        It 'should return true so Apply can add local bin for MCP tools' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }
    }

    Context 'CanApply - Codex installed but no link' {
        BeforeEach {
            Set-CodexPackageInstalled
            Mock Test-Path {
                if ($LiteralPath -like "*bin\codex.exe" -or $Path -like "*bin\codex.exe") { return $true }
                if ($LiteralPath -like "*Links\codex.exe") { return $false }
                return $false
            }
            Mock Get-UserEnvironmentPath { return "" }
            Mock Write-Host { }
        }

        It 'should return true' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }
    }

    Context 'Apply - executable not found' {
        BeforeEach {
            Mock Get-ChildItem { return $null } -ParameterFilter {
                $Path -like "*WinGet\Packages" -and $Filter -like "OpenAI.Codex_*"
            }
            Mock Test-Path { return $false }
            Mock Write-Host { }
        }

        It 'should return failure when executable path is null' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $false
            $result.Message | Should -Match "実行ファイルが見つかりません"
        }
    }

    Context 'Apply - creates link when missing' {
        BeforeEach {
            Set-CodexPackageInstalled
            $script:includeCodexHost = $true
            Mock Test-Path {
                if ($LiteralPath -like "*bin\codex.exe" -or $Path -like "*bin\codex.exe") { return $true }
                $candidate = if ($LiteralPath) { $LiteralPath } else { $Path }
                if ($script:includeCodexHost -and $candidate -like "*codex-code-mode-host.exe") { return $candidate -notlike "*WinGet\Links\*" }
                if ($Path -like "*Links") { return $true }
                if ($LiteralPath -like "*Links\codex.exe") { return $false }
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

        It 'should create symlink and return success' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            Should -Invoke New-Item -Times 1 -ParameterFilter { $ItemType -eq "SymbolicLink" }
        }

        It 'should not copy the host beside a symlink shim' {
            $script:includeCodexHost = $true
            $result = $handler.Apply($ctx)

            $result.Success | Should -BeTrue
            Should -Invoke Copy-Item -Times 0 -ParameterFilter { $LiteralPath -like '*codex-code-mode-host.exe' }
        }
    }

    Context 'Apply - user-copy fallback when symlink cannot be created' {
        BeforeEach {
            Set-CodexPackageInstalled
            $script:includeCodexHost = $false
            $script:newItemTypes = @()
            Mock Test-Path {
                if ($LiteralPath -like "*bin\codex.exe" -or $Path -like "*bin\codex.exe") { return $true }
                $candidate = if ($LiteralPath) { $LiteralPath } else { $Path }
                if ($script:includeCodexHost -and $candidate -like "*codex-code-mode-host.exe") { return $candidate -notlike "*WinGet\Links\*" }
                if ($Path -like "*Links") { return $true }
                if ($LiteralPath -like "*Links\codex.exe") { return $false }
                return $false
            }
            Mock New-Item {
                $script:newItemTypes += $ItemType
                throw "Administrator privilege required"
            } -ParameterFilter {
                $ItemType -eq "SymbolicLink"
            }
            Mock New-Item {
                $script:newItemTypes += $ItemType
            } -ParameterFilter {
                $ItemType -eq "HardLink"
            }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock Remove-Item { }
            Mock Copy-Item { }
            Mock Get-UserEnvironmentPath { return "C:\Windows" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }

        It 'should create a copy fallback without creating a hardlink' {
            $script:includeCodexHost = $true
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $script:newItemTypes | Should -Contain "SymbolicLink"
            $script:newItemTypes | Should -Not -Contain "HardLink"
            Should -Invoke Copy-Item -Times 1 -ParameterFilter { $LiteralPath -like '*bin\codex.exe' }
        }

        It 'should copy the adjacent code-mode host with the fallback executable' {
            $script:includeCodexHost = $true
            $result = $handler.Apply($ctx)

            $result.Success | Should -BeTrue
            Should -Invoke Copy-Item -Times 1 -ParameterFilter {
                $LiteralPath -like '*codex-code-mode-host.exe' -and
                $Destination -like '*WinGet\Links\codex-code-mode-host.exe'
            }
        }

        It 'should fail instead of reporting success when the copied executable has no adjacent code-mode host' {
            $script:includeCodexHost = $false

            $result = $handler.Apply($ctx)

            $result.Success | Should -BeFalse
            $result.Error.Message | Should -Match 'codex-code-mode-host\.exe'
        }
    }

    Context 'CanApply - current link is missing its adjacent code-mode host' {
        BeforeEach {
            Set-CodexPackageInstalled
            Mock Test-Path {
                if ($LiteralPath -like "*bin\codex.exe" -or $Path -like "*bin\codex.exe") { return $true }
                if ($LiteralPath -like "*codex-code-mode-host.exe") { return $false }
                if ($LiteralPath -like "*Links\codex.exe") { return $true }
                return $false
            }
            Mock Get-Item {
                return [PSCustomObject]@{ LinkType = "SymbolicLink"; Target = $script:codexExe }
            } -ParameterFilter { $LiteralPath -like "*Links\codex.exe" }
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:expectedLinks;$script:expectedLocalBin" }
            Mock Write-Host { }
        }

        It 'should reapply and report a missing adjacent host instead of skipping setup' {
            $handler.CanApply($ctx) | Should -BeTrue
            $result = $handler.Apply($ctx)
            $result.Success | Should -BeFalse
            $result.Error.Message | Should -Match 'codex-code-mode-host\.exe'
        }
    }

    Context 'CanApply - current copied shim is missing its adjacent code-mode host' {
        BeforeEach {
            Set-CodexPackageInstalled
            Mock Test-Path {
                if ($LiteralPath -like '*codex-code-mode-host.exe' -and $LiteralPath -notlike '*WinGet\Links*') { return $true }
                if ($LiteralPath -like '*bin\codex.exe') { return $true }
                if ($LiteralPath -like '*Links\codex.exe') { return $true }
                if ($LiteralPath -like '*Links\codex-code-mode-host.exe') { return $false }
                if ($Path -like '*bin\codex.exe') { return $true }
                return $false
            }
            Mock Get-Item {
                return [PSCustomObject]@{ LinkType = ''; Target = $null }
            } -ParameterFilter { $LiteralPath -like '*Links\codex.exe' }
            Mock Get-FileHash { return [PSCustomObject]@{ Hash = 'same-content' } }
            Mock Copy-Item { }
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:expectedLinks;$script:expectedLocalBin" }
            Mock Write-Host { }
        }

        It 'should restore the adjacent code-mode host beside a current copied shim' {
            $handler.CanApply($ctx) | Should -BeTrue

            $result = $handler.Apply($ctx)

            $result.Success | Should -BeTrue
            Should -Invoke Copy-Item -Times 1 -ParameterFilter {
                $LiteralPath -like '*WinGet\Packages\OpenAI.Codex_*\codex-code-mode-host.exe' -and
                $Destination -like '*WinGet\Links\codex-code-mode-host.exe'
            }
        }
    }

    Context 'CanApply - direct archive fallback' {
        BeforeEach {
            Mock Get-ChildItem { return $null } -ParameterFilter {
                $Path -like "*WinGet\Packages" -and $Filter -like "OpenAI.Codex_*"
            }
            Mock Test-Path {
                return ($PathType -eq "Container" -and $LiteralPath -like "*Programs\Codex") -or
                    $LiteralPath -like "*Programs\Codex\bin\codex.exe" -or
                    $Path -like "*Programs\Codex\bin\codex.exe" -or
                    $LiteralPath -like "*Programs\Codex\bin\codex-code-mode-host.exe" -or
                    $Path -like "*Programs\Codex\bin\codex-code-mode-host.exe"
            }
            Mock Get-UserEnvironmentPath { return "" }
            Mock Write-Host { }
        }

        It 'should discover the archive fallback installation outside WinGet' {
            $handler.CanApply($ctx) | Should -BeTrue
        }
    }

    Context 'Apply - symlink creation fails' {
        BeforeEach {
            Set-CodexPackageInstalled
            Mock Test-Path {
                if ($LiteralPath -like "*bin\codex.exe" -or $Path -like "*bin\codex.exe") { return $true }
                if ($script:includeCodexHost -and $LiteralPath -like "*codex-code-mode-host.exe") { return $LiteralPath -notlike "*WinGet\Links\*" }
                if ($Path -like "*Links") { return $true }
                if ($LiteralPath -like "*Links\codex.exe") { return $false }
                return $false
            }
            Mock New-Item { throw "Developer Mode is required" } -ParameterFilter { $ItemType -eq "SymbolicLink" }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock Remove-Item { }
            Mock Copy-Item { }
            Mock Get-UserEnvironmentPath { return "C:\Windows" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }

        It 'should succeed with a copy fallback' {
            $script:includeCodexHost = $true
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            Should -Invoke New-Item -Times 1 -ParameterFilter { $ItemType -eq "SymbolicLink" }
            Should -Invoke Copy-Item -Times 1
        }
    }

    Context 'Apply - refreshes stale link after winget upgrade' {
        BeforeEach {
            Set-CodexPackageInstalled
            Mock Test-Path {
                if ($LiteralPath -like "*bin\codex.exe" -or $Path -like "*bin\codex.exe") { return $true }
                if ($script:includeCodexHost -and $LiteralPath -like "*codex-code-mode-host.exe") { return $LiteralPath -notlike "*WinGet\Links\*" }
                if ($Path -like "*Links") { return $true }
                if ($LiteralPath -like "*Links\codex.exe") { return $true }
                return $false
            }
            # 既存リンクは旧バージョンのコピーで陳腐化している
            Mock Get-Item {
                if ($LiteralPath -like "*Links\codex.exe") {
                    return [PSCustomObject]@{ LinkType = ""; Length = 174106600; LastWriteTimeUtc = [datetime]'2024-01-01' }
                }
                return [PSCustomObject]@{ LinkType = ""; Length = 246156592; LastWriteTimeUtc = [datetime]'2024-06-01' }
            }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "SymbolicLink" }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock Remove-Item { }
            Mock Move-Item { }
            Mock Copy-Item { }
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:expectedLinks" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }

        It 'should replace the stale link after creating the new symlink' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            Should -Invoke New-Item -Times 1 -ParameterFilter { $ItemType -eq "SymbolicLink" }
            Should -Invoke Move-Item -Times 2
            Should -Invoke Remove-Item -Times 0 -ParameterFilter { $LiteralPath -like "*Links\codex.exe" }
        }
    }

    Context 'Apply - symlink creation fails with existing stale link' {
        BeforeEach {
            Set-CodexPackageInstalled
            Mock Test-Path {
                if ($LiteralPath -like "*bin\codex.exe" -or $Path -like "*bin\codex.exe") { return $true }
                if ($script:includeCodexHost -and $LiteralPath -like "*codex-code-mode-host.exe") { return $LiteralPath -notlike "*WinGet\Links\*" }
                if ($Path -like "*Links") { return $true }
                if ($LiteralPath -like "*Links\codex.exe") { return $true }
                return $false
            }
            Mock Get-Item {
                return [PSCustomObject]@{ LinkType = ""; Length = 174106600; LastWriteTimeUtc = [datetime]'2024-01-01' }
            } -ParameterFilter { $LiteralPath -like "*Links\codex.exe" }
            Mock New-Item { throw "Developer Mode is required" } -ParameterFilter { $ItemType -eq "SymbolicLink" }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock Remove-Item { }
            Mock Move-Item { throw "old link should not be moved before symlink creation succeeds" }
            Mock Copy-Item { }
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:expectedLinks" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }

        It 'should replace the stale copy without moving it first' {
            $script:includeCodexHost = $true
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            Should -Invoke New-Item -Times 1 -ParameterFilter { $ItemType -eq "SymbolicLink" }
            Should -Invoke Move-Item -Times 0
            Should -Invoke Remove-Item -Times 1 -ParameterFilter { $LiteralPath -like "*Links\codex.exe" }
            Should -Invoke Copy-Item -Times 1
        }
    }

    Context 'Apply - link current, only PATH missing' {
        BeforeEach {
            Set-CodexPackageInstalled
            Mock Test-Path {
                if ($LiteralPath -like "*codex-code-mode-host.exe") { return $true }
                if ($LiteralPath -like "*bin\codex.exe" -or $Path -like "*bin\codex.exe") { return $true }
                if ($Path -like "*Links") { return $true }
                if ($LiteralPath -like "*Links\codex.exe") { return $true }
                return $false
            }
            # 既存リンクは現行 exe を指すシンボリックリンク（最新）
            Mock Get-Item {
                return [PSCustomObject]@{ LinkType = "SymbolicLink"; Target = $script:codexExe }
            } -ParameterFilter { $LiteralPath -like "*Links\codex.exe" }
            Mock New-Item { throw "should not recreate a current link" } -ParameterFilter {
                $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink"
            }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock Remove-Item { }
            Mock Copy-Item { }
            Mock Get-UserEnvironmentPath { return "C:\Windows;C:\Windows\System32;$script:expectedLocalBin" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }

        It 'should add WinGet Links PATH without recreating the link' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            Should -Invoke Set-UserEnvironmentPath -Times 1
            Should -Invoke Copy-Item -Times 0
            Should -Invoke New-Item -Times 0 -ParameterFilter { $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink" }
        }
    }

    Context 'Apply - link current, only local bin missing' {
        BeforeEach {
            Set-CodexPackageInstalled
            Mock Test-Path {
                if ($LiteralPath -like "*codex-code-mode-host.exe") { return $true }
                if ($LiteralPath -like "*bin\codex.exe" -or $Path -like "*bin\codex.exe") { return $true }
                if ($Path -like "*Links") { return $true }
                if ($LiteralPath -like "*Links\codex.exe") { return $true }
                return $false
            }
            Mock Get-Item {
                return [PSCustomObject]@{ LinkType = "SymbolicLink"; Target = $script:codexExe }
            } -ParameterFilter { $LiteralPath -like "*Links\codex.exe" }
            Mock New-Item { throw "should not recreate a current link" } -ParameterFilter {
                $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink"
            }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock Remove-Item { }
            Mock Copy-Item { }
            Mock Get-UserEnvironmentPath { return "C:\Windows;$script:expectedLinks" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }

        It 'should add local bin for MCP tools without recreating the link' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            Should -Invoke Set-UserEnvironmentPath -Times 1 -ParameterFilter { $Path -like "$script:expectedLocalBin*" }
            Should -Invoke Copy-Item -Times 0
            Should -Invoke New-Item -Times 0 -ParameterFilter { $ItemType -eq "SymbolicLink" -or $ItemType -eq "HardLink" }
        }
    }

    Context 'Apply - PATH update throws' {
        BeforeEach {
            Set-CodexPackageInstalled
            Mock Test-Path {
                if ($LiteralPath -like "*codex-code-mode-host.exe") { return $true }
                if ($LiteralPath -like "*bin\codex.exe" -or $Path -like "*bin\codex.exe") { return $true }
                if ($Path -like "*Links") { return $true }
                if ($LiteralPath -like "*Links\codex.exe") { return $true }
                return $false
            }
            Mock Get-Item {
                return [PSCustomObject]@{ LinkType = "SymbolicLink"; Target = $script:codexExe }
            } -ParameterFilter { $LiteralPath -like "*Links\codex.exe" }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock Get-UserEnvironmentPath { return "C:\Windows" }
            Mock Set-UserEnvironmentPath { throw [InvalidOperationException]::new("PATH write failed") }
            Mock Write-Host { }
        }

        It 'should return a failure result instead of throwing an overload error' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $false
            $result.Message | Should -Match "Codex 設定に失敗しました"
            $result.Error | Should -Match "PATH write failed"
        }
    }
}
