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

    Context 'コンストラクタ' {
        It 'Name が VscodeServer に設定される' {
            $handler.Name | Should -Be "VscodeServer"
        }

        It 'Description が設定される' {
            $handler.Description | Should -Be "VS Code Server のキャッシュ削除と事前インストール"
        }

        It 'Order が 30 に設定される' {
            $handler.Order | Should -Be 30
        }

        It 'RequiresAdmin が $false に設定される' {
            $handler.RequiresAdmin | Should -Be $false
        }
    }

    Context 'CanApply' {
        It 'SkipVscodeServerClean と SkipVscodeServerPreinstall が両方 true の場合は $false' {
            Mock Write-Host { }
            $ctx.Options["SkipVscodeServerClean"] = $true
            $ctx.Options["SkipVscodeServerPreinstall"] = $true

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'VS Code がインストールされていない場合（preinstall 有効、clean 無効）は $false' {
            Mock Write-Host { }
            Mock Test-PathExist { return $false }
            Mock Get-ChildItemSafe { return @() }
            Mock Get-ChildItem { return @() }
            $ctx.Options["SkipVscodeServerClean"] = $true
            $ctx.Options["SkipVscodeServerPreinstall"] = $false

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'VS Code がインストールされていない場合（clean 有効）は $true' {
            Mock Write-Host { }
            Mock Test-PathExist { return $false }
            Mock Get-ChildItemSafe { return @() }
            Mock Get-ChildItem { return @() }
            $ctx.Options["SkipVscodeServerClean"] = $false
            $ctx.Options["SkipVscodeServerPreinstall"] = $false

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }

        It 'VS Code Stable がインストールされている場合は $true' {
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

        It 'VS Code Insiders がインストールされている場合は $true' {
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

    Context 'Apply - キャッシュ削除' {
        BeforeEach {
            Mock Write-Host { }
            Mock Invoke-Wsl { return "" }
            Mock Test-PathExist { return $false }
            Mock Get-ChildItemSafe { return @() }
            Mock Get-ChildItem { return @() }
        }

        It 'SkipVscodeServerClean が false の場合はキャッシュを削除する' {
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

        It 'SkipVscodeServerClean が true の場合はキャッシュ削除をスキップする' {
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

        It 'キャッシュ削除コマンドが正しい' {
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

    Context 'Apply - 事前インストール' {
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

        It 'VS Code Stable の事前インストール' {
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

        It 'VS Code Insiders の事前インストール' {
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

        It '両方の VS Code がインストールされている場合は両方インストール' {
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

        It 'product.json が見つからない場合は警告を出す' {
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

        It 'SkipVscodeServerPreinstall が true の場合はスキップする' {
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

        It 'whoami が成功した場合はユーザー名を返す' {
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

        It 'whoami が失敗した場合は nixos を返す' {
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

        It '複数の product.json がある場合は最新を返す' {
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

        It 'パターンマッチでファイルを検索する' {
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

    Context 'GetVscodeProductInfo - null 返却' {
        BeforeEach {
            Mock Write-Host { }
            Mock Invoke-Wsl { return "nixos" }
        }

        It 'product.json のパースに失敗した場合は null を返す' {
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

    Context 'エラーハンドリング' {
        It '例外が発生した場合は失敗結果を返す' {
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
