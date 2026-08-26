#Requires -Module Pester

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../handlers/Handler.Hindsight.ps1
}

Describe 'HindsightHandler' {
    BeforeEach {
        $root = Join-Path $TestDrive 'dotfiles'
        $composeDir = Join-Path $root 'docker/hindsight'
        $scriptDir = Join-Path $root 'scripts/powershell'
        New-Item -ItemType Directory -Path $composeDir, $scriptDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $composeDir 'compose.yml') -Value 'services: {}'
        Set-Content -LiteralPath (Join-Path $scriptDir 'hindsight.ps1') -Value 'param($Action, $ComposeFile)'
        $ctx = [SetupContext]::new($root)
        $handler = [HindsightHandler]::new()
        Mock Get-Command { [PSCustomObject]@{ Name = $Name } }
    }

    It 'is disabled by default' {
        $handler.CanApply($ctx) | Should -BeFalse
    }

    It 'is enabled by the Docker-derived Hindsight option' {
        $ctx.Options['WithHindsight'] = $true
        $handler.CanApply($ctx) | Should -BeTrue
    }

    It 'runs before Hermes and outside its handler' {
        $handler.Order | Should -BeLessThan 56
        $handler.Name | Should -Be 'Hindsight'
        $source = Get-Content -LiteralPath $PSScriptRoot/../../handlers/Handler.HermesAgent.ps1 -Raw
        $source | Should -Not -Match 'hindsight\.ps1|docker\\hindsight'
    }
}
