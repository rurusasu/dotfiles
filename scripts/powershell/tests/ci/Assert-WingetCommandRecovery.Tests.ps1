BeforeAll {
    $script:probe = Join-Path $PSScriptRoot '../../ci/Assert-WingetCommandRecovery.ps1'
    $script:projectRoot = (Resolve-Path -LiteralPath "$PSScriptRoot/../../../..").Path
}

Describe 'WinGet command recovery manifest contract' {
    It 'should default to five retained portable packages with executable verification and no explicit paths' {
        $tokens = $null
        $parseErrors = $null
        $probeAst = [System.Management.Automation.Language.Parser]::ParseFile($script:probe, [ref]$tokens, [ref]$parseErrors)
        $parseErrors | Should -BeNullOrEmpty
        $packageParameter = @($probeAst.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'PackageId' })
        $packageParameter | Should -HaveCount 1
        $defaultPackageIds = @($packageParameter[0].DefaultValue.SafeGetValue())
        $expectedCommands = @{
            'junegunn.fzf'            = 'fzf'
            'x-motemen.ghq'           = 'ghq'
            'jqlang.jq'               = 'jq'
            'JesseDuffield.lazygit'   = 'lazygit'
            'BurntSushi.ripgrep.MSVC' = 'rg'
        }
        $defaultPackageIds | Should -HaveCount 5
        (($defaultPackageIds | Sort-Object) -join '|') | Should -Be (($expectedCommands.Keys | Sort-Object) -join '|')

        $manifest = Get-Content -LiteralPath (Join-Path $script:projectRoot 'windows/winget/packages.json') -Raw | ConvertFrom-Json
        foreach ($id in $defaultPackageIds) {
            $entries = @($manifest.Sources.Packages | Where-Object { $_.PackageIdentifier -eq $id })
            $entries | Should -HaveCount 1
            $entry = $entries[0]
            $entry.PSObject.Properties.Name | Should -Contain 'verifyCommand'
            $entry.verifyCommand.command | Should -Be $expectedCommands[$id]
            $entry.verifyCommand.args | Should -Be @('--version')
            $entry.verifyCommand.PSObject.Properties.Name | Should -Not -Contain 'type'
            $entry.PSObject.Properties.Name | Should -Not -Contain 'pathEntries'
        }
    }
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

    It 'should fail when a required package is missing from the manifest instead of passing zero checks' {
        { & $script:probe -ManifestPath $script:manifestPath -PackageId 'Missing.Tool' } | Should -Throw '*Missing.Tool*'
        $env:PATH | Should -Be $script:oldPath
    }

    It 'should fail when a required package has no verifier and restore the caller PATH' {
        $script:manifest.Sources[0].Packages[0].Remove('verifyCommand')
        $script:manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:manifestPath

        { & $script:probe -ManifestPath $script:manifestPath -PackageId 'Recovery.Tool' } | Should -Throw '*has no verification*Recovery.Tool*'
        $env:PATH | Should -Be $script:oldPath
    }

    It 'should fail when the required installed executable is missing and restore the caller PATH' {
        Remove-Item -LiteralPath (Join-Path $script:packageDirectory 'recovery-tool.exe')

        { & $script:probe -ManifestPath $script:manifestPath -PackageId 'Recovery.Tool' } | Should -Throw '*executable is missing or ambiguous*Recovery.Tool*'
        $env:PATH | Should -Be $script:oldPath
    }

    It 'should fail when multiple installed executables make recovery ambiguous and restore the caller PATH' {
        $otherDirectory = Join-Path (Split-Path -Parent $script:packageDirectory) 'other-bin'
        New-Item -ItemType Directory -Path $otherDirectory -Force | Out-Null
        Copy-Item -LiteralPath $env:ComSpec -Destination (Join-Path $otherDirectory 'recovery-tool.exe')

        { & $script:probe -ManifestPath $script:manifestPath -PackageId 'Recovery.Tool' } | Should -Throw '*executable is missing or ambiguous*Recovery.Tool*'
        $env:PATH | Should -Be $script:oldPath
    }

    It 'should reject an empty package selection instead of passing zero checks' {
        { & $script:probe -ManifestPath $script:manifestPath -PackageId @() } | Should -Throw
        $env:PATH | Should -Be $script:oldPath
    }

    It 'should fail when the real package command returns a nonzero exit code' {
        $script:manifest.Sources[0].Packages[0].verifyCommand.args = @('/d', '/c', 'exit 7')
        $script:manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:manifestPath

        { & $script:probe -ManifestPath $script:manifestPath -PackageId 'Recovery.Tool' } | Should -Throw '*verification*Recovery.Tool*'
        $env:PATH | Should -Be $script:oldPath
    }
}
