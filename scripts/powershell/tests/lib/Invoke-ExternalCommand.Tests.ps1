#Requires -Module Pester

<#
.SYNOPSIS
    Invoke-ExternalCommand.ps1 のユニットテスト

.DESCRIPTION
    外部コマンドラッパー関数のテスト
    100% カバレッジを目標とする
#>

BeforeAll {
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
}

Describe 'Invoke-Wsl' {
    It '引数を WSL に渡す' {
        Mock wsl { return "test output" }
        
        $result = Invoke-Wsl --list --quiet
        
        Should -Invoke wsl -Times 1
    }

    It '引数なしで呼び出せる' {
        Mock wsl { return "" }
        
        Invoke-Wsl
        
        Should -Invoke wsl -Times 1
    }

    It '複数の引数を渡せる' {
        Mock wsl { param($args) return "OK" }
        
        Invoke-Wsl -d NixOS -u root -- sh -lc "whoami"
        
        Should -Invoke wsl -Times 1
    }
}

Describe 'Invoke-Diskpart' {
    BeforeAll {
        $script:diskpartCalled = $false
        $script:setContentCalled = $false
        Mock diskpart { 
            $script:diskpartCalled = $true
            return "diskpart output" 
        }
        # Set-ContentNoNewline をモックして実際のファイル書き込みをスキップ
        Mock Set-ContentNoNewline { 
            $script:setContentCalled = $true
        }
        Mock Remove-Item { }
        Mock New-TemporaryFile { 
            return [PSCustomObject]@{ FullName = "C:\temp\diskpart_test.txt" }
        }
    }

    It 'スクリプトファイルを作成して diskpart を実行する' {
        Invoke-Diskpart -ScriptContent "list disk"
        
        $script:diskpartCalled | Should -Be $true
    }

    It '一時ファイルにスクリプト内容を書き込む' {
        Invoke-Diskpart -ScriptContent "select disk 0"
        
        $script:setContentCalled | Should -Be $true
    }
}

Describe 'Get-ExternalCommand' {
    It 'コマンドが存在する場合はコマンド情報を返す' {
        Mock Get-Command { 
            return [PSCustomObject]@{ 
                Name = "powershell"
                Source = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
            } 
        }
        
        $result = Get-ExternalCommand -Name "powershell"
        
        $result | Should -Not -BeNullOrEmpty
        $result.Name | Should -Be "powershell"
    }

    It 'コマンドが存在しない場合は $null を返す' {
        Mock Get-Command { return $null } -ParameterFilter { 
            $Name -eq "nonexistent" 
        }
        
        $result = Get-ExternalCommand -Name "nonexistent"
        
        $result | Should -BeNullOrEmpty
    }
}

Describe 'Test-PathExists' {
    It 'パスが存在する場合は $true を返す' {
        Mock Test-Path { return $true }
        
        $result = Test-PathExists -Path "C:\Windows"
        
        $result | Should -Be $true
    }

    It 'パスが存在しない場合は $false を返す' {
        Mock Test-Path { return $false }
        
        $result = Test-PathExists -Path "C:\NonExistent"
        
        $result | Should -Be $false
    }
}

Describe 'Get-ProcessSafe' {
    It 'プロセスが存在する場合はプロセス情報を返す' {
        Mock Get-Process { 
            return [PSCustomObject]@{ 
                Name = "pwsh"
                Id = 1234
            } 
        }
        
        $result = Get-ProcessSafe -Name "pwsh"
        
        $result | Should -Not -BeNullOrEmpty
        $result.Name | Should -Be "pwsh"
    }

    It 'プロセスが存在しない場合は $null を返す' {
        Mock Get-Process { return $null } -ParameterFilter {
            $ErrorAction -eq 'SilentlyContinue'
        }
        
        $result = Get-ProcessSafe -Name "NonExistentProcess"
        
        $result | Should -BeNullOrEmpty
    }
}

Describe 'Stop-ProcessSafe' {
    It 'プロセスを停止する' {
        Mock Stop-Process { }
        
        Stop-ProcessSafe -Name "TestProcess"
        
        Should -Invoke Stop-Process -Times 1 -ParameterFilter {
            $Name -eq "TestProcess"
        }
    }

    It 'プロセスが存在しなくてもエラーにならない' {
        Mock Stop-Process { }
        
        { Stop-ProcessSafe -Name "NonExistent" } | Should -Not -Throw
    }
}

Describe 'Start-ProcessSafe' {
    It 'プロセスを起動する' {
        Mock Start-Process { return [PSCustomObject]@{ Id = 5678 } }
        
        Start-ProcessSafe -FilePath "C:\test\app.exe"
        
        Should -Invoke Start-Process -Times 1 -ParameterFilter {
            $FilePath -eq "C:\test\app.exe"
        }
    }
}

Describe 'Copy-FileSafe' {
    It 'ファイルをコピーする' {
        Mock Copy-Item { }
        
        Copy-FileSafe -Source "C:\source.txt" -Destination "C:\dest.txt"
        
        Should -Invoke Copy-Item -Times 1 -ParameterFilter {
            $LiteralPath -eq "C:\source.txt" -and
            $Destination -eq "C:\dest.txt"
        }
    }

    It '-Force オプションを渡せる' {
        Mock Copy-Item { }
        
        Copy-FileSafe -Source "C:\source.txt" -Destination "C:\dest.txt" -Force
        
        Should -Invoke Copy-Item -Times 1 -ParameterFilter {
            $Force -eq $true
        }
    }
}

Describe 'Get-FileContentSafe' {
    It 'ファイルの内容を取得する' {
        Mock Get-Content { return "file content" }
        
        $result = Get-FileContentSafe -Path "C:\test.txt"
        
        $result | Should -Be "file content"
        Should -Invoke Get-Content -Times 1 -ParameterFilter {
            $LiteralPath -eq "C:\test.txt" -and
            $Raw -eq $true
        }
    }
}

Describe 'Get-JsonContent' {
    It 'JSON ファイルをパースして返す' {
        Mock Get-Content { return '{"key": "value"}' }
        
        $result = Get-JsonContent -Path "C:\test.json"
        
        $result.key | Should -Be "value"
    }

    It '配列を含む JSON をパースできる' {
        Mock Get-Content { return '{"items": [1, 2, 3]}' }
        
        $result = Get-JsonContent -Path "C:\test.json"
        
        $result.items | Should -HaveCount 3
    }
}

Describe 'New-DirectorySafe' {
    It 'ディレクトリを作成する' {
        Mock New-Item { return [PSCustomObject]@{ FullName = "C:\newdir" } }
        
        New-DirectorySafe -Path "C:\newdir"
        
        Should -Invoke New-Item -Times 1 -ParameterFilter {
            $ItemType -eq "Directory" -and
            $Path -eq "C:\newdir" -and
            $Force -eq $true
        }
    }
}

Describe 'Get-ChildItemSafe' {
    It 'ディレクトリ内のファイルを取得する' {
        Mock Get-ChildItem { 
            return @(
                [PSCustomObject]@{ Name = "file1.txt" },
                [PSCustomObject]@{ Name = "file2.txt" }
            )
        }
        
        $result = Get-ChildItemSafe -Path "C:\test"
        
        $result | Should -HaveCount 2
    }

    It 'フィルターを適用できる' {
        Mock Get-ChildItem { 
            return @([PSCustomObject]@{ Name = "file.ps1" })
        }
        
        Get-ChildItemSafe -Path "C:\test" -Filter "*.ps1"
        
        Should -Invoke Get-ChildItem -Times 1 -ParameterFilter {
            $Filter -eq "*.ps1"
        }
    }

    It '再帰的に検索できる' {
        Mock Get-ChildItem { return @() }
        
        Get-ChildItemSafe -Path "C:\test" -Recurse
        
        Should -Invoke Get-ChildItem -Times 1 -ParameterFilter {
            $Recurse -eq $true
        }
    }

    It 'ディレクトリのみを取得できる' {
        Mock Get-ChildItem { return @() }
        
        Get-ChildItemSafe -Path "C:\test" -Directory
        
        Should -Invoke Get-ChildItem -Times 1 -ParameterFilter {
            $Directory -eq $true
        }
    }
}

Describe 'Get-RegistryValue' {
    It 'レジストリ値を取得する' {
        Mock Get-ItemProperty { 
            return [PSCustomObject]@{ 
                TestValue = "TestData"
            } 
        }
        
        $result = Get-RegistryValue -Path "HKCU:\Test"
        
        $result.TestValue | Should -Be "TestData"
    }

    It 'パスが存在しない場合は $null を返す' {
        Mock Get-ItemProperty { return $null }
        
        $result = Get-RegistryValue -Path "HKCU:\NonExistent"
        
        $result | Should -BeNullOrEmpty
    }
}

Describe 'Get-RegistryChildItem' {
    It 'レジストリの子キーを取得する' {
        Mock Get-ChildItem { 
            return @(
                [PSCustomObject]@{ Name = "Key1" },
                [PSCustomObject]@{ Name = "Key2" }
            )
        }
        
        $result = Get-RegistryChildItem -Path "HKCU:\Test"
        
        $result | Should -HaveCount 2
    }

    It 'パスが存在しない場合は空を返す' {
        Mock Get-ChildItem { return @() }
        
        $result = Get-RegistryChildItem -Path "HKCU:\NonExistent"
        
        $result | Should -HaveCount 0
    }
}

Describe 'Invoke-WebRequestSafe' {
    It 'ファイルをダウンロードする' {
        Mock Invoke-WebRequest { }
        
        Invoke-WebRequestSafe -Uri "https://example.com/file.zip" -OutFile "C:\temp\file.zip"
        
        Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
            $Uri -eq "https://example.com/file.zip" -and
            $OutFile -eq "C:\temp\file.zip" -and
            $UseBasicParsing -eq $true
        }
    }
}

Describe 'Invoke-RestMethodSafe' {
    It 'REST API を呼び出す' {
        Mock Invoke-RestMethod { 
            return [PSCustomObject]@{ result = "success" } 
        }
        
        $result = Invoke-RestMethodSafe -Uri "https://api.example.com/data"
        
        $result.result | Should -Be "success"
    }

    It 'ヘッダーを渡せる' {
        Mock Invoke-RestMethod { return @{} }
        
        Invoke-RestMethodSafe -Uri "https://api.example.com" -Headers @{ "Authorization" = "Bearer token" }
        
        Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter {
            $Headers["Authorization"] -eq "Bearer token"
        }
    }
}

Describe 'Start-SleepSafe' {
    It '指定秒数スリープする' {
        Mock Start-Sleep { }
        
        Start-SleepSafe -Seconds 5
        
        Should -Invoke Start-Sleep -Times 1 -ParameterFilter {
            $Seconds -eq 5
        }
    }
}
