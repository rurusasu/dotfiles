BeforeAll {
    $script:sourceRoot = Split-Path -Parent $PSScriptRoot

    . (Join-Path $PSScriptRoot 'support/Resolve-TestModule.ps1')
    $analyzerModule = Resolve-TestModule -Name PSScriptAnalyzer
    Import-Module -Name $analyzerModule.Path -Force -ErrorAction Stop

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

Describe 'PowerShell static analysis' {
    It 'should report no errors or warnings in runtime sources' {
        $issues = @(foreach ($file in $script:runtimeFiles) {
                Invoke-ScriptAnalyzer -Path $file.FullName -ExcludeRule PSUseOutputTypeCorrectly, PSUseShouldProcessForStateChangingFunctions, PSAvoidUsingWriteHost -Severity Error, Warning -ErrorAction Stop |
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

