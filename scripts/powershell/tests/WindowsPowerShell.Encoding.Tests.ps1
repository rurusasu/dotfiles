BeforeAll {
    $script:sourceRoot = Split-Path -Parent $PSScriptRoot
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $script:sourceRoot)
}

Describe 'Windows PowerShell source encoding' {
    It 'should retain Unicode when files are read with an ANSI fallback' {
        $violations = @()
        foreach ($file in Get-ChildItem $script:sourceRoot -Recurse -File | Where-Object Extension -In '.ps1', '.psm1', '.psd1') {
            $expected = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
            # StreamReader detects a BOM; without one, emulate Japanese Windows 5.1.
            $reader = [IO.StreamReader]::new($file.FullName, [Text.Encoding]::GetEncoding(932), $true)
            try {
                if ($reader.ReadToEnd() -cne $expected) { $violations += $file.FullName }
            }
            finally { $reader.Dispose() }
        }
        $violations | Should -BeNullOrEmpty
    }

    It 'should parse bootstrap entrypoints and load every real handler on Windows PowerShell 5.1' {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            Set-ItResult -Skipped -Because 'Windows PowerShell 5.1 requires Windows'
            return
        }
        $probe = @'
param([string]$Root)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5) { throw 'Expected Windows PowerShell 5.1' }
Write-Output ('ANSI codepage: ' + [Text.Encoding]::Default.CodePage)
foreach ($name in 'install.ps1', 'install.user.ps1', 'install.admin.ps1') {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root $name), [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors) { throw ($parseErrors | Out-String) }
}
. (Join-Path $Root 'lib/SetupHandler.ps1')
. (Join-Path $Root 'lib/Invoke-ExternalCommand.ps1')
$handlerRoot = Join-Path $Root 'handlers'
$warnings = @()
$handlers = @(Get-SetupHandler -HandlersPath $handlerRoot -WarningVariable warnings)
if ($warnings) { throw ($warnings -join [Environment]::NewLine) }
$expected = @(Get-ChildItem $handlerRoot -Filter 'Handler.*.ps1').Count
if ($expected -eq 0 -or $handlers.Count -ne $expected) { throw 'Not all handlers loaded' }
Write-Output ('BOOTSTRAP_LOADED: ' + $handlers.Count)
'@
        $probePath = Join-Path $TestDrive 'probe.ps1'
        [IO.File]::WriteAllText($probePath, $probe, [Text.UTF8Encoding]::new($false))
        $exe = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $output = & $exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probePath -Root $script:sourceRoot 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
        $output -join [Environment]::NewLine | Should -Match 'BOOTSTRAP_LOADED: \d+'
    }
}

Describe 'PowerShell formatter encoding' {
    It 'should preserve the encoding boundary when treefmt passes a filename argument' {
        if ($PSVersionTable.PSVersion.Major -lt 7) {
            Set-ItResult -Skipped -Because 'treefmt runs its formatter under pwsh'
            return
        }
        foreach ($config in '.treefmt.toml', 'nix/flakes/treefmt.nix') {
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
        foreach ($config in '.treefmt.toml', 'nix/flakes/treefmt.nix') {
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
