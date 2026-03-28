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
}

Describe 'PnpmHandler' {
    BeforeEach {
        $script:handler = [PnpmHandler]::new()
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
            } else {
                $handler.$property | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'CanApply - pnpm not found, bootstrap fails' {
        BeforeEach {
            Mock Get-ExternalCommand { return $null }
            Mock Invoke-Corepack { $global:LASTEXITCODE = 1 }
            Mock Invoke-Npm { $global:LASTEXITCODE = 1 }
            Mock Write-Host { }
        }

        It 'should return false' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - pnpm not found, corepack bootstrap succeeds' {
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

        It 'should return true' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }
    }

    Context 'CanApply - pnpm not found, npm bootstrap succeeds' {
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

        It 'should return true' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
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

    Context 'EnsurePnpmSetup - bin path already available' {
        BeforeEach {
            $script:pnpmBin = Join-Path $TestDrive "pnpm-bin"
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
        }

        It 'should return the bin path' {
            $result = $handler.EnsurePnpmSetup()
            $result | Should -Be $script:pnpmBin
        }

        It 'should not call pnpm setup' {
            $handler.EnsurePnpmSetup()
            Should -Invoke Invoke-Pnpm -ParameterFilter { $Arguments -contains "setup" } -Times 0
        }
    }

    Context 'EnsurePnpmSetup - bin path fails, setup succeeds' {
        BeforeEach {
            $script:origPnpmHome = $env:PNPM_HOME
            $env:PNPM_HOME = ""
            $script:pnpmBin = Join-Path $TestDrive "pnpm-bin-after-setup"
            $script:setupCalled = $false
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "bin") {
                    if ($script:setupCalled) {
                        $global:LASTEXITCODE = 0
                        return $script:pnpmBin
                    }
                    $global:LASTEXITCODE = 1
                    return ""
                }
                if ($Arguments -contains "setup") {
                    $script:setupCalled = $true
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
        }

        It 'should call pnpm setup' {
            $handler.EnsurePnpmSetup()
            Should -Invoke Invoke-Pnpm -ParameterFilter { $Arguments -contains "setup" } -Times 1
        }

        It 'should return the bin path obtained after setup' {
            $result = $handler.EnsurePnpmSetup()
            $result | Should -Be $script:pnpmBin
        }

        It 'should set PNPM_HOME for current process when unset' {
            $env:PNPM_HOME = ""
            $handler.EnsurePnpmSetup()
            $env:PNPM_HOME | Should -Not -BeNullOrEmpty
        }
    }

    Context 'EnsurePnpmSetup - bin path fails, setup fails' {
        BeforeEach {
            # bin コマンドが失敗（PNPM_HOME 未設定を示す）
            Mock Invoke-Pnpm {
                $global:LASTEXITCODE = 1
                return ""
            } -ParameterFilter { $Arguments -contains "bin" }
            # setup コマンドも失敗
            Mock Invoke-Pnpm {
                $global:LASTEXITCODE = 1
                return ""
            } -ParameterFilter { $Arguments -contains "setup" }
            Mock Write-Host { }
        }

        It 'should return null' {
            $result = $handler.EnsurePnpmSetup()
            $result | Should -BeNullOrEmpty
        }

        It 'should not throw' {
            { $handler.EnsurePnpmSetup() } | Should -Not -Throw
        }
    }

    Context 'EnsurePnpmSetup - bin path fails after setup, PNPM_HOME fallback' {
        BeforeEach {
            $script:origPnpmHome = $env:PNPM_HOME
            $env:PNPM_HOME = Join-Path $TestDrive "pnpm-home-fallback"
            $script:setupCalled = $false
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "bin") {
                    $global:LASTEXITCODE = 1
                    return ""
                }
                if ($Arguments -contains "setup") {
                    $script:setupCalled = $true
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
        }

        It 'should return PNPM_HOME as fallback when pnpm bin still fails after setup' {
            $expected = $env:PNPM_HOME
            $result = $handler.EnsurePnpmSetup()
            $result | Should -Be $expected
        }

        It 'should not throw' {
            { $handler.EnsurePnpmSetup() } | Should -Not -Throw
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
            New-Item $script:pnpmBin -ItemType Directory -Force | Out-Null
            $script:origPath = $env:PATH
            $env:PATH = "C:\Windows\System32"
            Mock Get-UserEnvironmentPath { return $script:pnpmBin }
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
                return @{ globalPackages = @("@google/gemini-cli", "typescript") }
            }
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "root") { $global:LASTEXITCODE = 0; return $script:globalRoot }
                if ($Arguments -contains "bin") { $global:LASTEXITCODE = 0; return $script:pnpmBin }
                $global:LASTEXITCODE = 0; return ""
            }
            Mock Write-Host { }
            Mock Get-UserEnvironmentPath { return $script:pnpmBin }
            Mock Set-UserEnvironmentPath { }
        }
        AfterEach { $env:PATH = $script:origPath }

        It 'should skip all already-installed packages' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "2 個スキップ"
        }

        It 'should not call pnpm add for installed packages' {
            $handler.Apply($ctx)
            Should -Invoke Invoke-Pnpm -ParameterFilter { $Arguments -contains "add" } -Times 0
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
                return @{ globalPackages = @("pkg-a", "pkg-b") }
            }
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "root") { $global:LASTEXITCODE = 1; return "" }
                if ($Arguments -contains "bin") { $global:LASTEXITCODE = 0; return $script:pnpmBin }
                if ($Arguments -contains "add") { $global:LASTEXITCODE = 0; return "installed" }
                $global:LASTEXITCODE = 0; return ""
            }
            # root 失敗 → EnsureGeminiCommandShim 0-arg でリトライするが root も失敗して早期 return
            # TestGeminiCommand (Invoke-Gemini) には到達しないが明示的にモックして安全に
            Mock Invoke-Gemini { $global:LASTEXITCODE = 1; throw "not installed" }
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

        It 'should call pnpm root a second time inside 0-arg EnsureGeminiCommandShim when root was empty' {
            # root 事前取得失敗 → Apply が 0-arg EnsureGeminiCommandShim にフォールバック
            # → 内部で再度 pnpm root -g を呼ぶ（合計2回）
            # 2回目も失敗するため shim 作成はスキップされる（動作として正常）
            $handler.Apply($ctx)
            Should -Invoke Invoke-Pnpm -ParameterFilter { $Arguments -contains "root" } -Times 2
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
                    globalPackages = @("@google/gemini-cli", "typescript")
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
                    globalPackages = @("good-pkg", "bad-pkg")
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
            Mock Write-Host { }
            Mock Get-UserEnvironmentPath { return $script:pnpmBin }
            Mock Set-UserEnvironmentPath { }
        }
        AfterEach {
            $env:PATH = $script:origPath
        }

        It 'should report mixed success/failure counts' {
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個成功"
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

    Context 'EnsureGeminiCommandShim - gemini command healthy' {
        BeforeEach {
            $script:origProfile = $env:USERPROFILE
            $env:USERPROFILE = $TestDrive
            $script:globalRoot = Join-Path $TestDrive "pnpm-global\node_modules"
            $entryDir = Join-Path $script:globalRoot "@google\gemini-cli\dist"
            New-Item $entryDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $entryDir "index.js") -Value "console.log('ok')" -NoNewline
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "root") {
                    $global:LASTEXITCODE = 0
                    return $script:globalRoot
                }
                $global:LASTEXITCODE = 0
                return ""
            }
            Mock Invoke-Gemini {
                $global:LASTEXITCODE = 0
                return "0.32.0"
            }
            Mock Get-UserEnvironmentPath { return "C:\Windows\System32" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }
        AfterEach {
            $env:USERPROFILE = $script:origProfile
        }

        It 'should skip shim creation when gemini is healthy' {
            $handler.EnsureGeminiCommandShim()
            (Join-Path $TestDrive ".local\bin\gemini.cmd") | Should -Not -Exist
            Should -Invoke Set-UserEnvironmentPath -Times 0
        }
    }

    Context 'EnsureGeminiCommandShim - gemini command broken' {
        BeforeEach {
            $script:origProfile = $env:USERPROFILE
            $env:USERPROFILE = $TestDrive
            $script:globalRoot = Join-Path $TestDrive "pnpm-global\node_modules"
            $entryDir = Join-Path $script:globalRoot "@google\gemini-cli\dist"
            New-Item $entryDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $entryDir "index.js") -Value "console.log('ok')" -NoNewline
            Mock Invoke-Pnpm {
                param($Arguments)
                if ($Arguments -contains "root") {
                    $global:LASTEXITCODE = 0
                    return $script:globalRoot
                }
                $global:LASTEXITCODE = 0
                return ""
            }
            Mock Invoke-Gemini {
                $global:LASTEXITCODE = 1
                throw "broken"
            }
            Mock Get-UserEnvironmentPath { return "C:\Windows\System32" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }
        AfterEach {
            $env:USERPROFILE = $script:origProfile
        }

        It 'should create gemini.cmd shim and prepend .local\bin to user PATH' {
            $handler.EnsureGeminiCommandShim()
            $shimPath = Join-Path $TestDrive ".local\bin\gemini.cmd"
            $shimPath | Should -Exist
            $content = Get-Content $shimPath -Raw
            $content | Should -Match 'GEMINI_JS'
            $content | Should -Match 'pnpm root -g'
            $content | Should -Match 'node "%GEMINI_JS%" %\*'
            Should -Invoke Set-UserEnvironmentPath -Times 1
        }
    }

    Context 'EnsureGeminiCommandShim([string]) - 1-arg overload with pre-computed root' {
        BeforeEach {
            $script:origProfile = $env:USERPROFILE
            $env:USERPROFILE = $TestDrive
            $script:globalRoot = Join-Path $TestDrive "pnpm-global\node_modules"
            $entryDir = Join-Path $script:globalRoot "@google\gemini-cli\dist"
            New-Item $entryDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $entryDir "index.js") -Value "console.log('ok')" -NoNewline
            Mock Invoke-Pnpm { $global:LASTEXITCODE = 0; return "" }
            Mock Invoke-Gemini { $global:LASTEXITCODE = 1; throw "broken" }
            Mock Get-UserEnvironmentPath { return "C:\Windows\System32" }
            Mock Set-UserEnvironmentPath { }
            Mock Write-Host { }
        }
        AfterEach {
            $env:USERPROFILE = $script:origProfile
        }

        It 'should create shim when called with explicit root and gemini is broken' {
            $handler.EnsureGeminiCommandShim($script:globalRoot)
            $shimPath = Join-Path $TestDrive ".local\bin\gemini.cmd"
            $shimPath | Should -Exist
        }

        It 'should not call pnpm root -g when root is provided' {
            $handler.EnsureGeminiCommandShim($script:globalRoot)
            Should -Invoke Invoke-Pnpm -ParameterFilter { $Arguments -contains "root" } -Times 0
        }

        It 'should return immediately when root is empty string' {
            $handler.EnsureGeminiCommandShim("")
            # 空ルートでは Set-UserEnvironmentPath も Invoke-Gemini も呼ばれない
            Should -Invoke Set-UserEnvironmentPath -Times 0
            Should -Invoke Invoke-Gemini -Times 0
        }
    }
}
