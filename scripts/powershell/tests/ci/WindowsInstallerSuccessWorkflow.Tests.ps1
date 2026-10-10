Describe 'Windows GUI installer success workflow contract' {
    BeforeAll {
        $script:repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
        $script:workflow = Get-Content -LiteralPath (Join-Path $script:repositoryRoot '.github/workflows/ci-nix.yml') -Raw -Encoding UTF8
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
            'TheBrowserCompany.Arc', 'Google.Chrome', 'Obsidian.Obsidian', 'wez.wezterm',
            'AgileBits.1Password', 'Discord.Discord', 'StablyAI.Orca', 'Microsoft.PowerToys',
            'Microsoft.WindowsTerminal', '9PLM9XGG6VKS'
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

    It 'should verify every GUI package including verify-only Orca and Store Codex' {
        Invoke-ShippedValidation -Name 'WinGet package inventory'
        $script:validationErrors | Should -BeNullOrEmpty
    }

    It 'should reject missing GUI success evidence' -TestCases @(
        @{ PackageId = 'StablyAI.Orca' }
        @{ PackageId = '9PLM9XGG6VKS' }
        @{ PackageId = 'AgileBits.1Password' }
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
        @{ Inventory = 'Google.Chrome|Obsidian.Obsidian' }
        @{ Inventory = 'extra' }
        @{ Inventory = 'duplicate' }
    ) {
        param($Inventory)
        if ($Inventory -eq 'extra') { $Inventory = ($script:guiIds + @('OpenAI.Codex.CLI')) -join '|' }
        if ($Inventory -eq 'duplicate') { $Inventory = ($script:guiIds + @('Google.Chrome')) -join '|' }
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
        $script:installerE2E | Should -Match 'SetValue\(''PATH'', \$originalUserPathRegistryValue, \$originalUserPathRegistryKind\)'
        $script:installerE2E | Should -Match 'DeleteValue\(''PATH'', \$false\)'
    }

    It 'should avoid self-update manifest mutations CLI probes and retired-package seed or removal' {
        $script:installerE2E | Should -Not -Match 'Microsoft\.PowerShell|Add-Member|Set-Content|Invoke-Npm|Invoke-Pnpm|Assert-WingetCommandRecovery|node --version|op\.exe|herdr|@openai/codex|Codex CLI|9NT1R1C2HH7J|RETIRED_PACKAGE_CLEANUP'
        @($script:validationCalls | ForEach-Object { $_.CommandElements[2].Value }) | Should -Be @(
            'installer evidence', 'WinGet package inventory', 'WezTerm install PATH and version'
        )
    }

    It 'should run the full installer in separate parallel PowerShell 5.1 and 7 jobs' {
        $script:workflow | Should -Match '(?s)windows-installer:.*?max-parallel:\s*2.*?runtime: Windows PowerShell 5\.1\s+version: "5\.1".*?runtime: PowerShell 7\s+version: "7"'
        $script:workflow | Should -Match 'shell:\s+cmd[\s\S]*?powershell\.exe .*Invoke-WindowsInstallerE2E\.ps1'
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
