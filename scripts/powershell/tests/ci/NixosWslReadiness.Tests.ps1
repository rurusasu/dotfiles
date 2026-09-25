Describe 'NixOS WSL Hermes readiness verifier transport' {
    BeforeAll {
        $script:verifierPath = Join-Path $PSScriptRoot '../../ci/Invoke-NixosWslE2E.ps1'
        $script:verifier = Get-Content -LiteralPath $script:verifierPath -Raw -Encoding UTF8
    }

    It 'passes the readiness script as a single line-ending-normalized base64 payload' {
        $script:verifier | Should -Match '\$readinessCommand = \$readinessCommand -replace "`r`n\?", "`n"'
        $script:verifier | Should -Match '\$readinessCommandBase64 = \[Convert\]::ToBase64String\(\[Text\.Encoding\]::UTF8\.GetBytes\(\$readinessCommand\)\)'
        $script:verifier | Should -Match 'printf ''%s'' ''\$readinessCommandBase64'' \| base64 -d \| bash'
        $script:verifier | Should -Not -Match '"bash", "-lc",\s*\$readinessCommand\b'
    }

    It 'seeds and preserves an explicit model for Hermes readiness' {
        $script:verifier | Should -Match 'default: openrouter/auto'
        $script:verifier | Should -Match "grep -qx '  default: openrouter/auto' /home/nixos/\.hermes/config\.yaml"
        $script:verifier | Should -Match 'config\.yaml.*chmod 600'
    }
}
