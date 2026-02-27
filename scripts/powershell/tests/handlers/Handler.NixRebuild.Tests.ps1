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
                if ($argStr -match "bun install") { $global:LASTEXITCODE = 0; return @("installed") }
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

        It 'should install bun global packages after nixos-rebuild' {
            $script:bunArgs = ""
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "-l -q") { $global:LASTEXITCODE = 0; return @("NixOS") }
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "bun install") {
                    $script:bunArgs = $argStr
                    $global:LASTEXITCODE = 0
                    return @("installed opencode-ai")
                }
                return ""
            }
            $handler.CanApply($ctx)

            $handler.Apply($ctx)

            $script:bunArgs | Should -Match "bun install -g"
            $script:bunArgs | Should -Match "opencode-ai"
        }

        It 'should succeed even when bun install fails' {
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "-l -q") { $global:LASTEXITCODE = 0; return @("NixOS") }
                if ($argStr -match "nixos-rebuild") { $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "bun install") { $global:LASTEXITCODE = 1; return @("error") }
                return ""
            }
            $handler.CanApply($ctx)

            $result = $handler.Apply($ctx)

            # bun install 失敗でも Apply 自体は成功とみなす
            $result.Success | Should -Be $true
        }

        It 'should pass correct arguments to WSL' {
            $script:wslArgs = ""
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "-l -q") { $global:LASTEXITCODE = 0; return @("NixOS") }
                if ($argStr -match "nixos-rebuild") { $script:wslArgs = $argStr; $global:LASTEXITCODE = 0; return "" }
                if ($argStr -match "bun install") { $global:LASTEXITCODE = 0; return "" }
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
                if ($argStr -match "bun install") { $global:LASTEXITCODE = 0; return "" }
                return ""
            }
            $handler.CanApply($ctx)

            $handler.Apply($ctx)

            $script:wslArgs | Should -Match "-d CustomNixOS"
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
