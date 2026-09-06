#Requires -Module Pester

Describe 'Hermes X API PowerShell entrypoint' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        $script:entrypoint = Get-Content `
            -LiteralPath (Join-Path $repositoryRoot 'scripts/powershell/hermes-xapi.ps1') `
            -Raw
    }

    It 'should preserve token probe diagnostics and classify the Docker result' {
        $script:entrypoint | Should -Match 'TokenProbe\s*=\s*\{(?s).*Resolve-HermesXApiTokenProbeResult'
        $script:entrypoint | Should -Match 'Resolve-HermesXApiTokenProbeResult\s+`?\s*-ExitCode'
        $script:entrypoint | Should -Match '-Output\s+\$probeOutput'
        $script:entrypoint | Should -Not -Match '(?s)TokenProbe\s*=\s*\{.*\)\s*-eq\s*0'
        $script:entrypoint | Should -Not -Match 'xurl token >/dev/null 2>&1'
    }
}
