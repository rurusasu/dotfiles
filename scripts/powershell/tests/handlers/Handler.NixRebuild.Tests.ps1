#Requires -Module Pester

<#
.SYNOPSIS
    Handler.NixRebuild.ps1 のユニットテスト

.DESCRIPTION
    NixRebuildHandler クラスのテスト
#>

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.NixRebuild.ps1
    $script:projectRoot = (Resolve-Path -LiteralPath "$PSScriptRoot/../../../..").Path
}

Describe 'NixRebuildHandler' {
    BeforeEach {
        $script:handler = [NixRebuildHandler]::new()
        $script:ctx = [SetupContext]::new($script:projectRoot)
    }

    Context 'Constructor' {
        It 'should set Name to NixRebuild' {
            $handler.Name | Should -Be "NixRebuild"
        }

        It 'should set Description correctly' {
            $handler.Description | Should -Be "nixos-rebuild switch の実行"
        }

        It 'should set Order to 55' {
            $handler.Order | Should -Be 55
        }

        It 'should set RequiresAdmin to False' {
            $handler.RequiresAdmin | Should -Be $false
        }
    }

    Context 'CanApply' {
        It 'should return false when SkipNixRebuild is true' {
            Mock Write-Host { }
            $ctx.Options["SkipNixRebuild"] = $true

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'should return false when WSL is not available' {
            Mock Invoke-Wsl {
                $global:LASTEXITCODE = 1
                return ""
            }
            Mock Write-Host { }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'should return false when WSL command throws' {
            Mock Invoke-Wsl {
                throw "Wsl/CallMsi/Install/REGDB_E_CLASSNOTREG"
            }
            Mock Write-Host { }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'should return false when distro does not exist' {
            Mock Invoke-Wsl {
                $global:LASTEXITCODE = 0
                return @("Ubuntu", "Debian")
            }
            Mock Write-Host { }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'should return true when distro exists' {
            Mock Invoke-Wsl {
                $global:LASTEXITCODE = 0
                return @("NixOS", "Ubuntu")
            }
            Mock Write-Host { }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }
    }

    Context 'Apply' {
        BeforeEach {
            Mock Write-Host { }
            # windows/pnpm/packages.json が worktree/CI に存在しない場合でも
            # pnpm テストが動作するよう Test-Path をモック
            Mock Test-Path { return $true } -ParameterFilter { $LiteralPath -and $LiteralPath -match 'pnpm.*packages\.json' }
        }

        It 'should succeed when nixos-rebuild switch succeeds' {
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return @("building NixOS...") }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") { $global:LASTEXITCODE = 0; return @("installed") }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return @("pre-commit installed") }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }
                if ($argStr -match "pnpm setup") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Be "NixOS 設定を適用しました"
            Should -Invoke Write-Host -ParameterFilter {
                $ForegroundColor -eq 'Gray' -and ([string]$Object) -match 'building NixOS'
            } -Times 1
        }

        It 'should fail when nixos-rebuild switch fails' {
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 1; return @("error: build failed") }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }
                if ($argStr -match "pnpm setup") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "nixos-rebuild switch が失敗しました"
            $result.Message | Should -Match "error: build failed"
            Should -Invoke Write-Host -ParameterFilter {
                $ForegroundColor -eq 'Red' -and ([string]$Object) -match 'error: build failed'
            } -Times 1
        }

        It 'should install pnpm global packages after nixos-rebuild' {
            $script:pnpmArgs = ""
            Mock Get-JsonContent {
                return @{ globalPackages = @("@example/native-tool", "@google/gemini-cli") }
            }
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") {
                    $script:pnpmArgs = $argStr
                    $global:LASTEXITCODE = 0
                    return @("installed")
                }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }
                if ($argStr -match "pnpm setup") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $handler.Apply($ctx)

            $script:pnpmArgs | Should -Match "pnpm add -g"
            $script:pnpmArgs | Should -Match "gemini-cli"
        }

        It 'should stream WSL pnpm install output to the CLI' {
            Mock Get-JsonContent {
                return @{ globalPackages = @("@example/native-tool", "@google/gemini-cli") }
            }
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") {
                    $global:LASTEXITCODE = 0
                    return @("Progress: resolved 2", "Done in 2s")
                }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }
                if ($argStr -match "pnpm setup") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            Should -Invoke Write-Host -ParameterFilter {
                $ForegroundColor -eq "Gray" -and ([string]$Object) -match "Progress: resolved 2"
            } -Times 1
            Should -Invoke Write-Host -ParameterFilter {
                $ForegroundColor -eq "Gray" -and ([string]$Object) -match "Done in 2s"
            } -Times 1
        }

        It 'should install every configured WSL pnpm tool without timeout' {
            $script:pnpmArgs = ""
            Mock Get-JsonContent {
                return @{ globalPackages = @(
                        @{ name = "@prisma/language-server" },
                        @{ name = "@agentclientprotocol/claude-agent-acp" },
                        @{ name = "typescript-language-server" },
                        @{
                            name        = "@google/gemini-cli"
                            installArgs = @("--allow-build=@github/keytar", "--allow-build=node-pty")
                        }
                    )
                }
            }
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") {
                    $script:pnpmArgs = $argStr
                    $global:LASTEXITCODE = 0
                    return "installed"
                }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }
                if ($argStr -match "pnpm setup") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $script:pnpmArgs | Should -Match "pnpm add -g"
            $script:pnpmArgs | Should -Match "--reporter=append-only"
            $script:pnpmArgs | Should -Match "--yes"
            $script:pnpmArgs | Should -Match '\$PNPM_HOME/bin:\$PNPM_HOME'
            $script:pnpmArgs | Should -Match "@prisma/language-server"
            $script:pnpmArgs | Should -Match "@agentclientprotocol/claude-agent-acp"
            $script:pnpmArgs | Should -Match "typescript-language-server"
            $script:pnpmArgs | Should -Match "@google/gemini-cli"
            $script:pnpmArgs | Should -Match "--allow-build=@github/keytar"
            $script:pnpmArgs | Should -Match "--allow-build=node-pty"
            $script:pnpmArgs | Should -Not -Match "\btimeout\b"
        }

        It 'should run WSL pnpm verification with visible output and timeout guard' {
            $script:verifyArgs = ""
            Mock Get-JsonContent {
                return @{ globalPackages = @(
                        @{ name = "@agentclientprotocol/claude-agent-acp"; verifyCommand = @{ command = "claude-agent-acp"; args = @("--version") } }
                    )
                }
            }
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") { $global:LASTEXITCODE = 0; return "installed" }
                if ($argStr -match "timeout 30s") {
                    $script:verifyArgs = $argStr
                    $global:LASTEXITCODE = 0
                    return "0.41.0"
                }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }
                if ($argStr -match "pnpm setup") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $script:verifyArgs | Should -Match "timeout 30s"
            $script:verifyArgs | Should -Match '\$PNPM_HOME/bin:\$PNPM_HOME'
            $script:verifyArgs | Should -Match "claude-agent-acp"
            $script:verifyArgs | Should -Match "--version"
            Should -Invoke Write-Host -ParameterFilter {
                $ForegroundColor -eq "Gray" -and ([string]$Object) -match "検証中: claude-agent-acp --version"
            } -Times 1
            Should -Invoke Write-Host -ParameterFilter {
                $ForegroundColor -eq "Gray" -and ([string]$Object) -match "0.41.0"
            } -Times 1
        }

        It 'should verify WSL stdio pnpm tools by command existence without executing them' {
            $script:verifyArgs = ""
            Mock Get-JsonContent {
                return @{ globalPackages = @(
                        @{ name = "@agentclientprotocol/claude-agent-acp"; verifyCommand = @{ type = "commandExists"; command = "claude-agent-acp"; args = @() } }
                    )
                }
            }
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") { $global:LASTEXITCODE = 0; return "installed" }
                if ($argStr -match "timeout 30s bash -lc" -and $argStr -match "command -v") {
                    $script:verifyArgs = $argStr
                    $global:LASTEXITCODE = 0
                    return "/home/nixos/.npm-global/bin/claude-agent-acp"
                }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }
                if ($argStr -match "pnpm setup") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $script:verifyArgs | Should -Match "timeout 30s bash -lc"
            $script:verifyArgs | Should -Match "command -v"
            $script:verifyArgs | Should -Match "claude-agent-acp"
            Should -Invoke Write-Host -ParameterFilter {
                $ForegroundColor -eq "Gray" -and ([string]$Object) -match "検証中: command -v claude-agent-acp"
            } -Times 1
        }

        It 'should fail WSL pnpm verification clearly when timeout expires' {
            Mock Get-JsonContent {
                return @{ globalPackages = @(
                        @{ name = "@agentclientprotocol/claude-agent-acp"; verifyCommand = @{ command = "claude-agent-acp"; args = @("--version") } }
                    )
                }
            }
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") { $global:LASTEXITCODE = 0; return "installed" }
                if ($argStr -match "timeout 30s") { $global:LASTEXITCODE = 124; return "" }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }
                if ($argStr -match "pnpm setup") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "pnpm グローバルパッケージのインストールまたは検証に失敗しました"
            Should -Invoke Write-Host -ParameterFilter {
                $ForegroundColor -eq "Yellow" -and ([string]$Object) -match "タイムアウト"
            } -Times 1
        }

        It 'should install pnpm global packages when entries are objects with name field' {
            $script:pnpmArgs = ""
            Mock Get-JsonContent {
                return @{ globalPackages = @(
                        @{
                            name          = "@example/native-tool"
                            installArgs   = @("--allow-build", "native-addon")
                            verifyCommand = @{ command = "native-tool"; args = @("status") }
                        },
                        @{ name = "@google/gemini-cli" }
                    )
                }
            }
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") {
                    $script:pnpmArgs = $argStr
                    $global:LASTEXITCODE = 0
                    return @("installed")
                }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }
                if ($argStr -match "pnpm setup") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $handler.Apply($ctx)

            $script:pnpmArgs | Should -Match "pnpm add -g"
            $script:pnpmArgs | Should -Match "--allow-build"
            $script:pnpmArgs | Should -Match "native-addon"
            $script:pnpmArgs | Should -Match "gemini-cli"
            $script:pnpmArgs | Should -Not -Match "@\{name="
        }

        It 'should skip already installed pnpm packages' {
            $script:pnpmAddCalled = $false
            Mock Get-JsonContent {
                return @{ globalPackages = @(
                        "@example/native-tool",
                        "@prisma/language-server",
                        "@agentclientprotocol/claude-agent-acp",
                        "typescript-language-server",
                        "typescript",
                        "@google/gemini-cli"
                    )
                }
            }
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "pnpm ls -g") {
                    $global:LASTEXITCODE = 0
                    return @("@example/native-tool@1.0.0", "@prisma/language-server@5.22.0", "@agentclientprotocol/claude-agent-acp@1.0.0", "typescript-language-server@4.3.3", "typescript@5.6.3", "@google/gemini-cli@0.32.1")
                }
                if ($argStr -match "pnpm add") {
                    $script:pnpmAddCalled = $true
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }
                if ($argStr -match "pnpm setup") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $handler.Apply($ctx)

            $script:pnpmAddCalled | Should -Be $false
        }

        It 'should reinstall installed pnpm package when verifyCommand fails in WSL' {
            $script:pnpmAddCalled = $false
            $script:verifyCalls = 0
            Mock Get-JsonContent {
                return @{ globalPackages = @(
                        @{ name = "@example/native-tool"; verifyCommand = @{ command = "native-tool"; args = @("status") } }
                    )
                }
            }
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "pnpm ls -g") {
                    $global:LASTEXITCODE = 0
                    return @("@example/native-tool@1.0.0")
                }
                if ($argStr -match "native-tool.*status") {
                    $script:verifyCalls++
                    if ($script:verifyCalls -eq 1) {
                        $global:LASTEXITCODE = 1
                        return "native-tool not found"
                    }
                    $global:LASTEXITCODE = 0
                    return "ok"
                }
                if ($argStr -match "pnpm add") {
                    $script:pnpmAddCalled = $true
                    $global:LASTEXITCODE = 0
                    return @("installed")
                }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }
                if ($argStr -match "pnpm setup") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $script:pnpmAddCalled | Should -Be $true
            $script:verifyCalls | Should -Be 2
        }

        It 'should fail when pnpm global install fails' {
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") { $global:LASTEXITCODE = 1; return @("error") }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }
                if ($argStr -match "pnpm setup") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "pnpm グローバルパッケージ"
        }

        It 'should pass correct arguments to WSL' {
            $script:wslArgs = ""
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $script:wslArgs = $argStr; $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }
                if ($argStr -match "pnpm setup") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $handler.Apply($ctx)

            $script:wslArgs | Should -Match "-d NixOS"
            $script:wslArgs | Should -Match "-u root"
            $script:wslArgs | Should -Match "cd /home/nixos/.dotfiles"
            $script:wslArgs | Should -Match "nixos-rebuild switch --flake"
        }

        It 'should set git safe.directory before nixos-rebuild as root' {
            $script:gitConfigCalled = $false
            $script:rebuildCalled = $false
            $script:gitCalledFirst = $false
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "grep.*directory.*gitconfig|printf.*\[safe\]") {
                    $script:gitConfigCalled = $true
                    if (-not $script:rebuildCalled) { $script:gitCalledFirst = $true }
                    $global:LASTEXITCODE = 0; return ""
                }
                if ($argStr -match "nixos-rebuild") { $script:rebuildCalled = $true; $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }
                if ($argStr -match "pnpm setup") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $handler.Apply($ctx)

            $script:gitConfigCalled | Should -Be $true
            $script:gitCalledFirst | Should -Be $true
        }

        It 'should use custom distro name from context' {
            $ctx.DistroName = "CustomNixOS"
            $script:wslArgs = ""
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $script:wslArgs = $argStr; $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }
                if ($argStr -match "pnpm setup") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $handler.Apply($ctx)

            $script:wslArgs | Should -Match "-d CustomNixOS"
        }

        It 'should install pre-commit hooks after pnpm packages' {
            $script:callOrder = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") {
                    $script:callOrder.Add("pnpm")
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "core\.hooksPath") {
                    $script:callOrder.Add("unset-hookspath")
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "pre-commit install") {
                    $script:callOrder.Add("pre-commit")
                    $global:LASTEXITCODE = 0
                    return @("pre-commit installed at .git/hooks/pre-commit")
                }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }
                if ($argStr -match "pnpm setup") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $script:callOrder | Should -Contain "pnpm"
            $script:callOrder | Should -Contain "unset-hookspath"
            $script:callOrder | Should -Contain "pre-commit"
            $script:callOrder.IndexOf("pnpm") | Should -BeLessThan $script:callOrder.IndexOf("unset-hookspath")
            $script:callOrder.IndexOf("unset-hookspath") | Should -BeLessThan $script:callOrder.IndexOf("pre-commit")
        }

        It 'should succeed even when pre-commit install fails' {
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 1; return @("error") }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }
                if ($argStr -match "pnpm setup") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $result = $handler.Apply($ctx)

            # pre-commit install 失敗でも Apply 自体は成功とみなす
            $result.Success | Should -Be $true
        }

        It 'should pass correct WSL args for pre-commit install' {
            $script:preCommitArgs = ""
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") {
                    $script:preCommitArgs = $argStr
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }
                if ($argStr -match "pnpm setup") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $handler.Apply($ctx)

            $script:preCommitArgs | Should -Match "-d NixOS"
            $script:preCommitArgs | Should -Match "-u nixos"
            $script:preCommitArgs | Should -Match "cd ~/.dotfiles"
            $script:preCommitArgs | Should -Match "pre-commit install --install-hooks"
        }

        It 'should not call corepack when pnpm is already available' {
            $script:corepakCalled = $false
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "npm install -g pnpm") { $script:corepakCalled = $true; $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }
                if ($argStr -match "pnpm setup") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $handler.Apply($ctx)

            $script:corepakCalled | Should -Be $false
        }

        It 'should install native pnpm when only Windows interop pnpm is found via /mnt/' {
            $script:npmInstallCalled = $false
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                # grep -qv '^/mnt/' で /mnt/ パスを弾く → exit 1 を返す
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 1; return "" }
                if ($argStr -match "npm install -g pnpm") { $script:npmInstallCalled = $true; $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }
                if ($argStr -match "pnpm setup") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $handler.Apply($ctx)

            $script:npmInstallCalled | Should -Be $true
        }

        It 'should enable pnpm via corepack when pnpm is not found' {
            $script:corepakCalled = $false
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 1; return "" }
                if ($argStr -match "npm install -g pnpm") { $script:corepakCalled = $true; $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }
                if ($argStr -match "pnpm setup") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $handler.Apply($ctx)

            $script:corepakCalled | Should -Be $true
        }

        It 'should fail when pnpm bootstrap fails' {
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 1; return "" }
                if ($argStr -match "npm install -g pnpm") { $global:LASTEXITCODE = 1; return @("error") }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }
                if ($argStr -match "pnpm setup") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "pnpm グローバルパッケージ"
        }

        It 'should setup PNPM_HOME when directory does not exist' {
            $script:pnpmSetupCalled = $false
            $script:bashrcUpdated = $false
            $script:pnpmHomeCheckArgs = ""
            $script:pnpmSetupArgs = ""
            $script:bashrcArgs = ""
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "echo exists") { $script:pnpmHomeCheckArgs = $argStr; $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm setup") { $script:pnpmSetupCalled = $true; $script:pnpmSetupArgs = $argStr; $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $script:bashrcUpdated = $true; $script:bashrcArgs = $argStr; $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $script:pnpmSetupCalled | Should -Be $true
            $script:bashrcUpdated | Should -Be $true
            $script:pnpmHomeCheckArgs | Should -Match '\$PNPM_HOME/bin'
            $script:pnpmSetupArgs | Should -Match '\$PNPM_HOME/bin'
            $script:bashrcArgs | Should -Match '\$PNPM_HOME/bin:\$PNPM_HOME'
        }

        It 'should skip PNPM_HOME setup when directory already exists' {
            $script:pnpmSetupCalled = $false
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }
                if ($argStr -match "pnpm setup") { $script:pnpmSetupCalled = $true; $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $script:pnpmSetupCalled | Should -Be $false
        }

        It 'should unset core.hooksPath before pre-commit install' {
            $script:hooksPathUnset = $false
            $script:preCommitCalled = $false
            $script:unsetBeforePreCommit = $false
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "core\.hooksPath") {
                    $script:hooksPathUnset = $true
                    $global:LASTEXITCODE = 0; return ""
                }
                if ($argStr -match "pre-commit install") {
                    $script:preCommitCalled = $true
                    $script:unsetBeforePreCommit = $script:hooksPathUnset
                    $global:LASTEXITCODE = 0; return ""
                }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }
                if ($argStr -match "pnpm setup") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $handler.Apply($ctx)

            $script:hooksPathUnset | Should -Be $true
            $script:preCommitCalled | Should -Be $true
            $script:unsetBeforePreCommit | Should -Be $true
        }

        It 'should return failure when exception is thrown' {
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "-l -q") {
                    $global:LASTEXITCODE = 0
                    return @("NixOS")
                }
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }
                if ($argStr -match "pnpm setup") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $global:LASTEXITCODE = 0; return "" }
                throw "WSL error"
            }
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "WSL error"
        }
    }

    Context 'EnsureDotfilesAvailable' {
        BeforeEach {
            Mock Write-Host { }
        }

        It 'should return early when dotfiles exists as a non-symlink' {
            $script:linkCalled = $false
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "if \[ -L /home/nixos/\.dotfiles \]") { $global:LASTEXITCODE = 0; return "__non_symlink__" }
                if ($argStr -match "ln -sfn") { $script:linkCalled = $true; $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }

            $handler.EnsureDotfilesAvailable("NixOS", "D:\ruru\dotfiles")

            $script:linkCalled | Should -Be $false
        }

        It 'should return early when dotfiles symlink already targets the requested path' {
            $script:linkCalled = $false
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "if \[ -L /home/nixos/\.dotfiles \]") { $global:LASTEXITCODE = 0; return "/mnt/d/ruru/dotfiles" }
                if ($argStr -match "ln -sfn") { $script:linkCalled = $true; $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }

            $handler.EnsureDotfilesAvailable("NixOS", "D:\ruru\dotfiles")

            $script:linkCalled | Should -Be $false
        }

        It 'should update dotfiles symlink when it targets a different path' {
            $script:linkArgs = ""
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "if \[ -L /home/nixos/\.dotfiles \]") { $global:LASTEXITCODE = 0; return "/mnt/d/ruru/dotfiles" }
                if ($argStr -match "test -d") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "ln -sfn") { $script:linkArgs = $argStr; $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }

            $handler.EnsureDotfilesAvailable("NixOS", "D:\ruru\dotfiles-nixrebuild-link-clone")

            $script:linkArgs | Should -Match "ln -sfn"
            $script:linkArgs | Should -Match "/mnt/d/ruru/dotfiles-nixrebuild-link-clone"
            $script:linkArgs | Should -Match "/home/nixos/.dotfiles"
        }

        It 'should create symlink when dotfiles missing but WSL mount accessible' {
            $script:linkArgs = ""
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "if \[ -L /home/nixos/\.dotfiles \]") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -d") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "ln -sfn") { $script:linkArgs = $argStr; $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }

            $handler.EnsureDotfilesAvailable("NixOS", "D:\ruru\dotfiles")

            $script:linkArgs | Should -Match "ln -sf"
            $script:linkArgs | Should -Match "/mnt/d/ruru/dotfiles"
            $script:linkArgs | Should -Match "/home/nixos/.dotfiles"
        }

        It 'should throw when dotfiles missing and WSL mount inaccessible' {
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "if \[ -L /home/nixos/\.dotfiles \]") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -d") { $global:LASTEXITCODE = 1; return "" }
                $global:LASTEXITCODE = 0; return ""
            }

            { $handler.EnsureDotfilesAvailable("NixOS", "D:\ruru\dotfiles") } | Should -Throw
        }

        It 'should convert Windows path to WSL mount path correctly' {
            $script:mountPath = ""
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "if \[ -L /home/nixos/\.dotfiles \]") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "test -d") {
                    # argStr から /mnt/... パスを抽出
                    if ($argStr -match '(/mnt/[^\s"]+)') { $script:mountPath = $Matches[1] }
                    $global:LASTEXITCODE = 1; return ""
                }
                $global:LASTEXITCODE = 0; return ""
            }

            try { $handler.EnsureDotfilesAvailable("NixOS", "C:\Users\foo\dotfiles") } catch { }

            $script:mountPath | Should -Be "/mnt/c/Users/foo/dotfiles"
        }
    }
}
