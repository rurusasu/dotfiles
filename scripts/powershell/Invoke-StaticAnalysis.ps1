#Requires -Version 5.1
[CmdletBinding()]
param([string]$SourceRoot = $PSScriptRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)
if ([string]::IsNullOrWhiteSpace($env:DOTFILES_PSSA_MODULE)) {
    throw 'The locked PSScriptAnalyzer dependency is required. Run task lint:powershell.'
}
Import-Module $env:DOTFILES_PSSA_MODULE -Force -ErrorAction Stop

$sourceFiles = @(Get-ChildItem -LiteralPath $SourceRoot -Recurse -File |
        Where-Object Extension -In '.ps1', '.psm1', '.psd1')
$runtimeFiles = @($sourceFiles | Where-Object {
        $relativePath = $_.FullName.Substring($SourceRoot.Length + 1).Replace('\', '/')
        $relativePath -eq 'install.ps1' -or $relativePath -match '^lib/' -or $relativePath -like 'Invoke-*.ps1'
    })
if ($runtimeFiles.Count -eq 0) {
    throw 'No runtime PowerShell sources were found in installer, CI adapters, or lib/. Static analysis cannot pass without sources.'
}

$issues = @(foreach ($file in $runtimeFiles) {
        Invoke-ScriptAnalyzer -Path $file.FullName -ExcludeRule PSUseOutputTypeCorrectly, PSUseShouldProcessForStateChangingFunctions, PSAvoidUsingWriteHost -Severity Error, Warning -ErrorAction Stop |
            ForEach-Object {
                "$($file.FullName):$($_.Line) - [$($_.Severity)] $($_.RuleName): $($_.Message)"
            }
    })
$issues += @(foreach ($file in $sourceFiles) {
        $expected = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
        # StreamReader detects a BOM; without one, emulate Japanese Windows 5.1.
        $reader = [IO.StreamReader]::new($file.FullName, [Text.Encoding]::GetEncoding(932), $true)
        try {
            if ($reader.ReadToEnd() -cne $expected) { "$($file.FullName): Unicode differs with the Windows ANSI fallback." }
        }
        finally { $reader.Dispose() }
    })
if ($issues.Count -gt 0) { throw ($issues -join [Environment]::NewLine) }
