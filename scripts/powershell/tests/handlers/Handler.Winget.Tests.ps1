BeforeAll {
    # ソースファイルの読み込み
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.Winget.ps1
}

Describe 'WingetHandler' {
    BeforeEach {
        $script:handler = [WingetHandler]::new()
        $script:ctx = [SetupContext]::new("D:\dotfiles")
    }

    Context 'コンストラクタ' {
        It 'Name が Winget であること' {
            $handler.Name | Should -Be "Winget"
        }

        It 'Description が設定されていること' {
            $handler.Description | Should -Not -BeNullOrEmpty
        }

        It 'Order が 90 であること' {
            $handler.Order | Should -Be 90
        }

        It 'RequiresAdmin が true であること' {
            $handler.RequiresAdmin | Should -Be $true
        }
    }

    Context 'CanApply - winget が見つからない場合' {
        BeforeEach {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist { return $true }
        }

        It 'false を返すこと' {
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - import モードでパッケージファイルがない場合' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $false }
        }

        It 'false を返すこと' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.CanApply($ctx)
            $result | Should -Be $false
        }
    }

    Context 'CanApply - import モードで条件を満たす場合' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
        }

        It 'true を返すこと' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }
    }

    Context 'CanApply - export モードで winget がある場合' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
        }

        It 'パッケージファイルがなくても true を返すこと' {
            $ctx.Options["WingetMode"] = "export"
            $result = $handler.CanApply($ctx)
            $result | Should -Be $true
        }
    }

    Context 'Apply - import モード成功' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Invoke-Winget {
                $global:LASTEXITCODE = 0
                return "Packages installed"
            }
        }

        It '成功結果を返すこと' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "インストール"
        }

        It 'winget import が呼ばれること' {
            $script:wingetCalled = $false
            $script:wingetArgs = $null
            Mock Invoke-Winget {
                param($Arguments)
                $script:wingetCalled = $true
                $script:wingetArgs = $Arguments
                $global:LASTEXITCODE = 0
            }

            $ctx.Options["WingetMode"] = "import"
            $handler.Apply($ctx)

            $script:wingetCalled | Should -Be $true
            $script:wingetArgs | Should -Contain "import"
        }
    }

    Context 'Apply - import モード一部失敗' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Invoke-Winget {
                $global:LASTEXITCODE = 1
                return "Some packages failed"
            }
        }

        It '成功結果を返すこと（一部失敗の警告付き）' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "一部失敗"
        }
    }

    Context 'Apply - export モード成功' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock New-DirectorySafe { }
            Mock Invoke-Winget {
                $global:LASTEXITCODE = 0
                return "Packages exported"
            }
        }

        It '成功結果を返すこと' {
            $ctx.Options["WingetMode"] = "export"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "エクスポート"
        }

        It 'winget export が呼ばれること' {
            $script:wingetCalled = $false
            $script:wingetArgs = $null
            Mock Invoke-Winget {
                param($Arguments)
                $script:wingetCalled = $true
                $script:wingetArgs = $Arguments
                $global:LASTEXITCODE = 0
            }

            $ctx.Options["WingetMode"] = "export"
            $handler.Apply($ctx)

            $script:wingetCalled | Should -Be $true
            $script:wingetArgs | Should -Contain "export"
        }
    }

    Context 'Apply - export モードでディレクトリがない場合' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $false }
            Mock New-DirectorySafe { }
            Mock Invoke-Winget {
                $global:LASTEXITCODE = 0
                return "Packages exported"
            }
        }

        It 'ディレクトリが作成されること' {
            $script:dirCreated = $false
            Mock New-DirectorySafe {
                $script:dirCreated = $true
            }

            $ctx.Options["WingetMode"] = "export"
            $handler.Apply($ctx)

            $script:dirCreated | Should -Be $true
        }
    }

    Context 'Apply - export モード一部失敗' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Invoke-Winget {
                $global:LASTEXITCODE = 1
                return "Some packages could not be exported"
            }
        }

        It '成功結果を返すこと（一部除外の警告付き）' {
            $ctx.Options["WingetMode"] = "export"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $true
            $result.Message | Should -Match "一部除外"
        }
    }

    Context 'Apply - 不明なモード' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
        }

        It '失敗結果を返すこと' {
            $ctx.Options["WingetMode"] = "unknown"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $false
            $result.Message | Should -Match "不明なモード"
        }
    }

    Context 'Apply - 例外発生' {
        BeforeEach {
            Mock Get-ExternalCommand { return @{ Source = "C:\winget.exe" } }
            Mock Test-PathExist { return $true }
            Mock Invoke-Winget { throw "winget error" }
        }

        It '失敗結果を返すこと' {
            $ctx.Options["WingetMode"] = "import"
            $result = $handler.Apply($ctx)
            $result.Success | Should -Be $false
            $result.Message | Should -Match "winget error"
        }
    }

}
