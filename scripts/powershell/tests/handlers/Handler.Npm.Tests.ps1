BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.Npm.ps1
    $script:projectRoot = (Resolve-Path -LiteralPath "$PSScriptRoot/../../../..").Path
}

Describe 'NpmHandler' {
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
            } else {
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

        It 'should skip already installed packages' {
            $ctx.Options["NpmMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個インストール"
            $result.Message | Should -Match "1 個スキップ"
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

        It 'should return success with all installed message' {
            $ctx.Options["NpmMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "インストール済み"
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
                } else {
                    $global:LASTEXITCODE = 1
                }
                return "output"
            }
        }

        It 'should return success with partial failure info' {
            $ctx.Options["NpmMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "1 個成功"
            $result.Message | Should -Match "1 個失敗"
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
}
