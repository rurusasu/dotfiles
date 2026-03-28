#Requires -Module Pester

<#
.SYNOPSIS
    Handler.Chezmoi.ps1 のユニットテスト

.DESCRIPTION
    ChezmoiHandler クラスのテスト
    100% カバレッジを目標とする
#>

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.Chezmoi.ps1
}

Describe 'ChezmoiHandler' {
    BeforeEach {
        $script:handler = [ChezmoiHandler]::new()
        $script:ctx = [SetupContext]::new("D:\dotfiles")
    }

    Context 'Constructor' {
        It 'should set <property> to <expected>' -ForEach @(
            @{ property = "Name"; expected = "Chezmoi" }
            @{ property = "Description"; expected = "chezmoi による dotfiles 適用" }
            @{ property = "Order"; expected = 10 }
            @{ property = "RequiresAdmin"; expected = $false }
        ) {
            $handler.$property | Should -Be $expected
        }
    }

    Context 'CanApply - chezmoi detection' {
        BeforeEach {
            # TestChezmoiExecutable() のために Invoke-Chezmoi をモック（成功）
            Mock Invoke-Chezmoi {
                $global:LASTEXITCODE = 0
                return "chezmoi version 2.45.0"
            }
        }

        It 'should return true when chezmoi is in PATH' {
            Mock Get-ExternalCommand {
                return [PSCustomObject]@{
                    Source = "C:\chezmoi\chezmoi.exe"
                }
            }
            Mock Test-PathExist { return $true }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }

        It 'should return true when chezmoi is in WinGet Links' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist {
                param($Path)
                # WinGet Links の chezmoi.exe が存在
                if ($Path -like "*WinGet\Links\chezmoi.exe") { return $true }
                # ソースディレクトリも存在
                if ($Path -like "*chezmoi") { return $true }
                return $false
            }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }

        It 'should return true when chezmoi is in WinGet Packages' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist {
                param($Path)
                if ($Path -like "*WinGet\Links*") { return $false }
                if ($Path -like "*WinGet\Packages") { return $true }
                if ($Path -like "*chezmoi.exe") { return $true }
                if ($Path -like "*chezmoi") { return $true }  # ソースディレクトリ
                return $false
            }
            Mock Get-ChildItemSafe {
                return @([PSCustomObject]@{
                        Name     = "twpayne.chezmoi_1.0.0"
                        FullName = "C:\WinGet\Packages\twpayne.chezmoi_1.0.0"
                    })
            }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }

        It 'should return true when chezmoi is in Programs directory' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist {
                param($Path)
                if ($Path -like "*WinGet\Links*") { return $false }
                if ($Path -like "*WinGet\Packages") { return $false }
                if ($Path -like "*Programs\chezmoi\chezmoi.exe") { return $true }
                if ($Path -like "*chezmoi") { return $true }  # ソースディレクトリ
                return $false
            }
            Mock Get-ChildItemSafe { return @() }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }

        It 'should return false and show install instructions when chezmoi is not found' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist { return $false }
            Mock Get-ChildItemSafe { return @() }
            $script:notFoundMessageShown = $false
            Mock Write-Host {
                param($Object)
                if ($Object -match "chezmoi がインストールされていません") {
                    $script:notFoundMessageShown = $true
                }
            }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
            $script:notFoundMessageShown | Should -Be $true
        }
    }

    Context 'CanApply - source directory' {
        It 'should return false when chezmoi source directory does not exist' {
            Mock Get-ExternalCommand {
                return [PSCustomObject]@{ Source = "C:\chezmoi.exe" }
            }
            # TestChezmoiExecutable() のモック
            Mock Invoke-Chezmoi {
                $global:LASTEXITCODE = 0
                return "chezmoi version 2.45.0"
            }
            Mock Test-PathExist {
                param($Path)
                if ($Path -like "*chezmoi.exe") { return $true }
                return $false  # ソースディレクトリは存在しない
            }
            $script:sourceDirNotFoundShown = $false
            Mock Write-Host {
                param($Object)
                if ($Object -match "ソースディレクトリが見つかりません") {
                    $script:sourceDirNotFoundShown = $true
                }
            }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
            $script:sourceDirNotFoundShown | Should -Be $true
        }
    }

    Context 'Apply - success cases' {
        BeforeEach {
            Mock Get-ExternalCommand {
                return [PSCustomObject]@{ Source = "C:\chezmoi\chezmoi.exe" }
            }
            Mock Test-PathExist { return $true }
            Mock New-DirectorySafe { }
            Mock Write-Host { }
            # op が見つからない想定（EnsureOnePasswordAvailable は警告のみ出して続行）
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'op' }
            Mock Get-ChildItemSafe { return @() }
            # Find-WinGetExe が実ファイルシステムにアクセスしないようモック
            Mock Find-WinGetExe { return $null }
            # 管理者セッションとしてモック（DeployProfileToOtherUsers が実行されるケースを検証）
            Mock Test-IsAdminSession { return $true }
            # DeployProfileToOtherUsers でプロファイルが存在しないケース（早期リターン）
            Mock Test-Path { return $false }
        }

        It 'should succeed when chezmoi apply succeeds' {
            Mock Invoke-Chezmoi {
                $global:LASTEXITCODE = 0
                if ($Arguments -contains '--version') {
                    return "chezmoi version 2.45.0"
                }
            }
            $handler.CanApply($ctx)

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
            $result.Message | Should -Be "dotfiles を適用しました"
        }

        It 'should pass correct non-interactive arguments to chezmoi apply' {
            $script:chezmoiExePath = ""
            Mock Invoke-Chezmoi {
                param($ExePath, $Arguments)
                $script:chezmoiExePath = $ExePath
                $global:LASTEXITCODE = 0
                if ($Arguments -contains '--version') {
                    return "chezmoi version 2.45.0"
                }
            }
            $handler.CanApply($ctx)

            $handler.Apply($ctx)

            $script:chezmoiExePath | Should -Be "C:\chezmoi\chezmoi.exe"
            Should -Invoke Invoke-Chezmoi -ParameterFilter {
                $Arguments -contains "--persistent-state" -and
                $Arguments -contains "--cache" -and
                $Arguments -contains "--no-tty" -and
                $Arguments -contains "apply" -and
                $Arguments -contains "--source" -and
                $Arguments -contains "D:\dotfiles\chezmoi"
            } -Times 1
            Should -Invoke Invoke-Chezmoi -ParameterFilter {
                $Arguments -contains "init" -and
                $Arguments -contains "--source"
            } -Times 1
        }

        It 'should show success message after completion' {
            $script:successMessageShown = $false
            Mock Invoke-Chezmoi {
                $global:LASTEXITCODE = 0
                if ($Arguments -contains '--version') {
                    return "chezmoi version 2.45.0"
                }
            }
            Mock Write-Host {
                param($Object, $ForegroundColor)
                if ($Object -match "chezmoi apply 完了" -and $ForegroundColor -eq "Green") {
                    $script:successMessageShown = $true
                }
            }
            $handler.CanApply($ctx)

            $handler.Apply($ctx)

            $script:successMessageShown | Should -Be $true
        }
    }

    Context 'Apply - non-interactive execution' {
        BeforeEach {
            Mock Get-ExternalCommand {
                return [PSCustomObject]@{ Source = "C:\chezmoi\chezmoi.exe" }
            }
            Mock Test-PathExist { return $true }
            Mock New-DirectorySafe { }
            Mock Write-Host { }
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'op' }
            Mock Get-ChildItemSafe { return @() }
            # Find-WinGetExe が実ファイルシステムにアクセスしないようモック
            Mock Find-WinGetExe { return $null }
            # 非管理者セッションでは DeployProfileToOtherUsers はスキップされる
            Mock Test-IsAdminSession { return $false }
        }

        It 'should not call DeployProfileToOtherUsers when not running as admin' {
            Mock Invoke-Chezmoi {
                $global:LASTEXITCODE = 0
                if ($Arguments -contains '--version') {
                    return "chezmoi version 2.45.0"
                }
            }
            $script:getChildItemDeployCallCount = 0
            # DeployProfileToOtherUsers が呼ばれると $usersDir の Get-ChildItem が実行される
            # 非管理者では Test-IsAdminSession が false を返すのでここには到達しない
            Mock Get-ChildItem {
                # USERPROFILE の親ディレクトリへのアクセスを検出
                $script:getChildItemDeployCallCount++
                return @()
            }

            $handler.CanApply($ctx) | Should -Be $true
            $handler.Apply($ctx) | Out-Null

            # 非管理者では DeployProfileToOtherUsers が呼ばれないため Get-ChildItem も呼ばれない
            $script:getChildItemDeployCallCount | Should -Be 0
        }

        It 'should invoke chezmoi init to regenerate config before apply' {
            Mock Invoke-Chezmoi {
                $global:LASTEXITCODE = 0
                if ($Arguments -contains '--version') {
                    return "chezmoi version 2.45.0"
                }
            }

            $handler.CanApply($ctx) | Should -Be $true
            $handler.Apply($ctx) | Out-Null

            Should -Invoke Invoke-Chezmoi -ParameterFilter {
                $Arguments -contains "init" -and
                $Arguments -contains "--source"
            } -Times 1
        }

        It 'should include --no-tty in apply command' {
            Mock Invoke-Chezmoi {
                $global:LASTEXITCODE = 0
                if ($Arguments -contains '--version') {
                    return "chezmoi version 2.45.0"
                }
            }

            $handler.CanApply($ctx) | Should -Be $true
            $handler.Apply($ctx) | Out-Null

            Should -Invoke Invoke-Chezmoi -ParameterFilter {
                $Arguments -contains "--persistent-state" -and
                $Arguments -contains "--cache" -and
                $Arguments -contains "--no-tty" -and
                $Arguments -contains "apply" -and
                $Arguments -contains "--source" -and
                $Arguments -contains "D:\dotfiles\chezmoi"
            } -Times 1
        }

        It 'should include -v in apply command to show progress' {
            Mock Invoke-Chezmoi {
                $global:LASTEXITCODE = 0
                if ($Arguments -contains '--version') {
                    return "chezmoi version 2.45.0"
                }
            }

            $handler.CanApply($ctx) | Should -Be $true
            $handler.Apply($ctx) | Out-Null

            Should -Invoke Invoke-Chezmoi -ParameterFilter {
                $Arguments -contains "-v" -and
                $Arguments -contains "apply"
            } -Times 1
        }

        It 'should include --force in apply command to skip conflict prompts' {
            Mock Invoke-Chezmoi {
                $global:LASTEXITCODE = 0
                if ($Arguments -contains '--version') {
                    return "chezmoi version 2.45.0"
                }
            }

            $handler.CanApply($ctx) | Should -Be $true
            $handler.Apply($ctx) | Out-Null

            Should -Invoke Invoke-Chezmoi -ParameterFilter {
                $Arguments -contains "--force" -and
                $Arguments -contains "apply"
            } -Times 1
        }

        It 'should use -MergeStderr to show script stderr output in console' {
            Mock Invoke-Chezmoi {
                $global:LASTEXITCODE = 0
                if ($Arguments -contains '--version') {
                    return "chezmoi version 2.45.0"
                }
            }

            $handler.CanApply($ctx) | Should -Be $true
            $handler.Apply($ctx) | Out-Null

            Should -Invoke Invoke-Chezmoi -ParameterFilter {
                $MergeStderr -eq $true -and
                $Arguments -contains "apply"
            } -Times 1
        }

        It 'should create runtime directories before apply' {
            Mock Invoke-Chezmoi {
                $global:LASTEXITCODE = 0
                if ($Arguments -contains '--version') {
                    return "chezmoi version 2.45.0"
                }
            }

            $handler.CanApply($ctx) | Should -Be $true
            $handler.Apply($ctx) | Out-Null

            Should -Invoke New-DirectorySafe -Times 2
        }
    }

    Context 'Apply - failure cases' {
        BeforeEach {
            Mock Get-ExternalCommand {
                return [PSCustomObject]@{ Source = "C:\chezmoi\chezmoi.exe" }
            }
            Mock Test-PathExist { return $true }
            Mock New-DirectorySafe { }
            Mock Write-Host { }
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'op' }
            Mock Get-ChildItemSafe { return @() }
            # Find-WinGetExe が実ファイルシステムにアクセスしないようモック
            Mock Find-WinGetExe { return $null }
            # 非管理者セッションでは DeployProfileToOtherUsers はスキップされる
            Mock Test-IsAdminSession { return $false }
        }

        It 'should fail when chezmoi apply returns non-zero exit code' {
            Mock Invoke-Chezmoi {
                if ($Arguments -contains '--version') {
                    $global:LASTEXITCODE = 0
                    return "chezmoi version 2.45.0"
                }
                if ($Arguments -contains 'apply') {
                    $global:LASTEXITCODE = 1
                    return ""
                }
                $global:LASTEXITCODE = 0
                return ""
            }
            $handler.CanApply($ctx)

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "chezmoi apply が失敗しました"
        }

        It 'should show manual execution command on failure' {
            # 例外でエラーをシミュレート - メッセージに chezmoi エラー を含める
            $script:errorMessageShown = $false
            Mock Write-Host {
                param($Object)
                if ($Object -match "chezmoi エラー") {
                    $script:errorMessageShown = $true
                }
            }
            Mock Invoke-Chezmoi {
                if ($Arguments -contains '--version') {
                    $global:LASTEXITCODE = 0
                    return "chezmoi version 2.45.0"
                }
                throw "chezmoi エラー"
            }
            $handler.CanApply($ctx)

            $result = $handler.Apply($ctx)

            # 例外が発生した場合、CreateFailureResult でメッセージが設定される
            $result.Success | Should -Be $false
            $result.Message | Should -Match "chezmoi エラー"
        }

        It 'should fail when exception is thrown' {
            Mock Invoke-Chezmoi {
                if ($Arguments -contains '--version') {
                    $global:LASTEXITCODE = 0
                    return "chezmoi version 2.45.0"
                }
                throw "chezmoi エラー"
            }
            $handler.CanApply($ctx)

            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $false
            $result.Message | Should -Match "chezmoi エラー"
        }
    }

    Context 'ShowChezmoiInstallInstructions' {
        It 'should include winget command in install instructions' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist { return $false }
            Mock Get-ChildItemSafe { return @() }
            Mock Write-Host { }

            $handler.CanApply($ctx)

            Should -Invoke Write-Host -ParameterFilter {
                $Object -match "winget install.*twpayne.chezmoi"
            }
        }

        It 'should include GitHub direct fetch method in install instructions' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist { return $false }
            Mock Get-ChildItemSafe { return @() }
            Mock Write-Host { }

            $handler.CanApply($ctx)

            Should -Invoke Write-Host -ParameterFilter {
                $Object -match "chezmoi init rurusasu/dotfiles"
            }
        }

        It 'should include source path in install instructions' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist { return $false }
            Mock Get-ChildItemSafe { return @() }
            Mock Write-Host { }

            $handler.CanApply($ctx)

            Should -Invoke Write-Host -ParameterFilter {
                $Object -match "D:\\dotfiles\\chezmoi"
            }
        }

        It 'should not use deprecated --source-path option in install instructions' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist { return $false }
            Mock Get-ChildItemSafe { return @() }
            Mock Write-Host { }

            $handler.CanApply($ctx)

            Should -Invoke Write-Host -ParameterFilter {
                $Object -match "--source-path"
            } -Times 0
        }
    }

    Context 'FindChezmoiExe - search order' {
        BeforeEach {
            # TestChezmoiExecutable() のモック
            Mock Invoke-Chezmoi {
                $global:LASTEXITCODE = 0
                return "chezmoi version 2.45.0"
            }
        }

        It 'should search in order: PATH, WinGet Links, WinGet Packages, Programs' {
            $script:searchOrder = @()

            Mock Get-ExternalCommand {
                $script:searchOrder += "PATH"
                return $null
            }
            Mock Test-PathExist {
                param($Path)
                if ($Path -like "*WinGet\Links*") {
                    $script:searchOrder += "Links"
                    return $false
                }
                if ($Path -like "*WinGet\Packages") {
                    $script:searchOrder += "Packages"
                    return $false
                }
                if ($Path -like "*Programs\chezmoi*") {
                    $script:searchOrder += "Programs"
                    return $false
                }
                return $false
            }
            Mock Get-ChildItemSafe { return @() }
            Mock Write-Host { }

            $handler.CanApply($ctx)

            $script:searchOrder[0] | Should -Be "PATH"
            $script:searchOrder | Should -Contain "Links"
            $script:searchOrder | Should -Contain "Packages"
        }

        It 'should not search other locations when found in PATH' {
            Mock Get-ExternalCommand {
                return [PSCustomObject]@{ Source = "C:\chezmoi.exe" }
            }
            Mock Test-PathExist { return $true }

            $handler.CanApply($ctx)

            # Test-PathExist は chezmoi ソースディレクトリの確認のみ
            Should -Invoke Test-PathExist -Times 1
        }
    }

    Context 'WinGet Packages search' {
        BeforeEach {
            # TestChezmoiExecutable() のモック
            Mock Invoke-Chezmoi {
                $global:LASTEXITCODE = 0
                return "chezmoi version 2.45.0"
            }
        }

        It 'should search packages with twpayne.chezmoi* pattern' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist {
                param($Path)
                if ($Path -like "*WinGet\Links*") { return $false }
                if ($Path -like "*WinGet\Packages") { return $true }
                if ($Path -like "*twpayne.chezmoi*\chezmoi.exe") { return $true }
                if ($Path -like "*chezmoi") { return $true }
                return $false
            }
            Mock Get-ChildItemSafe {
                param($Path)
                if ($Path -like "*Packages*") {
                    return @([PSCustomObject]@{
                            Name     = "twpayne.chezmoi_2.40.0_x64"
                            FullName = "C:\WinGet\Packages\twpayne.chezmoi_2.40.0_x64"
                        })
                }
                return @()
            }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
            Should -Invoke Get-ChildItemSafe -ParameterFilter {
                $Directory -eq $true
            }
        }

        It 'should search next location when chezmoi.exe not found in package' {
            Mock Get-ExternalCommand { return $null }
            Mock Test-PathExist {
                param($Path)
                if ($Path -like "*WinGet\Links*") { return $false }
                if ($Path -like "*WinGet\Packages") { return $true }
                if ($Path -like "*twpayne.chezmoi*\chezmoi.exe") { return $false }
                if ($Path -like "*Programs\chezmoi*") { return $true }
                if ($Path -like "*chezmoi") { return $true }
                return $false
            }
            Mock Get-ChildItemSafe {
                return @([PSCustomObject]@{
                        Name     = "twpayne.chezmoi_2.40.0"
                        FullName = "C:\WinGet\Packages\twpayne.chezmoi_2.40.0"
                    })
            }

            $result = $handler.CanApply($ctx)

            # Programs で見つかる
            $result | Should -Be $true
        }
    }

    Context 'EnsureOnePasswordAvailable' {
        BeforeEach {
            Mock Get-ExternalCommand {
                return [PSCustomObject]@{ Source = "C:\chezmoi\chezmoi.exe" }
            }
            Mock Invoke-Chezmoi {
                $global:LASTEXITCODE = 0
                return "chezmoi version 2.45.0"
            }
            Mock Test-PathExist { return $true }
            Mock New-DirectorySafe { }
            Mock Invoke-Chezmoi {
                $global:LASTEXITCODE = 0
            }
            # 非管理者セッションでは DeployProfileToOtherUsers はスキップされる
            Mock Test-IsAdminSession { return $false }
            # Find-WinGetExe が実ファイルシステムにアクセスしないようモック
            Mock Find-WinGetExe { return $null }
        }

        It 'should log warning and continue when op is not found' {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'op' }
            Mock Get-ChildItemSafe { return @() }
            # Find-WinGetExe が実ファイルシステムにアクセスしないようモック
            Mock Find-WinGetExe { return $null } -ParameterFilter { $PackagePattern -like '*1Password*' }
            $script:warningLogged = $false
            Mock Write-Host {
                param($Object)
                if ($Object -match '1Password CLI.*見つかりません') { $script:warningLogged = $true }
            }
            $handler.CanApply($ctx)

            $result = $handler.Apply($ctx)

            $script:warningLogged | Should -Be $true
            $result.Success | Should -Be $true
        }

        It 'should proceed silently when op whoami succeeds' {
            Mock Get-Command { return [PSCustomObject]@{ Source = 'C:\op.exe' } } -ParameterFilter { $Name -eq 'op' }
            Mock Invoke-OpWhoAmI {
                return [PSCustomObject]@{ Output = 'my@example.com'; ExitCode = 0 }
            }
            Mock Read-Host { return '' }
            $script:signedInLogged = $false
            $script:instructionsShown = $false
            Mock Write-Host {
                param($Object)
                if ($Object -match 'サインイン済み') { $script:signedInLogged = $true }
                if ($Object -match '認証が必要') { $script:instructionsShown = $true }
            }
            $handler.CanApply($ctx)

            $handler.Apply($ctx)

            $script:signedInLogged | Should -Be $true
            # サインイン済みなのでセットアップ案内は表示されない
            $script:instructionsShown | Should -Be $false
            Should -Invoke Read-Host -Times 0
        }

        It 'should attempt op signin when op whoami fails' {
            Mock Get-Command { return [PSCustomObject]@{ Source = 'C:\op.exe' } } -ParameterFilter { $Name -eq 'op' }
            Mock Invoke-OpWhoAmI {
                return [PSCustomObject]@{ Output = ''; ExitCode = 1 }
            }
            Mock Invoke-OpSignIn {
                return [PSCustomObject]@{ Output = ''; ExitCode = 0 }
            }
            Mock Read-Host { return '' }
            Mock Test-InteractiveEnvironment { return $true }
            $script:instructionsShown = $false
            Mock Write-Host {
                param($Object)
                if ($Object -match '認証が必要') { $script:instructionsShown = $true }
            }
            $handler.CanApply($ctx)

            $handler.Apply($ctx)

            $script:instructionsShown | Should -Be $true
            Should -Invoke Invoke-OpSignIn -Times 3
        }

        It 'should sign in and log success after op signin succeeds' {
            Mock Get-Command { return [PSCustomObject]@{ Source = 'C:\op.exe' } } -ParameterFilter { $Name -eq 'op' }
            $script:whoamiCallCount = 0
            Mock Invoke-OpWhoAmI {
                $script:whoamiCallCount++
                # 2回目で成功（op signin 後）
                if ($script:whoamiCallCount -ge 2) {
                    return [PSCustomObject]@{ Output = 'my@example.com'; ExitCode = 0 }
                }
                return [PSCustomObject]@{ Output = ''; ExitCode = 1 }
            }
            Mock Invoke-OpSignIn {
                return [PSCustomObject]@{ Output = ''; ExitCode = 0 }
            }
            Mock Read-Host { return '' }
            Mock Test-InteractiveEnvironment { return $true }
            $script:signedInLogged = $false
            Mock Write-Host {
                param($Object)
                if ($Object -match 'サインイン完了') { $script:signedInLogged = $true }
            }
            $handler.CanApply($ctx)

            $handler.Apply($ctx)

            $script:signedInLogged | Should -Be $true
        }

        It 'should log warning after max retries exhausted' {
            Mock Get-Command { return [PSCustomObject]@{ Source = 'C:\op.exe' } } -ParameterFilter { $Name -eq 'op' }
            Mock Invoke-OpWhoAmI {
                return [PSCustomObject]@{ Output = ''; ExitCode = 1 }
            }
            Mock Invoke-OpSignIn {
                return [PSCustomObject]@{ Output = ''; ExitCode = 1 }
            }
            Mock Read-Host { return '' }
            Mock Test-InteractiveEnvironment { return $true }
            $script:failureWarningLogged = $false
            Mock Write-Host {
                param($Object)
                if ($Object -match 'サインインに失敗') { $script:failureWarningLogged = $true }
            }
            $handler.CanApply($ctx)

            $handler.Apply($ctx)

            $script:failureWarningLogged | Should -Be $true
            Should -Invoke Read-Host -Times 2
        }
    }

    Context 'FindOpExe' {
        BeforeEach {
            Mock Invoke-Chezmoi {
                $global:LASTEXITCODE = 0
                return "chezmoi version 2.45.0"
            }
            Mock Get-ExternalCommand {
                return [PSCustomObject]@{ Source = "C:\chezmoi\chezmoi.exe" }
            }
            Mock Test-PathExist { return $true }
            Mock New-DirectorySafe { }
            Mock Write-Host { }
            Mock Invoke-OpWhoAmI {
                return [PSCustomObject]@{ Output = 'my@example.com'; ExitCode = 0 }
            }
            # 非管理者セッションでは DeployProfileToOtherUsers はスキップされる
            Mock Test-IsAdminSession { return $false }
            # Find-WinGetExe が実ファイルシステムにアクセスしないようデフォルトモック
            Mock Find-WinGetExe { return $null }
        }

        It 'should find op from PATH' {
            Mock Get-Command {
                return [PSCustomObject]@{ Source = 'C:\tools\op.exe' }
            } -ParameterFilter { $Name -eq 'op' }

            $handler.CanApply($ctx)
            $handler.Apply($ctx)

            Should -Invoke Invoke-OpWhoAmI -ParameterFilter {
                $OpExe -eq 'C:\tools\op.exe'
            } -Times 1
        }

        It 'should find op from WinGet Packages when not in PATH' {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'op' }
            # Find-WinGetExe が全ユーザーの WinGet Packages を検索するため、
            # Get-ChildItem と Test-Path をモックして op.exe を返す
            Mock Find-WinGetExe {
                return 'C:\WinGet\Packages\AgileBits.1Password.CLI_2.32.1\op.exe'
            } -ParameterFilter { $PackagePattern -like '*1Password*' }

            $handler.CanApply($ctx)
            $handler.Apply($ctx)

            Should -Invoke Invoke-OpWhoAmI -ParameterFilter {
                $OpExe -eq 'C:\WinGet\Packages\AgileBits.1Password.CLI_2.32.1\op.exe'
            } -Times 1
        }

        It 'should log warning when op is not found anywhere' {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'op' }
            Mock Find-WinGetExe { return $null } -ParameterFilter { $PackagePattern -like '*1Password*' }
            $script:notFoundWarned = $false
            Mock Write-Host {
                param($Object)
                if ($Object -match '1Password CLI.*見つかりません') { $script:notFoundWarned = $true }
            }

            $handler.CanApply($ctx)
            $handler.Apply($ctx)

            $script:notFoundWarned | Should -Be $true
            Should -Invoke Invoke-OpWhoAmI -Times 0
        }
    }

    Context 'TestChezmoiExecutable - DLL check' {
        It 'should return false when chezmoi fails due to DLL error' {
            Mock Get-ExternalCommand {
                return [PSCustomObject]@{ Source = "C:\chezmoi.exe" }
            }
            Mock Test-PathExist { return $true }
            Mock Invoke-Chezmoi {
                throw "VCRUNTIME140.dll が見つかりません"
            }
            $script:warningShown = $false
            Mock Write-Host {
                param($Object)
                if ($Object -match "chezmoi が正常に動作しません") {
                    $script:warningShown = $true
                }
            }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
            $script:warningShown | Should -Be $true
        }

        It 'should return false when chezmoi returns non-zero exit code' {
            Mock Get-ExternalCommand {
                return [PSCustomObject]@{ Source = "C:\chezmoi.exe" }
            }
            Mock Test-PathExist { return $true }
            Mock Invoke-Chezmoi {
                $global:LASTEXITCODE = 1
                return ""
            }
            Mock Write-Host { }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $false
        }

        It 'should return true when chezmoi --version succeeds' {
            Mock Get-ExternalCommand {
                return [PSCustomObject]@{ Source = "C:\chezmoi.exe" }
            }
            Mock Test-PathExist { return $true }
            Mock Invoke-Chezmoi {
                $global:LASTEXITCODE = 0
                return "chezmoi version 2.45.0"
            }

            $result = $handler.CanApply($ctx)

            $result | Should -Be $true
        }
    }

    Context 'DeployProfileToOtherUsers - admin session' {
        BeforeEach {
            Mock Get-ExternalCommand {
                return [PSCustomObject]@{ Source = "C:\chezmoi\chezmoi.exe" }
            }
            Mock Test-PathExist { return $true }
            Mock New-DirectorySafe { }
            Mock Write-Host { }
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'op' }
            Mock Get-ChildItemSafe { return @() }
            Mock Find-WinGetExe { return $null }
            Mock Invoke-Chezmoi {
                $global:LASTEXITCODE = 0
                return "chezmoi version 2.45.0"
            }
            Mock Test-IsAdminSession { return $true }
        }

        It 'should skip deploy when profile source does not exist' {
            Mock Test-Path { return $false }
            $script:copyItemCalled = $false
            Mock Copy-Item { $script:copyItemCalled = $true }

            $handler.CanApply($ctx)
            $handler.Apply($ctx)

            $script:copyItemCalled | Should -Be $false
        }

        It 'should deploy profile to other users when admin' {
            Mock Test-Path { return $true }
            Mock Get-ChildItemSafe {
                return @([PSCustomObject]@{ Name = "OtherUser"; FullName = "C:\Users\OtherUser" })
            }
            $script:copyItemCalled = $false
            Mock Copy-Item { $script:copyItemCalled = $true }

            $handler.CanApply($ctx)
            $handler.Apply($ctx)

            $script:copyItemCalled | Should -Be $true
        }

        It 'should skip inaccessible user directories without failing' {
            Mock Test-Path { return $true }
            Mock Get-ChildItemSafe {
                return @([PSCustomObject]@{ Name = "OtherUser"; FullName = "C:\Users\OtherUser" })
            }
            Mock Copy-Item { throw [System.UnauthorizedAccessException]"Access to the path is denied." }

            $handler.CanApply($ctx)
            $result = $handler.Apply($ctx)

            $result.Success | Should -Be $true
        }
    }

    Context 'DeployProfileToOtherUsers - non-admin session' {
        BeforeEach {
            Mock Get-ExternalCommand {
                return [PSCustomObject]@{ Source = "C:\chezmoi\chezmoi.exe" }
            }
            Mock Test-PathExist { return $true }
            Mock New-DirectorySafe { }
            Mock Write-Host { }
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'op' }
            Mock Get-ChildItemSafe { return @() }
            Mock Find-WinGetExe { return $null }
            Mock Invoke-Chezmoi {
                $global:LASTEXITCODE = 0
                return "chezmoi version 2.45.0"
            }
            Mock Test-IsAdminSession { return $false }
        }

        It 'should not call Copy-Item even when profile source exists' {
            Mock Test-Path { return $true }
            Mock Copy-Item { }

            $handler.CanApply($ctx)
            $handler.Apply($ctx)

            Should -Invoke Copy-Item -Times 0
        }
    }

    Context 'Test-IsAdminSession' {
        It 'should return a bool value' {
            $result = Test-IsAdminSession
            $result | Should -BeOfType [bool]
        }

        It 'should return false in non-elevated test environment' {
            # テスト環境は通常管理者で実行しないため false が期待値
            $result = Test-IsAdminSession
            $result | Should -Be $false
        }
    }
}
