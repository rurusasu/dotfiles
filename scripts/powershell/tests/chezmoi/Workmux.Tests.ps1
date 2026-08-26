#Requires -Module Pester

BeforeAll {
    $repoRoot = Join-Path $PSScriptRoot '../../../..'
    $configPath = Join-Path $repoRoot 'chezmoi/dot_config/workmux/config.yaml'
    $config = Get-Content -LiteralPath $configPath -Raw
}

Describe 'Workmux agent configuration' {
    It 'should select a configured non-Claude agent by default' {
        $defaultAgent = [regex]::Match($config, '(?m)^agent:\s+(\S+)\s*$').Groups[1].Value
        $configuredAgents = [regex]::Matches($config, '(?m)^  ([a-z0-9_-]+):') |
            ForEach-Object { $_.Groups[1].Value }

        $defaultAgent | Should -Be 'cx'
        $configuredAgents | Should -Contain $defaultAgent
        $config | Should -Not -Match '(?i)claude'
    }
}
