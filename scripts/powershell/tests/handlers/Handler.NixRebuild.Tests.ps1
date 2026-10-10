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
        }

        It 'should succeed when nixos-rebuild switch succeeds' {
            $script:nixosRebuildTimeoutSeconds = $null
            Mock Invoke-Wsl {
                param($Arguments, $TimeoutSeconds)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $script:nixosRebuildTimeoutSeconds = $TimeoutSeconds; $global:LASTEXITCODE = 0; return @("building NixOS...") }

                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return @("pre-commit installed") }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }

                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Be "NixOS 設定を適用しました"
            $script:nixosRebuildTimeoutSeconds | Should -Be 5400
            $ctx.Options["NixRebuildApplied"] | Should -Be $true
            Should -Invoke Write-Host -ParameterFilter {
                $ForegroundColor -eq 'Gray' -and ([string]$Object) -match 'building NixOS'
            } -Times 1
            Should -Invoke Invoke-Wsl -ParameterFilter {
                ($Arguments -join " ") -match "nixos-rebuild" -and
                ($Arguments -join " ") -match "--option accept-flake-config true"
            } -Times 1
        }

        It 'should fail when nixos-rebuild switch fails' {
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 1; return @("error: build failed") }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }

                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $ctx.Options.ContainsKey("NixRebuildApplied") | Should -Be $false
            $result.Message | Should -Match "nixos-rebuild switch が失敗しました"
            $result.Message | Should -Match "error: build failed"
            Should -Invoke Write-Host -ParameterFilter {
                $ForegroundColor -eq 'Red' -and ([string]$Object) -match 'error: build failed'
            } -Times 1
        }

        It 'should pass correct arguments to WSL' {
            $script:wslArgs = ""
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $script:wslArgs = $argStr; $global:LASTEXITCODE = 0; return "" }

                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }

                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $handler.Apply($ctx)

            $script:wslArgs | Should -Match "-d NixOS"
            $script:wslArgs | Should -Match "-u root"
            $script:wslArgs | Should -Match "nixos-rebuild switch --flake .#nixos --impure"
            $script:wslArgs | Should -Not -Match '--fast|--no-reexec|systemd-run --help'
        }

        It 'should pass the Hermes feature to the NixOS rebuild wrapper' {
            $script:wslArgs = ''
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join ' '
                if ($argStr -match 'nixos-rebuild') { $script:wslArgs = $argStr; $global:LASTEXITCODE = 0; return '' }

                if ($argStr -match 'core\.hooksPath|pre-commit install|echo exists|test -e') { $global:LASTEXITCODE = 0; return '' }
                $global:LASTEXITCODE = 0
                return ''
            }

            $handler.Apply($ctx)

            Should -Invoke Invoke-Wsl -ParameterFilter {
                ($Arguments -join ' ') -match '\bdocker\b'
            } -Times 0
        }

        It 'should update the flake lock before nixos-rebuild so Nix packages use latest inputs' {
            $script:flakeUpdateCalled = $false
            $script:rebuildCalled = $false
            $script:flakeUpdateCalledFirst = $false
            $script:flakeUpdateArgs = ""
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "flake update --flake") {
                    $script:flakeUpdateArgs = $argStr
                    $script:flakeUpdateCalled = $true
                    if (-not $script:rebuildCalled) { $script:flakeUpdateCalledFirst = $true }
                    $global:LASTEXITCODE = 0; return @("updated lock file")
                }
                if ($argStr -match "nixos-rebuild") { $script:rebuildCalled = $true; $global:LASTEXITCODE = 0; return "" }

                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }

                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $handler.Apply($ctx)

            $script:flakeUpdateCalled | Should -Be $true
            $script:flakeUpdateCalledFirst | Should -Be $true
            $script:flakeUpdateArgs | Should -Match "-u nixos"
        }

        It 'should update flake inputs with explicit Nix features before switching' {
            $script:flakeUpdateArgs = ''
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join ' '
                if ($argStr -match 'flake update --flake') {
                    $script:flakeUpdateArgs = $argStr
                }
                if ($argStr -match 'nixos-rebuild') { $global:LASTEXITCODE = 0; return '' }

                if ($argStr -match 'core\.hooksPath|pre-commit install|echo exists|test -e') { $global:LASTEXITCODE = 0; return '' }
                $global:LASTEXITCODE = 0
                return ''
            }

            $handler.Apply($ctx)

            $script:flakeUpdateArgs | Should -Match "--extra-experimental-features 'nix-command flakes' flake update --flake \."
        }

        It 'should update flake inputs even when a legacy skip option is supplied' {
            $ctx.Options['SkipFlakeUpdate'] = $true
            $script:flakeUpdateCalled = $false
            $script:rebuildCalled = $false
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "flake update --flake") { $script:flakeUpdateCalled = $true }
                if ($argStr -match "nixos-rebuild") { $script:rebuildCalled = $true; $global:LASTEXITCODE = 0; return "" }

                if ($argStr -match "core\.hooksPath|pre-commit install|echo exists|test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0
                return ""
            }

            $result = $handler.Apply($ctx)

            $result.Success | Should -BeTrue
            $script:flakeUpdateCalled | Should -BeTrue
            $script:rebuildCalled | Should -BeTrue
        }

        It 'should rebuild without writing Git trust or global configuration' {
            $script:gitConfigCalled = $false
            $script:rebuildCalled = $false
            $script:gitCalledFirst = $false
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match 'dotfiles_trust_git_directory|git config --global') {
                    $script:gitConfigCalled = $true
                    if (-not $script:rebuildCalled) { $script:gitCalledFirst = $true }
                    $global:LASTEXITCODE = 0; return ""
                }
                if ($argStr -match "nixos-rebuild") { $script:rebuildCalled = $true; $global:LASTEXITCODE = 0; return "" }

                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }

                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $handler.Apply($ctx)

            $script:gitConfigCalled | Should -BeFalse
            $script:rebuildCalled | Should -BeTrue
        }

        It 'should not invoke a mutable Git trust bootstrap' {
            Mock Invoke-Wsl {
                param($Arguments)
                $global:LASTEXITCODE = 0
                if (($Arguments -join ' ') -match '-u root.*dotfiles_trust_git_directory') {
                    $global:LASTEXITCODE = 1
                }
                return ''
            }
            $result = $handler.Apply($ctx)

            Should -Invoke Invoke-Wsl -Times 0 -ParameterFilter { ($Arguments -join ' ') -match 'dotfiles_trust_git_directory' }
            Should -Invoke Invoke-Wsl -Times 1 -ParameterFilter { ($Arguments -join ' ') -match 'nixos-rebuild' }
        }

        It 'should validate native Hermes using the resolved NixOS user and distro' {
            $ctx.DistroName = 'CustomNixOS'
            $script:hermesArguments = @()
            Mock Invoke-Wsl {
                param($Arguments)
                $global:LASTEXITCODE = 0
                if (($Arguments -join ' ') -match '/var/lib/dotfiles/user') {
                    return "alice`t/home/alice"
                }
                if (($Arguments -join ' ') -match 'hermes-agent.service') {
                    $script:hermesArguments = $Arguments
                    return 'hermes 1.0.0'
                }
                return ''
            }
            Mock Get-JsonContent { return @{ globalPackages = @() } }
            Mock Invoke-Docker { throw 'Hermes must run directly in NixOS' }

            $result = $handler.Apply($ctx)

            $result.Success | Should -BeTrue
            ($script:hermesArguments -join ' ') | Should -Match '-d CustomNixOS -u alice'
            ($script:hermesArguments -join ' ') | Should -Match 'XDG_RUNTIME_DIR=/run/user/'
            ($script:hermesArguments -join ' ') | Should -Match 'command -v hermes'
        }

        It 'should fail NixOS setup when native Hermes service validation fails' {
            Mock Invoke-Wsl {
                param($Arguments)
                $global:LASTEXITCODE = 0
                if (($Arguments -join ' ') -match 'hermes-agent.service') {
                    $global:LASTEXITCODE = 3
                    return 'inactive'
                }
                return ''
            }
            Mock Get-JsonContent { return @{ globalPackages = @() } }

            $result = $handler.Apply($ctx)

            $result.Success | Should -BeFalse
            $result.Message | Should -Match 'Hermes.*inactive'
            $ctx.Options.ContainsKey('NixRebuildApplied') | Should -BeFalse
        }

        It 'should use custom distro name from context' {
            $ctx.DistroName = "CustomNixOS"
            $script:wslArgs = ""
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $script:wslArgs = $argStr; $global:LASTEXITCODE = 0; return "" }

                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }

                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $handler.Apply($ctx)

            $script:wslArgs | Should -Match "-d CustomNixOS"
        }

        It 'should install pre-commit hooks after nixos-rebuild' {
            $script:callOrder = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $script:callOrder.Add("nixos-rebuild"); $global:LASTEXITCODE = 0; return "" }

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

                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $script:callOrder | Should -Contain "nixos-rebuild"
            $script:callOrder | Should -Contain "unset-hookspath"
            $script:callOrder | Should -Contain "pre-commit"
            $script:callOrder.IndexOf("nixos-rebuild") | Should -BeLessThan $script:callOrder.IndexOf("unset-hookspath")
            $script:callOrder.IndexOf("unset-hookspath") | Should -BeLessThan $script:callOrder.IndexOf("pre-commit")
        }

        It 'should succeed even when pre-commit install fails' {
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }

                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") { $global:LASTEXITCODE = 1; return @("error") }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }

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

                if ($argStr -match "core\.hooksPath") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "pre-commit install") {
                    $script:preCommitArgs = $argStr
                    $global:LASTEXITCODE = 0
                    return ""
                }
                if ($argStr -match "echo exists") { $global:LASTEXITCODE = 0; return "exists" }

                if ($argStr -match "test -e") { $global:LASTEXITCODE = 0; return "" }
                $global:LASTEXITCODE = 0; return ""
            }
            $handler.Apply($ctx)

            $script:preCommitArgs | Should -Match "-d NixOS"
            $script:preCommitArgs | Should -Match "-u nixos"
            $script:preCommitArgs | Should -Match "cd ~/.dotfiles"
            $script:preCommitArgs | Should -Match "pre-commit install --install-hooks"
        }

        It 'should unset core.hooksPath before pre-commit install' {
            $script:hooksPathUnset = $false
            $script:preCommitCalled = $false
            $script:unsetBeforePreCommit = $false
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }

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

            { $handler.EnsureDotfilesAvailable("NixOS", "C:\Users\foo\dotfiles") } | Should -Throw "*dotfiles が見つかりません*"

            $script:mountPath | Should -Be "/mnt/c/Users/foo/dotfiles"
        }

        It 'should resolve the configured WSL user and home instead of assuming nixos' {
            $script:identityArgs = ""
            $script:userArgs = ""
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "/var/lib/dotfiles/user") {
                    $script:identityArgs = $argStr
                    $global:LASTEXITCODE = 0
                    return "alice`t/home/alice"
                }
                if ($argStr -match "-u alice") {
                    $script:userArgs = $argStr
                }
                $global:LASTEXITCODE = 0
                return ""
            }

            $handler.ResolveNixOsIdentity("NixOS")
            $handler.EnsureDotfilesAvailable("NixOS", "D:\ruru\dotfiles")

            $handler.NixOsUser | Should -Be "alice"
            $handler.NixOsHome | Should -Be "/home/alice"
            $script:identityArgs | Should -Match "-u root"
            $script:userArgs | Should -Match "-u alice"
        }
    }
}
