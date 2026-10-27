BeforeAll {
    $script:sourceRoot = Split-Path -Parent $PSScriptRoot
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $script:sourceRoot)
    $script:settingsPath = Join-Path $script:sourceRoot 'PSScriptAnalyzerSettings.psd1'
    $script:oldPssaModule = $env:DOTFILES_PSSA_MODULE

    . (Join-Path $PSScriptRoot 'support/Resolve-TestModule.ps1')
    $analyzerModule = Resolve-TestModule -Name PSScriptAnalyzer
    Import-Module -Name $analyzerModule.Path -Force -ErrorAction Stop
    # The formatter and analyzer use the same preprovisioned module.
    $env:DOTFILES_PSSA_MODULE = Join-Path $analyzerModule.ModuleBase 'PSScriptAnalyzer.psd1'

    $script:sourceFiles = @(Get-ChildItem -LiteralPath $script:sourceRoot -Recurse -File |
            Where-Object Extension -In '.ps1', '.psm1', '.psd1')
    $script:runtimeFiles = @($script:sourceFiles | Where-Object {
            $relativePath = $_.FullName.Substring($script:sourceRoot.Length + 1).Replace('\', '/')
            $relativePath -eq 'install.ps1' -or $relativePath -match '^lib/'
        })
    if ($script:runtimeFiles.Count -eq 0) {
        throw 'No runtime PowerShell sources were found in install.ps1 or lib/. Static analysis cannot pass without sources.'
    }
}

AfterAll { $env:DOTFILES_PSSA_MODULE = $script:oldPssaModule }

Describe 'PowerShell static analysis' {
    It 'should report no errors or warnings in runtime sources' {
        $issues = @(foreach ($file in $script:runtimeFiles) {
                Invoke-ScriptAnalyzer -Path $file.FullName -Settings $script:settingsPath -Severity Error, Warning -ErrorAction Stop |
                    ForEach-Object {
                        "$($file.FullName):$($_.Line) - [$($_.Severity)] $($_.RuleName): $($_.Message)"
                    }
            })
        $issues | Should -BeNullOrEmpty
    }
}

Describe 'Windows PowerShell source encoding' {
    It 'should retain Unicode when files are read with an ANSI fallback' {
        $violations = @(foreach ($file in $script:sourceFiles) {
                $expected = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
                # StreamReader detects a BOM; without one, emulate Japanese Windows 5.1.
                $reader = [IO.StreamReader]::new($file.FullName, [Text.Encoding]::GetEncoding(932), $true)
                try {
                    if ($reader.ReadToEnd() -cne $expected) { $file.FullName }
                }
                finally { $reader.Dispose() }
            })
        $violations | Should -BeNullOrEmpty
    }
}

Describe 'PowerShell formatter encoding' {
    It 'should preserve the encoding boundary when treefmt passes a filename argument' {
        if ($PSVersionTable.PSVersion.Major -lt 7) {
            Set-ItResult -Skipped -Because 'treefmt runs its formatter under pwsh'
            return
        }
        foreach ($config in @('nix/treefmt.nix')) {
            $line = Get-Content (Join-Path $script:repoRoot $config) | Where-Object { $_ -match '^\s*"& \{ \$ErrorActionPreference' }
            $command = $line.Trim().TrimEnd(',') | ConvertFrom-Json
            $formatter = [scriptblock]::Create($command + ' @args')
            $oldFilename = $env:FILENAME
            try {
                $env:FILENAME = $null
                foreach ($case in @(
                        @{ Path = 'scripts/powershell/ascii.ps1'; Unicode = $false; Bom = $false; Expected = $false },
                        @{ Path = 'scripts/powershell/data.psd1'; Unicode = $true; Bom = $false; Expected = $true },
                        @{ Path = 'scripts/powershell/module.psm1'; Unicode = $true; Bom = $false; Expected = $true },
                        @{ Path = 'chezmoi/unicode.ps1'; Unicode = $true; Bom = $false; Expected = $false },
                        @{ Path = 'scripts/powershell/existing.ps1'; Unicode = $false; Bom = $true; Expected = $true }
                    )) {
                    $target = Join-Path (Join-Path $TestDrive 'path with spaces') $case.Path
                    New-Item -ItemType Directory -Force (Split-Path -Parent $target) | Out-Null
                    $value = if ($case.Unicode) { [string][char]0x672a } else { 'value' }
                    $content = "@{ Name = '$value' }`r`n"
                    [IO.File]::WriteAllText($target, $content, [Text.UTF8Encoding]::new($case.Bom))
                    & $formatter $target
                    $prefix = [BitConverter]::ToString([IO.File]::ReadAllBytes($target)[0..2])
                    ($prefix -eq 'EF-BB-BF') | Should -Be $case.Expected -Because $case.Path
                    [IO.File]::ReadAllText($target) | Should -BeExactly $content
                }
            }
            finally { $env:FILENAME = $oldFilename }
        }
    }

    It 'should repair a missing BOM without changing formatted text and remain idempotent' {
        if ($PSVersionTable.PSVersion.Major -lt 7) {
            Set-ItResult -Skipped -Because 'treefmt runs its formatter under pwsh'
            return
        }
        foreach ($config in @('nix/treefmt.nix')) {
            $line = Get-Content (Join-Path $script:repoRoot $config) | Where-Object { $_ -match '^\s*"& \{ \$ErrorActionPreference' }
            $command = $line.Trim().TrimEnd(',') | ConvertFrom-Json
            $formatter = [scriptblock]::Create($command)
            $directory = Join-Path $TestDrive 'scripts/powershell'
            New-Item -ItemType Directory -Force $directory | Out-Null
            $target = Join-Path $directory 'fixture.ps1'
            # Construct the original failing Japanese text without making this test ANSI-dependent.
            $label = -join @([char]0x672a, [char]0x8a2d, [char]0x5b9a)
            $expected = 'Write-Output "' + $label + '"' + "`r`n"
            [IO.File]::WriteAllText($target, $expected, [Text.UTF8Encoding]::new($false))
            $oldFilename = $env:FILENAME
            try {
                $env:FILENAME = $target
                & $formatter
                [BitConverter]::ToString([IO.File]::ReadAllBytes($target)[0..2]) | Should -Be 'EF-BB-BF'
                [IO.File]::ReadAllText($target) | Should -BeExactly $expected
                $first = [Convert]::ToBase64String([IO.File]::ReadAllBytes($target))
                $modified = [IO.File]::GetLastWriteTimeUtc($target)
                & $formatter
                [Convert]::ToBase64String([IO.File]::ReadAllBytes($target)) | Should -BeExactly $first
                [IO.File]::GetLastWriteTimeUtc($target) | Should -Be $modified
            }
            finally { $env:FILENAME = $oldFilename }
        }
    }
}
