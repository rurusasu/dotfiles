Describe 'Legacy administrator workflow fixture' {
    BeforeAll {
        $script:repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
        $workflow = Get-Content -LiteralPath (Join-Path $script:repositoryRoot '.github/workflows/ci-nix.yml') -Raw -Encoding UTF8
        $script:windowsJob = [regex]::Match($workflow, '(?ms)^  windows:\s*\r?\n.*?(?=^  [a-zA-Z0-9_-]+:|\z)').Value
        $step = [regex]::Match($script:windowsJob, '(?ms)^      - name: Install and verify .*?\r?\n.*?        run: \|\r?\n(?<body>.*?)(?=^      - name:|\z)').Groups['body'].Value
        $step = [regex]::Replace($step, '(?m)^          ', '')
        $tokens = $null
        $errors = $null
        $script:stepAst = [Management.Automation.Language.Parser]::ParseInput($step, [ref]$tokens, [ref]$errors)
        if ($errors.Count) { throw ($errors -join "`n") }
        $script:manifestPath = Join-Path $script:repositoryRoot 'windows/winget/packages.json'
    }

    It 'should prepare real legacy adapter code and admin packages outside the production GUI manifest' {
        $originalWorkspace = $env:GITHUB_WORKSPACE
        $originalRunnerTemp = $env:RUNNER_TEMP
        $env:GITHUB_WORKSPACE = $script:repositoryRoot
        $env:RUNNER_TEMP = $TestDrive
        $productionManifest = [IO.File]::ReadAllText($script:manifestPath)
        try {
            $preparation = [regex]::Match($script:stepAst.Extent.Text, '(?ms)^\$legacyRoot = .*?(?=^\$options = )')
            $preparation.Success | Should -BeTrue -Because 'the legacy adapter needs an isolated repository and manifest'
            . ([scriptblock]::Create($preparation.Value))
            $adminAssignment = $script:stepAst.Find({ param($node)
                    $node -is [Management.Automation.Language.AssignmentStatementAst] -and
                    $node.Left.VariablePath.UserPath -eq 'adminScript'
                }, $true)
            . ([scriptblock]::Create($adminAssignment.Extent.Text))

            $adminScript | Should -Be (Join-Path $legacyRoot 'scripts/powershell/install.admin.ps1')
            [IO.Path]::GetFullPath($legacyRoot).StartsWith([IO.Path]::GetFullPath($TestDrive) + [IO.Path]::DirectorySeparatorChar) | Should -BeTrue
            [IO.File]::ReadAllText($adminScript) | Should -Be ([IO.File]::ReadAllText((Join-Path $script:repositoryRoot 'scripts/powershell/install.admin.ps1')))
            foreach ($relativePath in @('lib/SetupHandler.ps1', 'lib/Invoke-ExternalCommand.ps1', 'handlers/Handler.WingetAdmin.ps1', 'handlers/Handler.Winget.ps1')) {
                $copied = Join-Path $legacyRoot ('scripts/powershell/' + $relativePath)
                [IO.File]::ReadAllText($copied) | Should -Be ([IO.File]::ReadAllText((Join-Path $script:repositoryRoot ('scripts/powershell/' + $relativePath))))
            }
            $manifest = Get-Content -LiteralPath (Join-Path $legacyRoot 'windows/winget/packages.json') -Raw | ConvertFrom-Json
            @($manifest.Sources).Count | Should -Be 1
            $manifest.Sources[0].SourceDetails.Name | Should -Be 'winget'
            $packages = @($manifest.Sources[0].Packages)
            @($packages | ForEach-Object PackageIdentifier | Sort-Object) | Should -Be @('AutoHotkey.AutoHotkey', 'Microsoft.VisualStudio.2022.BuildTools')
            foreach ($package in $packages) {
                $package.requiresAdmin | Should -BeTrue
                $package.installTimeoutSeconds | Should -Be 3600
            }
            $packages[0].installArgs | Should -Be @('--scope', 'machine')
            $packages[1].installArgs | Should -Be @('--override', '--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --passive --wait --norestart')
            [IO.File]::ReadAllText($script:manifestPath) | Should -Be $productionManifest
            $productionManifest | Should -Not -Match 'AutoHotkey.AutoHotkey|Microsoft.VisualStudio.2022.BuildTools'
        }
        finally {
            $env:GITHUB_WORKSPACE = $originalWorkspace
            $env:RUNNER_TEMP = $originalRunnerTemp
        }
    }

    It 'should give each runtime its own admin artifact and identify the fixture coverage' {
        $script:windowsJob | Should -Match 'layer=windows-legacy-admin'
        $script:windowsJob | Should -Match 'bootstrap-windows-admin-\$\{\{ matrix.executable \}\}-\$\{\{ github.run_id \}\}-\$\{\{ github.run_attempt \}\}'
        $script:windowsJob | Should -Match 'ref: \$\{\{ env.TESTED_SHA \}\}'
    }
}
