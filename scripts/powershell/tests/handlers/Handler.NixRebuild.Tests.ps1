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
    $script:projectRoot = git -C $PSScriptRoot rev-parse --show-toplevel
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

        It 'should set Order to 15' {
            $handler.Order | Should -Be 15
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

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }
    }

    Context 'Apply' {
        BeforeEach {
            Mock Write-Host { }
        }

        It 'should succeed when nixos-rebuild switch succeeds' {
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "-l -q") { $global:LASTEXITCODE = 0; return @("NixOS") }
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return @("building NixOS...") }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") { $global:LASTEXITCODE = 0; return @("installed") }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return @("pre-commit installed") }
                return ""
            }
            $handler.CanApply($ctx)

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Be "NixOS 設定を適用しました"
        }

        It 'should fail when nixos-rebuild switch fails' {
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "-l -q") { $global:LASTEXITCODE = 0; return @("NixOS") }
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 1; return @("error: build failed") }
                return ""
            }
            $handler.CanApply($ctx)

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "nixos-rebuild switch が失敗しました"
        }

        It 'should install pnpm global packages after nixos-rebuild' {
            $script:pnpmArgs = ""
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "-l -q") { $global:LASTEXITCODE = 0; return @("NixOS") }
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") {
                    $script:pnpmArgs = $argStr
                    $global:LASTEXITCODE = 0
                    return @("installed opencode-ai")
                }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                return ""
            }
            $handler.CanApply($ctx)

            $handler.Apply($ctx)

            $script:pnpmArgs | Should -Match "pnpm add -g"
            $script:pnpmArgs | Should -Match "gemini-cli"
        }

        It 'should skip already installed pnpm packages' {
            $script:pnpmAddCalled = $false
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "-l -q") { $global:LASTEXITCODE = 0; return @("NixOS") }
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
                return ""
            }
            $handler.CanApply($ctx)

            $handler.Apply($ctx)

            $script:pnpmAddCalled | Should -Be $false
        }

        It 'should succeed even when pnpm global install fails' {
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "-l -q") { $global:LASTEXITCODE = 0; return @("NixOS") }
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") { $global:LASTEXITCODE = 1; return @("error") }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                return ""
            }
            $handler.CanApply($ctx)

            $result = $handler.Apply($ctx)

            # pnpm add 失敗でも Apply 自体は成功とみなす
            $result.Success | Should -Be $true
        }

        It 'should pass correct arguments to WSL' {
            $script:wslArgs = ""
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "-l -q") { $global:LASTEXITCODE = 0; return @("NixOS") }
                if ($argStr -match "nixos-rebuild") { $script:wslArgs = $argStr; $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                return ""
            }
            $handler.CanApply($ctx)

            $handler.Apply($ctx)

            $script:wslArgs | Should -Match "-d NixOS"
            $script:wslArgs | Should -Match "-u root"
            $script:wslArgs | Should -Match "cd /home/nixos/.dotfiles"
            $script:wslArgs | Should -Match "nixos-rebuild switch --flake"
        }

        It 'should use custom distro name from context' {
            $ctx.DistroName = "CustomNixOS"
            $script:wslArgs = ""
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "-l -q") { $global:LASTEXITCODE = 0; return @("CustomNixOS") }
                if ($argStr -match "nixos-rebuild") { $script:wslArgs = $argStr; $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                return ""
            }
            $handler.CanApply($ctx)

            $handler.Apply($ctx)

            $script:wslArgs | Should -Match "-d CustomNixOS"
        }

        It 'should install pre-commit hooks after pnpm packages' {
            $script:callOrder = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "-l -q") { $global:LASTEXITCODE = 0; return @("NixOS") }
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
                return ""
            }
            $handler.CanApply($ctx)

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
                if ($argStr -match "-l -q") { $global:LASTEXITCODE = 0; return @("NixOS") }
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 1; return @("error") }
                return ""
            }
            $handler.CanApply($ctx)

            $result = $handler.Apply($ctx)

            # pre-commit install 失敗でも Apply 自体は成功とみなす
            $result.Success | Should -Be $true
        }

        It 'should pass correct WSL args for pre-commit install' {
            $script:preCommitArgs = ""
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "-l -q") { $global:LASTEXITCODE = 0; return @("NixOS") }
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
                return ""
            }
            $handler.CanApply($ctx)

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
                if ($argStr -match "-l -q") { $global:LASTEXITCODE = 0; return @("NixOS") }
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 0; return "/nix/store/bin/pnpm" }
                if ($argStr -match "corepack") { $script:corepakCalled = $true; $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                return ""
            }
            $handler.CanApply($ctx)

            $handler.Apply($ctx)

            $script:corepakCalled | Should -Be $false
        }

        It 'should enable pnpm via corepack when pnpm is not found' {
            $script:corepakCalled = $false
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "-l -q") { $global:LASTEXITCODE = 0; return @("NixOS") }
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 1; return "" }
                if ($argStr -match "corepack") { $script:corepakCalled = $true; $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm ls -g") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pnpm add") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                return ""
            }
            $handler.CanApply($ctx)

            $handler.Apply($ctx)

            $script:corepakCalled | Should -Be $true
        }

        It 'should succeed even when corepack enable fails' {
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "-l -q") { $global:LASTEXITCODE = 0; return @("NixOS") }
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "command -v pnpm") { $global:LASTEXITCODE = 1; return "" }
                if ($argStr -match "corepack") { $global:LASTEXITCODE = 1; return @("error") }
                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                return ""
            }
            $handler.CanApply($ctx)

            $result = $handler.Apply($ctx)

            # corepack 失敗 → EnsurePnpmAvailable が throw → InstallPnpmGlobalPackages の catch で握りつぶし
            $result.Success | Should -Be $true
        }

        It 'should unset core.hooksPath before pre-commit install' {
            $script:hooksPathUnset = $false
            $script:preCommitCalled = $false
            $script:unsetBeforePreCommit = $false
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "-l -q") { $global:LASTEXITCODE = 0; return @("NixOS") }
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
                return ""
            }
            $handler.CanApply($ctx)

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
                throw "WSL error"
            }
            $handler.CanApply($ctx)

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "WSL error"
        }
    }
}
