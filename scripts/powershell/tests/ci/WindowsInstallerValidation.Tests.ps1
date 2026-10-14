Describe 'Windows GUI installer validation' {
    BeforeAll {
        $script:repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
        $installerPath = Join-Path $PSScriptRoot '../../ci/Invoke-WindowsInstallerE2E.ps1'
        $script:installerE2E = Get-Content -LiteralPath $installerPath -Raw -Encoding UTF8
        $tokens = $null
        $parseErrors = $null
        $outerAst = [Management.Automation.Language.Parser]::ParseFile($installerPath, [ref]$tokens, [ref]$parseErrors)
        $embedded = $outerAst.Find({ param($node)
                $node -is [Management.Automation.Language.StringConstantExpressionAst] -and
                $node.StringConstantType -eq 'SingleQuotedHereString'
            }, $true)
        $innerAst = [Management.Automation.Language.Parser]::ParseInput($embedded.Value, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count) { throw ($parseErrors -join "`n") }
        $validationFunction = $innerAst.Find({ param($node)
                $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Invoke-WindowsE2EValidation'
            }, $true)
        . ([scriptblock]::Create($validationFunction.Extent.Text))
        $script:validationCalls = @($innerAst.FindAll({ param($node)
                    $node -is [Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Invoke-WindowsE2EValidation'
                }, $true))
        $script:guiIds = @(
            'wez.wezterm',
            'AgileBits.1Password', 'Discord.Discord', 'StablyAI.Orca', 'Microsoft.PowerToys',
            'Microsoft.WindowsTerminal', '9PLM9XGG6VKS', '9PCFS5B6T72H', 'Microsoft.PowerShell', 'Task.Task', 'twpayne.chezmoi', 'TheBrowserCompany.Dia'
        )
        $script:validOutput = (@(
                'Using PowerShell 7'
                '[INFO] Process PATH normalized: removed 1000 missing directories and omitted 0 over-limit entries; final length 1000/8191.'
                'Total: 1 | Success: 1 | Failure: 0'
                'User Phase Complete!'
                "[Winget] CI_VERIFICATION_INVENTORY: $($script:guiIds -join '|')"
            ) + @($script:guiIds | ForEach-Object { "[Winget] $([char]0x2713) $_" })) -join "`n"
        function Invoke-ShippedValidation {
            param([string]$Name)
            $call = @($script:validationCalls | Where-Object { $_.CommandElements[2].Value -eq $Name })
            if ($call.Count -ne 1) { throw "Expected exactly one shipped validation: $Name" }
            & ([scriptblock]::Create($call[0].Extent.Text))
        }
    }

    BeforeEach {
        $script:originalWorkspace = $env:GITHUB_WORKSPACE
        $env:GITHUB_WORKSPACE = $script:repositoryRoot
        $script:validationErrors = [Collections.Generic.List[string]]::new()
        $script:out = $script:validOutput
        $script:exitCode = 0
        $script:isWindowsPowerShell = $false
        Set-StrictMode -Version Latest
    }

    AfterEach {
        $env:GITHUB_WORKSPACE = $script:originalWorkspace
    }

    It 'should accept a completed GUI install without npm pnpm or retired-package evidence' {
        Invoke-ShippedValidation -Name 'installer evidence'
        $script:validationErrors | Should -BeNullOrEmpty
    }

    It 'should reject npm or pnpm activity in an otherwise successful GUI install' -TestCases @(
        @{ Marker = '[Npm] installed a global package' }
        @{ Marker = '[Pnpm] bootstrapped pnpm' }
    ) {
        param($Marker)
        $script:out += "`n$Marker"
        Invoke-ShippedValidation -Name 'installer evidence'
        ($script:validationErrors -join ' | ') | Should -Match 'npm/pnpm activity'
    }

    It 'should reject a failed installer even with complete GUI evidence' {
        $script:exitCode = 7
        Invoke-ShippedValidation -Name 'installer evidence'
        ($script:validationErrors -join ' | ') | Should -Match 'exited with code 7'
    }

    It 'should reject missing normalization evidence or a mismatched launcher runtime' -TestCases @(
        @{ Fault = 'path' }
        @{ Fault = 'runtime' }
    ) {
        param($Fault)
        if ($Fault -eq 'path') {
            $script:out = ($script:out -split "`n" | Where-Object { $_ -notmatch 'Process PATH normalized:' }) -join "`n"
        }
        else { $script:isWindowsPowerShell = $true }
        Invoke-ShippedValidation -Name 'installer evidence'
        $script:validationErrors.Count | Should -Be 1
        ($script:validationErrors -join ' | ') | Should -Match 'stale PATH|forced Windows PowerShell'
    }

    It 'should verify every GUI package including direct Dia and verify-only Orca and Store apps' {
        Invoke-ShippedValidation -Name 'WinGet package inventory'
        $script:validationErrors | Should -BeNullOrEmpty
    }

    It 'should reject a direct installer omitted from inventory and success evidence' {
        $script:out = ($script:out -split "`n" | Where-Object { $_ -ne "[Winget] $([char]0x2713) TheBrowserCompany.Dia" }) -join "`n"
        $script:out = $script:out -replace '\|TheBrowserCompany\.Dia', ''
        Invoke-ShippedValidation -Name 'WinGet package inventory'
        ($script:validationErrors -join ' | ') | Should -Match 'missing from the verification inventory:.*TheBrowserCompany\.Dia'
    }

    It 'should reject missing GUI success evidence' -TestCases @(
        @{ PackageId = 'StablyAI.Orca' }
        @{ PackageId = '9PLM9XGG6VKS' }
        @{ PackageId = '9PCFS5B6T72H' }
        @{ PackageId = 'AgileBits.1Password' }
        @{ PackageId = 'TheBrowserCompany.Dia' }
    ) {
        param($PackageId)
        $script:out = ($script:out -split "`n" | Where-Object { $_ -ne "[Winget] $([char]0x2713) $PackageId" }) -join "`n"
        Invoke-ShippedValidation -Name 'WinGet package inventory'
        ($script:validationErrors -join ' | ') | Should -Match ([regex]::Escape($PackageId))
    }

    It 'should reject a missing inventory even if all success markers exist' {
        $script:out = ($script:out -split "`n" | Where-Object { $_ -notmatch 'CI_VERIFICATION_INVENTORY:' }) -join "`n"
        Invoke-ShippedValidation -Name 'WinGet package inventory'
        ($script:validationErrors -join ' | ') | Should -Match 'inventory'
    }

    It 'should reject multiple inventory records rather than trust the first record' {
        $script:out += "`n[Winget] CI_VERIFICATION_INVENTORY: Google.Chrome"
        Invoke-ShippedValidation -Name 'WinGet package inventory'
        ($script:validationErrors -join ' | ') | Should -Match 'exactly one WinGet verification inventory'
    }

    It 'should reject partial extra or duplicate inventory IDs' -TestCases @(
        @{ Inventory = 'Microsoft.PowerShell|Microsoft.PowerToys' }
        @{ Inventory = 'extra' }
        @{ Inventory = 'duplicate' }
    ) {
        param($Inventory)
        if ($Inventory -eq 'extra') { $Inventory = ($script:guiIds + @('OpenAI.Codex.CLI')) -join '|' }
        if ($Inventory -eq 'duplicate') { $Inventory = ($script:guiIds + @('Microsoft.PowerToys')) -join '|' }
        $script:out = $script:out -replace '(?m)(CI_VERIFICATION_INVENTORY: ).*$', ('$1' + $Inventory)
        Invoke-ShippedValidation -Name 'WinGet package inventory'
        ($script:validationErrors -join ' | ') | Should -Match 'missing from the verification inventory|outside the Windows E2E scope|duplicate package IDs'
    }

    It 'should aggregate installer and inventory failures independently' {
        $script:exitCode = 9
        $script:out = $script:out -replace '(?m)^\[Winget\].*9PLM9XGG6VKS.*$', ''
        Invoke-ShippedValidation -Name 'installer evidence'
        Invoke-ShippedValidation -Name 'WinGet package inventory'
        $script:validationErrors.Count | Should -Be 2
        $script:validationErrors[0] | Should -Match '^installer evidence:'
        $script:validationErrors[1] | Should -Match '^WinGet package inventory:'
        $script:installerE2E | Should -Match '(?s)if\s*\(\$validationErrors.Count\s*-gt\s*0\).*?throw \$failureSummary'
    }

    It 'should retain process PATH normalization evidence without requiring persisted repairs' {
        $script:installerE2E | Should -Match 'oversizedUserPathEntries = 1\.\.1000'
        $script:installerE2E | Should -Match 'Process PATH normalized: removed'
        $script:installerE2E | Should -Match 'Post-install PATH exceeds the cmd\.exe command environment limit'
        $script:installerE2E | Should -Not -Match 'User PATH repaired|remainingStaleUserPathEntries|runnerPnpmDirectories|PNPM_HOME'
        $script:installerE2E | Should -Match 'SetValue\(''PATH'', \$Snapshot.Value, \$Snapshot.Kind\)'
        $script:installerE2E | Should -Match 'DeleteValue\(''PATH'', \$false\)'
    }

    It 'should avoid self-update manifest mutations CLI probes and retired-package seed or removal' {
        $script:installerE2E | Should -Not -Match 'Add-Member|Set-Content|Invoke-Npm|Invoke-Pnpm|Assert-WingetCommandRecovery|node --version|op\.exe|herdr|@openai/codex|Codex CLI|9NT1R1C2HH7J|RETIRED_PACKAGE_CLEANUP'
        @($script:validationCalls | ForEach-Object { $_.CommandElements[2].Value }) | Should -Be @(
            'installer evidence', 'WinGet package inventory', 'WezTerm install PATH and version'
        )
    }

    It 'should preserve runtime selection and installer failure evidence' {
        $script:installerE2E | Should -Match 'install\.cmd -NoPause -UserPhaseOnly(?!\s+-WingetVerifyCommandOnly)'
        $script:installerE2E | Should -Match 'Using Windows PowerShell'
        $script:installerE2E | Should -Match 'PowerShell 7 installer E2E unexpectedly used the Windows PowerShell 5\.1 path'
        $script:installerE2E | Should -Match 'Falling back to Windows PowerShell'
        $script:installerE2E | Should -Match '(?s)Get-Command -Name ''pwsh.exe'' -CommandType Application -ErrorAction Stop\s*\|\s*Select-Object -First 1'
    }

    It 'should preserve the installer process exit code and full output through the success assertion' {
        $script:installerE2E | Should -Match '(?s)\$output = & cmd\.exe /d /c install\.cmd -NoPause -UserPhaseOnly.*?\$exitCode = \$LASTEXITCODE'
        $script:installerE2E | Should -Match '(?s)Assert-WindowsInstallerSuccess `\s+-Output \$out `\s+-ExitCode \$exitCode'
        $script:installerE2E | Should -Match 'Write-Host \$failureSummary -ForegroundColor Red'
    }
}

Describe 'Windows direct installer manifest validation' {
    BeforeAll {
        $repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
        $workflow = Get-Content -LiteralPath (Join-Path $repositoryRoot '.github/workflows/ci-nix.yml') -Raw
        $filter = [regex]::Match($workflow, '(?ms)^\s+jq -e ''\r?\n(?<Filter>.*?)^\s+'' windows/winget/packages\.json')
        if (-not $filter.Success) { throw 'Could not extract the shipped Windows manifest jq filter' }
        $script:manifestFilterPath = Join-Path $TestDrive 'windows-manifest.jq'
        $script:manifestFixturePath = Join-Path $TestDrive 'windows-manifest.json'
        [IO.File]::WriteAllText($script:manifestFilterPath, $filter.Groups['Filter'].Value, [Text.UTF8Encoding]::new($false))
        $script:jqCommand = Get-Command jq -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        $script:wslCommand = $null
        $script:wslJqPath = $null
        if (-not $script:jqCommand) {
            $script:wslCommand = Get-Command wsl.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($script:wslCommand) {
                $script:wslJqPath = (& $script:wslCommand.Source --exec sh -lc 'command -v jq' 2>$null | Out-String).Trim()
                if ($LASTEXITCODE -ne 0) { $script:wslJqPath = $null }
            }
        }
        $script:jqAvailable = $null -ne $script:jqCommand -or -not [string]::IsNullOrWhiteSpace($script:wslJqPath)
        function Invoke-ShippedManifestValidation {
            param($Manifest)
            [IO.File]::WriteAllText($script:manifestFixturePath, ($Manifest | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
            if ($script:jqCommand) {
                & $script:jqCommand.Source -e -f $script:manifestFilterPath $script:manifestFixturePath *> $null
            }
            else {
                $filterPath = (& $script:wslCommand.Source --exec wslpath -a -u $script:manifestFilterPath | Out-String).Trim()
                if ($LASTEXITCODE -ne 0) { throw 'Could not convert the jq filter path for optional WSL validation' }
                $fixturePath = (& $script:wslCommand.Source --exec wslpath -a -u $script:manifestFixturePath | Out-String).Trim()
                if ($LASTEXITCODE -ne 0) { throw 'Could not convert the manifest path for optional WSL validation' }
                & $script:wslCommand.Source --exec $script:wslJqPath -e -f $filterPath $fixturePath *> $null
            }
            return $LASTEXITCODE
        }
    }

    BeforeEach {
        $script:directManifest = @{
            Sources = @(@{
                    SourceDetails = @{
                        Name = 'direct'; Identifier = 'Dotfiles.DirectInstallers'
                        Argument = 'https://releases.diabrowser.com'; Type = 'Dotfiles.DirectInstaller'
                    }
                    Packages = @(@{
                            PackageIdentifier = 'TheBrowserCompany.Dia'
                            directInstaller = @{
                                type = 'appx'; name = 'TheBrowserCompany.Dia'
                                packageFamilyName = 'TheBrowserCompany.Dia_ttt1ap7aakyb4'
                                version = '1.1.0.6'; architecture = 'x64'; executable = 'Dia.exe'
                                publisher = 'CN=The Browser Company of New York Inc.'
                                url = 'https://releases.diabrowser.com/windows/release/1.1.0.6/Dia.x64.msix'
                                sha256 = 'b83e1e696cd5e479da7b8b580efc107e673fffec3a400011212a050aed61800e'
                                dependencies = @(@{
                                        name = 'Microsoft.VCLibs.140.00.UWPDesktop'
                                        packageFamilyName = 'Microsoft.VCLibs.140.00.UWPDesktop_8wekyb3d8bbwe'
                                        publisher = 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'
                                        version = '14.0.33728.0'; architecture = 'x64'
                                        url = 'https://releases.diabrowser.com/windows/dependencies/x64/Microsoft.VCLibs.x64.14.00.Desktop.14.0.33728.0.appx'
                                        sha256 = '077a3d1a5d0622bd3004dca85f5e192d6e98ec79b83d4aa06766759ea6c09c3d'
                                    })
                            }
                        })
                })
        }
    }

    It 'should accept complete direct AppX metadata using the shipped jq filter' {
        if (-not $script:jqAvailable) { Set-ItResult -Skipped -Because 'Real jq is unavailable in Windows or optional WSL'; return }
        Invoke-ShippedManifestValidation $script:directManifest | Should -Be 0
    }

    It 'should reject <Fault> in direct installer metadata using the shipped jq filter' -TestCases @(
        @{ Fault = 'missing direct metadata' }
        @{ Fault = 'wrong source type' }
        @{ Fault = 'wrong source identifier' }
        @{ Fault = 'insecure source URL' }
        @{ Fault = 'wrong installer type' }
        @{ Fault = 'mismatched package name' }
        @{ Fault = 'nonstring package family' }
        @{ Fault = 'invalid version' }
        @{ Fault = 'unsupported architecture' }
        @{ Fault = 'empty executable' }
        @{ Fault = 'empty publisher' }
        @{ Fault = 'insecure installer URL' }
        @{ Fault = 'invalid installer hash' }
        @{ Fault = 'nonarray dependencies' }
        @{ Fault = 'insecure dependency URL' }
        @{ Fault = 'invalid dependency hash' }
        @{ Fault = 'missing dependency name' }
        @{ Fault = 'nonstring dependency name' }
        @{ Fault = 'missing dependency family' }
        @{ Fault = 'nonstring dependency family' }
        @{ Fault = 'missing dependency publisher' }
        @{ Fault = 'nonstring dependency publisher' }
        @{ Fault = 'missing dependency version' }
        @{ Fault = 'nonstring dependency version' }
        @{ Fault = 'invalid dependency version' }
        @{ Fault = 'missing dependency architecture' }
        @{ Fault = 'nonstring dependency architecture' }
        @{ Fault = 'unsupported dependency architecture' }
    ) {
        param($Fault)
        if (-not $script:jqAvailable) { Set-ItResult -Skipped -Because 'Real jq is unavailable in Windows or optional WSL'; return }
        $source = $script:directManifest.Sources[0]
        $package = $source.Packages[0]
        $installer = $package.directInstaller
        switch ($Fault) {
            'missing direct metadata' { $package.Remove('directInstaller') }
            'wrong source type' { $source.SourceDetails.Type = 'Microsoft.Rest' }
            'wrong source identifier' { $source.SourceDetails.Identifier = 'StoreEdgeFD' }
            'insecure source URL' { $source.SourceDetails.Argument = 'http://releases.diabrowser.com' }
            'wrong installer type' { $installer.type = 'exe' }
            'mismatched package name' { $installer.name = 'Other.App' }
            'nonstring package family' { $installer.packageFamilyName = 12 }
            'invalid version' { $installer.version = 'latest' }
            'unsupported architecture' { $installer.architecture = 'arm64' }
            'empty executable' { $installer.executable = '' }
            'empty publisher' { $installer.publisher = '' }
            'insecure installer URL' { $installer.url = 'http://releases.diabrowser.com/Dia.msix' }
            'invalid installer hash' { $installer.sha256 = 'not-a-sha256' }
            'nonarray dependencies' { $installer.dependencies = 'dependency.appx' }
            'insecure dependency URL' { $installer.dependencies[0].url = 'http://releases.diabrowser.com/dependency.appx' }
            'invalid dependency hash' { $installer.dependencies[0].sha256 = 12 }
            'missing dependency name' { $installer.dependencies[0].Remove('name') }
            'nonstring dependency name' { $installer.dependencies[0].name = 12 }
            'missing dependency family' { $installer.dependencies[0].Remove('packageFamilyName') }
            'nonstring dependency family' { $installer.dependencies[0].packageFamilyName = 12 }
            'missing dependency publisher' { $installer.dependencies[0].Remove('publisher') }
            'nonstring dependency publisher' { $installer.dependencies[0].publisher = 12 }
            'missing dependency version' { $installer.dependencies[0].Remove('version') }
            'nonstring dependency version' { $installer.dependencies[0].version = 14 }
            'invalid dependency version' { $installer.dependencies[0].version = '14.0' }
            'missing dependency architecture' { $installer.dependencies[0].Remove('architecture') }
            'nonstring dependency architecture' { $installer.dependencies[0].architecture = 64 }
            'unsupported dependency architecture' { $installer.dependencies[0].architecture = 'arm64' }
        }
        Invoke-ShippedManifestValidation $script:directManifest | Should -Not -Be 0
    }
}
