#Requires -Module Pester

<#
.SYNOPSIS
    Handler.VscodeServer.ps1 のユニットテスト

.DESCRIPTION
    VscodeServerHandler クラスのテスト
    100% カバレッジを目標とする
#>

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.VscodeServer.ps1
}

Describe 'VscodeServerHandler' {
    BeforeEach {
        $script:handler = [VscodeServerHandler]::new()
        $script:ctx = [SetupContext]::new("D:\dotfiles")
    }

    Context 'Constructor' {
        It 'should set <property> to <expected>' -ForEach @(
            @{ property = "Name"; expected = "VscodeServer" }
            @{ property = "Description"; expected = "VS Code Server のキャッシュ削除と事前インストール" }
            @{ property = "Order"; expected = 40 }
            @{ property = "RequiresAdmin"; expected = $false }
        ) {
            $handler.$property | Should -Be $expected
        }
    }

    Context 'CanApply' {
        It 'should return false when both SkipVscodeServerClean and SkipVscodeServerPreinstall are true' {
            Mock Write-Host { }
            $ctx.Options["SkipVscodeServerClean"] = $true
            $ctx.Options["SkipVscodeServerPreinstall"] = $true

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'should return false when VS Code is not installed with preinstall enabled and clean disabled' {
            Mock Write-Host { }
            Mock Test-PathExist { return $false }
            Mock Get-ChildItemSafe { return @() }
            Mock Get-ChildItem { return @() }
            $ctx.Options["SkipVscodeServerClean"] = $true
            $ctx.Options["SkipVscodeServerPreinstall"] = $false

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'should return true when VS Code is not installed but clean is enabled' {
            Mock Write-Host { }
            Mock Test-PathExist { return $false }
            Mock Get-ChildItemSafe { return @() }
            Mock Get-ChildItem { return @() }
            $ctx.Options["SkipVscodeServerClean"] = $false
            $ctx.Options["SkipVscodeServerPreinstall"] = $false

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }

        It 'should return true when VS Code Stable is installed' {
            Mock Test-PathExist {
                param($Path)
                return $Path -like "*Microsoft VS Code*"
            }
            Mock Get-ChildItemSafe {
                return @([PSCustomObject]@{
                    FullName = "C:\VS Code\product.json"
                    LastWriteTime = Get-Date
                })
            }
            Mock Get-JsonContent {
                return [PSCustomObject]@{ commit = "abc123" }
            }
            Mock Get-ChildItem { return @() }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }

        It 'should return true when VS Code Insiders is installed' {
            Mock Test-PathExist {
                param($Path)
                return $Path -like "*VS Code Insiders*"
            }
            Mock Get-ChildItemSafe {
                return @([PSCustomObject]@{
                    FullName = "C:\VS Code Insiders\product.json"
                    LastWriteTime = Get-Date
                })
            }
            Mock Get-JsonContent {
                return [PSCustomObject]@{ commit = "def456" }
            }
            Mock Get-ChildItem { return @() }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }
    }

    Context 'Apply - cache deletion' {
        BeforeEach {
            Mock Write-Host { }
            Mock Invoke-Wsl { return "" }
            Mock Test-PathExist { return $false }
            Mock Get-ChildItemSafe { return @() }
            Mock Get-ChildItem { return @() }
        }

        It 'should delete cache when SkipVscodeServerClean is false' {
            $script:cacheDeleted = $false
            Mock Invoke-Wsl {
                param($Arguments)
                if (($Arguments -join " ") -match "rm -rf.*\.vscode-server") {
                    $script:cacheDeleted = $true
                }
            }
            $ctx.Options["SkipVscodeServerClean"] = $false
            $ctx.Options["SkipVscodeServerPreinstall"] = $true

            $result = $handler.Apply($ctx)

            $script:cacheDeleted | Should -Be $true
            $result.Success | Should -Be $true
        }

        It 'should skip cache deletion when SkipVscodeServerClean is true' {
            $script:cacheDeleted = $false
            Mock Invoke-Wsl {
                param($Arguments)
                if (($Arguments -join " ") -match "rm -rf.*\.vscode-server") {
                    $script:cacheDeleted = $true
                }
            }
            $ctx.Options["SkipVscodeServerClean"] = $true
            $ctx.Options["SkipVscodeServerPreinstall"] = $true

            $handler.Apply($ctx)

            $script:cacheDeleted | Should -Be $false
        }

        It 'should use correct cache deletion command' {
            $script:commandArgs = ""
            Mock Invoke-Wsl {
                param($Arguments)
                $script:commandArgs = $Arguments -join " "
            }
            $ctx.Options["SkipVscodeServerClean"] = $false
            $ctx.Options["SkipVscodeServerPreinstall"] = $true

            $handler.Apply($ctx)

            $script:commandArgs | Should -Match "\.vscode-server"
            $script:commandArgs | Should -Match "\.vscode-server-insiders"
            $script:commandArgs | Should -Match "\.vscode-remote-containers"
            $script:commandArgs | Should -Match "/root/"
        }
    }

    Context 'Apply - preinstall' {
        BeforeEach {
            Mock Write-Host { }
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "whoami") {
                    return "nixos"
                }
                return ""
            }
        }

        It 'should preinstall VS Code Stable' {
            $script:curlArgs = ""
            Mock Test-PathExist {
                param($Path)
                return $Path -like "*Microsoft VS Code" -and $Path -notlike "*Insiders*"
            }
            Mock Get-ChildItemSafe {
                param($Path)
                if ($Path -like "*Insiders*") { return @() }
                return @([PSCustomObject]@{
                    FullName = "C:\VS Code\product.json"
                    LastWriteTime = Get-Date
                })
            }
            Mock Get-JsonContent {
                return [PSCustomObject]@{ commit = "stable123" }
            }
            Mock Get-ChildItem { return @() }
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "curl") {
                    $script:curlArgs = $argStr
                }
            }
            $ctx.Options["SkipVscodeServerClean"] = $true
            $ctx.Options["SkipVscodeServerPreinstall"] = $false

            $result = $handler.Apply($ctx)

            $script:curlArgs | Should -Match "stable123"
            $script:curlArgs | Should -Match "server-linux-x64"
            $result.Success | Should -Be $true
        }

        It 'should preinstall VS Code Insiders' {
            $script:curlArgs = ""
            Mock Test-PathExist {
                param($Path)
                return $Path -like "*Insiders*"
            }
            Mock Get-ChildItemSafe {
                param($Path)
                if ($Path -notlike "*Insiders*") { return @() }
                return @([PSCustomObject]@{
                    FullName = "C:\VS Code Insiders\product.json"
                    LastWriteTime = Get-Date
                })
            }
            Mock Get-JsonContent {
                return [PSCustomObject]@{ commit = "insider456" }
            }
            Mock Get-ChildItem { return @() }
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "curl") {
                    $script:curlArgs = $argStr
                }
            }
            $ctx.Options["SkipVscodeServerClean"] = $true
            $ctx.Options["SkipVscodeServerPreinstall"] = $false

            $result = $handler.Apply($ctx)

            $script:curlArgs | Should -Match "insider456"
            $script:curlArgs | Should -Match "server-linux-x64"
            $result.Success | Should -Be $true
        }

        It 'should install both when both VS Code versions are installed' {
            Mock Test-PathExist { return $true }
            $callCount = 0
            $script:wslCallCount = 0
            Mock Get-ChildItemSafe {
                param($Path)
                return @([PSCustomObject]@{
                    FullName = "$Path\product.json"
                    LastWriteTime = Get-Date
                })
            }
            Mock Get-JsonContent {
                $script:callCount++
                if ($script:callCount -eq 1) {
                    return [PSCustomObject]@{ commit = "insider789" }
                }
                return [PSCustomObject]@{ commit = "stable789" }
            }
            Mock Get-ChildItem { return @() }
            Mock Invoke-Wsl { $script:wslCallCount++ }
            $ctx.Options["SkipVscodeServerClean"] = $true
            $ctx.Options["SkipVscodeServerPreinstall"] = $false

            $handler.Apply($ctx)

            # 両方のインストールコマンドが呼ばれる
            $script:wslCallCount | Should -BeGreaterOrEqual 2
        }

        It 'should show warning when product.json is not found' {
            Mock Test-PathExist { return $false }
            Mock Get-ChildItemSafe { return @() }
            Mock Get-ChildItem { return @() }
            $script:warningShown = $false
            Mock Write-Host {
                param($Object)
                if ($Object -match "product.json が見つからない") {
                    $script:warningShown = $true
                }
            }
            $ctx.Options["SkipVscodeServerClean"] = $true
            $ctx.Options["SkipVscodeServerPreinstall"] = $false

            $handler.Apply($ctx)

            $script:warningShown | Should -Be $true
        }

        It 'should skip when SkipVscodeServerPreinstall is true' {
            Mock Test-PathExist { return $true }
            $script:curlCalled = $false
            Mock Get-ChildItemSafe {
                return @([PSCustomObject]@{
                    FullName = "C:\VS Code\product.json"
                    LastWriteTime = Get-Date
                })
            }
            Mock Get-JsonContent {
                return [PSCustomObject]@{ commit = "abc123" }
            }
            Mock Get-ChildItem { return @() }
            Mock Invoke-Wsl {
                param($Arguments)
                if (($Arguments -join " ") -match "curl.*server-linux-x64") {
                    $script:curlCalled = $true
                }
            }
            $ctx.Options["SkipVscodeServerClean"] = $true
            $ctx.Options["SkipVscodeServerPreinstall"] = $true

            $handler.Apply($ctx)

            # インストールコマンドは呼ばれない
            $script:curlCalled | Should -Be $false
        }
    }

    Context 'GetWslDefaultUser' {
        BeforeEach {
            Mock Write-Host { }
            Mock Test-PathExist { return $false }
            Mock Get-ChildItemSafe { return @() }
            Mock Get-ChildItem { return @() }
        }

        It 'should return username when whoami succeeds' {
            $script:homePathUsed = ""
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "whoami") {
                    $global:LASTEXITCODE = 0
                    return "testuser"
                }
                if ($argStr -match "/home/(\w+)") {
                    $script:homePathUsed = $argStr
                }
                return ""
            }
            $ctx.Options["SkipVscodeServerClean"] = $false
            $ctx.Options["SkipVscodeServerPreinstall"] = $true

            $handler.Apply($ctx)

            # キャッシュ削除で /home/testuser が使われる
            $script:homePathUsed | Should -Match "/home/testuser"
        }

        It 'should return nixos when whoami fails' {
            $script:homePathUsed = ""
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "whoami") {
                    $global:LASTEXITCODE = 1
                    return ""
                }
                if ($argStr -match "/home/(\w+)") {
                    $script:homePathUsed = $argStr
                }
                return ""
            }
            $ctx.Options["SkipVscodeServerClean"] = $false
            $ctx.Options["SkipVscodeServerPreinstall"] = $true

            $handler.Apply($ctx)

            # デフォルトで /home/nixos が使われる
            $script:homePathUsed | Should -Match "/home/nixos"
        }
    }

    Context 'FindVscodeProductJson' {
        BeforeEach {
            Mock Write-Host { }
            Mock Invoke-Wsl { return "nixos" }
        }

        It 'should return latest when multiple product.json files exist' {
            Mock Test-PathExist { return $true }
            $script:commitUsed = ""
            Mock Get-ChildItemSafe {
                return @(
                    [PSCustomObject]@{
                        FullName = "C:\old\product.json"
                        LastWriteTime = (Get-Date).AddDays(-10)
                    },
                    [PSCustomObject]@{
                        FullName = "C:\new\product.json"
                        LastWriteTime = (Get-Date)
                    }
                )
            }
            Mock Get-JsonContent {
                param($Path)
                if ($Path -like "*new*") {
                    return [PSCustomObject]@{ commit = "newcommit" }
                }
                return [PSCustomObject]@{ commit = "oldcommit" }
            }
            Mock Get-ChildItem { return @() }
            Mock Invoke-Wsl {
                param($Arguments)
                $argStr = $Arguments -join " "
                if ($argStr -match "(newcommit|oldcommit)") {
                    $script:commitUsed = $Matches[1]
                }
            }
            $ctx.Options["SkipVscodeServerClean"] = $true
            $ctx.Options["SkipVscodeServerPreinstall"] = $false

            $handler.Apply($ctx)

            # 最新の commit が使われる
            $script:commitUsed | Should -Be "newcommit"
        }

        It 'should search files using pattern matching' {
            Mock Test-PathExist { return $false }
            Mock Get-ChildItemSafe { return @() }
            $script:getChildItemCalled = $false
            Mock Get-ChildItem {
                $script:getChildItemCalled = $true
                return @([PSCustomObject]@{
                    FullName = "C:\Users\test\AppData\Local\Programs\Microsoft VS Code\product.json"
                    LastWriteTime = Get-Date
                })
            }
            Mock Get-JsonContent {
                return [PSCustomObject]@{ commit = "patterncommit" }
            }
            $ctx.Options["SkipVscodeServerClean"] = $true
            $ctx.Options["SkipVscodeServerPreinstall"] = $false

            $handler.Apply($ctx)

            $script:getChildItemCalled | Should -Be $true
        }
    }

    Context 'GetVscodeProductInfo - null return' {
        BeforeEach {
            Mock Write-Host { }
            Mock Invoke-Wsl { return "nixos" }
        }

        It 'should return null when product.json parsing fails' {
            Mock Test-PathExist { return $true }
            Mock Get-ChildItemSafe {
                return @([PSCustomObject]@{
                    FullName = "C:\VS Code\product.json"
                    LastWriteTime = Get-Date
                })
            }
            Mock Get-JsonContent {
                throw "JSON パースエラー"
            }
            Mock Get-ChildItem { return @() }
            $ctx.Options["SkipVscodeServerClean"] = $true
            $ctx.Options["SkipVscodeServerPreinstall"] = $false

            # エラーが発生しても処理は継続される
            $result = $handler.Apply($ctx)

            # 成功（エラーはキャッチされる）
            $result.Success | Should -Be $true
        }
    }

    Context 'Error handling' {
        It 'should return failure when exception is thrown' {
            Mock Write-Host { }
            Mock Invoke-Wsl { throw "WSL エラー" }
            $ctx.Options["SkipVscodeServerClean"] = $false
            $ctx.Options["SkipVscodeServerPreinstall"] = $true

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "WSL エラー"
        }
    }
}
