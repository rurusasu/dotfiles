BeforeAll {
    $script:repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
    if (-not ('SetupContext' -as [type])) {
        . (Join-Path $script:repositoryRoot 'scripts/powershell/lib/SetupHandler.ps1')
    }
    . (Join-Path $script:repositoryRoot 'scripts/powershell/lib/Invoke-ExternalCommand.ps1')
    . (Join-Path $script:repositoryRoot 'scripts/powershell/ci/Initialize-WindowsInstallerRuntime.ps1')
}

Describe 'Windows installer runtime preparation' {
    BeforeEach {
        $script:preparationRepository = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:preparationTemporaryRoot = Join-Path $TestDrive 'staging'
        $manifestDirectory = Join-Path $script:preparationRepository 'windows/winget'
        New-Item -ItemType Directory -Path $manifestDirectory -Force | Out-Null
        $script:preparationManifestPath = Join-Path $manifestDirectory 'packages.json'
        Copy-Item -LiteralPath (Join-Path $script:repositoryRoot 'windows/winget/packages.json') -Destination $script:preparationManifestPath
        $script:preparationOriginal = [IO.File]::ReadAllText($script:preparationManifestPath)
        $script:runtimeHandler = [pscustomobject]@{
            Available = $true; Succeeded = $true; Calls = 0
            Manifest = $null; Options = $null; Root = $null
        }
        $script:runtimeHandler | Add-Member -MemberType ScriptMethod -Name CanApply -Value {
            param($Context)
            return $this.Available
        }
        $script:runtimeHandler | Add-Member -MemberType ScriptMethod -Name Apply -Value {
            param($Context)
            $this.Calls++
            $this.Root = $Context.DotfilesPath
            $this.Manifest = Get-Content -LiteralPath (Join-Path $Context.DotfilesPath 'windows/winget/packages.json') -Raw | ConvertFrom-Json
            $this.Options = $Context.Options.Clone()
            return [pscustomobject]@{ Success = $this.Succeeded; Message = 'fixture result' }
        }
    }

    It 'should prepare only the complete declared PowerShell package through the normal handler' {
        Initialize-WindowsInstallerRuntime -RepositoryRoot $script:preparationRepository -TemporaryRoot $script:preparationTemporaryRoot -RuntimeHandler $script:runtimeHandler
        $script:runtimeHandler.Calls | Should -Be 1
        @($script:runtimeHandler.Manifest.Sources).Count | Should -Be 1
        $source = $script:runtimeHandler.Manifest.Sources[0]
        $source.SourceDetails.Name | Should -Be 'winget'
        @($source.Packages).Count | Should -Be 1
        $source.Packages[0].PackageIdentifier | Should -Be 'Microsoft.PowerShell'
        $original = $script:preparationOriginal | ConvertFrom-Json
        $originalPackage = $original.Sources.Packages | Where-Object PackageIdentifier -EQ 'Microsoft.PowerShell'
        ($source.Packages[0] | ConvertTo-Json -Depth 100 -Compress) | Should -BeExactly ($originalPackage | ConvertTo-Json -Depth 100 -Compress)
        $script:runtimeHandler.Options['WingetProcessOnlyPath'] | Should -BeTrue
        $script:runtimeHandler.Options['SkipRetiredPackageCleanup'] | Should -BeTrue
        $script:runtimeHandler.Options['WingetRequireSuccessfulUpdate'] | Should -BeTrue
        $script:runtimeHandler.Options.ContainsKey('WingetVerifyCommandOnly') | Should -BeFalse
        [IO.File]::ReadAllText($script:preparationManifestPath) | Should -BeExactly $script:preparationOriginal
        Test-Path -LiteralPath $script:runtimeHandler.Root | Should -BeFalse
    }

    It 'should fail when the normal handler cannot apply and remove its staging directory' {
        $script:runtimeHandler.Available = $false
        { Initialize-WindowsInstallerRuntime -RepositoryRoot $script:preparationRepository -TemporaryRoot $script:preparationTemporaryRoot -RuntimeHandler $script:runtimeHandler } | Should -Throw '*WinGet is unavailable*'
        $script:runtimeHandler.Calls | Should -Be 0
        @(Get-ChildItem -LiteralPath $script:preparationTemporaryRoot -Force).Count | Should -Be 0
    }

    It 'should reject a failed runtime install and preserve the original manifest' {
        $script:runtimeHandler.Succeeded = $false
        { Initialize-WindowsInstallerRuntime -RepositoryRoot $script:preparationRepository -TemporaryRoot $script:preparationTemporaryRoot -RuntimeHandler $script:runtimeHandler } | Should -Throw '*PowerShell runtime preparation failed*'
        [IO.File]::ReadAllText($script:preparationManifestPath) | Should -BeExactly $script:preparationOriginal
        Test-Path -LiteralPath $script:runtimeHandler.Root | Should -BeFalse
    }

    It 'should reject an ambiguous PowerShell declaration before installing anything' {
        $manifest = $script:preparationOriginal | ConvertFrom-Json
        $manifest.Sources[0].Packages += @($manifest.Sources[0].Packages | Where-Object PackageIdentifier -EQ 'Microsoft.PowerShell')
        [IO.File]::WriteAllText($script:preparationManifestPath, ($manifest | ConvertTo-Json -Depth 100))
        { Initialize-WindowsInstallerRuntime -RepositoryRoot $script:preparationRepository -TemporaryRoot $script:preparationTemporaryRoot -RuntimeHandler $script:runtimeHandler } | Should -Throw '*exactly one Microsoft.PowerShell*'
        $script:runtimeHandler.Calls | Should -Be 0
    }

    It 'should resolve the default repository during a real Windows PowerShell File invocation' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        $sourcePath = Join-Path $script:repositoryRoot 'scripts/powershell/ci/Initialize-WindowsInstallerRuntime.ps1'
        $tokens = $null
        $parseErrors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
        $prepare = $ast.Find({ param($node)
                $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Initialize-WindowsInstallerRuntime'
            }, $true)
        # Keep the shipped parameter defaults, root resolution, and entrypoint.
        # Replace only the package operation so the real child cannot install.
        $replacement = 'function Initialize-WindowsInstallerRuntime { param([string]$RepositoryRoot) Write-Output ("ENTRYPOINT_ROOT=" + $RepositoryRoot) }'
        $source = [IO.File]::ReadAllText($sourcePath)
        $fixtureSource = $source.Remove($prepare.Extent.StartOffset, $prepare.Extent.EndOffset - $prepare.Extent.StartOffset).Insert($prepare.Extent.StartOffset, $replacement)
        $fixtureRepository = Join-Path $TestDrive 'entrypoint root with spaces'
        $fixturePath = Join-Path $fixtureRepository 'scripts/powershell/ci/Initialize-WindowsInstallerRuntime.ps1'
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $fixturePath))
        [IO.File]::WriteAllText($fixturePath, $fixtureSource, [Text.UTF8Encoding]::new($false))
        $nativePowerShell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $output = @(Invoke-ExternalCommandWithTimeout -Command $nativePowerShell -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-OutputFormat', 'Text', '-File', $fixturePath) -TimeoutSeconds 30)
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
        $output | Should -Contain ('ENTRYPOINT_ROOT=' + [IO.Path]::GetFullPath($fixtureRepository))
    }
}
