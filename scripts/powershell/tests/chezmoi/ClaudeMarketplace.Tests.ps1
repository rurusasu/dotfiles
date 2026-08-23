#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Join-Path $PSScriptRoot '../../../..'
    $script:chezmoiRoot = Join-Path $script:repoRoot 'chezmoi'
    $templatePath = Join-Path $script:chezmoiRoot '.chezmoiscripts/run_always_install-claude-plugins_windows.ps1.tmpl'
    $rendered = (Get-Content -LiteralPath $templatePath -Raw |
            & chezmoi --source $script:chezmoiRoot --override-data '{"chezmoi":{"os":"windows"}}' execute-template) -join [Environment]::NewLine
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to render the Windows Claude marketplace installer template.'
    }

    $normalizeFunction = [regex]::Match($rendered, '(?s)function Normalize-MarketplacePath \{.*?\n\}').Value
    $recoveryFunction = [regex]::Match(
        $rendered,
        '(?s)function Recover-InvalidMarketplace \{.*?\n\}(?=\r?\n\r?\n# Clone or update)'
    ).Value
    if ([string]::IsNullOrWhiteSpace($normalizeFunction) -or [string]::IsNullOrWhiteSpace($recoveryFunction)) {
        throw 'Failed to extract marketplace helper functions from the rendered installer.'
    }

    $script:marketplacesDir = Join-Path $TestDrive 'marketplaces'
    New-Item -ItemType Directory -Path $script:marketplacesDir -Force | Out-Null
    $script:gitNonInteractive = @()
    Invoke-Expression $normalizeFunction
    Invoke-Expression $recoveryFunction
}

Describe 'Claude marketplace Windows installer helpers' {
    It 'normalizes Git and PowerShell Windows path formats to the same path' {
        Normalize-MarketplacePath -Path 'C:/Users/test/.claude/' |
            Should -Be 'C:\Users\test\.claude'
        Normalize-MarketplacePath -Path '/c/Users/test/.claude/' |
            Should -Be 'C:\Users\test\.claude'
    }

    It 'preserves an invalid checkout after a successful staged recovery' {
        $fakeGit = Join-Path $TestDrive 'fake-git.ps1'
        @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
$cloneIndex = [Array]::IndexOf($Arguments, 'clone')
if ($cloneIndex -ge 0) {
    $destination = $Arguments[$cloneIndex + 2]
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $destination 'recovered.txt') -Value 'recovered'
    exit 0
}
exit 1
'@ | Set-Content -LiteralPath $fakeGit -Encoding utf8

        $script:gitCmd = $fakeGit
        $targetDir = Join-Path $script:marketplacesDir 'invalid'
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $targetDir 'original.txt') -Value 'original'

        Recover-InvalidMarketplace -Repository 'example/repository' -TargetDir $targetDir |
            Should -BeTrue
        Test-Path -LiteralPath (Join-Path $targetDir 'recovered.txt') |
            Should -BeTrue
        @(Get-ChildItem -LiteralPath $script:marketplacesDir -Filter 'invalid.invalid.*').Count |
            Should -Be 1
    }

    It 'keeps the original checkout when the staged clone fails' {
        $fakeGit = Join-Path $TestDrive 'failing-git.ps1'
        @'
exit 1
'@ | Set-Content -LiteralPath $fakeGit -Encoding utf8

        $script:gitCmd = $fakeGit
        $targetDir = Join-Path $script:marketplacesDir 'still-invalid'
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $targetDir 'original.txt') -Value 'original'

        Recover-InvalidMarketplace -Repository 'example/repository' -TargetDir $targetDir |
            Should -BeFalse
        Get-Content -LiteralPath (Join-Path $targetDir 'original.txt') |
            Should -Be 'original'
    }
}
