#Requires -Module Pester

<#
.SYNOPSIS
    Handler.NixRebuild.ps1 ã®ãƒ¦ãƒ‹ãƒƒãƒˆãƒ†ã‚¹ãƒˆ

.DESCRIPTION
    NixRebuildHandler ã‚¯ãƒ©ã‚¹ã®ãƒ†ã‚¹ãƒˆ
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
            $handler.Description | Should -Be "nixos-rebuild switch ã®å®Ÿè¡Œ"
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
            # windows/pnpm/packages.json ãŒ worktree/CI ã«å­˜åœ¨ã—ãªã„å ´åˆã§ã‚‚
            # pnpm ãƒ†ã‚¹ãƒˆãŒå‹•ä½œã™ã‚‹ã‚ˆã† Test-Path ã‚’ãƒ¢ãƒƒã‚¯
            Mock Test-Path { return $true } -ParameterFilter { $LiteralPath -and $LiteralPath -match 'pnpm.*packages\.json' }
        }

        It 'should succeed when nixos-rebuild switch succeeds' {
            $script:nixosRebuildTimeoutSeconds = $null
            Mock Invoke-Wsl {
                param($Arguments, $TimeoutSeconds)
                $argStr = $Arguments -join " "
                if ($argStr -match "nixos-rebuild") { $script:nixosRebuildTimeoutSeconds = $TimeoutSeconds; $global:LASTEXITCODE = 0; return @("building NixOS...") }
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
            $result.Message | Should -Be "NixOS è¨­å®šã‚’é©ç”¨ã—ã¾ã—ãŸ"
            $script:nixosRebuildTimeoutSeconds | Should -Be 5400
            $ctx.Options["NixRebuildApplied"] | Should -Be $true
            Should -Invoke Write-Host -ParameterFilter {
                $ForegroundColor -eq 'Gray' -and ([string]$Object) -match 'building NixOS'
            } -Times 1
            Should -Invoke Invoke-Wsl -ParameterFilter {
                ($Arguments -join " ") -match "nixos-rebuild-with-user" -and
                ($Arguments -join " ") -match "DOTFILES_ACCEPT_FLAKE_CONFIG=1"
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
            $ctx.Options.ContainsKey("NixRebuildApplied") | Should -Be $false
            $result.Message | Should -Match "nixos-rebuild switch ãŒå¤±æ•—ã—ã¾ã—ãŸ"
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
                $ForegroundColor -eq "Gray" -and ([string]$Object) -match "æ¤œè¨¼ä¸­: claude-agent-acp --version"
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
                $ForegroundColor -eq "Gray" -and ([string]$Object) -match "æ¤œè¨¼ä¸­: command -v claude-agent-acp"
            } -Times 1
        }

        It 'should fail WSL pnpm verification clearly when timeout expires' {
            Mock Get-JsonContent {
                return @{ globalPackages = @(
                        @{ name = "@agentclientprotoc_4¶‰ËkºwµçOHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]ÚœœHYŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆš[œİ[YˆBˆYˆ
	\™Ôİˆ[X]Ú[Y[İ]ÌÈŠHÈ	ÛØ˜[“TÕVUÓÑHHLÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÜ™WšÛÚÜÔ]ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Úœ™KXÛÛ[Z][œİ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™XÚÈ^\İÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ™^\İÈˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÙ]\ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™Ü™\Š””WÒÓQHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú\İYHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆB‚ˆ	™\İ[H	[™\‹\J	İ
B‚ˆ	™\İ[”İXØÙ\ÜÈÚİ[P™H	˜[ÙBˆ	™\İ[“Y\ÜØYÙHÚİ[SX]ÚœœH8à¬8àëxàï8àä8àêøàäxààøà¬xàï8à®8àk¸à©8àìøà®xàâ8àï8àêøào¸àgøàkù©':*/8àjùi,y¥eøàeøào¸àeøàgÈ‚ˆÚİ[R[›ÚÙHÜš]KRÜİT\˜[Y]\‘š[\ˆÂˆ	›Ü™YÜ›İ[™ÛÛÜˆY\H–Y[İÈˆX[™
Üİš[™×IØš™Xİ
H[X]Ú¸à¯øà©8àè8à¨¸à©¸àâ‚ˆHU[Y\ÈBˆB‚ˆ]	ÜÚİ[[œİ[œHÛØ˜[XÚØYÙ\ÈÚ[ˆ[šY\È\™HØš™XİÈÚ]˜[YHšY[	ÈÂˆ	ØÜš\œœP\™ÜÈHˆ‚ˆ[ØÚÈÙ]RœÛÛÛÛ[Âˆ™]\›ˆÈÛØ˜[XÚØYÙ\ÈH
ˆÂˆ˜[YHH^[\KÛ˜]]™K]ÛÛ‚ˆ[œİ[\™ÜÈH
‹KX[İËXZ[‹›˜]]™KXYÛˆŠBˆ™\šYPÛÛ[X[™HÈÛÛ[X[™H›˜]]™K]ÛÛÈ\™ÜÈH
œİ]\ÈŠHBˆKˆÈ˜[YHHÛÛÙÛKÙÙ[Z[šKXÛHˆBˆ
BˆBˆBˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]Ú›š^ÜË\™XZ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÛ[X[™]ˆœHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ‹Ûš^ÜİÜ™KØš[‹ÜœHˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÈYÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]ÚœœHYŠHÂˆ	ØÜš\œœP\™ÜÈH	\™Ôİ‚ˆ	ÛØ˜[“TÕVUÓÑHHˆ™]\›ˆ
š[œİ[YŠBˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÜ™WšÛÚÜÔ]ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Úœ™KXÛÛ[Z][œİ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™XÚÈ^\İÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ™^\İÈˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÙ]\ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™Ü™\Š””WÒÓQHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú\İYHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆBˆ	[™\‹\J	İ
B‚ˆ	ØÜš\œœP\™ÜÈÚİ[SX]ÚœœHYYÈ‚ˆ	ØÜš\œœP\™ÜÈÚİ[SX]Ú‹KX[İËXZ[‚ˆ	ØÜš\œœP\™ÜÈÚİ[SX]Ú›˜]]™KXYÛˆ‚ˆ	ØÜš\œœP\™ÜÈÚİ[SX]Ú™Ù[Z[šKXÛH‚ˆ	ØÜš\œœP\™ÜÈÚİ[S›İSX]ÚÛ˜[YOH‚ˆB‚ˆ]	ÜÚİ[[œİ[[™XYH[œİ[YœHXÚØYÙ\ÈÛÈ^HØ[ˆ\]HÈ]\İ	ÈÂˆ	ØÜš\œœPYØ[YH	˜[ÙBˆ[ØÚÈÙ]RœÛÛÛÛ[Âˆ™]\›ˆÈÛØ˜[XÚØYÙ\ÈH
ˆ^[\KÛ˜]]™K]ÛÛ‹ˆš\ÛXKÛ[™İXYÙK\Ù\™\ˆ‹ˆYÙ[ÛY[›İØÛÛØÛ]YKXYÙ[XXÜ‹ˆ\\ØÜš\[[™İXYÙK\Ù\™\ˆ‹ˆ\\ØÜš\‹ˆÛÛÙÛKÙÙ[Z[šKXÛH‚ˆ
BˆBˆBˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]Ú›š^ÜË\™XZ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÛ[X[™]ˆœHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ‹Ûš^ÜİÜ™KØš[‹ÜœHˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÈYÈŠHÂˆ	ÛØ˜[“TÕVUÓÑHHˆ™]\›ˆ
^[\KÛ˜]]™K]ÛÛKŒŒ‹š\ÛXKÛ[™İXYÙK\Ù\™\KŒŒ‹Œ‹YÙ[ÛY[›İØÛÛØÛ]YKXYÙ[XXÜKŒŒ‹\\ØÜš\[[™İXYÙK\Ù\™\ŒËŒÈ‹\\ØÜš\K‹ŒÈ‹ÛÛÙÛKÙÙ[Z[šKXÛPŒÌ‹ŒHŠBˆBˆYˆ
	\™Ôİˆ[X]ÚœœHYŠHÂˆ	ØÜš\œœPYØ[YH	YBˆ	ÛØ˜[“TÕVUÓÑHHˆ™]\›ˆˆ‚ˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÜ™WšÛÚÜÔ]ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Úœ™KXÛÛ[Z][œİ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™XÚÈ^\İÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ™^\İÈˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÙ]\ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™Ü™\Š””WÒÓQHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú\İYHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆBˆ	[™\‹\J	İ
B‚ˆ	ØÜš\œœPYØ[YÚİ[P™H	YBˆB‚ˆ]	ÜÚİ[™Z[œİ[[œİ[YœHXÚØYÙHÚ[ˆ™\šYPÛÛ[X[™˜Z[È[ˆÔÓ	ÈÂˆ	ØÜš\œœPYØ[YH	˜[ÙBˆ	ØÜš\™\šYPØ[ÈHˆ[ØÚÈÙ]RœÛÛÛÛ[Âˆ™]\›ˆÈÛØ˜[XÚØYÙ\ÈH
ˆÈ˜[YHH^[\KÛ˜]]™K]ÛÛÈ™\šYPÛÛ[X[™HÈÛÛ[X[™H›˜]]™K]ÛÛÈ\™ÜÈH
œİ]\ÈŠHHBˆ
BˆBˆBˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]Ú›š^ÜË\™XZ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÛ[X[™]ˆœHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ‹Ûš^ÜİÜ™KØš[‹ÜœHˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÈYÈŠHÂˆ	ÛØ˜[“TÕVUÓÑHHˆ™]\›ˆ
^[\KÛ˜]]™K]ÛÛKŒŒŠBˆBˆYˆ
	\™Ôİˆ[X]Ú›˜]]™K]ÛÛŠœİ]\ÈŠHÂˆ	ØÜš\™\šYPØ[ÊÊÂˆYˆ
	ØÜš\™\šYPØ[ÈY\HJHÂˆ	ÛØ˜[“TÕVUÓÑHHBˆ™]\›ˆ›˜]]™K]ÛÛ›İ›İ[™‚ˆBˆ	ÛØ˜[“TÕVUÓÑHHˆ™]\›ˆ›ÚÈ‚ˆBˆYˆ
	\™Ôİˆ[X]ÚœœHYŠHÂˆ	ØÜš\œœPYØ[YH	YBˆ	ÛØ˜[“TÕVUÓÑHHˆ™]\›ˆ
š[œİ[YŠBˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÜ™WšÛÚÜÔ]ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Úœ™KXÛÛ[Z][œİ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™XÚÈ^\İÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ™^\İÈˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÙ]\ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™Ü™\Š””WÒÓQHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú\İYHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆB‚ˆ	™\İ[H	[™\‹\J	İ
B‚ˆ	™\İ[”İXØÙ\ÜÈÚİ[P™H	YBˆ	ØÜš\œœPYØ[YÚİ[P™H	YBˆ	ØÜš\™\šYPØ[ÈÚİ[P™H‚ˆB‚ˆ]	ÜÚİ[˜Z[Ú[ˆœHÛØ˜[[œİ[˜Z[ÉÈÂˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]Ú›š^ÜË\™XZ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÛ[X[™]ˆœHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ‹Ûš^ÜİÜ™KØš[‹ÜœHˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÈYÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]ÚœœHYŠHÈ	ÛØ˜[“TÕVUÓÑHHNÈ™]\›ˆ
™\œ›ÜˆŠHBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÜ™WšÛÚÜÔ]ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Úœ™KXÛÛ[Z][œİ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™XÚÈ^\İÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ™^\İÈˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÙ]\ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™Ü™\Š””WÒÓQHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú\İYHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆBˆ	™\İ[H	[™\‹\J	İ
B‚ˆ	™\İ[”İXØÙ\ÜÈÚİ[P™H	˜[ÙBˆ	™\İ[“Y\ÜØYÙHÚİ[SX]ÚœœH8à¬8àëxàï8àä8àêøàäxààøà¬xàï8à®‚ˆB‚ˆ]	ÜÚİ[\ÜÈÛÜœ™Xİ\™İ[Y[ÈÈÔÓ	ÈÂˆ	ØÜš\ÜÛ\™ÜÈHˆ‚ˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]Ú›š^ÜË\™XZ[ŠHÈ	ØÜš\ÜÛ\™ÜÈH	\™ÔİÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÛ[X[™]ˆœHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ‹Ûš^ÜİÜ™KØš[‹ÜœHˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÈYÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]ÚœœHYŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÜ™WšÛÚÜÔ]ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Úœ™KXÛÛ[Z][œİ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™XÚÈ^\İÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ™^\İÈˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÙ]\ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™Ü™\Š””WÒÓQHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú\İYHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆBˆ	[™\‹\J	İ
B‚ˆ	ØÜš\ÜÛ\™ÜÈÚİ[SX]Ú‹Yš^ÔÈ‚ˆ	ØÜš\ÜÛ\™ÜÈÚİ[SX]Ú‹]H›Ûİ‚ˆ	ØÜš\ÜÛ\™ÜÈÚİ[SX]Ú›š^ÜË\™XZ[]Ú]]\Ù\‹œÚİÚ]ÚKY›ZÙHˆKZ[\\™H‚ˆ	ØÜš\ÜÛ\™ÜÈÚİ[SX]Ú‘Õ’ST×ÕÒUÒT“QTÏL‚ˆB‚ˆ]	ÜÚİ[\ÜÈH\›Y\È™X]\™HÈHš^ÔÈ™XZ[Ü˜\\‰ÈÂˆ	İ“Ü[ÛœÖÉÕÚ]\›Y\É×HH	YBˆ	ØÜš\ÜÛ\™ÜÈH	ÉÂˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆ	È	ÂˆYˆ
	\™Ôİˆ[X]Ú	Ûš^ÜË\™XZ[	ÊHÈ	ØÜš\ÜÛ\™ÜÈH	\™ÔİÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ	ÉÈBˆYˆ
	\™Ôİˆ[X]Ú	ØÛÛ[X[™]ˆœIÊHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ	ËÛš^ÜİÜ™KØš[‹ÜœIÈBˆYˆ
	\™Ôİˆ[X]Ú	ÜœHÈYÉÊHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ	ÉÈBˆYˆ
	\™Ôİˆ[X]Ú	ÜœHY	ÊHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ	ÉÈBˆYˆ
	\™Ôİˆ[X]Ú	ØÛÜ™WšÛÚÜÔ]™KXÛÛ[Z][œİ[XÚÈ^\İßœHÙ]\Ü™\Š””WÒÓQ_\İYIÊHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ	ÉÈBˆ	ÛØ˜[“TÕVUÓÑHHˆ™]\›ˆ	ÉÂˆB‚ˆ	[™\‹\J	İ
B‚ˆ	ØÜš\ÜÛ\™ÜÈÚİ[SX]Ú	ÑÕ’ST×ÕÒUÒT“QTÏLIÂˆÚİ[R[›ÚÙH[›ÚÙKUÜÛT\˜[Y]\‘š[\ˆÂˆ
	\™İ[Y[ÈZ›Ú[ˆ	È	ÊH[X]Ú	ÙØÚÙ\ˆİÜ\›Y\ÉÂˆHU[Y\ÈCBˆÚİ[R[›ÚÙH[›ÚÙKUÜÛT\˜[Y]\‘š[\ˆÂˆ
	\™İ[Y[ÈZ›Ú[ˆ	È	ÊH[X]Ú	ÙØÚÙ\ˆ[œÜXİK]\HÛÛZ[™\ˆKY›Ü›X]Šš\›Y\ÉÂˆHU[Y\ÈBˆB‚ˆ]	ÜÚİ[İÜÛ›HHYØXŞH\›Y\ÈØ]]Ø^H™Y›Ü™HXİ]˜][Ûˆ[™˜Z[YˆİÜ[™È]˜Z[ÉÈÂˆ	İ“Ü[ÛœÖÉÕÚ]\›Y\É×HH	YBˆ	İ“Ü[ÛœÖÉÔÚÚ\›ZÙU\]I×HH	YBˆ	ØÜš\œ™XZ[Ø[YH	˜[ÙBˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆ	È	ÂˆYˆ
	\™Ôİˆ[X]Ú	ÙØÚÙ\ˆİÜ\›Y\ÉÊHÂˆ	ÛØ˜[“TÕVUÓÑHHBˆ™]\›ˆ	ÛYØXŞHØ]]Ø^HÛİ[›İİÜ	ÂˆBˆYˆ
	\™Ôİˆ[X]Ú	Ûš^ÜË\™XZ[	ÊHÂˆ	ØÜš\œ™XZ[Ø[YH	YBˆ	ÛØ˜[“TÕVUÓÑHHˆ™]\›ˆ	ÉÂˆBˆ	ÛØ˜[“TÕVUÓÑHHˆ™]\›ˆ	ÉÂˆB‚ˆ	™\İ[H	[™\‹\J	İ
B‚ˆ	™\İ[”İXØÙ\ÜÈÚİ[P™Q˜[ÙBˆ	™\İ[“Y\ÜØYÙHÚİ[SX]Ú	ÛYØXŞH\›Y\ÈØ]]Ø^HÛİ[›İ™HİÜY	Âˆ	ØÜš\œ™XZ[Ø[YÚİ[P™Q˜[ÙBˆÚİ[R[›ÚÙH[›ÚÙKUÜÛT\˜[Y]\‘š[\ˆÂˆ
	\™İ[Y[ÈZ›Ú[ˆ	È	ÊH[X]Ú	ÙØÚÙ\ˆİÜ\›Y\ÉÂˆHU[Y\ÈBˆB‚ˆ]	ÜÚİ[™\İÜ™HH[›š[™ÈYØXŞH\›Y\ÈØ]]Ø^HÚ[ˆHš^™XZ[˜Z[ÉÈÂˆ	İ“Ü[ÛœÖÉÕÚ]\›Y\É×HH	YBˆ	İ“Ü[ÛœÖÉÔÚÚ\›ZÙU\]I×HH	YBˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆ	È	ÂˆYˆ
	\™Ôİˆ[X]Ú	ÙØÚÙ\ˆİÜ\›Y\ÉÊHÂˆ	ÛØ˜[“TÕVUÓÑHHˆ™]\›ˆ	ÑÕ’ST×ÓQĞPÖWÒT“QT×ÕĞT×Ô•S“’S‘ÉÂˆBˆYˆ
	\™Ôİˆ[X]Ú	Ûš^ÜË\™XZ[	ÊHÂˆ	ÛØ˜[“TÕVUÓÑHHBˆ™]\›ˆ	Ù\œ›ÜˆÚ[][]Y™XZ[˜Z[\™IÂˆBˆYˆ
	\™Ôİˆ[X]Ú	ÙØÚÙ\ˆİ\\›Y\ÉÊHÂˆ	ÛØ˜[“TÕVUÓÑHHˆ™]\›ˆ	ÛYØXŞHØ]]Ø^H™\İÜ™Y	ÂˆBˆYˆ
	\™Ôİˆ[X]Ú	ØÛÛ[X[™]ˆœIÊHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ	ËÛš^ÜİÜ™KØš[‹ÜœIÈBˆ	ÛØ˜[“TÕVUÓÑHHˆ™]\›ˆ	ÉÂˆB‚ˆ	™\İ[H	[™\‹\J	İ
B‚ˆ	™\İ[”İXØÙ\ÜÈÚİ[P™Q˜[ÙBˆ	™\İ[“Y\ÜØYÙHÚİ[SX]Ú	Ûš^ÜË\™XZ[İÚ]Ú8àc9i,y¥eøàeøào¸àeøàgÉÂˆ	İ“Ü[ÛœÖÉÓYØXŞR\›Y\ÑØ]]Ø^TİÜY	×HÚİ[P™UYBˆÚİ[R[›ÚÙH[›ÚÙKUÜÛT\˜[Y]\‘š[\ˆÂˆ
	\™İ[Y[ÈZ›Ú[ˆ	È	ÊH[X]Ú	ÙØÚÙ\ˆİ\\›Y\ÉÂˆHU[Y\ÈBˆB‚ˆ]	ÜÚİ[™\İÜ™HHYØXŞH\›Y\ÈØ]]Ø^HÚ[ˆH™XZ[ÛÛ[X[™›İÜÉÈÂˆ	İ“Ü[ÛœÖÉÕÚ]\›Y\É×HH	YBˆ	İ“Ü[ÛœÖÉÔÚÚ\›ZÙU\]I×HH	YBˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆ	È	ÂˆYˆ
	\™Ôİˆ[X]Ú	ÙØÚÙ\ˆ[œÜXİK]\HÛÛZ[™\‰ÊHÂˆ	ÛØ˜[“TÕVUÓÑHHˆ™]\›ˆ
	İYIË	ÑÕ’ST×ÓQĞPÖWÒT“QT×ÕĞT×Ô•S“’S‘ÉÊBˆBˆYˆ
	\™Ôİˆ[X]Ú	Ûš^ÜË\™XZ[	ÊHÈ›İÈ	Ü™XZ[›ØÙ\ÜÈ[YYİ]	ÈBˆYˆ
	\™Ôİˆ[X]Ú	ÙØÚÙ\ˆİ\\›Y\ÉÊHÂˆ	ÛØ˜[“TÕVUÓÑHHˆ™]\›ˆ	ÛYØXŞHØ]]Ø^H™\İÜ™Y	ÂˆBˆ	ÛØ˜[“TÕVUÓÑHHˆ™]\›ˆ	ÉÂˆB‚ˆ	™\İ[H	[™\‹\J	İ
B‚ˆ	™\İ[”İXØÙ\ÜÈÚİ[P™Q˜[ÙBˆ	™\İ[“Y\ÜØYÙHÚİ[SX]Ú	Ü™XZ[›ØÙ\ÜÈ[YYİ]	ÂˆÚİ[R[›ÚÙH[›ÚÙKUÜÛT\˜[Y]\‘š[\ˆÂˆ
	\™İ[Y[ÈZ›Ú[ˆ	È	ÊH[X]Ú	ÙØÚÙ\ˆİ\\›Y\ÉÂˆHU[Y\ÈBˆB‚ˆ]	ÜÚİ[\]HH›ZÙHØÚÈ™Y›Ü™Hš^ÜË\™XZ[ÛÈš^XÚØYÙ\È\ÙH]\İ[œ]ÉÈÂˆ	ØÜš\™›ZÙU\]PØ[YH	˜[ÙBˆ	ØÜš\œ™XZ[Ø[YH	˜[ÙBˆ	ØÜš\™›ZÙU\]PØ[Yš\œİH	˜[ÙBˆ	ØÜš\™›ZÙU\]P\™ÜÈHˆ‚ˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]Ú›š^›ZÙH\]HŠHÂˆ	ØÜš\™›ZÙU\]P\™ÜÈH	\™Ôİ‚ˆ	ØÜš\™›ZÙU\]PØ[YH	YBˆYˆ
[›İ	ØÜš\œ™XZ[Ø[Y
HÈ	ØÜš\™›ZÙU\]PØ[Yš\œİH	YHBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ
\]YØÚÈš[HŠBˆBˆYˆ
	\™Ôİˆ[X]Ú›š^ÜË\™XZ[ŠHÈ	ØÜš\œ™XZ[Ø[YH	YNÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÛ[X[™]ˆœHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ‹Ûš^ÜİÜ™KØš[‹ÜœHˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÈYÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]ÚœœHYŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÜ™WšÛÚÜÔ]ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Úœ™KXÛÛ[Z][œİ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™XÚÈ^\İÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ™^\İÈˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÙ]\ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™Ü™\Š””WÒÓQHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú\İYHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆBˆ	[™\‹\J	İ
B‚ˆ	ØÜš\™›ZÙU\]PØ[YÚİ[P™H	YBˆ	ØÜš\™›ZÙU\]PØ[Yš\œİÚİ[P™H	YBˆ	ØÜš\™›ZÙU\]P\™ÜÈÚİ[SX]Ú‹]Hš^ÜÈ‚ˆB‚ˆ]	ÜÚİ[ÚÚ\›ZÙH\]\ÈÚ[ˆHØ[\ˆ[œÈHÚXÚÙY[İ][œ]ÉÈÂˆ	İ“Ü[ÛœÖÉÔÚÚ\›ZÙU\]I×HH	YBˆ	ØÜš\™›ZÙU\]PØ[YH	˜[ÙBˆ	ØÜš\œ™XZ[Ø[YH	˜[ÙBˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]Ú›š^›ZÙH\]HŠHÈ	ØÜš\™›ZÙU\]PØ[YH	YHBˆYˆ
	\™Ôİˆ[X]Ú›š^ÜË\™XZ[ŠHÈ	ØÜš\œ™XZ[Ø[YH	YNÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÛ[X[™]ˆœHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ‹Ûš^ÜİÜ™KØš[‹ÜœHˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÈYßœHYÛÜ™WšÛÚÜÔ]™KXÛÛ[Z][œİ[XÚÈ^\İßœHÙ]\Ü™\Š””WÒÓQ_\İYHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆ	ÛØ˜[“TÕVUÓÑHHˆ™]\›ˆˆ‚ˆB‚ˆ	™\İ[H	[™\‹\J	İ
B‚ˆ	™\İ[”İXØÙ\ÜÈÚİ[P™UYBˆ	ØÜš\™›ZÙU\]PØ[YÚİ[P™Q˜[ÙBˆ	ØÜš\œ™XZ[Ø[YÚİ[P™UYBˆB‚ˆ]	ÜÚİ[Ù]Ú]ØY™K™\™XİÜH™Y›Ü™Hš^ÜË\™XZ[\È›Ûİ	ÈÂˆ	ØÜš\™Ú]ÛÛ™šYĞØ[YH	˜[ÙBˆ	ØÜš\œ™XZ[Ø[YH	˜[ÙBˆ	ØÜš\™Ú]Ø[Yš\œİH	˜[ÙBˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]Ú™Ü™\Š™\™XİÜKŠ™Ú]ÛÛ™šYßš[‹Š—ÜØY™WHŠHÂˆ	ØÜš\™Ú]ÛÛ™šYĞØ[YH	YBˆYˆ
[›İ	ØÜš\œ™XZ[Ø[Y
HÈ	ØÜš\™Ú]Ø[Yš\œİH	YHBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆBˆYˆ
	\™Ôİˆ[X]Ú›š^ÜË\™XZ[ŠHÈ	ØÜš\œ™XZ[Ø[YH	YNÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÛ[X[™]ˆœHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ‹Ûš^ÜİÜ™KØš[‹ÜœHˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÈYÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÜ™WšÛÚÜÔ]ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Úœ™KXÛÛ[Z][œİ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™XÚÈ^\İÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ™^\İÈˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÙ]\ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™Ü™\Š””WÒÓQHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú\İYHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆBˆ	[™\‹\J	İ
B‚ˆ	ØÜš\™Ú]ÛÛ™šYĞØ[YÚİ[P™H	YBˆ	ØÜš\™Ú]Ø[Yš\œİÚİ[P™H	YBˆB‚ˆ]	ÜÚİ[\ÙHİ\İÛH\İ›È˜[YHœ›ÛHÛÛ^	ÈÂˆ	İ‘\İ›Ó˜[YHHİ\İÛSš^ÔÈ‚ˆ	ØÜš\ÜÛ\™ÜÈHˆ‚ˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]Ú›š^ÜË\™XZ[ŠHÈ	ØÜš\ÜÛ\™ÜÈH	\™ÔİÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÛ[X[™]ˆœHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ‹Ûš^ÜİÜ™KØš[‹ÜœHˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÈYÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]ÚœœHYŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÜ™WšÛÚÜÔ]ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Úœ™KXÛÛ[Z][œİ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™XÚÈ^\İÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ™^\İÈˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÙ]\ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™Ü™\Š””WÒÓQHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú\İYHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆBˆ	[™\‹\J	İ
B‚ˆ	ØÜš\ÜÛ\™ÜÈÚİ[SX]Ú‹Yİ\İÛSš^ÔÈ‚ˆB‚ˆ]	ÜÚİ[[œİ[™KXÛÛ[Z]ÛÚÜÈY\ˆœHXÚØYÙ\ÉÈÂˆ	ØÜš\˜Ø[Ü™\ˆHÔŞ\İ[KÛÛXİ[ÛœË‘Ù[™\šXË“\İÜİš[™×WN›™]Ê
Bˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]Ú›š^ÜË\™XZ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÛ[X[™]ˆœHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ‹Ûš^ÜİÜ™KØš[‹ÜœHˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÈYÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]ÚœœHYŠHÂˆ	ØÜš\˜Ø[Ü™\‹Y
œœHŠBˆ	ÛØ˜[“TÕVUÓÑHHˆ™]\›ˆˆ‚ˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÜ™WšÛÚÜÔ]ŠHÂˆ	ØÜš\˜Ø[Ü™\‹Y
[œÙ]ZÛÚÜÜ]ŠBˆ	ÛØ˜[“TÕVUÓÑHHˆ™]\›ˆˆ‚ˆBˆYˆ
	\™Ôİˆ[X]Úœ™KXÛÛ[Z][œİ[ŠHÂˆ	ØÜš\˜Ø[Ü™\‹Y
œ™KXÛÛ[Z]ŠBˆ	ÛØ˜[“TÕVUÓÑHHˆ™]\›ˆ
œ™KXÛÛ[Z][œİ[Y]™Ú]ÚÛÚÜËÜ™KXÛÛ[Z]ŠBˆBˆYˆ
	\™Ôİˆ[X]Ú™XÚÈ^\İÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ™^\İÈˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÙ]\ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™Ü™\Š””WÒÓQHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú\İYHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆBˆ	™\İ[H	[™\‹\J	İ
B‚ˆ	™\İ[”İXØÙ\ÜÈÚİ[P™H	YBˆ	ØÜš\˜Ø[Ü™\ˆÚİ[PÛÛZ[ˆœœH‚ˆ	ØÜš\˜Ø[Ü™\ˆÚİ[PÛÛZ[ˆ[œÙ]ZÛÚÜÜ]‚ˆ	ØÜš\˜Ø[Ü™\ˆÚİ[PÛÛZ[ˆœ™KXÛÛ[Z]‚ˆ	ØÜš\˜Ø[Ü™\‹’[™^ÙŠœœHŠHÚİ[P™S\ÜÕ[ˆ	ØÜš\˜Ø[Ü™\‹’[™^ÙŠ[œÙ]ZÛÚÜÜ]ŠBˆ	ØÜš\˜Ø[Ü™\‹’[™^ÙŠ[œÙ]ZÛÚÜÜ]ŠHÚİ[P™S\ÜÕ[ˆ	ØÜš\˜Ø[Ü™\‹’[™^ÙŠœ™KXÛÛ[Z]ŠBˆB‚ˆ]	ÜÚİ[İXØÙYY]™[ˆÚ[ˆ™KXÛÛ[Z][œİ[˜Z[ÉÈÂˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]Ú›š^ÜË\™XZ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÛ[X[™]ˆœHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ‹Ûš^ÜİÜ™KØš[‹ÜœHˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÈYÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]ÚœœHYŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÜ™WšÛÚÜÔ]ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Úœ™KXÛÛ[Z][œİ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHNÈ™]\›ˆ
™\œ›ÜˆŠHBˆYˆ
	\™Ôİˆ[X]Ú™XÚÈ^\İÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ™^\İÈˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÙ]\ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™Ü™\Š””WÒÓQHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú\İYHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆBˆ	™\İ[H	[™\‹\J	İ
B‚ˆÈ™KXÛÛ[Z][œİ[9i,y¥eøàiøà ˆ\H:!ê¹/døàkù¢$9b§øàj8àoøàj¸àfBˆ	™\İ[”İXØÙ\ÜÈÚİ[P™H	YBˆB‚ˆ]	ÜÚİ[\ÜÈÛÜœ™XİÔÓ\™ÜÈ›Üˆ™KXÛÛ[Z][œİ[	ÈÂˆ	ØÜš\œ™PÛÛ[Z]\™ÜÈHˆ‚ˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]Ú›š^ÜË\™XZ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÛ[X[™]ˆœHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ‹Ûš^ÜİÜ™KØš[‹ÜœHˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÈYÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]ÚœœHYŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÜ™WšÛÚÜÔ]ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Úœ™KXÛÛ[Z][œİ[ŠHÂˆ	ØÜš\œ™PÛÛ[Z]\™ÜÈH	\™Ôİ‚ˆ	ÛØ˜[“TÕVUÓÑHHˆ™]\›ˆˆ‚ˆBˆYˆ
	\™Ôİˆ[X]Ú™XÚÈ^\İÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ™^\İÈˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÙ]\ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™Ü™\Š””WÒÓQHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú\İYHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆBˆ	[™\‹\J	İ
B‚ˆ	ØÜš\œ™PÛÛ[Z]\™ÜÈÚİ[SX]Ú‹Yš^ÔÈ‚ˆ	ØÜš\œ™PÛÛ[Z]\™ÜÈÚİ[SX]Ú‹]Hš^ÜÈ‚ˆ	ØÜš\œ™PÛÛ[Z]\™ÜÈÚİ[SX]Ú˜Ù‹Ë™İš[\È‚ˆ	ØÜš\œ™PÛÛ[Z]\™ÜÈÚİ[SX]Úœ™KXÛÛ[Z][œİ[KZ[œİ[ZÛÚÜÈ‚ˆB‚ˆ]	ÜÚİ[›İØ[ÛÜ™\XÚÈÚ[ˆœH\È[™XYH]˜Z[X›IÈÂˆ	ØÜš\˜ÛÜ™\ZĞØ[YH	˜[ÙBˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]Ú›š^ÜË\™XZ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÛ[X[™]ˆœHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ‹Ûš^ÜİÜ™KØš[‹ÜœHˆBˆYˆ
	\™Ôİˆ[X]Ú›œH[œİ[YÈœHŠHÈ	ØÜš\˜ÛÜ™\ZĞØ[YH	YNÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÈYÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]ÚœœHYŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÜ™WšÛÚÜÔ]ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Úœ™KXÛÛ[Z][œİ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™XÚÈ^\İÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ™^\İÈˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÙ]\ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™Ü™\Š””WÒÓQHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú\İYHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆBˆ	[™\‹\J	İ
B‚ˆ	ØÜš\˜ÛÜ™\ZĞØ[YÚİ[P™H	˜[ÙBˆB‚ˆ]	ÜÚİ[[œİ[˜]]™HœHÚ[ˆÛ›HÚ[™İÜÈ[\›ÜœH\È›İ[™šXHÛ[ÉÈÂˆ	ØÜš\›œR[œİ[Ø[YH	˜[ÙBˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]Ú›š^ÜË\™XZ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆÈÜ™\\]ˆ	×‹Û[ÉÈ8àiÈÛ[È8àäxà®xà¤¹o/¸àcÈ8¡¤ˆ^]H8à¤º/å8àfBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÛ[X[™]ˆœHŠHÈ	ÛØ˜[“TÕVUÓÑHHNÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú›œH[œİ[YÈœHŠHÈ	ØÜš\›œR[œİ[Ø[YH	YNÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÈYÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]ÚœœHYŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÜ™WšÛÚÜÔ]ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Úœ™KXÛÛ[Z][œİ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™XÚÈ^\İÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ™^\İÈˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÙ]\ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™Ü™\Š””WÒÓQHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú\İYHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆBˆ	[™\‹\J	İ
B‚ˆ	ØÜš\›œR[œİ[Ø[YÚİ[P™H	YBˆB‚ˆ]	ÜÚİ[[˜X›HœHšXHÛÜ™\XÚÈÚ[ˆœH\È›İ›İ[™	ÈÂˆ	ØÜš\˜ÛÜ™\ZĞØ[YH	˜[ÙBˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]Ú›š^ÜË\™XZ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÛ[X[™]ˆœHŠHÈ	ÛØ˜[“TÕVUÓÑHHNÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú›œH[œİ[YÈœHŠHÈ	ØÜš\˜ÛÜ™\ZĞØ[YH	YNÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÈYÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]ÚœœHYŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÜ™WšÛÚÜÔ]ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Úœ™KXÛÛ[Z][œİ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™XÚÈ^\İÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ™^\İÈˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÙ]\ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™Ü™\Š””WÒÓQHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú\İYHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆBˆ	[™\‹\J	İ
B‚ˆ	ØÜš\˜ÛÜ™\ZĞØ[YÚİ[P™H	YBˆB‚ˆ]	ÜÚİ[˜Z[Ú[ˆœH›Ûİİ˜\˜Z[ÉÈÂˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]Ú›š^ÜË\™XZ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÛ[X[™]ˆœHŠHÈ	ÛØ˜[“TÕVUÓÑHHNÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú›œH[œİ[YÈœHŠHÈ	ÛØ˜[“TÕVUÓÑHHNÈ™]\›ˆ
™\œ›ÜˆŠHBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÜ™WšÛÚÜÔ]ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Úœ™KXÛÛ[Z][œİ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™XÚÈ^\İÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ™^\İÈˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÙ]\ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™Ü™\Š””WÒÓQHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú\İYHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆBˆ	™\İ[H	[™\‹\J	İ
B‚ˆ	™\İ[”İXØÙ\ÜÈÚİ[P™H	˜[ÙBˆ	™\İ[“Y\ÜØYÙHÚİ[SX]ÚœœH8à¬8àëxàï8àä8àêøàäxààøà¬xàï8à®‚ˆB‚ˆ]	ÜÚİ[Ù]\”WÒÓQHÚ[ˆ\™XİÜHÙ\È›İ^\İ	ÈÂˆ	ØÜš\œœTÙ]\Ø[YH	˜[ÙBˆ	ØÜš\˜˜\Ú˜Õ\]YH	˜[ÙBˆ	ØÜš\œœRÛYPÚXÚĞ\™ÜÈHˆ‚ˆ	ØÜš\œœTÙ]\\™ÜÈHˆ‚ˆ	ØÜš\˜˜\Ú˜Ğ\™ÜÈHˆ‚ˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]Ú›š^ÜË\™XZ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÛ[X[™]ˆœHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ‹Ûš^ÜİÜ™KØš[‹ÜœHˆBˆYˆ
	\™Ôİˆ[X]Ú™XÚÈ^\İÈŠHÈ	ØÜš\œœRÛYPÚXÚĞ\™ÜÈH	\™ÔİÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÙ]\ŠHÈ	ØÜš\œœTÙ]\Ø[YH	YNÈ	ØÜš\œœTÙ]\\™ÜÈH	\™ÔİÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™Ü™\Š””WÒÓQHŠHÈ	ØÜš\˜˜\Ú˜Õ\]YH	YNÈ	ØÜš\˜˜\Ú˜Ğ\™ÜÈH	\™ÔİÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÈYÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]ÚœœHYŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÜ™WšÛÚÜÔ]ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Úœ™KXÛÛ[Z][œİ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú\İYHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆBˆ	™\İ[H	[™\‹\J	İ
B‚ˆ	™\İ[”İXØÙ\ÜÈÚİ[P™H	YBˆ	ØÜš\œœTÙ]\Ø[YÚİ[P™H	YBˆ	ØÜš\˜˜\Ú˜Õ\]YÚİ[P™H	YBˆ	ØÜš\œœRÛYPÚXÚĞ\™ÜÈÚİ[SX]Ú	×	”WÒÓQKØš[‰Âˆ	ØÜš\œœTÙ]\\™ÜÈÚİ[SX]Ú	×	”WÒÓQKØš[‰Âˆ	ØÜš\˜˜\Ú˜Ğ\™ÜÈÚİ[SX]Ú	×	”WÒÓQKØš[—	”WÒÓQIÂˆB‚ˆ]	ÜÚİ[ÚÚ\”WÒÓQHÙ]\Ú[ˆ\™XİÜH[™XYH^\İÉÈÂˆ	ØÜš\œœTÙ]\Ø[YH	˜[ÙBˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]Ú›š^ÜË\™XZ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÛ[X[™]ˆœHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ‹Ûš^ÜİÜ™KØš[‹ÜœHˆBˆYˆ
	\™Ôİˆ[X]Ú™XÚÈ^\İÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ™^\İÈˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÙ]\ŠHÈ	ØÜš\œœTÙ]\Ø[YH	YNÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™Ü™\Š””WÒÓQHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÈYÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]ÚœœHYŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÜ™WšÛÚÜÔ]ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Úœ™KXÛÛ[Z][œİ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú\İYHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆBˆ	™\İ[H	[™\‹\J	İ
B‚ˆ	™\İ[”İXØÙ\ÜÈÚİ[P™H	YBˆ	ØÜš\œœTÙ]\Ø[YÚİ[P™H	˜[ÙBˆB‚ˆ]	ÜÚİ[[œÙ]ÛÜ™KšÛÚÜÔ]™Y›Ü™H™KXÛÛ[Z][œİ[	ÈÂˆ	ØÜš\šÛÚÜÔ][œÙ]H	˜[ÙBˆ	ØÜš\œ™PÛÛ[Z]Ø[YH	˜[ÙBˆ	ØÜš\[œÙ]™Y›Ü™T™PÛÛ[Z]H	˜[ÙBˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]Ú›š^ÜË\™XZ[ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÛ[X[™]ˆœHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ‹Ûš^ÜİÜ™KØš[‹ÜœHˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÈYÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]ÚœœHYŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú˜ÛÜ™WšÛÚÜÔ]ŠHÂˆ	ØÜš\šÛÚÜÔ][œÙ]H	YBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆBˆYˆ
	\™Ôİˆ[X]Úœ™KXÛÛ[Z][œİ[ŠHÂˆ	ØÜš\œ™PÛÛ[Z]Ø[YH	YBˆ	ØÜš\[œÙ]™Y›Ü™T™PÛÛ[Z]H	ØÜš\šÛÚÜÔ][œÙ]ˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆBˆYˆ
	\™Ôİˆ[X]Ú™XÚÈ^\İÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ™^\İÈˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÙ]\ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™Ü™\Š””WÒÓQHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú\İYHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆBˆ	[™\‹\J	İ
B‚ˆ	ØÜš\šÛÚÜÔ][œÙ]Úİ[P™H	YBˆ	ØÜš\œ™PÛÛ[Z]Ø[YÚİ[P™H	YBˆ	ØÜš\[œÙ]™Y›Ü™T™PÛÛ[Z]Úİ[P™H	YBˆB‚ˆ]	ÜÚİ[™]\›ˆ˜Z[\™HÚ[ˆ^Ù\[Ûˆ\È›İÛ‰ÈÂˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]Ú‹[\HŠHÂˆ	ÛØ˜[“TÕVUÓÑHHˆ™]\›ˆ
“š^ÔÈŠBˆBˆYˆ
	\™Ôİˆ[X]Ú\İYHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™XÚÈ^\İÈŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ™^\İÈˆBˆYˆ
	\™Ôİˆ[X]ÚœœHÙ]\ŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú™Ü™\Š””WÒÓQHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆ›İÈ•ÔÓ\œ›Üˆ‚ˆBˆ	™\İ[H	[™\‹\J	İ
B‚ˆ	™\İ[”İXØÙ\ÜÈÚİ[P™H	˜[ÙBˆ	™\İ[“Y\ÜØYÙHÚİ[SX]Ú•ÔÓ\œ›Üˆ‚ˆBˆB‚ˆÛÛ^	Ñ[œİ\™Qİš[\Ğ]˜Z[X›IÈÂˆ™Y›Ü™QXXÚÂˆ[ØÚÈÜš]KRÜİÈBˆB‚ˆ]	ÜÚİ[™]\›ˆX\›HÚ[ˆİš[\È^\İÈ\ÈH›Û‹\Ş[[[šÉÈÂˆ	ØÜš\›[šĞØ[YH	˜[ÙBˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]ÚšYˆÈSÚÛYKÛš^ÜË×™İš[\ÈHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ—×Û›Û—ÜŞ[[[š××ÈˆBˆYˆ
	\™Ôİˆ[X]Ú›ˆ\Ù›ˆŠHÈ	ØÜš\›[šĞØ[YH	YNÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆB‚ˆ	[™\‹‘[œİ\™Qİš[\Ğ]˜Z[X›J“š^ÔÈ‹‘—\Wİš[\ÈŠB‚ˆ	ØÜš\›[šĞØ[YÚİ[P™H	˜[ÙBˆB‚ˆ]	ÜÚİ[™]\›ˆX\›HÚ[ˆİš[\ÈŞ[[[šÈ[™XYH\™Ù]ÈH™\]Y\İY]	ÈÂˆ	ØÜš\›[šĞØ[YH	˜[ÙBˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]ÚšYˆÈSÚÛYKÛš^ÜË×™İš[\ÈHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ‹Û[ÙÜ\KÙİš[\ÈˆBˆYˆ
	\™Ôİˆ[X]Ú›ˆ\Ù›ˆŠHÈ	ØÜš\›[šĞØ[YH	YNÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆB‚ˆ	[™\‹‘[œİ\™Qİš[\Ğ]˜Z[X›J“š^ÔÈ‹‘—\Wİš[\ÈŠB‚ˆ	ØÜš\›[šĞØ[YÚİ[P™H	˜[ÙBˆB‚ˆ]	ÜÚİ[\]Hİš[\ÈŞ[[[šÈÚ[ˆ]\™Ù]ÈHY™™\™[]	ÈÂˆ	ØÜš\›[šĞ\™ÜÈHˆ‚ˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]ÚšYˆÈSÚÛYKÛš^ÜË×™İš[\ÈHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆ‹Û[ÙÜ\KÙİš[\ÈˆBˆYˆ
	\™Ôİˆ[X]Ú\İYŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú›ˆ\Ù›ˆŠHÈ	ØÜš\›[šĞ\™ÜÈH	\™ÔİÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆB‚ˆ	[™\‹‘[œİ\™Qİš[\Ğ]˜Z[X›J“š^ÔÈ‹‘—\Wİš[\Ë[š^™XZ[[[šËXÛÛ™HŠB‚ˆ	ØÜš\›[šĞ\™ÜÈÚİ[SX]Ú›ˆ\Ù›ˆ‚ˆ	ØÜš\›[šĞ\™ÜÈÚİ[SX]Ú‹Û[ÙÜ\KÙİš[\Ë[š^™XZ[[[šËXÛÛ™H‚ˆ	ØÜš\›[šĞ\™ÜÈÚİ[SX]Ú‹ÚÛYKÛš^ÜËË™İš[\È‚ˆB‚ˆ]	ÜÚİ[Ü™X]HŞ[[[šÈÚ[ˆİš[\ÈZ\ÜÚ[™È]ÔÓ[İ[XØÙ\ÜÚX›IÈÂˆ	ØÜš\›[šĞ\™ÜÈHˆ‚ˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]ÚšYˆÈSÚÛYKÛš^ÜË×™İš[\ÈHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú\İYŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú›ˆ\Ù›ˆŠHÈ	ØÜš\›[šĞ\™ÜÈH	\™ÔİÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆB‚ˆ	[™\‹‘[œİ\™Qİš[\Ğ]˜Z[X›J“š^ÔÈ‹‘—\Wİš[\ÈŠB‚ˆ	ØÜš\›[šĞ\™ÜÈÚİ[SX]Ú›ˆ\Ùˆ‚ˆ	ØÜš\›[šĞ\™ÜÈÚİ[SX]Ú‹Û[ÙÜ\KÙİš[\È‚ˆ	ØÜš\›[šĞ\™ÜÈÚİ[SX]Ú‹ÚÛYKÛš^ÜËË™İš[\È‚ˆB‚ˆ]	ÜÚİ[›İÈÚ[ˆİš[\ÈZ\ÜÚ[™È[™ÔÓ[İ[[˜XØÙ\ÜÚX›IÈÂˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]ÚšYˆÈSÚÛYKÛš^ÜË×™İš[\ÈHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú\İYŠHÈ	ÛØ˜[“TÕVUÓÑHHNÈ™]\›ˆˆˆBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆB‚ˆÈ	[™\‹‘[œİ\™Qİš[\Ğ]˜Z[X›J“š^ÔÈ‹‘—\Wİš[\ÈŠHHÚİ[U›İÂˆB‚ˆ]	ÜÚİ[ÛÛ™\Ú[™İÜÈ]ÈÔÓ[İ[]ÛÜœ™XİIÈÂˆ	ØÜš\›[İ[]Hˆ‚ˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]ÚšYˆÈSÚÛYKÛš^ÜË×™İš[\ÈHŠHÈ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆˆBˆYˆ
	\™Ôİˆ[X]Ú\İYŠHÂˆÈ\™Ôİˆ8àbøà¢HÛ[Ë‹‹ˆ8àäxà®xà¤¹¢¯yaî‚ˆYˆ
	\™Ôİˆ[X]Ú	ÊÛ[Ö×—È—JÊIÊHÈ	ØÜš\›[İ[]H	X]Ú\ÖÌWHBˆ	ÛØ˜[“TÕVUÓÑHHNÈ™]\›ˆˆ‚ˆBˆ	ÛØ˜[“TÕVUÓÑHHÈ™]\›ˆˆ‚ˆB‚ˆÈ	[™\‹‘[œİ\™Qİš[\Ğ]˜Z[X›J“š^ÔÈ‹Î—\Ù\œ×›Û×İš[\ÈŠHHÚİ[U›İÈŠ™İš[\È8àc:)¢øài8àbøà¢¸ào¸àføà¤Êˆ‚‚ˆ	ØÜš\›[İ[]Úİ[P™H‹Û[ØËÕ\Ù\œËÙ›ÛËÙİš[\È‚ˆB‚ˆ]	ÜÚİ[™\ÛÛ™HHÛÛ™šYİ\™YÔÓ\Ù\ˆ[™ÛYH[œİXYÙˆ\Üİ[Z[™Èš^ÜÉÈÂˆ	ØÜš\šY[]P\™ÜÈHˆ‚ˆ	ØÜš\\Ù\\™ÜÈHˆ‚ˆ[ØÚÈ[›ÚÙKUÜÛÂˆ\˜[J	\™İ[Y[ÊBˆ	\™ÔİˆH	\™İ[Y[ÈZ›Ú[ˆˆ‚ˆYˆ
	\™Ôİˆ[X]Ú‹İ˜\‹ÛX‹Ùİš[\Ëİ\Ù\ˆŠHÂˆ	ØÜš\šY[]P\™ÜÈH	\™Ôİ‚ˆ	ÛØ˜[“TÕVUÓÑHHˆ™]\›ˆ˜[XÙXÚÛYKØ[XÙH‚ˆBˆYˆ
	\™Ôİˆ[X]Ú‹]H[XÙHŠHÂˆ	ØÜš\\Ù\\™ÜÈH	\™Ôİ‚ˆBˆ	ÛØ˜[“TÕVUÓÑHHˆ™]\›ˆˆ‚ˆB‚ˆ	[™\‹”™\ÛÛ™Sš^ÜÒY[]J“š^ÔÈŠBˆ	[™\‹‘[œİ\™Qİš[\Ğ]˜Z[X›J“š^ÔÈ‹‘—\Wİš[\ÈŠB‚ˆ	[™\‹“š^ÜÕ\Ù\ˆÚİ[P™H˜[XÙH‚ˆ	[™\‹“š^ÜÒÛYHÚİ[P™H‹ÚÛYKØ[XÙH‚ˆ	ØÜš\šY[]P\™ÜÈÚİ[SX]Ú‹]H›Ûİ‚ˆ	ØÜš\\Ù\\™ÜÈÚİ[SX]Ú‹]H[XÙH‚ˆBˆBŸB