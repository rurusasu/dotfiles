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
        }

        It 'should install pnpm global packages after nixos-rebuild' {
            $script:pnpmArgs = ""
            Mock Get-JsonContent {
                return @{ globalPackages = @("@google/gemini-cli", "@anthropic-ai/claude-code") }
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

        It 'should skip already installed pnpm packages' {
            $script:pnpmAddCalled = $false
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "pnpm ls -g") {
                    $global:LASTEXITCODE = 0
                    return @("@google/gemini-cli@0.32.1", "@anthropic-ai/claude-code@2.1.70")
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

        It 'should succeed even when pnpm global install fails' {
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

            # pnpm add 失敗でも Apply 自体は成功とみなす
            $result.Success | Should -Be $true
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

        It 'should succeed even when corepack enable fails' {
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

            # corepack 失敗 → EnsurePnpmAvailable が throw → InstallPnpmGlobalPackages の catch で握りつぶし
            $result.Success | Should -Be $true
        }

        It 'should setup PNPM_HOME when directory does not exist' {
            $script:pnpmSetupCalled = $false
            $script:bashrcUpdated = $false
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm setup") { $script:pnpmSetupCalled = $true; $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "grep.*PNPM_HOME") { $script:bashrcUpdated = $true; $global:LASTEXITCODE = 0; return "" }
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
                if ($argStr -match "-l -q")
                {
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

        It 'should return early when dotfiles already exist' {
            $script:linkCalled = $false
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "ln -sf") { $script:linkCalled = $true; $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }

            $handler.EnsureDotfilesAvailable("NixOS", "D:\ruru\dotfiles")

            $script:linkCalled | Should -Be $false
        }

        It 'should create symlink when dotfiles missing but WSL mount accessible' {
            $script:linkArgs = ""
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 1; return "" }
                if ($argStr -match "test -d") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "ln -sf") { $script:linkArgs = $argStr; $global:LASTEXITCODE = 0; return "" }
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
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 1; return "" }
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
                if ($argStr -match "test -e") { $global:LASTEXITCODE = 1; return "" }
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
