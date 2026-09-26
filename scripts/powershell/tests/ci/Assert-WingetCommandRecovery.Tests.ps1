BeforeAll {
    $script:probe = Join-Path $PSScriptRoot '../../ci/Assert-WingetCommandRecovery.ps1'
}

Describe 'Installed WinGet command recovery acceptance' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    BeforeEach {
        $script:oldLocalAppData = $env:LOCALAPPDATA
        $script:oldProgramFiles = $env:ProgramFiles
        $script:oldPath = $env:PATH
        $env:LOCALAPPDATA = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $env:ProgramFiles = Join-Path $TestDrive 'machine-packages'
        $script:packageDirectory = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\Recovery.Tool_test\bin'
        New-Item -ItemType Directory -Path $script:packageDirectory -Force | Out-Null
        Copy-Item -LiteralPath $env:ComSpec -Destination (Join-Path $script:packageDirectory 'recovery-tool.exe')
        $script:manifestPath = Join-Path $TestDrive 'manifest.json'
        $script:manifest = @{
            Sources = @(@{ Packages = @(@{
                            PackageIdentifier = 'Recovery.Tool'
                            verifyCommand     = @{ command = 'recovery-tool'; args = @('/d', '/c', 'exit 0') }
                        }) 
                })
        }
        $script:manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:manifestPath
    }

    AfterEach {
        $env:LOCALAPPDATA = $script:oldLocalAppData
        $env:ProgramFiles = $script:oldProgramFiles
        $env:PATH = $script:oldPath
    }

    It 'should launch the installed package without inherited package paths and restore the caller PATH' {
        & $script:probe -ManifestPath $script:manifestPath -PackageId 'Recovery.Tool'

        $env:PATH | Should -Be $script:oldPath
    }

    It 'should fail when a required package was not installed instead of passing zero checks' {
        { & $script:probe -ManifestPath $script:manifestPath -PackageId 'Missing.Tool' } | Should -Throw '*Missing.Tool*'
        $env:PATH | Should -Be $script:oldPath
    }

    It 'should fail when the real package command returns a nonzero exit code' {
        $script:manifest.Sources[0].Packages[0].verifyCommand.args = @('/d', '/c', 'exit 7')
        $script:manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:manifestPath

        { & $script:probe -ManifestPath $script:manifestPath -PackageId 'Recovery.Tool' } | Should -Throw '*verification*Recovery.Tool*'
        $env:PATH | Should -Be $script:oldPath
    }
}
